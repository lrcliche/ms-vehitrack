BEGIN;

-- A driver phone is not the same thing as the vehicle's dedicated telemetry unit.
-- Keep link intervals per driver/device so device telemetry history remains attributable.
CREATE TABLE IF NOT EXISTS business.driver_device (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenant(id),
    driver_id uuid NOT NULL,
    device_id uuid NOT NULL REFERENCES device.device(id),
    linked_by_tenant_user_id uuid NOT NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz,
    unassigned_at timestamptz,
    unassigned_by_tenant_user_id uuid,
    FOREIGN KEY (driver_id,tenant_id) REFERENCES business.driver(id,tenant_id),
    FOREIGN KEY (linked_by_tenant_user_id,tenant_id) REFERENCES business.tenant_user(id,tenant_id),
    FOREIGN KEY (unassigned_by_tenant_user_id,tenant_id) REFERENCES business.tenant_user(id,tenant_id),
    CHECK (unassigned_at IS NULL OR unassigned_at > assigned_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS driver_device_active_device_uidx
    ON business.driver_device(device_id) WHERE unassigned_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS driver_device_active_pair_uidx
    ON business.driver_device(driver_id,device_id) WHERE unassigned_at IS NULL;
CREATE INDEX IF NOT EXISTS driver_device_history_idx
    ON business.driver_device(tenant_id,driver_id,assigned_at DESC);
REVOKE ALL ON business.driver_device FROM PUBLIC;

CREATE OR REPLACE FUNCTION business.fnc_driver_me_attach_device(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_device_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business, device
AS $$
DECLARE v_driver_id uuid; v_existing_driver_id uuid; v_link_id uuid; v_inserted boolean := false;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    IF NOT EXISTS (SELECT 1 FROM device.device d WHERE d.id=p_device_id AND d.tenant_id=p_tenant_id) THEN
        RAISE EXCEPTION 'device is not registered in this tenant' USING ERRCODE='VT041';
    END IF;
    IF EXISTS (SELECT 1 FROM device.device d WHERE d.id=p_device_id AND d.tenant_id=p_tenant_id AND d.is_blocked) THEN
        RAISE EXCEPTION 'device is blocked' USING ERRCODE='VT002';
    END IF;
    IF EXISTS (SELECT 1 FROM business.vehicle_device vd WHERE vd.device_id=p_device_id AND vd.tenant_id=p_tenant_id AND vd.unassigned_at IS NULL) THEN
        RAISE EXCEPTION 'vehicle telemetry device cannot be linked as a driver phone' USING ERRCODE='VT076';
    END IF;
    SELECT dd.id,dd.driver_id INTO v_link_id,v_existing_driver_id
      FROM business.driver_device dd
     WHERE dd.device_id=p_device_id AND dd.unassigned_at IS NULL
     FOR UPDATE;
    IF FOUND THEN
        IF v_existing_driver_id<>v_driver_id THEN
            RAISE EXCEPTION 'device is already linked to another driver' USING ERRCODE='VT076';
        END IF;
        UPDATE business.driver_device SET last_seen_at=now() WHERE id=v_link_id;
        RETURN jsonb_build_object('linked',true,'already_linked',true,'link_id',v_link_id,'device_id',p_device_id);
    END IF;
    BEGIN
        INSERT INTO business.driver_device(tenant_id,driver_id,device_id,linked_by_tenant_user_id,assigned_at,last_seen_at)
        VALUES(p_tenant_id,v_driver_id,p_device_id,p_actor_tenant_user_id,now(),now())
        RETURNING id INTO v_link_id;
        v_inserted := true;
    EXCEPTION WHEN unique_violation THEN
        SELECT dd.id,dd.driver_id INTO v_link_id,v_existing_driver_id
          FROM business.driver_device dd
         WHERE dd.device_id=p_device_id AND dd.unassigned_at IS NULL;
        IF v_existing_driver_id IS DISTINCT FROM v_driver_id THEN
            RAISE EXCEPTION 'device is already linked to another driver' USING ERRCODE='VT076';
        END IF;
        UPDATE business.driver_device SET last_seen_at=now() WHERE id=v_link_id;
    END;
    RETURN jsonb_build_object('linked',true,'already_linked',NOT v_inserted,'link_id',v_link_id,'device_id',p_device_id);
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_driver_me_detach_device(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_device_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_driver_id uuid; v_count integer;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    UPDATE business.driver_device
       SET unassigned_at=now(),unassigned_by_tenant_user_id=p_actor_tenant_user_id
     WHERE tenant_id=p_tenant_id AND driver_id=v_driver_id AND device_id=p_device_id AND unassigned_at IS NULL;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    RETURN jsonb_build_object('detached',v_count>0,'device_id',p_device_id);
END;
$$;

-- Driver JWT + active driver_device link authorizes the phone. vehicle_device remains
-- exclusively for the vehicle's own installed tracker and is not changed by app login.
CREATE OR REPLACE FUNCTION business.fnc_driver_me_ingest_telemetry(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,
    p_device_id uuid,p_batch_id uuid,p_samples jsonb,p_client_created_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business, device, tracking
AS $$
DECLARE
    v_driver_id uuid;
    v_result jsonb;
    v_latitude double precision;
    v_longitude double precision;
    v_accuracy numeric;
    v_recorded_at timestamptz;
    v_location_updated boolean := false;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    UPDATE business.driver_device dd SET last_seen_at=now()
     WHERE dd.tenant_id=p_tenant_id AND dd.driver_id=v_driver_id AND dd.device_id=p_device_id
       AND dd.unassigned_at IS NULL
       AND EXISTS (SELECT 1 FROM device.device d WHERE d.id=dd.device_id AND d.tenant_id=p_tenant_id AND NOT d.is_blocked);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device is not linked to this driver' USING ERRCODE='VT080';
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

REVOKE ALL ON FUNCTION business.fnc_driver_me_attach_device(uuid,uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_driver_me_detach_device(uuid,uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_driver_me_ingest_telemetry(uuid,uuid,uuid,uuid,uuid,jsonb,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION business.fnc_driver_me_attach_device(uuid,uuid,uuid,uuid) TO postgres;
GRANT EXECUTE ON FUNCTION business.fnc_driver_me_detach_device(uuid,uuid,uuid,uuid) TO postgres;
GRANT EXECUTE ON FUNCTION business.fnc_driver_me_ingest_telemetry(uuid,uuid,uuid,uuid,uuid,jsonb,timestamptz) TO postgres;

COMMIT;
