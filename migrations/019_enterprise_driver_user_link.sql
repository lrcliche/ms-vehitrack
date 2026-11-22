BEGIN;

-- Extends the existing enterprise driver upsert with an optional same-tenant user link.
CREATE OR REPLACE PROCEDURE business.prc_upsert_enterprise_driver(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_driver jsonb,INOUT p_result jsonb
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE
    v_id uuid;
    v_status text;
    v_driver business.driver%ROWTYPE;
    v_tenant_user_id uuid;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'drivers.write');
    IF NULLIF(trim(p_driver->>'nombre_completo'),'') IS NULL OR COALESCE((p_driver->>'viatico_diario')::numeric,-1)<0 THEN
        RAISE EXCEPTION 'invalid driver fields' USING ERRCODE='VT060';
    END IF;
    v_status := CASE COALESCE(p_driver->>'estado','disponible') WHEN 'disponible' THEN 'available'
        WHEN 'descanso' THEN 'rest' WHEN 'inactivo' THEN 'inactive' ELSE NULL END;
    IF v_status IS NULL THEN RAISE EXCEPTION 'invalid driver status' USING ERRCODE='VT060'; END IF;
    IF NULLIF(p_driver->>'numero_licencia','') IS NULL AND
       (NULLIF(p_driver->>'categoria_licencia','') IS NOT NULL OR NULLIF(p_driver->>'vencimiento_licencia','') IS NOT NULL) THEN
        RAISE EXCEPTION 'license number is required with license details' USING ERRCODE='VT060';
    END IF;

    IF NULLIF(trim(p_driver->>'tenant_user_id'),'') IS NOT NULL THEN
        v_tenant_user_id := (p_driver->>'tenant_user_id')::uuid;
        IF NOT EXISTS (
            SELECT 1
              FROM business.tenant_user tu
              JOIN business."user" u ON u.id=tu.user_id
             WHERE tu.id=v_tenant_user_id AND tu.tenant_id=p_tenant_id
               AND tu.is_active AND u.is_active
        ) THEN
            RAISE EXCEPTION 'active tenant user not found' USING ERRCODE='VT052';
        END IF;
        IF NOT EXISTS (
            SELECT 1
              FROM business.tenant_user_role tur
              JOIN business.role r ON r.id=tur.role_id AND r.is_active
              JOIN business.tenant_user tu ON tu.id=tur.tenant_user_id
             WHERE tur.tenant_user_id=v_tenant_user_id AND tu.tenant_id=p_tenant_id
               AND r.code='driver' AND (r.tenant_id IS NULL OR r.tenant_id=p_tenant_id)
        ) THEN
            RAISE EXCEPTION 'tenant user does not have the driver role' USING ERRCODE='VT080';
        END IF;
    END IF;

    IF NULLIF(p_driver->>'id','') IS NULL THEN
        IF v_tenant_user_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM business.driver d WHERE d.tenant_id=p_tenant_id AND d.tenant_user_id=v_tenant_user_id
        ) THEN
            RAISE EXCEPTION 'tenant user is already linked to a driver' USING ERRCODE='VT076';
        END IF;
        INSERT INTO business.driver(tenant_id,tenant_user_id,full_name,identification_number,phone,license_number,license_category,
            license_expires_at,daily_allowance_cop,operational_status)
        VALUES(p_tenant_id,v_tenant_user_id,trim(p_driver->>'nombre_completo'),NULLIF(trim(p_driver->>'numero_identificacion'),''),
            NULLIF(trim(p_driver->>'telefono'),''),NULLIF(trim(p_driver->>'numero_licencia'),''),
            NULLIF(trim(p_driver->>'categoria_licencia'),''),NULLIF(p_driver->>'vencimiento_licencia','')::date,
            (p_driver->>'viatico_diario')::numeric,v_status) RETURNING * INTO v_driver;
    ELSE
        v_id := (p_driver->>'id')::uuid;
        SELECT * INTO v_driver FROM business.driver WHERE id=v_id AND tenant_id=p_tenant_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'driver not found' USING ERRCODE='VT052'; END IF;
        IF v_driver.operational_status='assigned' THEN RAISE EXCEPTION 'driver has an active assignment' USING ERRCODE='VT075'; END IF;
        IF v_tenant_user_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM business.driver d
             WHERE d.tenant_id=p_tenant_id AND d.tenant_user_id=v_tenant_user_id AND d.id<>v_id
        ) THEN
            RAISE EXCEPTION 'tenant user is already linked to a driver' USING ERRCODE='VT076';
        END IF;
        UPDATE business.driver SET tenant_user_id=COALESCE(v_tenant_user_id,tenant_user_id),
            full_name=trim(p_driver->>'nombre_completo'),
            identification_number=NULLIF(trim(p_driver->>'numero_identificacion'),''),phone=NULLIF(trim(p_driver->>'telefono'),''),
            license_number=NULLIF(trim(p_driver->>'numero_licencia'),''),license_category=NULLIF(trim(p_driver->>'categoria_licencia'),''),
            license_expires_at=NULLIF(p_driver->>'vencimiento_licencia','')::date,
            daily_allowance_cop=(p_driver->>'viatico_diario')::numeric,operational_status=v_status,updated_at=now()
         WHERE id=v_id AND tenant_id=p_tenant_id RETURNING * INTO v_driver;
    END IF;
    p_result := jsonb_build_object('id',v_driver.id,'nombre_completo',v_driver.full_name,
        'numero_identificacion',v_driver.identification_number,'telefono',v_driver.phone,'numero_licencia',v_driver.license_number,
        'categoria_licencia',v_driver.license_category,'vencimiento_licencia',v_driver.license_expires_at,
        'viatico_diario',v_driver.daily_allowance_cop,'estado',CASE v_driver.operational_status WHEN 'available' THEN 'disponible'
        WHEN 'assigned' THEN 'asignado' WHEN 'rest' THEN 'descanso' ELSE 'inactivo' END,
        'licencia_vigente',COALESCE(v_driver.license_expires_at >= CURRENT_DATE,false),
        'usuario_vinculado',v_driver.tenant_user_id IS NOT NULL,
        'observaciones',v_driver.operational_notes,'fecha_creacion',v_driver.created_at);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'driver license or account is already linked for tenant' USING ERRCODE='VT076';
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_list_enterprise_drivers(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,
    p_status text,p_search text,p_page integer,p_limit integer
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_status text; v_total integer; v_items jsonb;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'drivers.read');
    v_status := CASE p_status WHEN 'disponible' THEN 'available' WHEN 'asignado' THEN 'assigned'
        WHEN 'descanso' THEN 'rest' WHEN 'inactivo' THEN 'inactive' ELSE NULL END;
    IF p_status IS NOT NULL AND p_status<>'' AND v_status IS NULL THEN RAISE EXCEPTION 'invalid driver status' USING ERRCODE='VT060'; END IF;
    SELECT count(*) INTO v_total FROM business.driver d WHERE d.tenant_id=p_tenant_id
      AND d.is_active AND (p_status IS NULL OR p_status='' OR d.operational_status=v_status)
      AND (p_search IS NULL OR p_search='' OR d.full_name ILIKE '%'||p_search||'%' OR COALESCE(d.license_number,'') ILIKE '%'||p_search||'%');
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',q.id,'nombre_completo',q.full_name,'numero_identificacion',q.identification_number,'telefono',q.phone,
        'numero_licencia',q.license_number,'categoria_licencia',q.license_category,'vencimiento_licencia',q.license_expires_at,
        'viatico_diario',q.daily_allowance_cop,'estado',CASE q.operational_status WHEN 'available' THEN 'disponible'
        WHEN 'assigned' THEN 'asignado' WHEN 'rest' THEN 'descanso' ELSE 'inactivo' END,
        'licencia_vigente',COALESCE(q.license_expires_at >= CURRENT_DATE,false),
        'usuario_vinculado',q.tenant_user_id IS NOT NULL,
        'observaciones',q.operational_notes,'fecha_creacion',q.created_at
    ) ORDER BY q.full_name),'[]'::jsonb) INTO v_items FROM (
        SELECT d.* FROM business.driver d WHERE d.tenant_id=p_tenant_id AND d.is_active
          AND (p_status IS NULL OR p_status='' OR d.operational_status=v_status)
          AND (p_search IS NULL OR p_search='' OR d.full_name ILIKE '%'||p_search||'%' OR COALESCE(d.license_number,'') ILIKE '%'||p_search||'%')
        ORDER BY d.full_name OFFSET ((greatest(p_page,1)-1)*least(greatest(p_limit,1),100)) LIMIT least(greatest(p_limit,1),100)
    ) q;
    RETURN jsonb_build_object('elementos',v_items,'total',v_total,'pagina',greatest(p_page,1),'limite',least(greatest(p_limit,1),100));
END;
$$;

REVOKE ALL ON PROCEDURE business.prc_upsert_enterprise_driver(uuid,uuid,uuid,jsonb,jsonb) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE business.prc_upsert_enterprise_driver(uuid,uuid,uuid,jsonb,jsonb) TO postgres;
REVOKE ALL ON FUNCTION business.fnc_list_enterprise_drivers(uuid,uuid,uuid,text,text,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION business.fnc_list_enterprise_drivers(uuid,uuid,uuid,text,text,integer,integer) TO postgres;

COMMIT;
