-- =====================================================================================
-- VehiTrack · migrations/010_geocode_house_interpolation.sql
-- Interpolación del NÚMERO DE CASA (nomenclatura métrica colombiana) en el backend.
-- «Carrera 48 # 76-147» = sobre la Carrera 48, a 147 m de la esquina de la Calle 76,
-- hacia donde crecen las calles. La app ya parsea la placa (vía, tipo+número de la
-- calle generadora, metros) y le pasa esos valores; esta función resuelve la GEOMETRÍA
-- en una sola consulta y devuelve el punto de la casa.
--
-- Depende de 002 (geo.street_intersection.search_text = "via_a con via_b" + índices).
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/010_geocode_house_interpolation.sql
--
-- -------------------------------------------------------------------------------------
-- POR QUE / COMO
-- -------------------------------------------------------------------------------------
-- La app lo hacía con 3 llamadas de geocode y adivinando la calle vecina ±1, que a veces
-- no existe (la Carrera 48 de Barranquilla llega a la Calle 76, no a la 77) y caía a la
-- esquina. Aquí se resuelve por el SEARCH_TEXT de la intersección (independiente del
-- segmento OSM: las calles están partidas en tramos y la esquina se guarda contra UN
-- tramo, así que atar por street_id fallaba). Se busca la esquina generadora, la calle
-- vecina MÁS CERCANA EN NÚMERO para orientar la numeración, y se proyecta la placa con
-- ST_Project (azimut geográfico). Enfoque por puntos (sin ST_LineMerge, frágil con
-- calles multi-segmento). Una sola llamada, robusta.
-- =====================================================================================

-- La versión previa (sin p_cross_type, atada a street_id) se reemplaza.
DROP FUNCTION IF EXISTS geo.fnc_interpolate_house(text, int, int, text, double precision, double precision);

-- geo.fnc_interpolate_house
-- Parametros: p_via ('carrera 48'), p_cross_type ('calle'|'carrera'|...), p_cross_num (76),
--             p_meters (147), p_muni (opcional), p_lat/p_lon (sesgo).
-- Retorna   : (lat, lon) del punto de la casa; 0 filas si no resuelve la esquina
--             generadora (el llamador cae a su cascada). Sin vecina para orientar,
--             devuelve la esquina exacta.
CREATE OR REPLACE FUNCTION geo.fnc_interpolate_house(
    p_via        text,
    p_cross_type text,
    p_cross_num  int,
    p_meters     int,
    p_muni       text             DEFAULT NULL,
    p_lat        double precision DEFAULT NULL,
    p_lon        double precision DEFAULT NULL
) RETURNS TABLE (
    lat double precision,
    lon double precision
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_bias  geometry := CASE WHEN p_lat IS NOT NULL AND p_lon IS NOT NULL
                             THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326) END;
    v_via   text     := public.fnc_expand_abbreviation(public.fnc_normalize_text(p_via));
    v_ctype text     := public.fnc_expand_abbreviation(public.fnc_normalize_text(p_cross_type));
    -- Consulta de la esquina generadora, igual que la búsqueda de cruces que ya funciona.
    v_genq  text     := v_via || ' con ' || v_ctype || ' ' || p_cross_num::text;
    v_min   numeric  := public.fnc_setting_num('geocode.min_similarity');
    -- Regex: la vía como token (evita "carrera 480") y el número de la calle vecina.
    v_via_rx  text := replace(v_via, ' ', '\s+') || '(?:$|[^0-9])';
    v_cnum_rx text := v_ctype || '\s*0*(\d+)';
    v_gen    geometry;
    v_nb     geometry;
    v_nb_num int;
    v_az     double precision;
    v_pt     geometry;
BEGIN
    IF p_meters IS NULL OR p_cross_num IS NULL THEN
        RETURN;
    END IF;

    -- 1) Esquina generadora por el search_text de la intersección ("via con calle N").
    SELECT x.geom INTO v_gen
      FROM geo.street_intersection x
     WHERE x.search_text % v_genq
       AND similarity(x.search_text, v_genq) >= v_min
     ORDER BY similarity(x.search_text, v_genq) DESC,
              CASE WHEN v_bias IS NULL THEN 0
                   ELSE ST_Distance(x.geom::geography, v_bias::geography) END
     LIMIT 1;
    IF v_gen IS NULL THEN
        RETURN;  -- ni la esquina resuelve: el llamador sigue su cascada
    END IF;

    -- 2) Calle vecina MÁS CERCANA EN NÚMERO (≠ generadora) sobre la misma vía y cerca de
    --    la esquina, para orientar la numeración. Sirve la 75 si la 77 no existe.
    SELECT x.geom,
           (regexp_match(x.search_text, v_cnum_rx, 'i'))[1]::int
      INTO v_nb, v_nb_num
      FROM geo.street_intersection x
     WHERE x.search_text ~* v_via_rx
       AND x.search_text ~* v_cnum_rx
       AND (regexp_match(x.search_text, v_cnum_rx, 'i'))[1]::int <> p_cross_num
       AND ST_DWithin(x.geom, v_gen, 0.02)   -- ~2 km: misma zona de la vía
     ORDER BY abs((regexp_match(x.search_text, v_cnum_rx, 'i'))[1]::int - p_cross_num) ASC,
              ST_Distance(x.geom, v_gen) ASC
     LIMIT 1;

    IF v_nb IS NULL THEN
        RETURN QUERY SELECT ST_Y(v_gen)::double precision, ST_X(v_gen)::double precision;
        RETURN;
    END IF;

    -- 3) Azimut en el sentido de numeración CRECIENTE y proyección de la placa.
    IF v_nb_num > p_cross_num THEN
        v_az := ST_Azimuth(v_gen::geography, v_nb::geography);  -- hacia la calle mayor
    ELSE
        v_az := ST_Azimuth(v_nb::geography, v_gen::geography);  -- vecina menor → generadora
    END IF;

    v_pt := ST_Project(v_gen::geography, p_meters, v_az)::geometry;
    RETURN QUERY SELECT ST_Y(v_pt)::double precision, ST_X(v_pt)::double precision;
END $$;

COMMENT ON FUNCTION geo.fnc_interpolate_house(text, text, int, int, text, double precision, double precision) IS
    'Interpola el número de casa (nomenclatura métrica CO) sobre la vía: ST_Project desde la
     esquina generadora (resuelta por search_text de la intersección), orientado por la calle
     vecina más cercana en número. Ver 010.';
