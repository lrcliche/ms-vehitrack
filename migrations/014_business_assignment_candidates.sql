-- Tenant-scoped read model for enterprise assignment suggestions.
-- Returns a pending request and vehicles with an active driver association.
BEGIN;

-- On a v2 cache miss return the newly stored route in the same shape as a cache hit.
-- Without this, POST /api/v2/routes exposes only route_cache_id/waypoints_hash on first use.
CREATE OR REPLACE PROCEDURE routing.prc_store_business_route(
    p_tenant_id uuid,
    p_user_id uuid,
    p_tenant_user_id uuid,
    p_waypoints jsonb,
    p_geojson jsonb,
    p_distance_m numeric,
    p_duration_s int,
    p_profile text DEFAULT 'car',
    p_steps jsonb DEFAULT NULL,
    p_alternatives jsonb DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_geom geometry;
    v_hash text;
    v_id bigint;
    v_ttl int := public.fnc_setting_num('routing.cache_ttl_minutes')::int;
    v_max int := public.fnc_setting_num('routing.max_waypoints')::int;
BEGIN
    IF public.fnc_current_tenant() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'tenant context mismatch' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM business.tenant_user tu
        JOIN business."user" u ON u.id = tu.user_id
        WHERE tu.id = p_tenant_user_id
          AND tu.tenant_id = p_tenant_id
          AND tu.user_id = p_user_id
          AND tu.is_active
          AND u.is_active
    ) THEN
        RAISE EXCEPTION 'business user is not active in tenant' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.route_profile WHERE id = p_profile) THEN
        RAISE EXCEPTION 'route_profile % invalid', p_profile USING ERRCODE = 'VT061';
    END IF;
    IF jsonb_typeof(p_waypoints) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'waypoints must be an array' USING ERRCODE = 'VT060';
    END IF;
    IF jsonb_array_length(p_waypoints) < 2 THEN
        RAISE EXCEPTION 'at least two waypoints required' USING ERRCODE = 'VT060';
    END IF;
    IF jsonb_array_length(p_waypoints) > v_max THEN
        RAISE EXCEPTION 'route exceeds maximum waypoint count' USING ERRCODE = 'VT062';
    END IF;

    v_geom := ST_SetSRID(ST_GeomFromGeoJSON(p_geojson::text), 4326);
    IF v_geom IS NULL OR ST_GeometryType(v_geom) <> 'ST_LineString' THEN
        RAISE EXCEPTION 'invalid route geometry' USING ERRCODE = 'VT060';
    END IF;

    v_hash := routing.fnc_waypoints_hash(p_waypoints, p_profile);
    INSERT INTO routing.route_cache (
        waypoints_hash, route_profile_id, geom, distance_m, duration_s,
        steps, alternatives, computed_at, expires_at
    ) VALUES (
        v_hash, p_profile, v_geom, p_distance_m, p_duration_s,
        p_steps, p_alternatives, now(), now() + (v_ttl || ' minute')::interval
    )
    ON CONFLICT (waypoints_hash, route_profile_id) DO UPDATE SET
        geom = EXCLUDED.geom,
        distance_m = EXCLUDED.distance_m,
        duration_s = EXCLUDED.duration_s,
        steps = EXCLUDED.steps,
        alternatives = EXCLUDED.alternatives,
        computed_at = now(),
        expires_at = EXCLUDED.expires_at
    RETURNING id INTO v_id;

    INSERT INTO routing.route_request (tenant_id, user_id, route_cache_id, was_cache_hit)
    VALUES (p_tenant_id, p_user_id, v_id, false);

    p_result := routing.fnc_get_route(p_waypoints, p_profile)
        || jsonb_build_object('waypoints_hash', v_hash);
END $$;

GRANT EXECUTE ON PROCEDURE routing.prc_store_business_route(
    uuid, uuid, uuid, jsonb, jsonb, numeric, int, text, jsonb, jsonb, jsonb
) TO postgres;

CREATE OR REPLACE FUNCTION business.fnc_get_assignment_candidates(
    p_tenant_id uuid,
    p_actor_user_id uuid,
    p_tenant_user_id uuid,
    p_service_request_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result jsonb;
BEGIN
    IF public.fnc_current_tenant() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'tenant context mismatch' USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM business.tenant_user tu
        JOIN business."user" u ON u.id = tu.user_id
        JOIN business.tenant_user_role tur ON tur.tenant_user_id = tu.id
        JOIN business.role r ON r.id = tur.role_id
        JOIN business.role_permission rp ON rp.role_id = r.id
        JOIN business.permission p ON p.id = rp.permission_id
        WHERE tu.id = p_tenant_user_id
          AND tu.tenant_id = p_tenant_id
          AND tu.user_id = p_actor_user_id
          AND tu.is_active
          AND u.is_active
          AND r.is_active
          AND (r.tenant_id IS NULL OR r.tenant_id = p_tenant_id)
          AND p.code = 'services.read'
    ) THEN
        RAISE EXCEPTION 'service read permission denied' USING ERRCODE = 'VT070';
    END IF;

    SELECT jsonb_build_object(
        'service_request', jsonb_build_object(
            'id', sr.id,
            'status', sr.status,
            'origin_address', sr.origin_address,
            'origin_latitude', sr.origin_latitude,
            'origin_longitude', sr.origin_longitude,
            'destination_address', sr.destination_address,
            'destination_latitude', sr.destination_latitude,
            'destination_longitude', sr.destination_longitude,
            'scheduled_at', sr.scheduled_at,
            'passenger_count', sr.passenger_count,
            'agreed_fare_cop', sr.agreed_fare_cop
        ),
        'candidates', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', v.id,
                'plate', v.plate,
                'vehicle_type_id', v.vehicle_type_id,
                'brand', v.brand,
                'model', v.model,
                'model_year', v.model_year,
                'passenger_capacity', v.passenger_capacity,
                'operational_status', v.operational_status,
                'cost_per_km_cop', v.cost_per_km_cop,
                'dispatch_cost_cop', v.dispatch_cost_cop,
                'fuel_efficiency_km_per_gallon', v.fuel_efficiency_km_per_gallon,
                'driver', jsonb_build_object(
                    'id', d.id,
                    'full_name', d.full_name,
                    'phone', d.phone,
                    'license_category', d.license_category,
                    'license_expires_at', d.license_expires_at,
                    'operational_status', d.operational_status
                ),
                'current_location', CASE WHEN loc.recorded_at IS NULL THEN NULL ELSE
                    jsonb_build_object(
                        'latitude', loc.latitude,
                        'longitude', loc.longitude,
                        'recorded_at', loc.recorded_at
                    ) END
            ) ORDER BY v.cost_per_km_cop, v.dispatch_cost_cop, v.plate)
            FROM business.vehicle v
            JOIN business.driver_vehicle dv
              ON dv.vehicle_id = v.id
             AND dv.tenant_id = v.tenant_id
             AND dv.unassigned_at IS NULL
            JOIN business.driver d
              ON d.id = dv.driver_id
             AND d.tenant_id = v.tenant_id
            LEFT JOIN business.vehicle_device vd
              ON vd.vehicle_id = v.id
             AND vd.tenant_id = v.tenant_id
             AND vd.unassigned_at IS NULL
            LEFT JOIN device.device dev
              ON dev.id = vd.device_id
             AND dev.tenant_id = v.tenant_id
             AND NOT dev.is_blocked
            LEFT JOIN LATERAL (
                SELECT ST_Y(pos.geom)::double precision AS latitude,
                       ST_X(pos.geom)::double precision AS longitude,
                       pos.recorded_at
                FROM tracking.position pos
                WHERE pos.tenant_id = v.tenant_id
                  AND pos.device_id = dev.id
                ORDER BY pos.recorded_at DESC
                LIMIT 1
            ) loc ON true
            WHERE v.tenant_id = sr.tenant_id
              AND v.is_active
              AND v.operational_status = 'available'
              AND v.passenger_capacity >= sr.passenger_count
              AND d.is_active
              AND d.operational_status = 'available'
              AND NOT EXISTS (
                  SELECT 1
                  FROM business.driver_availability da
                  WHERE da.tenant_id = d.tenant_id
                    AND da.driver_id = d.id
                    AND da.starts_at <= sr.scheduled_at
                    AND da.ends_at > sr.scheduled_at
                    AND da.availability_status IN ('unavailable','rest')
              )
        ), '[]'::jsonb)
    )
    INTO v_result
    FROM business.service_request sr
    WHERE sr.id = p_service_request_id
      AND sr.tenant_id = p_tenant_id
      AND sr.status = 'pending';

    IF v_result IS NULL THEN
        IF EXISTS (
            SELECT 1 FROM business.service_request sr
            WHERE sr.id = p_service_request_id AND sr.tenant_id = p_tenant_id
        ) THEN
            RAISE EXCEPTION 'service request is not pending' USING ERRCODE = 'VT073';
        END IF;
        RAISE EXCEPTION 'service request not found' USING ERRCODE = 'P0002';
    END IF;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION business.fnc_get_assignment_candidates(uuid, uuid, uuid, uuid) TO postgres;

COMMIT;
