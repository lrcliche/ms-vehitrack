-- Driver App self-service reads. The driver identity is the business.driver row linked
-- to the authenticated business.tenant_user in the v2 JWT.
BEGIN;

CREATE OR REPLACE FUNCTION business.fnc_assert_driver_identity(
    p_tenant_id uuid,
    p_actor_user_id uuid,
    p_actor_tenant_user_id uuid
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_driver_id uuid;
BEGIN
    IF public.fnc_current_tenant() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'tenant context mismatch' USING ERRCODE='42501';
    END IF;
    SELECT d.id INTO v_driver_id
    FROM business.driver d
    JOIN business.tenant_user tu ON tu.id=d.tenant_user_id AND tu.tenant_id=d.tenant_id
    JOIN business."user" u ON u.id=tu.user_id
    WHERE d.tenant_id=p_tenant_id AND tu.id=p_actor_tenant_user_id
      AND tu.user_id=p_actor_user_id AND tu.is_active AND u.is_active AND d.is_active;
    IF v_driver_id IS NULL THEN
        RAISE EXCEPTION 'authenticated user is not an active driver' USING ERRCODE='VT080';
    END IF;
    RETURN v_driver_id;
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_driver_me(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_driver_id uuid; v_result jsonb;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    SELECT jsonb_build_object(
        'id',d.id,'nombre_completo',d.full_name,'email',u.email,'telefono',d.phone,
        'empresa',COALESCE(NULLIF(cp.trade_name,''),NULLIF(cp.legal_name,''),t.name),
        'estado',CASE d.operational_status WHEN 'available' THEN 'disponible' WHEN 'assigned' THEN 'asignado'
            WHEN 'rest' THEN 'descanso' ELSE 'inactivo' END,
        'numero_licencia',d.license_number,'categoria_licencia',d.license_category,
        'vencimiento_licencia',d.license_expires_at,
        'licencia_vigente',COALESCE(d.license_expires_at>=CURRENT_DATE,false),
        'foto_url',NULL,
        'vehiculo_asignado',CASE WHEN v.id IS NULL THEN NULL ELSE jsonb_build_object(
            'id',v.id,'placa',v.plate,
            'etiqueta',COALESCE(NULLIF(trim(concat_ws(' ',v.brand,v.model)),''),dv.name,v.plate),
            'tipo',dv.name,'capacidad_pasajeros',v.passenger_capacity
        ) END
    ) INTO v_result
    FROM business.driver d
    JOIN business.tenant_user tu ON tu.id=d.tenant_user_id AND tu.tenant_id=d.tenant_id
    JOIN business."user" u ON u.id=tu.user_id
    JOIN public.tenant t ON t.id=d.tenant_id
    LEFT JOIN business.company_profile cp ON cp.tenant_id=d.tenant_id
    LEFT JOIN LATERAL (
        SELECT chosen.vehicle_id
        FROM (
            SELECT a.vehicle_id,0 AS priority,a.confirmed_at AS assigned_at
            FROM business.service_assignment a
            JOIN business.service_execution e ON e.service_assignment_id=a.id AND e.tenant_id=a.tenant_id
            WHERE a.tenant_id=d.tenant_id AND a.driver_id=d.id AND a.status='confirmed'
              AND e.status='in_progress' AND e.ended_at IS NULL
            UNION ALL
            SELECT dvh.vehicle_id,1,dvh.assigned_at
            FROM business.driver_vehicle dvh
            WHERE dvh.tenant_id=d.tenant_id AND dvh.driver_id=d.id AND dvh.unassigned_at IS NULL
        ) chosen
        ORDER BY chosen.priority,chosen.assigned_at DESC NULLS LAST
        LIMIT 1
    ) assigned ON true
    LEFT JOIN business.vehicle v ON v.id=assigned.vehicle_id AND v.tenant_id=d.tenant_id AND v.is_active
    LEFT JOIN business.dictionary_value dv ON dv.id=v.vehicle_type_id AND dv.is_active
    WHERE d.id=v_driver_id;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_driver_me_documents(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_owner text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_driver_id uuid; v_items jsonb;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    IF p_owner IS NULL OR p_owner NOT IN ('conductor','vehiculo') THEN
        RAISE EXCEPTION 'owner must be conductor or vehiculo' USING ERRCODE='VT060';
    END IF;
    WITH assigned_vehicle AS (
        SELECT chosen.vehicle_id FROM (
            SELECT a.vehicle_id,0 AS priority,a.confirmed_at AS assigned_at
            FROM business.service_assignment a
            JOIN business.service_execution e ON e.service_assignment_id=a.id AND e.tenant_id=a.tenant_id
            WHERE a.tenant_id=p_tenant_id AND a.driver_id=v_driver_id AND a.status='confirmed'
              AND e.status='in_progress' AND e.ended_at IS NULL
            UNION ALL
            SELECT dvh.vehicle_id,1,dvh.assigned_at FROM business.driver_vehicle dvh
            WHERE dvh.tenant_id=p_tenant_id AND dvh.driver_id=v_driver_id AND dvh.unassigned_at IS NULL
        ) chosen ORDER BY chosen.priority,chosen.assigned_at DESC NULLS LAST LIMIT 1
    ), docs AS (
        SELECT 'conductor'::text AS owner,dd.id,COALESCE(dv.code,'otro') AS type,
            COALESCE(dv.name,dd.file_name) AS label,dd.document_number AS number,
            dd.issued_at AS issued,dd.expires_at AS expires,dd.storage_key,dd.uploaded_at
        FROM business.driver_document dd
        LEFT JOIN business.dictionary_value dv ON dv.id=dd.document_type_id
        WHERE p_owner='conductor' AND dd.tenant_id=p_tenant_id AND dd.driver_id=v_driver_id
        UNION ALL
        SELECT 'vehiculo'::text,vd.id,COALESCE(dv.code,'otro'),COALESCE(dv.name,vd.file_name),
            vd.document_number,vd.issued_at,vd.expires_at,vd.storage_key,vd.uploaded_at
        FROM assigned_vehicle av
        JOIN business.vehicle_document vd ON vd.vehicle_id=av.vehicle_id AND vd.tenant_id=p_tenant_id
        LEFT JOIN business.dictionary_value dv ON dv.id=vd.document_type_id
        WHERE p_owner='vehiculo'
        UNION ALL
        SELECT 'conductor',d.id,'driving_license','Licencia de conducción',d.license_number,
            NULL::date,d.license_expires_at,NULL::text,d.updated_at
        FROM business.driver d
        WHERE p_owner='conductor' AND d.id=v_driver_id AND d.license_number IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM business.driver_document dd
              JOIN business.dictionary_value dv ON dv.id=dd.document_type_id
              JOIN business.dictionary dic ON dic.id=dv.dictionary_id
              WHERE dd.tenant_id=p_tenant_id AND dd.driver_id=v_driver_id
                AND dic.code='driver_document_type' AND dv.code='driving_license'
          )
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',x.id,'tipo',x.type,'etiqueta',x.label,'numero_documento',x.number,
        'emitido_el',x.issued,'vence_el',x.expires,
        'vigencia',CASE WHEN x.expires IS NULL THEN 'pendiente'
            WHEN x.expires<CURRENT_DATE THEN 'vencido'
            WHEN x.expires<=CURRENT_DATE+30 THEN 'por_vencer' ELSE 'vigente' END,
        'tiene_adjunto',NULLIF(trim(x.storage_key),'') IS NOT NULL,
        'url_adjunto',CASE WHEN NULLIF(trim(x.storage_key),'') IS NULL THEN NULL ELSE
            '/api/v2/drivers/me/documents/'||x.owner||'/'||x.id::text||'/file' END
    ) ORDER BY x.uploaded_at DESC,x.label),'[]'::jsonb) INTO v_items FROM docs x;
    RETURN jsonb_build_object('elementos',v_items);
END;
$$;

CREATE OR REPLACE FUNCTION business.fnc_driver_me_document_file(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_owner text,p_document_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business
AS $$
DECLARE v_driver_id uuid; v_result jsonb;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    IF p_owner='conductor' THEN
        SELECT jsonb_build_object('storage_key',dd.storage_key,'file_name',dd.file_name)
          INTO v_result FROM business.driver_document dd
         WHERE dd.id=p_document_id AND dd.tenant_id=p_tenant_id AND dd.driver_id=v_driver_id;
    ELSIF p_owner='vehiculo' THEN
        SELECT jsonb_build_object('storage_key',vd.storage_key,'file_name',vd.file_name)
          INTO v_result FROM business.vehicle_document vd
         WHERE vd.id=p_document_id AND vd.tenant_id=p_tenant_id
           AND (
             EXISTS (SELECT 1 FROM business.service_assignment a
                     JOIN business.service_execution e ON e.service_assignment_id=a.id AND e.tenant_id=a.tenant_id
                     WHERE a.tenant_id=p_tenant_id AND a.driver_id=v_driver_id AND a.vehicle_id=vd.vehicle_id
                       AND a.status='confirmed' AND e.status='in_progress' AND e.ended_at IS NULL)
             OR EXISTS (SELECT 1 FROM business.driver_vehicle dvh
                        WHERE dvh.tenant_id=p_tenant_id AND dvh.driver_id=v_driver_id
                          AND dvh.vehicle_id=vd.vehicle_id AND dvh.unassigned_at IS NULL)
           );
    ELSE
        RAISE EXCEPTION 'owner must be conductor or vehiculo' USING ERRCODE='VT060';
    END IF;
    IF v_result IS NULL THEN RAISE EXCEPTION 'driver document not found' USING ERRCODE='VT052'; END IF;
    RETURN v_result;
END;
$$;

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

CREATE OR REPLACE FUNCTION business.fnc_driver_me_day_summary(
    p_tenant_id uuid,p_actor_user_id uuid,p_actor_tenant_user_id uuid,p_date date
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, business, tracking
AS $$
DECLARE
    v_driver_id uuid; v_from timestamptz; v_to timestamptz;
    v_services integer; v_km numeric; v_hours numeric; v_active uuid; v_next uuid;
BEGIN
    v_driver_id := business.fnc_assert_driver_identity(p_tenant_id,p_actor_user_id,p_actor_tenant_user_id);
    IF p_date IS NULL THEN RAISE EXCEPTION 'date is required' USING ERRCODE='VT060'; END IF;
    v_from := p_date::timestamp AT TIME ZONE 'America/Bogota';
    v_to := (p_date+1)::timestamp AT TIME ZONE 'America/Bogota';
    WITH rows AS (
        SELECT a.id AS assignment_id,sr.id AS request_id,sr.scheduled_at,e.id AS execution_id,
            e.started_at,e.ended_at,e.status,
            COALESCE(e.actual_distance_km,gps.actual_km) AS actual_km
        FROM business.service_assignment a
        JOIN business.service_request sr ON sr.id=a.service_request_id AND sr.tenant_id=a.tenant_id
        LEFT JOIN business.service_execution e ON e.service_assignment_id=a.id AND e.tenant_id=a.tenant_id
        LEFT JOIN LATERAL (
            SELECT SUM(COALESCE(st.distance_km,tr.distance_m/1000.0)) AS actual_km
            FROM business.service_trip st
            LEFT JOIN tracking.trip tr ON tr.id=st.trip_id AND tr.tenant_id=st.tenant_id
            WHERE st.service_execution_id=e.id AND st.tenant_id=a.tenant_id
        ) gps ON true
        WHERE a.tenant_id=p_tenant_id AND a.driver_id=v_driver_id
          AND a.status='confirmed' AND sr.status NOT IN ('cancelled')
    )
    SELECT count(*) FILTER (WHERE r.scheduled_at>=v_from AND r.scheduled_at<v_to),
        COALESCE(sum(r.actual_km) FILTER (WHERE r.scheduled_at>=v_from AND r.scheduled_at<v_to),0),
        COALESCE(sum(greatest(0,extract(epoch FROM (
            LEAST(COALESCE(r.ended_at,now()),v_to)-GREATEST(COALESCE(r.started_at,r.scheduled_at),v_from)
        )))/3600.0) FILTER (WHERE r.scheduled_at<v_to AND COALESCE(r.ended_at,now())>v_from),0)
    INTO v_services,v_km,v_hours FROM rows r;
    SELECT sr.id INTO v_active
    FROM business.service_assignment a
    JOIN business.service_request sr ON sr.id=a.service_request_id AND sr.tenant_id=a.tenant_id
    JOIN business.service_execution e ON e.service_assignment_id=a.id AND e.tenant_id=a.tenant_id
    WHERE a.tenant_id=p_tenant_id AND a.driver_id=v_driver_id AND a.status='confirmed'
      AND e.status='in_progress' AND e.ended_at IS NULL AND sr.scheduled_at<=now()
    ORDER BY sr.scheduled_at,a.confirmed_at LIMIT 1;
    SELECT sr.id INTO v_next
    FROM business.service_assignment a
    JOIN business.service_request sr ON sr.id=a.service_request_id AND sr.tenant_id=a.tenant_id
    WHERE a.tenant_id=p_tenant_id AND a.driver_id=v_driver_id AND a.status='confirmed'
      AND sr.status='assigned' AND sr.scheduled_at>now()
    ORDER BY sr.scheduled_at,a.confirmed_at LIMIT 1;
    RETURN jsonb_build_object('fecha',p_date,'servicios',v_services,'recorrido_km',round(v_km,3),
        'operacion_horas',round(v_hours,2),'servicio_activo_id',v_active,'proximo_servicio_id',v_next);
END;
$$;

REVOKE ALL ON FUNCTION business.fnc_assert_driver_identity(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_driver_me(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_driver_me_documents(uuid,uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_driver_me_document_file(uuid,uuid,uuid,text,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_driver_me_services(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION business.fnc_driver_me_day_summary(uuid,uuid,uuid,date) FROM PUBLIC;
GRANT USAGE ON SCHEMA business TO postgres;
GRANT EXECUTE ON FUNCTION
    business.fnc_driver_me(uuid,uuid,uuid),
    business.fnc_driver_me_documents(uuid,uuid,uuid,text),
    business.fnc_driver_me_document_file(uuid,uuid,uuid,text,uuid),
    business.fnc_driver_me_services(uuid,uuid,uuid),
    business.fnc_driver_me_day_summary(uuid,uuid,uuid,date)
TO postgres;

COMMIT;
