-- Enterprise operational endpoints for API v2.
-- Go calls only these functions/procedures; table access and tenant checks stay in PostgreSQL.
-- Apply manually as vehitrack_owner after migrations 001-015.
BEGIN;

ALTER TABLE business.driver
    ADD COLUMN IF NOT EXISTS daily_allowance_cop numeric(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS operational_notes text;
ALTER TABLE business.vehicle
    ADD COLUMN IF NOT EXISTS status_reason text;
ALTER TABLE business.service_request
    ADD COLUMN IF NOT EXISTS status_reason text;
CREATE UNIQUE INDEX IF NOT EXISTS driver_tenant_license_uidx
    ON business.driver (tenant_id, lower(license_number))
    WHERE license_number IS NOT NULL;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'driver_daily_allowance_nonnegative'
          AND conrelid = 'business.driver'::regclass
    ) THEN
        ALTER TABLE business.driver
            ADD CONSTRAINT driver_daily_allowance_nonnegative
            CHECK (daily_allowance_cop >= 0);
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_assert_enterprise_permission(
    p_tenant_id uuid,
    p_actor_user_id uuid,
    p_actor_tenant_user_id uuid,
    p_permission text
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
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
        WHERE tu.id = p_actor_tenant_user_id
          AND tu.tenant_id = p_tenant_id AND tu.user_id = p_actor_user_id
          AND tu.is_active AND u.is_active AND r.is_active
          AND (r.tenant_id IS NULL OR r.tenant_id = p_tenant_id)
          AND p.code = p_permission
    ) THEN
        RAISE EXCEPTION 'enterprise permission denied: %', p_permission USING ERRCODE = 'VT080';
    END IF;
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_enterprise_dashboard_kpis(
    p_tenant_id uuid, p_actor_user_id uuid, p_actor_tenant_user_id uuid,
    p_from date, p_to date
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_result jsonb;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'services.read');
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'fleet.read');
    IF (p_from IS NULL) <> (p_to IS NULL) OR (p_from IS NOT NULL AND p_to < p_from) THEN
        RAISE EXCEPTION 'invalid date range' USING ERRCODE = 'VT060';
    END IF;
    SELECT jsonb_build_object(
        'vehiculos_total', count(*) FILTER (WHERE v.is_active),
        'vehiculos_disponibles', count(*) FILTER (WHERE v.is_active AND v.operational_status='available'),
        'vehiculos_en_servicio', count(*) FILTER (WHERE v.is_active AND v.operational_status='assigned')
    ) INTO v_result FROM business.vehicle v WHERE v.tenant_id=p_tenant_id;
    v_result := v_result || jsonb_build_object(
        'solicitudes_pendientes', (
            SELECT count(*) FROM business.service_request sr
            WHERE sr.tenant_id=p_tenant_id AND sr.status='pending'
              AND (p_from IS NULL OR sr.scheduled_at >= p_from::timestamptz)
              AND (p_to IS NULL OR sr.scheduled_at < (p_to + 1)::timestamptz)
        ),
        'recorridos_finalizados', (
            SELECT count(*) FROM business.service_execution e
            WHERE e.tenant_id=p_tenant_id AND e.status='completed'
              AND (p_from IS NULL OR e.ended_at >= p_from::timestamptz)
              AND (p_to IS NULL OR e.ended_at < (p_to + 1)::timestamptz)
        )
    );
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_enterprise_financial_summary(
    p_tenant_id uuid, p_actor_user_id uuid, p_actor_tenant_user_id uuid, p_period text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_start timestamptz; v_income numeric(14,2); v_estimated numeric(14,2); v_actual numeric(14,2);
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'reports.read');
    IF p_period NOT IN ('semana','mes','trimestre') THEN
        RAISE EXCEPTION 'invalid financial period' USING ERRCODE = 'VT060';
    END IF;
    v_start := CASE p_period
        WHEN 'semana' THEN date_trunc('week', now())
        WHEN 'mes' THEN date_trunc('month', now())
        ELSE date_trunc('quarter', now()) END;
    SELECT COALESCE(sum(COALESCE(p.actual_income_cop,0)),0),
           COALESCE(sum(COALESCE(p.estimated_cost_cop,0)),0),
           COALESCE(sum(COALESCE(p.actual_expense_cop,0)),0)
      INTO v_income,v_estimated,v_actual
    FROM business.service_profitability p
    JOIN business.service_execution e ON e.id=p.service_execution_id
    WHERE p.tenant_id=p_tenant_id AND e.status='completed' AND e.ended_at >= v_start;
    RETURN jsonb_build_object(
        'ingreso_total',v_income,'costo_estimado',v_estimated,'costo_real',v_actual,
        'margen_estimado',v_income-v_estimated,'margen_real',v_income-v_actual
    );
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_list_enterprise_vehicles(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,
    p_status text,p_min_capacity integer,p_search text,p_page integer,p_limit integer
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_status text; v_total integer; v_items jsonb;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'fleet.read');
    v_status := CASE p_status WHEN 'disponible' THEN 'available' WHEN 'en_servicio' THEN 'assigned'
        WHEN 'mantenimiento' THEN 'maintenance' WHEN 'inactivo' THEN 'inactive' ELSE NULL END;
    IF p_status IS NOT NULL AND p_status<>'' AND v_status IS NULL THEN RAISE EXCEPTION 'invalid vehicle status' USING ERRCODE='VT060'; END IF;
    SELECT count(*) INTO v_total FROM business.vehicle v
    LEFT JOIN business.dictionary_value dv ON dv.id=v.vehicle_type_id
    WHERE v.tenant_id=p_tenant_id AND (p_status IS NULL OR p_status='' OR v.operational_status=v_status)
      AND (p_min_capacity IS NULL OR v.passenger_capacity>=p_min_capacity)
      AND (p_search IS NULL OR p_search='' OR v.plate ILIKE '%'||p_search||'%' OR COALESCE(dv.name,'') ILIKE '%'||p_search||'%');
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',q.id,'placa',q.plate,'tipo',q.vehicle_type,'marca',q.brand,'modelo',q.model,
        'anio_modelo',q.model_year,'capacidad_pasajeros',q.passenger_capacity,
        'rendimiento_km_gal',q.fuel_efficiency_km_per_gallon,'costo_por_km',q.cost_per_km_cop,
        'costo_despacho',q.dispatch_cost_cop,'estado',CASE q.operational_status
            WHEN 'available' THEN 'disponible' WHEN 'assigned' THEN 'en_servicio'
            WHEN 'maintenance' THEN 'mantenimiento' ELSE 'inactivo' END,
        'motivo_estado',q.status_reason,'fecha_creacion',q.created_at
    ) ORDER BY q.plate), '[]'::jsonb) INTO v_items FROM (
        SELECT v.*,dv.code AS vehicle_type FROM business.vehicle v
        LEFT JOIN business.dictionary_value dv ON dv.id=v.vehicle_type_id
        WHERE v.tenant_id=p_tenant_id AND (p_status IS NULL OR p_status='' OR v.operational_status=v_status)
          AND (p_min_capacity IS NULL OR v.passenger_capacity>=p_min_capacity)
          AND (p_search IS NULL OR p_search='' OR v.plate ILIKE '%'||p_search||'%' OR COALESCE(dv.name,'') ILIKE '%'||p_search||'%')
        ORDER BY v.plate OFFSET ((greatest(p_page,1)-1)*least(greatest(p_limit,1),100)) LIMIT least(greatest(p_limit,1),100)
    ) q;
    RETURN jsonb_build_object('elementos',v_items,'total',v_total,'pagina',greatest(p_page,1),'limite',least(greatest(p_limit,1),100));
END;
$$;

CREATE OR REPLACE PROCEDURE business.prc_upsert_enterprise_vehicle(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_vehicle jsonb,INOUT p_result jsonb
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_id uuid; v_type_id uuid; v_status text; v_vehicle business.vehicle%ROWTYPE;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'fleet.write');
    IF NULLIF(trim(p_vehicle->>'placa'),'') IS NULL OR NULLIF(trim(p_vehicle->>'tipo'),'') IS NULL
       OR COALESCE((p_vehicle->>'capacidad_pasajeros')::integer,0)<1
       OR COALESCE((p_vehicle->>'costo_por_km')::numeric,-1)<0
       OR COALESCE((p_vehicle->>'costo_despacho')::numeric,-1)<0
       OR (p_vehicle ? 'rendimiento_km_gal' AND p_vehicle->>'rendimiento_km_gal' IS NOT NULL AND (p_vehicle->>'rendimiento_km_gal')::numeric<=0) THEN
        RAISE EXCEPTION 'invalid vehicle fields' USING ERRCODE='VT060';
    END IF;
    SELECT dv.id INTO v_type_id FROM business.dictionary_value dv
    JOIN business.dictionary d ON d.id=dv.dictionary_id
    WHERE d.code='vehicle_type' AND dv.is_active
      AND (lower(dv.code)=lower(trim(p_vehicle->>'tipo')) OR lower(dv.name)=lower(trim(p_vehicle->>'tipo')))
    LIMIT 1;
    IF v_type_id IS NULL THEN RAISE EXCEPTION 'unknown vehicle type' USING ERRCODE='VT060'; END IF;
    v_status := CASE COALESCE(p_vehicle->>'estado','disponible') WHEN 'disponible' THEN 'available'
        WHEN 'mantenimiento' THEN 'maintenance' WHEN 'inactivo' THEN 'inactive' ELSE NULL END;
    IF v_status IS NULL THEN RAISE EXCEPTION 'invalid vehicle status' USING ERRCODE='VT060'; END IF;
    IF NULLIF(p_vehicle->>'id','') IS NULL THEN
        INSERT INTO business.vehicle(tenant_id,plate,vehicle_type_id,brand,model,model_year,passenger_capacity,
            fuel_efficiency_km_per_gallon,cost_per_km_cop,dispatch_cost_cop,operational_status)
        VALUES(p_tenant_id,upper(trim(p_vehicle->>'placa')),v_type_id,NULLIF(trim(p_vehicle->>'marca'),''),
            NULLIF(trim(p_vehicle->>'modelo'),''),NULLIF(p_vehicle->>'anio_modelo','')::integer,
            (p_vehicle->>'capacidad_pasajeros')::integer,NULLIF(p_vehicle->>'rendimiento_km_gal','')::numeric,
            (p_vehicle->>'costo_por_km')::numeric,(p_vehicle->>'costo_despacho')::numeric,v_status)
        RETURNING * INTO v_vehicle;
    ELSE
        v_id := (p_vehicle->>'id')::uuid;
        SELECT * INTO v_vehicle FROM business.vehicle WHERE id=v_id AND tenant_id=p_tenant_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'vehicle not found' USING ERRCODE='VT052'; END IF;
        IF v_vehicle.operational_status='assigned' THEN RAISE EXCEPTION 'vehicle has an active assignment' USING ERRCODE='VT075'; END IF;
        UPDATE business.vehicle SET plate=upper(trim(p_vehicle->>'placa')),vehicle_type_id=v_type_id,
            brand=NULLIF(trim(p_vehicle->>'marca'),''),model=NULLIF(trim(p_vehicle->>'modelo'),''),
            model_year=NULLIF(p_vehicle->>'anio_modelo','')::integer,passenger_capacity=(p_vehicle->>'capacidad_pasajeros')::integer,
            fuel_efficiency_km_per_gallon=NULLIF(p_vehicle->>'rendimiento_km_gal','')::numeric,
            cost_per_km_cop=(p_vehicle->>'costo_por_km')::numeric,dispatch_cost_cop=(p_vehicle->>'costo_despacho')::numeric,
            operational_status=v_status,updated_at=now()
        WHERE id=v_id AND tenant_id=p_tenant_id RETURNING * INTO v_vehicle;
    END IF;
    SELECT jsonb_build_object('id',v.id,'placa',v.plate,'tipo',dv.code,'marca',v.brand,'modelo',v.model,
        'anio_modelo',v.model_year,'capacidad_pasajeros',v.passenger_capacity,
        'rendimiento_km_gal',v.fuel_efficiency_km_per_gallon,'costo_por_km',v.cost_per_km_cop,
        'costo_despacho',v.dispatch_cost_cop,'estado',CASE v.operational_status WHEN 'available' THEN 'disponible'
        WHEN 'assigned' THEN 'en_servicio' WHEN 'maintenance' THEN 'mantenimiento' ELSE 'inactivo' END,
        'motivo_estado',v.status_reason,'fecha_creacion',v.created_at)
    INTO p_result FROM business.vehicle v LEFT JOIN business.dictionary_value dv ON dv.id=v.vehicle_type_id WHERE v.id=v_vehicle.id;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'vehicle plate already exists for tenant' USING ERRCODE='VT076';
END;
$$;

CREATE OR REPLACE PROCEDURE business.prc_update_enterprise_vehicle_status(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_vehicle_id uuid,p_status text,p_reason text,INOUT p_result jsonb
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_status text; v_vehicle business.vehicle%ROWTYPE;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'fleet.write');
    v_status := CASE p_status WHEN 'disponible' THEN 'available' WHEN 'mantenimiento' THEN 'maintenance' WHEN 'inactivo' THEN 'inactive' ELSE NULL END;
    IF v_status IS NULL THEN RAISE EXCEPTION 'invalid vehicle status' USING ERRCODE='VT060'; END IF;
    SELECT * INTO v_vehicle FROM business.vehicle WHERE id=p_vehicle_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'vehicle not found' USING ERRCODE='VT052'; END IF;
    IF v_vehicle.operational_status='assigned' THEN RAISE EXCEPTION 'vehicle has an active assignment' USING ERRCODE='VT075'; END IF;
    UPDATE business.vehicle SET operational_status=v_status,status_reason=NULLIF(trim(p_reason),''),updated_at=now()
      WHERE id=p_vehicle_id AND tenant_id=p_tenant_id;
    SELECT jsonb_build_object('id',v.id,'placa',v.plate,'tipo',dv.code,'capacidad_pasajeros',v.passenger_capacity,
        'costo_por_km',v.cost_per_km_cop,'costo_despacho',v.dispatch_cost_cop,'estado',CASE v.operational_status
        WHEN 'available' THEN 'disponible' WHEN 'assigned' THEN 'en_servicio' WHEN 'maintenance' THEN 'mantenimiento' ELSE 'inactivo' END,
        'motivo_estado',v.status_reason,'fecha_creacion',v.created_at)
      INTO p_result FROM business.vehicle v LEFT JOIN business.dictionary_value dv ON dv.id=v.vehicle_type_id WHERE v.id=p_vehicle_id;
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

CREATE OR REPLACE PROCEDURE business.prc_upsert_enterprise_driver(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_driver jsonb,INOUT p_result jsonb
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_id uuid; v_status text; v_driver business.driver%ROWTYPE;
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
    IF NULLIF(p_driver->>'id','') IS NULL THEN
        INSERT INTO business.driver(tenant_id,full_name,identification_number,phone,license_number,license_category,
            license_expires_at,daily_allowance_cop,operational_status)
        VALUES(p_tenant_id,trim(p_driver->>'nombre_completo'),NULLIF(trim(p_driver->>'numero_identificacion'),''),
            NULLIF(trim(p_driver->>'telefono'),''),NULLIF(trim(p_driver->>'numero_licencia'),''),
            NULLIF(trim(p_driver->>'categoria_licencia'),''),NULLIF(p_driver->>'vencimiento_licencia','')::date,
            (p_driver->>'viatico_diario')::numeric,v_status) RETURNING * INTO v_driver;
    ELSE
        v_id := (p_driver->>'id')::uuid;
        SELECT * INTO v_driver FROM business.driver WHERE id=v_id AND tenant_id=p_tenant_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'driver not found' USING ERRCODE='VT052'; END IF;
        IF v_driver.operational_status='assigned' THEN RAISE EXCEPTION 'driver has an active assignment' USING ERRCODE='VT075'; END IF;
        UPDATE business.driver SET full_name=trim(p_driver->>'nombre_completo'),
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
        'observaciones',v_driver.operational_notes,'fecha_creacion',v_driver.created_at);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'driver license already exists for tenant' USING ERRCODE='VT076';
END;
$$;

CREATE OR REPLACE PROCEDURE business.prc_update_enterprise_driver_availability(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_driver_id uuid,p_status text,p_notes text,
    p_starts_at timestamptz,p_ends_at timestamptz,INOUT p_result jsonb
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_status text; v_schedule_status text; v_driver business.driver%ROWTYPE; v_window_id uuid;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'drivers.write');
    v_status := CASE p_status WHEN 'disponible' THEN 'available' WHEN 'descanso' THEN 'rest' WHEN 'inactivo' THEN 'inactive' ELSE NULL END;
    IF v_status IS NULL THEN RAISE EXCEPTION 'invalid driver status' USING ERRCODE='VT060'; END IF;
    IF (p_starts_at IS NULL)<>(p_ends_at IS NULL) OR (p_starts_at IS NOT NULL AND p_ends_at<=p_starts_at) THEN
        RAISE EXCEPTION 'invalid driver availability window' USING ERRCODE='VT060';
    END IF;
    SELECT * INTO v_driver FROM business.driver WHERE id=p_driver_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'driver not found' USING ERRCODE='VT052'; END IF;
    IF v_driver.operational_status='assigned' THEN RAISE EXCEPTION 'driver has an active assignment' USING ERRCODE='VT075'; END IF;
    IF p_starts_at IS NULL THEN
        UPDATE business.driver SET operational_status=v_status,operational_notes=NULLIF(trim(p_notes),''),updated_at=now()
          WHERE id=p_driver_id AND tenant_id=p_tenant_id RETURNING * INTO v_driver;
    ELSE
        v_schedule_status := CASE v_status WHEN 'available' THEN 'available' WHEN 'rest' THEN 'rest' ELSE 'unavailable' END;
        IF v_schedule_status<>'available' AND EXISTS(
            SELECT 1 FROM business.service_assignment a
            JOIN business.service_request sr ON sr.id=a.service_request_id AND sr.tenant_id=a.tenant_id
            WHERE a.tenant_id=p_tenant_id AND a.driver_id=p_driver_id AND a.status='confirmed'
              AND sr.scheduled_at>=p_starts_at AND sr.scheduled_at<p_ends_at
        ) THEN RAISE EXCEPTION 'driver has a confirmed assignment in this availability window' USING ERRCODE='VT075'; END IF;
        SELECT da.id INTO v_window_id FROM business.driver_availability da
          WHERE da.tenant_id=p_tenant_id AND da.driver_id=p_driver_id
            AND da.starts_at=p_starts_at AND da.ends_at=p_ends_at FOR UPDATE;
        IF v_window_id IS NULL AND EXISTS(
            SELECT 1 FROM business.driver_availability da
            WHERE da.tenant_id=p_tenant_id AND da.driver_id=p_driver_id
              AND da.starts_at<p_ends_at AND da.ends_at>p_starts_at
        ) THEN
            RAISE EXCEPTION 'availability window overlaps an existing shift' USING ERRCODE='VT075';
        END IF;
        IF v_window_id IS NULL THEN
            INSERT INTO business.driver_availability(tenant_id,driver_id,starts_at,ends_at,availability_status)
            VALUES(p_tenant_id,p_driver_id,p_starts_at,p_ends_at,v_schedule_status);
        ELSE
            UPDATE business.driver_availability SET availability_status=v_schedule_status
              WHERE id=v_window_id AND tenant_id=p_tenant_id;
        END IF;
        UPDATE business.driver SET operational_notes=NULLIF(trim(p_notes),''),updated_at=now()
          WHERE id=p_driver_id AND tenant_id=p_tenant_id RETURNING * INTO v_driver;
    END IF;
    p_result := jsonb_build_object('id',v_driver.id,'nombre_completo',v_driver.full_name,
        'numero_licencia',v_driver.license_number,'categoria_licencia',v_driver.license_category,
        'vencimiento_licencia',v_driver.license_expires_at,'viatico_diario',v_driver.daily_allowance_cop,
        'estado',CASE v_driver.operational_status WHEN 'available' THEN 'disponible' WHEN 'assigned' THEN 'asignado'
        WHEN 'rest' THEN 'descanso' ELSE 'inactivo' END,
        'licencia_vigente',COALESCE(v_driver.license_expires_at >= CURRENT_DATE,false),
        'observaciones',v_driver.operational_notes,'fecha_creacion',v_driver.created_at,
        'turno',CASE WHEN p_starts_at IS NULL THEN NULL ELSE jsonb_build_object(
            'desde',p_starts_at,'hasta',p_ends_at,'estado',p_status) END);
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_list_enterprise_requests(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,
    p_status text,p_service_date date,p_customer text,p_page integer,p_limit integer
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_status text; v_total integer; v_items jsonb;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'services.read');
    v_status := CASE p_status WHEN 'pendiente' THEN 'pending' WHEN 'asignada' THEN 'assigned'
        WHEN 'finalizada' THEN 'completed' WHEN 'cancelada' THEN 'cancelled' ELSE NULL END;
    IF p_status IS NOT NULL AND p_status<>'' AND v_status IS NULL THEN RAISE EXCEPTION 'invalid request status' USING ERRCODE='VT060'; END IF;
    SELECT count(*) INTO v_total FROM business.service_request sr WHERE sr.tenant_id=p_tenant_id
      AND (p_status IS NULL OR p_status='' OR sr.status=v_status)
      AND (p_service_date IS NULL OR sr.scheduled_at >= p_service_date::timestamptz AND sr.scheduled_at < (p_service_date+1)::timestamptz)
      AND (p_customer IS NULL OR p_customer='' OR COALESCE(sr.customer_name,'') ILIKE '%'||p_customer||'%');
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',q.id,'nombre_cliente',q.customer_name,
        'origen_direccion',q.origin_address,'origen_lat',q.origin_latitude,'origen_lng',q.origin_longitude,
        'destino_direccion',q.destination_address,'destino_lat',q.destination_latitude,'destino_lng',q.destination_longitude,
        'fecha_servicio',q.scheduled_at,'pasajeros',q.passenger_count,'tarifa_pactada',q.agreed_fare_cop,
        'estado',CASE q.status WHEN 'pending' THEN 'pendiente' WHEN 'assigned' THEN 'asignada'
        WHEN 'completed' THEN 'finalizada' ELSE 'cancelada' END,'motivo_estado',q.status_reason
    ) ORDER BY q.scheduled_at DESC),'[]'::jsonb) INTO v_items FROM (
        SELECT sr.* FROM business.service_request sr WHERE sr.tenant_id=p_tenant_id
          AND (p_status IS NULL OR p_status='' OR sr.status=v_status)
          AND (p_service_date IS NULL OR sr.scheduled_at >= p_service_date::timestamptz AND sr.scheduled_at < (p_service_date+1)::timestamptz)
          AND (p_customer IS NULL OR p_customer='' OR COALESCE(sr.customer_name,'') ILIKE '%'||p_customer||'%')
        ORDER BY sr.scheduled_at DESC OFFSET ((greatest(p_page,1)-1)*least(greatest(p_limit,1),100)) LIMIT least(greatest(p_limit,1),100)
    ) q;
    RETURN jsonb_build_object('elementos',v_items,'total',v_total,'pagina',greatest(p_page,1),'limite',least(greatest(p_limit,1),100));
END;
$$;

CREATE OR REPLACE PROCEDURE business.prc_change_enterprise_request_status(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_request_id uuid,p_status text,p_reason text,INOUT p_result jsonb
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_status text; v_request business.service_request%ROWTYPE;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'services.write');
    v_status := CASE p_status WHEN 'cancelada' THEN 'cancelled' WHEN 'finalizada' THEN 'completed' ELSE NULL END;
    IF v_status IS NULL THEN RAISE EXCEPTION 'invalid request status transition' USING ERRCODE='VT060'; END IF;
    SELECT * INTO v_request FROM business.service_request WHERE id=p_request_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'service request not found' USING ERRCODE='VT052'; END IF;
    IF v_status='cancelled' AND v_request.status<>'pending' THEN RAISE EXCEPTION 'only pending requests can be cancelled' USING ERRCODE='VT075'; END IF;
    IF v_status='completed' AND NOT EXISTS(SELECT 1 FROM business.service_execution e JOIN business.service_assignment a ON a.id=e.service_assignment_id
        WHERE a.service_request_id=p_request_id AND a.tenant_id=p_tenant_id AND e.status='completed') THEN
        RAISE EXCEPTION 'request can be finalized only after trip close' USING ERRCODE='VT075';
    END IF;
    UPDATE business.service_request SET status=v_status,status_reason=NULLIF(trim(p_reason),''),updated_at=now()
      WHERE id=p_request_id AND tenant_id=p_tenant_id RETURNING * INTO v_request;
    p_result := jsonb_build_object('id',v_request.id,'nombre_cliente',v_request.customer_name,
        'origen_direccion',v_request.origin_address,'origen_lat',v_request.origin_latitude,'origen_lng',v_request.origin_longitude,
        'destino_direccion',v_request.destination_address,'destino_lat',v_request.destination_latitude,'destino_lng',v_request.destination_longitude,
        'fecha_servicio',v_request.scheduled_at,'pasajeros',v_request.passenger_count,'tarifa_pactada',v_request.agreed_fare_cop,
        'estado',CASE v_request.status WHEN 'pending' THEN 'pendiente' WHEN 'assigned' THEN 'asignada' WHEN 'completed' THEN 'finalizada' ELSE 'cancelada' END,
        'motivo_estado',v_request.status_reason);
END;
$$;

CREATE OR REPLACE PROCEDURE business.prc_confirm_enterprise_assignment(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,
    p_request_id uuid,p_vehicle_id uuid,p_driver_id uuid,p_empty_km numeric,p_service_km numeric,
    p_estimated_duration_s numeric,p_reason text,INOUT p_result jsonb
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE
    v_request business.service_request%ROWTYPE;
    v_vehicle business.vehicle%ROWTYPE;
    v_driver business.driver%ROWTYPE;
    v_assignment_id uuid;
    v_execution_id uuid;
    v_cost numeric(14,2);
    v_margin numeric(14,2);
    v_driver_days integer;
    v_cost_breakdown jsonb;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'services.assign');
    IF p_empty_km IS NULL OR p_empty_km<0 OR p_service_km IS NULL OR p_service_km<=0 OR
       p_estimated_duration_s IS NULL OR p_estimated_duration_s<=0 THEN
        RAISE EXCEPTION 'invalid server route estimate' USING ERRCODE='VT060';
    END IF;
    SELECT * INTO v_request FROM business.service_request
      WHERE id=p_request_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'service request not found' USING ERRCODE='VT052'; END IF;
    IF v_request.status<>'pending' THEN RAISE EXCEPTION 'service request is not pending' USING ERRCODE='VT075'; END IF;
    SELECT * INTO v_vehicle FROM business.vehicle WHERE id=p_vehicle_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'vehicle not found' USING ERRCODE='VT052'; END IF;
    SELECT * INTO v_driver FROM business.driver WHERE id=p_driver_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'driver not found' USING ERRCODE='VT052'; END IF;
    IF NOT v_vehicle.is_active OR v_vehicle.operational_status<>'available' OR
       v_vehicle.passenger_capacity<v_request.passenger_count OR v_vehicle.cost_per_km_cop<=0 OR
       NOT v_driver.is_active OR v_driver.operational_status<>'available' OR
       NULLIF(trim(v_driver.license_number),'') IS NULL OR NULLIF(trim(v_driver.license_category),'') IS NULL OR
       v_driver.license_expires_at IS NULL OR v_driver.license_expires_at<v_request.scheduled_at::date THEN
        RAISE EXCEPTION 'vehicle or driver is not eligible for this request' USING ERRCODE='VT075';
    END IF;
    IF EXISTS(SELECT 1 FROM business.driver_availability da WHERE da.tenant_id=p_tenant_id AND da.driver_id=p_driver_id
        AND da.starts_at<=v_request.scheduled_at AND da.ends_at>v_request.scheduled_at
        AND da.availability_status IN ('unavailable','rest')) THEN
        RAISE EXCEPTION 'driver is unavailable at request time' USING ERRCODE='VT075';
    END IF;
    v_driver_days := greatest(1,ceil(p_estimated_duration_s/86400.0)::integer);
    v_cost := round((p_empty_km+p_service_km)*v_vehicle.cost_per_km_cop + v_vehicle.dispatch_cost_cop +
        v_driver.daily_allowance_cop*v_driver_days,2);
    v_margin := round(v_request.agreed_fare_cop-v_cost,2);
    v_cost_breakdown := jsonb_build_object(
        'costo_por_km_cop',v_vehicle.cost_per_km_cop,
        'km_vacios',p_empty_km,'km_servicio',p_service_km,
        'costo_kilometraje_cop',round((p_empty_km+p_service_km)*v_vehicle.cost_per_km_cop,2),
        'costo_despacho_cop',v_vehicle.dispatch_cost_cop,
        'viatico_diario_cop',v_driver.daily_allowance_cop,'dias_viatico',v_driver_days,
        'viatico_total_cop',v_driver.daily_allowance_cop*v_driver_days,
        'nota','Peajes y otros costos variables no se estiman si no tienen tarifa configurada.'
    );
    INSERT INTO business.service_assignment(tenant_id,service_request_id,vehicle_id,driver_id,
        estimated_empty_km,estimated_service_km,estimated_cost_cop,estimated_margin_cop,
        criteria_explanation,cost_breakdown,status,confirmed_at)
    VALUES(p_tenant_id,p_request_id,p_vehicle_id,p_driver_id,p_empty_km,p_service_km,v_cost,v_margin,
        NULLIF(trim(p_reason),''),v_cost_breakdown,'confirmed',now()) RETURNING id INTO v_assignment_id;
    INSERT INTO business.service_execution(tenant_id,service_assignment_id,started_at,registered_income_cop,status,notes)
    VALUES(p_tenant_id,v_assignment_id,now(),v_request.agreed_fare_cop,'in_progress',NULLIF(trim(p_reason),''))
    RETURNING id INTO v_execution_id;
    INSERT INTO business.service_trip(tenant_id,service_execution_id,distance_km)
    VALUES(p_tenant_id,v_execution_id,NULL);
    UPDATE business.vehicle SET operational_status='assigned',updated_at=now() WHERE id=p_vehicle_id AND tenant_id=p_tenant_id;
    UPDATE business.driver SET operational_status='assigned',updated_at=now() WHERE id=p_driver_id AND tenant_id=p_tenant_id;
    UPDATE business.service_request SET status='assigned',updated_at=now() WHERE id=p_request_id AND tenant_id=p_tenant_id;
    p_result := jsonb_build_object('asignacion_id',v_assignment_id,'estado','confirmada','costo_estimado',v_cost,
        'estado_vehiculo','en_servicio','estado_conductor','asignado','recorrido_id',v_execution_id,
        'detalle_costos',v_cost_breakdown);
END;
$$;

CREATE OR REPLACE PROCEDURE business.prc_close_enterprise_trip_expenses(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,
    p_assignment_id uuid,p_actual_km numeric,p_fuel_cop numeric,p_tolls_cop numeric,
    p_maintenance_cop numeric,p_driver_cop numeric,p_other_cop numeric,p_notes text,INOUT p_result jsonb
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE
    v_assignment business.service_assignment%ROWTYPE;
    v_execution business.service_execution%ROWTYPE;
    v_trip business.service_trip%ROWTYPE;
    v_request business.service_request%ROWTYPE;
    v_actual numeric(14,2);
    v_actual_margin numeric(14,2);
    v_income numeric(14,2);
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'services.close');
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'expenses.write');
    IF p_actual_km IS NULL OR p_actual_km<0 OR p_fuel_cop<0 OR p_tolls_cop<0 OR p_maintenance_cop<0 OR p_driver_cop<0 OR p_other_cop<0 THEN
        RAISE EXCEPTION 'invalid trip close amounts' USING ERRCODE='VT060';
    END IF;
    SELECT * INTO v_assignment FROM business.service_assignment
      WHERE id=p_assignment_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'assignment not found' USING ERRCODE='VT052'; END IF;
    SELECT * INTO v_execution FROM business.service_execution
      WHERE service_assignment_id=p_assignment_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND OR v_execution.status<>'in_progress' THEN RAISE EXCEPTION 'trip is not open' USING ERRCODE='VT075'; END IF;
    SELECT * INTO v_trip FROM business.service_trip
      WHERE service_execution_id=v_execution.id AND tenant_id=p_tenant_id AND trip_id IS NULL
      ORDER BY recorded_at LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'enterprise trip expense record missing' USING ERRCODE='VT075'; END IF;
    SELECT * INTO v_request FROM business.service_request WHERE id=v_assignment.service_request_id AND tenant_id=p_tenant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'service request not found' USING ERRCODE='VT052'; END IF;
    IF p_fuel_cop>0 THEN INSERT INTO business.trip_expense(tenant_id,service_trip_id,expense_type,amount_cop,description) VALUES(p_tenant_id,v_trip.id,'fuel',p_fuel_cop,NULLIF(trim(p_notes),'')); END IF;
    IF p_tolls_cop>0 THEN INSERT INTO business.trip_expense(tenant_id,service_trip_id,expense_type,amount_cop,description) VALUES(p_tenant_id,v_trip.id,'toll',p_tolls_cop,NULLIF(trim(p_notes),'')); END IF;
    IF p_maintenance_cop>0 THEN INSERT INTO business.trip_expense(tenant_id,service_trip_id,expense_type,amount_cop,description) VALUES(p_tenant_id,v_trip.id,'maintenance',p_maintenance_cop,NULLIF(trim(p_notes),'')); END IF;
    IF p_driver_cop>0 THEN INSERT INTO business.trip_expense(tenant_id,service_trip_id,expense_type,amount_cop,description) VALUES(p_tenant_id,v_trip.id,'driver',p_driver_cop,NULLIF(trim(p_notes),'')); END IF;
    IF p_other_cop>0 THEN INSERT INTO business.trip_expense(tenant_id,service_trip_id,expense_type,amount_cop,description) VALUES(p_tenant_id,v_trip.id,'other',p_other_cop,NULLIF(trim(p_notes),'')); END IF;
    UPDATE business.service_trip SET distance_km=p_actual_km WHERE id=v_trip.id AND tenant_id=p_tenant_id;
    UPDATE business.service_execution SET actual_distance_km=p_actual_km,ended_at=now(),status='completed',
        notes=COALESCE(NULLIF(trim(p_notes),''),notes),updated_at=now()
      WHERE id=v_execution.id AND tenant_id=p_tenant_id RETURNING * INTO v_execution;
    UPDATE business.service_request SET status='completed',updated_at=now()
      WHERE id=v_request.id AND tenant_id=p_tenant_id;
    UPDATE business.vehicle SET operational_status='available',updated_at=now()
      WHERE id=v_assignment.vehicle_id AND tenant_id=p_tenant_id AND operational_status='assigned';
    UPDATE business.driver SET operational_status='available',updated_at=now()
      WHERE id=v_assignment.driver_id AND tenant_id=p_tenant_id AND operational_status='assigned';
    SELECT COALESCE(sum(x.amount_cop),0) INTO v_actual FROM business.trip_expense x
      WHERE x.tenant_id=p_tenant_id AND x.service_trip_id=v_trip.id;
    v_income := COALESCE(v_execution.registered_income_cop,v_request.agreed_fare_cop,0);
    v_actual_margin := v_income-v_actual;
    p_result := jsonb_build_object('recorrido_id',v_execution.id,'tarifa_pactada',v_request.agreed_fare_cop,
        'costo_estimado',COALESCE(v_assignment.estimated_cost_cop,0),'costo_real',v_actual,
        'desviacion_costos',v_actual-COALESCE(v_assignment.estimated_cost_cop,0),
        'margen_real',v_actual_margin,
        'porcentaje_margen_real',CASE WHEN v_income>0 THEN round(v_actual_margin/v_income*100,2) ELSE 0 END);
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_enterprise_profitability_report(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,
    p_from date,p_to date,p_vehicle_id uuid,p_driver_id uuid,p_page integer,p_limit integer
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_total integer; v_rows jsonb; v_summary jsonb;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id,'reports.read');
    IF p_from IS NULL OR p_to IS NULL OR p_to<p_from THEN RAISE EXCEPTION 'invalid report date range' USING ERRCODE='VT060'; END IF;
    SELECT count(*) INTO v_total FROM business.service_execution e
    JOIN business.service_assignment a ON a.id=e.service_assignment_id AND a.tenant_id=e.tenant_id
    WHERE e.tenant_id=p_tenant_id AND e.status='completed'
      AND e.ended_at>=p_from::timestamptz AND e.ended_at<(p_to+1)::timestamptz
      AND (p_vehicle_id IS NULL OR a.vehicle_id=p_vehicle_id) AND (p_driver_id IS NULL OR a.driver_id=p_driver_id);
    SELECT jsonb_build_object(
        'tarifa_total',COALESCE(sum(COALESCE(p.actual_income_cop,0)),0),
        'costo_estimado_total',COALESCE(sum(COALESCE(p.estimated_cost_cop,0)),0),
        'costo_real_total',COALESCE(sum(COALESCE(p.actual_expense_cop,0)),0),
        'desviacion',COALESCE(sum(COALESCE(p.actual_expense_cop,0)-COALESCE(p.estimated_cost_cop,0)),0),
        'margen_estimado_total',COALESCE(sum(COALESCE(p.actual_income_cop,0)-COALESCE(p.estimated_cost_cop,0)),0),
        'margen_real_total',COALESCE(sum(COALESCE(p.actual_margin_cop,0)),0)
    ) INTO v_summary FROM business.service_profitability p
    JOIN business.service_execution e ON e.id=p.service_execution_id AND e.tenant_id=p.tenant_id
    JOIN business.service_assignment a ON a.id=e.service_assignment_id AND a.tenant_id=e.tenant_id
    WHERE p.tenant_id=p_tenant_id AND e.status='completed'
      AND e.ended_at>=p_from::timestamptz AND e.ended_at<(p_to+1)::timestamptz
      AND (p_vehicle_id IS NULL OR a.vehicle_id=p_vehicle_id) AND (p_driver_id IS NULL OR a.driver_id=p_driver_id);
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'solicitud_id',q.service_request_id,'vehiculo_id',q.vehicle_id,'placa',q.plate,
        'conductor_id',q.driver_id,'conductor',q.driver_name,'tarifa_pactada',q.agreed_fare_cop,
        'costo_estimado',COALESCE(q.estimated_cost_cop,0),'costo_real',COALESCE(q.actual_expense_cop,0),
        'desviacion_costos',COALESCE(q.actual_expense_cop,0)-COALESCE(q.estimated_cost_cop,0),
        'margen_estimado',COALESCE(q.actual_income_cop,0)-COALESCE(q.estimated_cost_cop,0),
        'margen_real',COALESCE(q.actual_margin_cop,0),'fecha_cierre',q.ended_at
    ) ORDER BY q.ended_at DESC),'[]'::jsonb) INTO v_rows FROM (
        SELECT a.service_request_id,a.vehicle_id,v.plate,a.driver_id,d.full_name AS driver_name,
            sr.agreed_fare_cop,p.estimated_cost_cop,p.actual_income_cop,p.actual_expense_cop,p.actual_margin_cop,e.ended_at
        FROM business.service_profitability p
        JOIN business.service_execution e ON e.id=p.service_execution_id AND e.tenant_id=p.tenant_id
        JOIN business.service_assignment a ON a.id=e.service_assignment_id AND a.tenant_id=e.tenant_id
        JOIN business.service_request sr ON sr.id=a.service_request_id AND sr.tenant_id=a.tenant_id
        JOIN business.vehicle v ON v.id=a.vehicle_id AND v.tenant_id=a.tenant_id
        JOIN business.driver d ON d.id=a.driver_id AND d.tenant_id=a.tenant_id
        WHERE p.tenant_id=p_tenant_id AND e.status='completed'
          AND e.ended_at>=p_from::timestamptz AND e.ended_at<(p_to+1)::timestamptz
          AND (p_vehicle_id IS NULL OR a.vehicle_id=p_vehicle_id) AND (p_driver_id IS NULL OR a.driver_id=p_driver_id)
        ORDER BY e.ended_at DESC OFFSET ((greatest(p_page,1)-1)*least(greatest(p_limit,1),100)) LIMIT least(greatest(p_limit,1),100)
    ) q;
    RETURN jsonb_build_object('resumen',v_summary,'recorridos',v_rows,'total',v_total,
        'pagina',greatest(p_page,1),'limite',least(greatest(p_limit,1),100));
END;
$$;

-- Preserve the v2 candidate contract while considering available drivers and vehicles
-- independently; return data required to estimate cost and validate license eligibility.
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
                'current_location',CASE WHEN loc.recorded_at IS NULL THEN NULL ELSE jsonb_build_object(
                    'latitude',loc.latitude,'longitude',loc.longitude,'recorded_at',loc.recorded_at
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

-- All exposed routines execute with the migration owner and perform explicit tenant/permission
-- checks. The runtime role receives EXECUTE only, not direct DML grants on business tables.
REVOKE ALL ON FUNCTION business.fnc_assert_enterprise_permission(uuid,uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_enterprise_dashboard_kpis(uuid,uuid,uuid,date,date) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_enterprise_financial_summary(uuid,uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_list_enterprise_vehicles(uuid,uuid,uuid,text,integer,text,integer,integer) FROM PUBLIC;
REVOKE ALL ON PROCEDURE business.prc_upsert_enterprise_vehicle(uuid,uuid,uuid,jsonb,jsonb) FROM PUBLIC;
REVOKE ALL ON PROCEDURE business.prc_update_enterprise_vehicle_status(uuid,uuid,uuid,uuid,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_list_enterprise_drivers(uuid,uuid,uuid,text,text,integer,integer) FROM PUBLIC;
REVOKE ALL ON PROCEDURE business.prc_upsert_enterprise_driver(uuid,uuid,uuid,jsonb,jsonb) FROM PUBLIC;
REVOKE ALL ON PROCEDURE business.prc_update_enterprise_driver_availability(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_list_enterprise_requests(uuid,uuid,uuid,text,date,text,integer,integer) FROM PUBLIC;
REVOKE ALL ON PROCEDURE business.prc_change_enterprise_request_status(uuid,uuid,uuid,uuid,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON PROCEDURE business.prc_confirm_enterprise_assignment(uuid,uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,text,jsonb) FROM PUBLIC;
REVOKE ALL ON PROCEDURE business.prc_close_enterprise_trip_expenses(uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_enterprise_profitability_report(uuid,uuid,uuid,date,date,uuid,uuid,integer,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_get_assignment_candidates(uuid,uuid,uuid,uuid) FROM PUBLIC;

GRANT USAGE ON SCHEMA business TO postgres;
GRANT EXECUTE ON FUNCTION business.fnc_assert_enterprise_permission(uuid,uuid,uuid,text),
    business.fnc_enterprise_dashboard_kpis(uuid,uuid,uuid,date,date),
    business.fnc_enterprise_financial_summary(uuid,uuid,uuid,text),
    business.fnc_list_enterprise_vehicles(uuid,uuid,uuid,text,integer,text,integer,integer),
    business.fnc_list_enterprise_drivers(uuid,uuid,uuid,text,text,integer,integer),
    business.fnc_list_enterprise_requests(uuid,uuid,uuid,text,date,text,integer,integer),
    business.fnc_enterprise_profitability_report(uuid,uuid,uuid,date,date,uuid,uuid,integer,integer),
    business.fnc_get_assignment_candidates(uuid,uuid,uuid,uuid)
TO postgres;
GRANT EXECUTE ON PROCEDURE business.prc_upsert_enterprise_vehicle(uuid,uuid,uuid,jsonb,jsonb),
    business.prc_update_enterprise_vehicle_status(uuid,uuid,uuid,uuid,text,text,jsonb),
    business.prc_upsert_enterprise_driver(uuid,uuid,uuid,jsonb,jsonb),
    business.prc_update_enterprise_driver_availability(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,jsonb),
    business.prc_change_enterprise_request_status(uuid,uuid,uuid,uuid,text,text,jsonb),
    business.prc_confirm_enterprise_assignment(uuid,uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,text,jsonb),
    business.prc_close_enterprise_trip_expenses(uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)
TO postgres;

COMMIT;

