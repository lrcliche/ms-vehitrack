BEGIN;

CREATE TABLE IF NOT EXISTS business.driver_location (
    tenant_id uuid NOT NULL REFERENCES public.tenant(id),
    driver_id uuid NOT NULL,
    latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    accuracy_m numeric CHECK (accuracy_m IS NULL OR accuracy_m BETWEEN 0 AND 1000),
    recorded_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id,driver_id),
    FOREIGN KEY (driver_id,tenant_id) REFERENCES business.driver(id,tenant_id)
);

CREATE OR REPLACE FUNCTION business.fnc_driver_me_update_location(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,
    p_latitude double precision,p_longitude double precision,p_accuracy_m numeric,p_recorded_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_driver_id uuid; v_accepted boolean := false;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    IF p_latitude IS NULL OR p_latitude NOT BETWEEN -90 AND 90 OR
       p_longitude IS NULL OR p_longitude NOT BETWEEN -180 AND 180 OR
       (p_accuracy_m IS NOT NULL AND p_accuracy_m NOT BETWEEN 0 AND 1000) OR
       p_recorded_at IS NULL OR p_recorded_at > now()+interval '5 minutes' OR
       p_recorded_at < now()-interval '24 hours' THEN
        RAISE EXCEPTION 'invalid or stale driver location' USING ERRCODE='VT060';
    END IF;
    INSERT INTO business.driver_location(tenant_id,driver_id,latitude,longitude,accuracy_m,recorded_at,updated_at)
    VALUES(p_tenant_id,v_driver_id,p_latitude,p_longitude,p_accuracy_m,p_recorded_at,now())
    ON CONFLICT (tenant_id,driver_id) DO UPDATE SET
        latitude=EXCLUDED.latitude,longitude=EXCLUDED.longitude,accuracy_m=EXCLUDED.accuracy_m,
        recorded_at=EXCLUDED.recorded_at,updated_at=now()
    WHERE EXCLUDED.recorded_at>=business.driver_location.recorded_at
    RETURNING true INTO v_accepted;
    RETURN jsonb_build_object('accepted',COALESCE(v_accepted,false),'recorded_at',p_recorded_at);
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_driver_me_ingest_telemetry(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,
    p_device_id uuid,p_batch_id uuid,p_samples jsonb,p_client_created_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business, device, tracking
AS $$
DECLARE
    v_driver_id uuid;
    v_vehicle_id uuid;
    v_result jsonb;
    v_latitude double precision;
    v_longitude double precision;
    v_accuracy numeric;
    v_recorded_at timestamptz;
    v_location_updated boolean := false;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    SELECT vd.vehicle_id INTO v_vehicle_id
      FROM business.vehicle_device vd
      JOIN business.vehicle v ON v.id=vd.vehicle_id AND v.tenant_id=vd.tenant_id AND v.is_active
      JOIN device.device dev ON dev.id=vd.device_id AND dev.tenant_id=vd.tenant_id AND NOT dev.is_blocked
     WHERE vd.tenant_id=p_tenant_id AND vd.device_id=p_device_id AND vd.unassigned_at IS NULL
       AND (
           EXISTS (SELECT 1 FROM business.driver_vehicle dv
                   WHERE dv.tenant_id=p_tenant_id AND dv.driver_id=v_driver_id
                     AND dv.vehicle_id=vd.vehicle_id AND dv.unassigned_at IS NULL)
           OR EXISTS (SELECT 1 FROM business.service_assignment a
                      JOIN business.service_execution e ON e.service_assignment_id=a.id AND e.tenant_id=a.tenant_id
                      WHERE a.tenant_id=p_tenant_id AND a.driver_id=v_driver_id AND a.vehicle_id=vd.vehicle_id
                        AND a.status='confirmed' AND e.status='in_progress' AND e.ended_at IS NULL)
       )
     ORDER BY vd.assigned_at DESC LIMIT 1;
    IF v_vehicle_id IS NULL THEN
        RAISE EXCEPTION 'device is not assigned to this driver vehicle' USING ERRCODE='VT080';
    END IF;

    CALL tracking.prc_ingest_telemetry(p_device_id,p_batch_id,p_samples,p_client_created_at,v_result);

    SELECT ST_Y(pos.geom)::double precision,ST_X(pos.geom)::double precision,pos.accuracy_m,pos.recorded_at
      INTO v_latitude,v_longitude,v_accuracy,v_recorded_at
      FROM tracking.position pos
     WHERE pos.tenant_id=p_tenant_id AND pos.device_id=p_device_id AND pos.ingest_batch_id=p_batch_id
       AND pos.recorded_at>=now()-interval '10 minutes'
       AND (pos.accuracy_m IS NULL OR pos.accuracy_m<=100)
     ORDER BY pos.recorded_at DESC LIMIT 1;
    IF FOUND THEN
        INSERT INTO business.driver_location(tenant_id,driver_id,latitude,longitude,accuracy_m,recorded_at,updated_at)
        VALUES(p_tenant_id,v_driver_id,v_latitude,v_longitude,v_accuracy,v_recorded_at,now())
        ON CONFLICT (tenant_id,driver_id) DO UPDATE SET
            latitude=EXCLUDED.latitude,longitude=EXCLUDED.longitude,accuracy_m=EXCLUDED.accuracy_m,
            recorded_at=EXCLUDED.recorded_at,updated_at=now()
        WHERE EXCLUDED.recorded_at>=business.driver_location.recorded_at
        RETURNING true INTO v_location_updated;
        v_location_updated := COALESCE(v_location_updated,false);
    END IF;
    RETURN jsonb_set(COALESCE(v_result,'{}'::jsonb),'{driver_location_updated}',to_jsonb(v_location_updated),true);
END;
$$;

-- Driver app GPS is a recent location fallback when a vehicle device has not reported.
-- Existing eligibility, capacity, availability and permission checks remain unchanged.
CREATE OR REPLACE FUNCTION business.fnc_get_assignment_candidates(
    p_tenant_id uuid,p_actor_user_id uuid,p_tenant_user_id uuid,p_service_request_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, business, device, tracking
AS $$
DECLARE v_result jsonb;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_tenant_user_id,'services.read');
    SELECT jsonb_build_object(
        'service_request',jsonb_build_object(
            'id',sr.id,'status',sr.status,'origin_address',sr.origin_address,
            'origin_latitude',sr.origin_latitude,'origin_longitude',sr.origin_longitude,
            'destination_address',sr.destination_address,'destination_latitude',sr.destination_latitude,
            'destination_longitude',sr.destination_longitude,'scheduled_at',sr.scheduled_at,
            'passenger_count',sr.passenger_count,'agreed_fare_cop',sr.agreed_fare_cop
        ),
        'candidates',COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id',v.id,'plate',v.plate,'vehicle_type_id',v.vehicle_type_id,'brand',v.brand,
                'model',v.model,'model_year',v.model_year,'passenger_capacity',v.passenger_capacity,
                'operational_status',v.operational_status,'cost_per_km_cop',v.cost_per_km_cop,
                'dispatch_cost_cop',v.dispatch_cost_cop,'fuel_efficiency_km_per_gallon',v.fuel_efficiency_km_per_gallon,
                'driver',jsonb_build_object(
                    'id',d.id,'full_name',d.full_name,'phone',d.phone,'license_number',d.license_number,
                    'license_category',d.license_category,'license_expires_at',d.license_expires_at,
                    'daily_allowance_cop',d.daily_allowance_cop,'operational_status',d.operational_status
                ),
                'current_location',CASE WHEN COALESCE(dl.recorded_at,loc.recorded_at) IS NULL THEN NULL ELSE jsonb_build_object(
                    'latitude',COALESCE(dl.latitude,loc.latitude),
                    'longitude',COALESCE(dl.longitude,loc.longitude),
                    'recorded_at',COALESCE(dl.recorded_at,loc.recorded_at),
                    'source',CASE WHEN dl.driver_id IS NOT NULL THEN 'driver_app' ELSE 'vehicle_device' END
                ) END
            ) ORDER BY v.cost_per_km_cop,v.dispatch_cost_cop,d.daily_allowance_cop,d.full_name)
            FROM business.vehicle v
            CROSS JOIN business.driver d
            LEFT JOIN business.vehicle_device vd ON vd.vehicle_id=v.id AND vd.tenant_id=v.tenant_id AND vd.unassigned_at IS NULL
            LEFT JOIN device.device dev ON dev.id=vd.device_id AND dev.tenant_id=v.tenant_id AND NOT dev.is_blocked
            LEFT JOIN LATERAL (
                SELECT ST_Y(pos.geom)::double precision AS latitude,ST_X(pos.geom)::double precision AS longitude,pos.recorded_at
                FROM tracking.position pos WHERE pos.tenant_id=v.tenant_id AND pos.device_id=dev.id
                ORDER BY pos.recorded_at DESC LIMIT 1
            ) loc ON true
            LEFT JOIN business.driver_location dl ON dl.tenant_id=d.tenant_id AND dl.driver_id=d.id
                AND dl.recorded_at>=now()-interval '10 minutes'
                AND (dl.accuracy_m IS NULL OR dl.accuracy_m<=100)
            WHERE v.tenant_id=sr.tenant_id AND d.tenant_id=sr.tenant_id
              AND v.is_active AND v.operational_status='available' AND v.passenger_capacity>=sr.passenger_count
              AND d.is_active AND d.operational_status='available'
              AND NOT EXISTS(SELECT 1 FROM business.driver_availability da
                  WHERE da.tenant_id=d.tenant_id AND da.driver_id=d.id AND da.starts_at<=sr.scheduled_at
                    AND da.ends_at>sr.scheduled_at AND da.availability_status IN ('unavailable','rest'))
              AND NOT EXISTS(SELECT 1 FROM business.service_assignment a
                  JOIN business.service_execution e ON e.service_assignment_id=a.id AND e.tenant_id=a.tenant_id
                  WHERE a.tenant_id=v.tenant_id AND a.vehicle_id=v.id AND a.status='confirmed' AND e.status='in_progress')
              AND NOT EXISTS(SELECT 1 FROM business.service_assignment a
                  JOIN business.service_execution e ON e.service_assignment_id=a.id AND e.tenant_id=a.tenant_id
                  WHERE a.tenant_id=d.tenant_id AND a.driver_id=d.id AND a.status='confirmed' AND e.status='in_progress')
        ),'[]'::jsonb)
    ) INTO v_result
    FROM business.service_request sr
    WHERE sr.id=p_service_request_id AND sr.tenant_id=p_tenant_id AND sr.status='pending';
    IF v_result IS NULL THEN
        IF EXISTS(SELECT 1 FROM business.service_request sr WHERE sr.id=p_service_request_id AND sr.tenant_id=p_tenant_id) THEN
            RAISE EXCEPTION 'service request is not pending' USING ERRCODE='VT073';
        END IF;
        RAISE EXCEPTION 'service request not found' USING ERRCODE='P0002';
    END IF;
    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION business.fnc_driver_me_update_location(uuid,uuid,uuid,double precision,double precision,numeric,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION business.fnc_driver_me_update_location(uuid,uuid,uuid,double precision,double precision,numeric,timestamptz) TO postgres;
REVOKE ALL ON FUNCTION business.fnc_driver_me_ingest_telemetry(uuid,uuid,uuid,uuid,uuid,jsonb,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION business.fnc_driver_me_ingest_telemetry(uuid,uuid,uuid,uuid,uuid,jsonb,timestamptz) TO postgres;
REVOKE ALL ON FUNCTION business.fnc_get_assignment_candidates(uuid,uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION business.fnc_get_assignment_candidates(uuid,uuid,uuid,uuid) TO postgres;

COMMIT;
