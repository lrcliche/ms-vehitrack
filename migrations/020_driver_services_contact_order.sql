BEGIN;

CREATE OR REPLACE FUNCTION business.fnc_driver_me_services(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business, tracking
AS $$
DECLARE v_driver_id uuid; v_items jsonb;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    SELECT COALESCE(jsonb_agg(q.item ORDER BY q.scheduled_at DESC),'[]'::jsonb) INTO v_items
    FROM (
        SELECT sr.scheduled_at,
            jsonb_build_object(
                'id',sr.id,
                'codigo','SOL-'||to_char(sr.created_at,'YYYY')||'-'||upper(substr(replace(sr.id::text,'-',''),1,8)),
                'tipo','traslado','estado',CASE
                    WHEN sr.status='cancelled' OR a.status='cancelled' OR e.status='cancelled' THEN 'cancelado'
                    WHEN sr.status='completed' OR e.status='completed' THEN 'finalizado'
                    WHEN sr.scheduled_at>now() THEN 'programado'
                    WHEN e.status='in_progress' AND e.ended_at IS NULL THEN 'en_curso'
                    ELSE 'asignado' END,
                'origen_direccion',sr.origin_address,'destino_direccion',sr.destination_address,
                'programado_en',sr.scheduled_at,
                'iniciado_en',CASE WHEN sr.scheduled_at>now() THEN NULL ELSE e.started_at END,
                'pasajeros',sr.passenger_count,'placa',v.plate,
                'vehiculo_etiqueta',COALESCE(NULLIF(trim(concat_ws(' ',v.brand,v.model)),''),vdv.name,v.plate),
                'empresa',COALESCE(NULLIF(c.name,''),NULLIF(sr.customer_name,''),
                    NULLIF(cp.trade_name,''),NULLIF(cp.legal_name,''),t.name),
                'contacto_nombre',cc.name,'contacto_telefono',cc.phone,'contacto_email',cc.email,
                'instrucciones',sr.notes,'notas',e.notes,
                'origen',CASE WHEN sr.origin_latitude IS NULL OR sr.origin_longitude IS NULL THEN NULL
                    ELSE jsonb_build_object('lat',sr.origin_latitude,'lon',sr.origin_longitude) END,
                'destino',CASE WHEN sr.destination_latitude IS NULL OR sr.destination_longitude IS NULL THEN NULL
                    ELSE jsonb_build_object('lat',sr.destination_latitude,'lon',sr.destination_longitude) END,
                'distancia_km',COALESCE(e.actual_distance_km,gps.actual_km,a.estimated_service_km),
                'velocidad_promedio_kmh',gps.avg_speed_kmh
            ) AS item
        FROM business.service_assignment a
        JOIN business.service_request sr ON sr.id=a.service_request_id AND sr.tenant_id=a.tenant_id
        LEFT JOIN business.service_execution e ON e.service_assignment_id=a.id AND e.tenant_id=a.tenant_id
        JOIN business.vehicle v ON v.id=a.vehicle_id AND v.tenant_id=a.tenant_id
        LEFT JOIN business.dictionary_value vdv ON vdv.id=v.vehicle_type_id
        JOIN public.tenant t ON t.id=a.tenant_id
        LEFT JOIN business.company_profile cp ON cp.tenant_id=a.tenant_id
        LEFT JOIN business.customer c ON c.id=sr.customer_id AND c.tenant_id=sr.tenant_id
        LEFT JOIN LATERAL (
            SELECT cc0.name,cc0.phone,cc0.email FROM business.customer_contact cc0
            WHERE cc0.tenant_id=sr.tenant_id AND cc0.customer_id=sr.customer_id
            ORDER BY cc0.id LIMIT 1
        ) cc ON true
        LEFT JOIN LATERAL (
            SELECT SUM(COALESCE(st.distance_km,tr.distance_m/1000.0)) AS actual_km,
                   AVG(tr.avg_speed_kmh) AS avg_speed_kmh
            FROM business.service_trip st
            LEFT JOIN tracking.trip tr ON tr.id=st.trip_id AND tr.tenant_id=st.tenant_id
            WHERE st.service_execution_id=e.id AND st.tenant_id=a.tenant_id
        ) gps ON true
        WHERE a.tenant_id=p_tenant_id AND a.driver_id=v_driver_id AND a.status IN ('confirmed','cancelled')
    ) q;
    RETURN jsonb_build_object('elementos',v_items);
END;
$$;

REVOKE ALL ON FUNCTION business.fnc_driver_me_services(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION business.fnc_driver_me_services(uuid,uuid,uuid) TO postgres;

COMMIT;
