-- Token-authenticated business login and route request attribution.
-- Depends on migrations 001-012, including business.user and business.tenant_user.
-- Apply as the database owner; never place credentials in this migration.
BEGIN;

ALTER TABLE routing.route_request
    ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES business."user"(id);
ALTER TABLE routing.route_request
    ALTER COLUMN device_id DROP NOT NULL;
ALTER TABLE routing.route_request
    DROP CONSTRAINT IF EXISTS route_request_actor_check;
ALTER TABLE routing.route_request
    ADD CONSTRAINT route_request_actor_check
    CHECK (num_nonnulls(device_id, user_id) = 1);

GRANT USAGE ON SCHEMA business TO postgres;
GRANT SELECT ON business."user", business.tenant_user, business.role,
    business.tenant_user_role, business.role_permission, business.permission
TO postgres;
GRANT INSERT ON business."user", business.tenant_user,
    business.tenant_user_role TO postgres;

CREATE OR REPLACE PROCEDURE business.prc_create_user(
    p_tenant_id uuid,
    p_actor_user_id uuid,
    p_actor_tenant_user_id uuid,
    p_email text,
    p_full_name text,
    p_password_hash text,
    p_role_code text,
    INOUT p_result jsonb
) LANGUAGE plpgsql AS $$
DECLARE
    v_can_write boolean;
    v_can_assign_roles boolean;
    v_role_code text;
    v_role_id uuid;
    v_user_id uuid;
    v_tenant_user_id uuid;
BEGIN
    IF public.fnc_current_tenant() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'tenant context mismatch' USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(bool_or(p.code = 'users.write'), false),
           COALESCE(bool_or(p.code = 'users.assign_roles'), false)
    INTO v_can_write, v_can_assign_roles
    FROM business.tenant_user caller
    JOIN business."user" u ON u.id = caller.user_id
    JOIN business.tenant_user_role tur ON tur.tenant_user_id = caller.id
    JOIN business.role r ON r.id = tur.role_id
    JOIN business.role_permission rp ON rp.role_id = r.id
    JOIN business.permission p ON p.id = rp.permission_id
    WHERE caller.id = p_actor_tenant_user_id
      AND caller.user_id = p_actor_user_id
      AND caller.tenant_id = p_tenant_id
      AND caller.is_active
      AND u.is_active
      AND r.is_active
      AND (r.tenant_id IS NULL OR r.tenant_id = p_tenant_id)
      AND p.code IN ('users.write', 'users.assign_roles');
    IF NOT v_can_write THEN
        RAISE EXCEPTION 'user creation permission denied' USING ERRCODE = 'VT070';
    END IF;

    SELECT id, code INTO v_role_id, v_role_code
    FROM business.role
    WHERE code = p_role_code
      AND is_active
      AND (tenant_id IS NULL OR tenant_id = p_tenant_id)
    ORDER BY CASE WHEN tenant_id = p_tenant_id THEN 0 ELSE 1 END
    LIMIT 1;
    IF NOT FOUND OR v_role_code = 'super_admin' THEN
        RAISE EXCEPTION 'role cannot be assigned in this tenant' USING ERRCODE = 'VT071';
    END IF;
    IF v_role_code <> 'viewer' AND NOT v_can_assign_roles THEN
        RAISE EXCEPTION 'role assignment permission denied' USING ERRCODE = 'VT072';
    END IF;

    INSERT INTO business."user" (email, full_name, password_hash)
    VALUES (lower(trim(p_email)), trim(p_full_name), p_password_hash)
    RETURNING id INTO v_user_id;

    INSERT INTO business.tenant_user (tenant_id, user_id)
    VALUES (p_tenant_id, v_user_id)
    RETURNING id INTO v_tenant_user_id;

    INSERT INTO business.tenant_user_role (tenant_user_id, role_id)
    VALUES (v_tenant_user_id, v_role_id);

    p_result := jsonb_build_object(
        'id', v_user_id,
        'tenant_user_id', v_tenant_user_id,
        'role_code', v_role_code,
        'email', lower(trim(p_email)),
        'full_name', trim(p_full_name)
    );
END $$;

GRANT EXECUTE ON PROCEDURE business.prc_create_user(
    uuid, uuid, uuid, text, text, text, text, jsonb
) TO postgres;

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

    p_result := jsonb_build_object('route_cache_id', v_id, 'waypoints_hash', v_hash);
END $$;

CREATE OR REPLACE PROCEDURE routing.prc_record_business_route_hit(
    p_tenant_id uuid,
    p_user_id uuid,
    p_tenant_user_id uuid,
    p_route_cache_id bigint
) LANGUAGE plpgsql AS $$
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

    UPDATE routing.route_cache SET hit_count = hit_count + 1 WHERE id = p_route_cache_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'route cache entry not found' USING ERRCODE = 'P0002';
    END IF;
    INSERT INTO routing.route_request (tenant_id, user_id, route_cache_id, was_cache_hit)
    VALUES (p_tenant_id, p_user_id, p_route_cache_id, true);
END $$;

GRANT EXECUTE ON PROCEDURE routing.prc_store_business_route(
    uuid, uuid, uuid, jsonb, jsonb, numeric, int, text, jsonb, jsonb, jsonb
) TO postgres;
GRANT EXECUTE ON PROCEDURE routing.prc_record_business_route_hit(
    uuid, uuid, uuid, bigint
) TO postgres;

COMMIT;
