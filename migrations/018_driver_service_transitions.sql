BEGIN;

-- Driver self-service transitions are scoped to the JWT driver identity and tenant.
CREATE OR REPLACE FUNCTION business.fnc_driver_me_service_start(
    p_tenant_id uuid, p_actor_user_id uuid, p_actor_tenant_user_id uuid, p_service_request_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_driver_id uuid; v_assignment business.service_assignment%ROWTYPE;
        v_execution business.service_execution%ROWTYPE; v_result jsonb;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    SELECT a.* INTO v_assignment
      FROM business.service_assignment a
      JOIN business.service_request sr ON sr.id=a.service_request_id AND sr.tenant_id=a.tenant_id
     WHERE sr.id=p_service_request_id AND a.tenant_id=p_tenant_id
       AND a.driver_id=v_driver_id AND a.status='confirmed'
     FOR UPDATE OF a;
    IF NOT FOUND THEN RAISE EXCEPTION 'assigned service not found' USING ERRCODE='VT052'; END IF;
    SELECT e.* INTO v_execution FROM business.service_execution e
     WHERE e.service_assignment_id=v_assignment.id AND e.tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND OR v_execution.status<>'in_progress' OR v_execution.ended_at IS NOT NULL THEN
        RAISE EXCEPTION 'service cannot be started' USING ERRCODE='VT075';
    END IF;
    UPDATE business.service_execution SET started_at=COALESCE(started_at,now()),updated_at=now()
     WHERE id=v_execution.id AND tenant_id=p_tenant_id;
    SELECT item INTO v_result
      FROM jsonb_array_elements(business.fnc_driver_me_services(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id)->'elementos') AS x(item)
     WHERE item->>'id'=p_service_request_id::text;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_driver_me_service_finish(
    p_tenant_id uuid, p_actor_user_id uuid, p_actor_tenant_user_id uuid, p_service_request_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_driver_id uuid; v_assignment business.service_assignment%ROWTYPE;
        v_execution business.service_execution%ROWTYPE; v_result jsonb;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    SELECT a.* INTO v_assignment
      FROM business.service_assignment a
      JOIN business.service_request sr ON sr.id=a.service_request_id AND sr.tenant_id=a.tenant_id
     WHERE sr.id=p_service_request_id AND a.tenant_id=p_tenant_id
       AND a.driver_id=v_driver_id AND a.status='confirmed'
     FOR UPDATE OF a;
    IF NOT FOUND THEN RAISE EXCEPTION 'assigned service not found' USING ERRCODE='VT052'; END IF;
    SELECT e.* INTO v_execution FROM business.service_execution e
     WHERE e.service_assignment_id=v_assignment.id AND e.tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND OR v_execution.status<>'in_progress' OR v_execution.ended_at IS NOT NULL THEN
        RAISE EXCEPTION 'service is not in progress' USING ERRCODE='VT075';
    END IF;
    UPDATE business.service_execution SET ended_at=now(),status='completed',updated_at=now()
     WHERE id=v_execution.id AND tenant_id=p_tenant_id;
    UPDATE business.service_request SET status='completed',updated_at=now()
     WHERE id=p_service_request_id AND tenant_id=p_tenant_id;
    UPDATE business.vehicle SET operational_status='available',updated_at=now()
     WHERE id=v_assignment.vehicle_id AND tenant_id=p_tenant_id AND operational_status='assigned';
    UPDATE business.driver SET operational_status='available',updated_at=now()
     WHERE id=v_driver_id AND tenant_id=p_tenant_id AND operational_status='assigned';
    SELECT item INTO v_result
      FROM jsonb_array_elements(business.fnc_driver_me_services(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id)->'elementos') AS x(item)
     WHERE item->>'id'=p_service_request_id::text;
    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION business.fnc_driver_me_service_start(uuid,uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_driver_me_service_finish(uuid,uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
    business.fnc_driver_me_service_start(uuid,uuid,uuid,uuid),
    business.fnc_driver_me_service_finish(uuid,uuid,uuid,uuid)
TO postgres;

COMMIT;
