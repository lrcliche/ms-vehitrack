-- =====================================================================================
-- VehiTrack · migrations/010_geocode_house_interpolation.sql
-- Interpolación del NÚMERO DE CASA (nomenclatura métrica colombiana) en el backend.
-- «Carrera 48 # 76-147» = sobre la Carrera 48, a 147 m de la esquina de la Calle 76,
-- hacia donde crecen las calles. La app ya parsea la placa (vía, calle generadora,
-- metros) y le pasa esos valores; esta función resuelve la GEOMETRÍA en una sola
-- consulta y devuelve el punto de la casa.
--
-- Depende de 002 (geo.street, geo.street_intersection + índices GIST/GIN).
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/010_geocode_house_interpolation.sql
--
-- -------------------------------------------------------------------------------------
-- POR QUE
-- -------------------------------------------------------------------------------------
-- El cliente lo hacía con 3 llamadas de geocode (esquina + vecinas) y adivinando la
-- vecina ±1, que a veces no existe (la Carrera 48 de Barranquilla llega a la Calle 76,
-- no a la 77) y caía a la esquina. Aquí, con la BD a la mano, se busca la calle vecina
-- MÁS CERCANA EN NÚMERO (75 si no hay 77) para orientar, y se proyecta la distancia con
-- ST_Project (azimut geográfico). Enfoque por PUNTOS (no ST_LineMerge, frágil con calles
-- multi-segmento). Una sola llamada, rápida y robusta.
-- =====================================================================================

-- geo.fnc_interpolate_house
-- Parametros: p_via (texto de la vía, p.ej. 'carrera 48'), p_cross_num (calle generadora,
--             p.ej. 76), p_meters (placa, p.ej. 147), p_muni (opcional), p_lat/p_lon (sesgo).
-- Retorna   : (lat, lon) del punto de la casa; 0 filas si no se puede resolver la esquina
--             generadora (el llamador cae a su cascada normal). Si no hay vecina para
--             orientar, devuelve la esquina exacta (mejor eso que nada).
CREATE OR REPLACE FUNCTION geo.fnc_interpolate_house(
    p_via       text,
    p_cross_num int,
    p_meters    int,
    p_muni      text             DEFAULT NULL,
    p_lat       double precision DEFAULT NULL,
    p_lon       double precision DEFAULT NULL
) RETURNS TABLE (
    lat double precision,
    lon double precision
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_bias   geometry := CASE WHEN p_lat IS NOT NULL AND p_lon IS NOT NULL
                              THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326) END;
    v_norm   text     := public.fnc_expand_abbreviation(public.fnc_normalize_text(p_via));
    v_via_id bigint;
    v_gen    geometry;  -- punto de la esquina generadora (vía × calle p_cross_num)
    v_nb     geometry;  -- punto de la calle vecina más cercana en número
    v_nb_num int;
    v_az     double precision;
    v_pt     geometry;
    -- Regex para leer el número de una "calle N" del nombre completo del cruce.
    c_calle_num constant text := '(?:calle|cll|cl)\s*0*(\d+)';
BEGIN
    IF p_meters IS NULL OR p_cross_num IS NULL THEN
        RETURN;
    END IF;

    -- 1) La vía (p.ej. "carrera 48") más parecida y cercana al sesgo.
    SELECT s.id INTO v_via_id
      FROM geo.street s
     WHERE s.search_text % v_norm
       AND (p_muni IS NULL OR s.municipality_id = p_muni)
       AND (v_bias IS NULL OR ST_DWithin(s.geom, v_bias, 0.6))
     ORDER BY similarity(s.search_text, v_norm) DESC,
              CASE WHEN v_bias IS NULL THEN 0
                   ELSE ST_Distance(s.geom::geography, v_bias::geography) END
     LIMIT 1;
    IF v_via_id IS NULL THEN
        RETURN;
    END IF;

    -- 2) La esquina generadora: cruce de la vía con una "calle p_cross_num".
    SELECT x.geom INTO v_gen
      FROM geo.street_intersection x
      JOIN geo.street o
        ON o.id = CASE WHEN x.street_a_id = v_via_id THEN x.street_b_id ELSE x.street_a_id END
     WHERE (x.street_a_id = v_via_id OR x.street_b_id = v_via_id)
       AND o.full_name ~* ('(?:calle|cll|cl)\s*0*' || p_cross_num::text || '(?:$|[^0-9])')
     ORDER BY CASE WHEN v_bias IS NULL THEN 0
                   ELSE ST_Distance(x.geom::geography, v_bias::geography) END
     LIMIT 1;
    IF v_gen IS NULL THEN
        RETURN;  -- ni la esquina resuelve: el llamador sigue su cascada
    END IF;

    -- 3) La calle vecina MÁS CERCANA EN NÚMERO (≠ la generadora) sobre la misma vía,
    --    para orientar la numeración. Funciona con 75 si la 77 no existe.
    SELECT x.geom,
           (regexp_match(o.full_name, c_calle_num, 'i'))[1]::int
      INTO v_nb, v_nb_num
      FROM geo.street_intersection x
      JOIN geo.street o
        ON o.id = CASE WHEN x.street_a_id = v_via_id THEN x.street_b_id ELSE x.street_a_id END
     WHERE (x.street_a_id = v_via_id OR x.street_b_id = v_via_id)
       AND o.full_name ~* c_calle_num
       AND (regexp_match(o.full_name, c_calle_num, 'i'))[1]::int <> p_cross_num
     ORDER BY abs((regexp_match(o.full_name, c_calle_num, 'i'))[1]::int - p_cross_num) ASC,
              ST_Distance(x.geom, v_gen) ASC
     LIMIT 1;

    IF v_nb IS NULL THEN
        -- Sin vecina para orientar: se devuelve la esquina exacta.
        RETURN QUERY SELECT ST_Y(v_gen)::double precision, ST_X(v_gen)::double precision;
        RETURN;
    END IF;

    -- 4) Azimut en el sentido de numeración CRECIENTE y proyección de la placa.
    IF v_nb_num > p_cross_num THEN
        v_az := ST_Azimuth(v_gen::geography, v_nb::geography);   -- hacia la calle mayor
    ELSE
        v_az := ST_Azimuth(v_nb::geography, v_gen::geography);   -- vecina menor → generadora
    END IF;

    v_pt := ST_Project(v_gen::geography, p_meters, v_az)::geometry;
    RETURN QUERY SELECT ST_Y(v_pt)::double precision, ST_X(v_pt)::double precision;
END $$;

COMMENT ON FUNCTION geo.fnc_interpolate_house(text, int, int, text, double precision, double precision) IS
    'Interpola el número de casa (nomenclatura métrica CO) sobre la vía: ST_Project desde la
     esquina generadora, orientado por la calle vecina más cercana en número. Ver 010.';
