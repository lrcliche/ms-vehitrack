BEGIN;

CREATE OR REPLACE FUNCTION business.fnc_list_enterprise_trips(
    p_tenant_id uuid,
    p_actor_user_id uuid,
    p_actor_tenant_user_id uuid,
    p_from date,
    p_to date,
    p_status text,
    p_page integer,
    p_limit integer
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE
    v_total integer;
    v_trips jsonb;
BEGIN
    PERFORM business.fnc_assert_enterprise_permission(
        p_tenant_id, p_actor_user_id, p_actor_tenant_user_id, 'services.read'
    );
    IF (p_from IS NULL) <> (p_to IS NULL)
       OR (p_from IS NOT NULL AND p_to < p_from)
       OR (p_status IS NOT NULL AND p_status NOT IN ('en_curso', 'finalizado'))
       OR p_page < 1 OR p_limit < 1 OR p_limit > 100 THEN
        RAISE EXCEPTION 'invalid enterprise trip list filter' USING ERRCODE = 'VT060';
    END IF;

    WITH trips AS (
        SELECT e.id AS execution_id,
               a.id AS assignment_id,
               sr.id AS request_id,
               sr.origin_address,
               sr.destination_address,
               v.id AS vehicle_id,
               v.plate,
               d.id AS driver_id,
               d.full_name AS driver_name,
               CASE e.status WHEN 'in_progress' THEN 'en_curso' ELSE 'finalizado' END AS trip_status,
               COALESCE(e.started_at, a.confirmed_at, a.assigned_at) AS started_at,
               e.ended_at,
               sr.agreed_fare_cop AS agreed_fare,
               COALESCE(a.estimated_cost_cop, 0) AS estimated_cost,
               e.actual_distance_km,
               e.registered_income_cop,
               COALESCE(exp.fuel_cop, 0) AS fuel_cop,
               COALESCE(exp.tolls_cop, 0) AS tolls_cop,
               COALESCE(exp.maintenance_cop, 0) AS maintenance_cop,
               COALESCE(exp.driver_cop, 0) AS driver_cop,
               COALESCE(exp.other_cop, 0) AS other_cop,
               COALESCE(exp.actual_cost, 0) AS actual_cost
        FROM business.service_execution e
        JOIN business.service_assignment a
          ON a.id = e.service_assignment_id AND a.tenant_id = e.tenant_id
        JOIN business.service_request sr
          ON sr.id = a.service_request_id AND sr.tenant_id = a.tenant_id
        JOIN business.vehicle v ON v.id = a.vehicle_id AND v.tenant_id = a.tenant_id
        JOIN business.driver d ON d.id = a.driver_id AND d.tenant_id = a.tenant_id
        LEFT JOIN LATERAL (
            SELECT id FROM business.service_trip
            WHERE service_execution_id = e.id AND tenant_id = e.tenant_id AND trip_id IS NULL
            ORDER BY recorded_at, id LIMIT 1
        ) st ON true
        LEFT JOIN LATERAL (
            SELECT sum(x.amount_cop) FILTER (WHERE x.expense_type = 'fuel') AS fuel_cop,
                   sum(x.amount_cop) FILTER (WHERE x.expense_type = 'toll') AS tolls_cop,
                   sum(x.amount_cop) FILTER (WHERE x.expense_type = 'maintenance') AS maintenance_cop,
                   sum(x.amount_cop) FILTER (WHERE x.expense_type = 'driver') AS driver_cop,
                   sum(x.amount_cop) FILTER (WHERE x.expense_type = 'other') AS other_cop,
                   sum(x.amount_cop) AS actual_cost
            FROM business.trip_expense x
            WHERE x.tenant_id = e.tenant_id AND x.service_trip_id = st.id
        ) exp ON true
        WHERE e.tenant_id = p_tenant_id
          AND a.status = 'confirmed'
          AND e.status IN ('in_progress', 'completed')
          AND (p_from IS NULL OR COALESCE(e.started_at, a.confirmed_at, a.assigned_at) >= p_from::timestamptz)
          AND (p_to IS NULL OR COALESCE(e.started_at, a.confirmed_at, a.assigned_at) < (p_to + 1)::timestamptz)
          AND (p_status IS NULL OR
               (p_status = 'en_curso' AND e.status = 'in_progress') OR
               (p_status = 'finalizado' AND e.status = 'completed'))
    )
    SELECT count(*)::integer INTO v_total FROM trips;

    WITH trips AS (
        SELECT e.id AS execution_id,
               a.id AS assignment_id,
               sr.id AS request_id,
               sr.origin_address,
               sr.destination_address,
               v.id AS vehicle_id,
               v.plate,
               d.id AS driver_id,
               d.full_name AS driver_name,
               e.status AS execution_status,
               COALESCE(e.started_at, a.confirmed_at, a.assigned_at) AS started_at,
               e.ended_at,
               sr.agreed_fare_cop AS agreed_fare,
               COALESCE(a.estimated_cost_cop, 0) AS estimated_cost,
               e.actual_distance_km,
               COALESCE(e.registered_income_cop, sr.agreed_fare_cop, 0) AS actual_income,
               COALESCE(exp.fuel_cop, 0) AS fuel_cop,
               COALESCE(exp.tolls_cop, 0) AS tolls_cop,
               COALESCE(exp.maintenance_cop, 0) AS maintenance_cop,
               COALESCE(exp.driver_cop, 0) AS driver_cop,
               COALESCE(exp.other_cop, 0) AS other_cop,
               COALESCE(exp.actual_cost, 0) AS actual_cost
        FROM business.service_execution e
        JOIN business.service_assignment a
          ON a.id = e.service_assignment_id AND a.tenant_id = e.tenant_id
        JOIN business.service_request sr
          ON sr.id = a.service_request_id AND sr.tenant_id = a.tenant_id
        JOIN business.vehicle v ON v.id = a.vehicle_id AND v.tenant_id = a.tenant_id
        JOIN business.driver d ON d.id = a.driver_id AND d.tenant_id = a.tenant_id
        LEFT JOIN LATERAL (
            SELECT id FROM business.service_trip
            WHERE service_execution_id = e.id AND tenant_id = e.tenant_id AND trip_id IS NULL
            ORDER BY recorded_at, id LIMIT 1
        ) st ON true
        LEFT JOIN LATERAL (
            SELECT sum(x.amount_cop) FILTER (WHERE x.expense_type = 'fuel') AS fuel_cop,
                   sum(x.amount_cop) FILTER (WHERE x.expense_type = 'toll') AS tolls_cop,
                   sum(x.amount_cop) FILTER (WHERE x.expense_type = 'maintenance') AS maintenance_cop,
                   sum(x.amount_cop) FILTER (WHERE x.expense_type = 'driver') AS driver_cop,
                   sum(x.amount_cop) FILTER (WHERE x.expense_type = 'other') AS other_cop,
                   sum(x.amount_cop) AS actual_cost
            FROM business.trip_expense x
            WHERE x.tenant_id = e.tenant_id AND x.service_trip_id = st.id
        ) exp ON true
        WHERE e.tenant_id = p_tenant_id
          AND a.status = 'confirmed'
          AND e.status IN ('in_progress', 'completed')
          AND (p_from IS NULL OR COALESCE(e.started_at, a.confirmed_at, a.assigned_at) >= p_from::timestamptz)
          AND (p_to IS NULL OR COALESCE(e.started_at, a.confirmed_at, a.assigned_at) < (p_to + 1)::timestamptz)
          AND (p_status IS NULL OR
               (p_status = 'en_curso' AND e.status = 'in_progress') OR
               (p_status = 'finalizado' AND e.status = 'completed'))
    ), page_rows AS (
        SELECT * FROM trips
        ORDER BY started_at DESC, execution_id DESC
        OFFSET ((p_page - 1) * p_limit) LIMIT p_limit
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', execution_id,
            'codigo', 'REC-' || upper(left(replace(execution_id::text, '-', ''), 8)),
            'asignacion_id', assignment_id,
            'solicitud_codigo', 'SOL-' || upper(left(replace(request_id::text, '-', ''), 8)),
            'origen', origin_address,
            'destino', destination_address,
            'vehiculo_id', vehicle_id,
            'placa', plate,
            'conductor_id', driver_id,
            'conductor_codigo', 'CON-' || upper(left(replace(driver_id::text, '-', ''), 8)),
            'conductor_nombre', driver_name,
            'estado', CASE execution_status WHEN 'in_progress' THEN 'en_curso' ELSE 'finalizado' END,
            'fecha_inicio', started_at,
            'fecha_fin', ended_at,
            'tarifa_pactada', agreed_fare,
            'costo_estimado', estimated_cost,
            'margen_estimado', agreed_fare - estimated_cost
        ) || CASE WHEN execution_status = 'completed' THEN jsonb_build_object(
            'km_reales', actual_distance_km,
            'costo_real', actual_cost,
            'desviacion_costos', actual_cost - estimated_cost,
            'margen_real', actual_income - actual_cost,
            'gastos', jsonb_build_object(
                'costo_combustible', fuel_cop,
                'costo_peajes', tolls_cop,
                'costo_mantenimiento', maintenance_cop,
                'costo_conductor', driver_cop,
                'otros_gastos', other_cop
            )
        ) ELSE '{}'::jsonb END
        ORDER BY started_at DESC, execution_id DESC
    ), '[]'::jsonb) INTO v_trips
    FROM page_rows;

    RETURN jsonb_build_object(
        'elementos', v_trips,
        'total', v_total,
        'pagina', p_page,
        'limite', p_limit
    );
END;
$$;

REVOKE ALL ON FUNCTION business.fnc_list_enterprise_trips(uuid,uuid,uuid,date,date,text,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION business.fnc_list_enterprise_trips(uuid,uuid,uuid,date,date,text,integer,integer) TO postgres;

COMMIT;
