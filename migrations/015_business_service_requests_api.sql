-- Persist the customer-name snapshot required by the enterprise request form and expose
-- creation through a tenant- and permission-checked routine.
BEGIN;

ALTER TABLE business.service_request
    ADD COLUMN IF NOT EXISTS customer_name text;

CREATE OR REPLACE PROCEDURE business.prc_create_service_request(
    p_tenant_id uuid,
    p_actor_user_id uuid,
    p_actor_tenant_user_id uuid,
    p_customer_name text,
    p_origin_address text,
    p_origin_latitude numeric,
    p_origin_longitude numeric,
    p_destination_address text,
    p_destination_latitude numeric,
    p_destination_longitude numeric,
    p_scheduled_at timestamptz,
    p_passenger_count integer,
    p_agreed_fare_cop numeric,
    p_notes text,
    INOUT p_result jsonb
) LANGUAGE plpgsql AS $$
DECLARE
    v_can_write boolean;
    v_request_id uuid;
    v_created_at timestamptz;
BEGIN
    IF public.fnc_current_tenant() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'tenant context mismatch' USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(bool_or(p.code = 'services.write'), false)
      INTO v_can_write
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
      AND p.code = 'services.write';
    IF NOT v_can_write THEN
        RAISE EXCEPTION 'service write permission denied' USING ERRCODE = 'VT070';
    END IF;

    IF NULLIF(trim(p_customer_name), '') IS NULL
       OR NULLIF(trim(p_origin_address), '') IS NULL
       OR NULLIF(trim(p_destination_address), '') IS NULL
       OR p_origin_latitude IS NULL OR p_origin_longitude IS NULL
       OR p_destination_latitude IS NULL OR p_destination_longitude IS NULL
       OR p_scheduled_at IS NULL OR p_passenger_count IS NULL OR p_passenger_count < 1
       OR p_agreed_fare_cop IS NULL OR p_agreed_fare_cop < 0 THEN
        RAISE EXCEPTION 'invalid service request fields' USING ERRCODE = 'VT060';
    END IF;

    INSERT INTO business.service_request (
        tenant_id, customer_name, origin_address, origin_latitude, origin_longitude,
        destination_address, destination_latitude, destination_longitude,
        scheduled_at, passenger_count, agreed_fare_cop, notes
    ) VALUES (
        p_tenant_id, trim(p_customer_name), trim(p_origin_address), p_origin_latitude, p_origin_longitude,
        trim(p_destination_address), p_destination_latitude, p_destination_longitude,
        p_scheduled_at, p_passenger_count, p_agreed_fare_cop, NULLIF(trim(p_notes), '')
    ) RETURNING id, created_at INTO v_request_id, v_created_at;

    p_result := jsonb_build_object(
        'id', v_request_id,
        'customer_name', trim(p_customer_name),
        'origin_address', trim(p_origin_address),
        'origin_latitude', p_origin_latitude,
        'origin_longitude', p_origin_longitude,
        'destination_address', trim(p_destination_address),
        'destination_latitude', p_destination_latitude,
        'destination_longitude', p_destination_longitude,
        'scheduled_at', p_scheduled_at,
        'passenger_count', p_passenger_count,
        'agreed_fare_cop', p_agreed_fare_cop,
        'status', 'pending',
        'created_at', v_created_at
    );
END;
$$;

GRANT EXECUTE ON PROCEDURE business.prc_create_service_request(
    uuid, uuid, uuid, text, text, numeric, numeric, text, numeric, numeric,
    timestamptz, integer, numeric, text, jsonb
) TO postgres;

COMMIT;
