-- =====================================================================================
-- VehiTrack · migrations/009_geocode_spatial_prefilter.sql
-- Prefiltro espacial en geo.fnc_search_place: cuando llega lat/lon, primero se busca
-- LOCAL (a ~geocode.local_radius_m del punto, usando el índice GIST) y solo si no hay
-- nada se cae a la búsqueda NACIONAL. Antes el lat/lon solo ordenaba, no filtraba, así
-- que cada búsqueda escaneaba todas las "carrera 48"/"calle 76" del país y corría
-- ST_LineMerge/ST_LineInterpolatePoint sobre TODAS -> ~4 s por consulta.
--
-- Depende de 002 (geo.fnc_search_place, geo.street/street_intersection + índices GIST).
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/009_geocode_spatial_prefilter.sql
--
-- -------------------------------------------------------------------------------------
-- POR QUE
-- -------------------------------------------------------------------------------------
-- El 99% de las búsquedas son un destino cercano: acotarlas a ~60 km del GPS con el
-- índice GIST (gist_intersection_geom / gist de street.geom) recorta el conjunto a lo
-- local ANTES de las operaciones de geometría caras -> de ~4 s a <1 s. El fallback
-- nacional conserva la búsqueda de destinos lejanos (otra ciudad): si lo local viene
-- vacío, se repite sin el filtro espacial. Sin lat/lon, va directo a nacional (igual
-- que antes). El resultado y el orden son idénticos; solo cambia el rendimiento.
-- =====================================================================================

-- Radio del prefiltro local (metros). fnc_setting_num LANZA si la clave no existe, así
-- que se siembra aquí, en la misma migración que usa la función.
INSERT INTO public.app_setting (key, value, description) VALUES
  ('geocode.local_radius_m', '60000',
   'Radio (m) del prefiltro espacial de fnc_search_place: primero busca a esta distancia del lat/lon y solo si no hay cae a nacional.')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION geo.fnc_search_place(
    p_query           text,
    p_municipality_id text DEFAULT NULL,
    p_lat             double precision DEFAULT NULL,
    p_lon             double precision DEFAULT NULL,
    p_limit           int  DEFAULT 8
) RETURNS TABLE (
    result_kind         text,
    place_id            bigint,
    street_id           bigint,
    intersection_id     bigint,
    label               text,
    context             text,
    lat                 double precision,
    lon                 double precision,
    municipality_id     text,
    confidence          numeric,
    geocode_resolver_id text,
    is_verified         boolean
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_norm    text     := public.fnc_expand_abbreviation(public.fnc_normalize_text(p_query));
    v_min     numeric  := public.fnc_setting_num('geocode.min_similarity');
    v_cap     int      := public.fnc_setting_num('geocode.max_results')::int;
    v_stf     numeric  := public.fnc_setting_num('geocode.street_score_factor');
    v_vf      numeric  := public.fnc_setting_num('geocode.verified_score_factor');
    v_bias    geometry := CASE WHEN p_lat IS NOT NULL AND p_lon IS NOT NULL
                               THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326) END;
    -- Radio local en GRADOS (aprox: 1° ≈ 111.32 km). ST_DWithin planar con el índice
    -- GIST; la aproximación en grados sobra para un prefiltro.
    v_deg     double precision :=
        (public.fnc_setting_num('geocode.local_radius_m') / 111320.0)::double precision;
BEGIN
    -- ── PASO 1: LOCAL. Solo si hay sesgo. El ST_DWithin va "desnudo" (sin OR) para que
    --    el planificador use el índice GIST y acote a lo cercano antes de las ops de
    --    geometría. Si encuentra algo, se devuelve y no se toca el nacional.
    IF v_bias IS NOT NULL THEN
        RETURN QUERY
        WITH cand AS (
            SELECT q.place_id AS pid, 1.000::numeric AS score, 'cache'::text AS res
              FROM geo.geocode_query q
             WHERE q.query_normalized = v_norm
               AND COALESCE(q.municipality_id,'') = COALESCE(p_municipality_id,'')
               AND q.place_id IS NOT NULL
               AND (q.expires_at IS NULL OR q.expires_at > now())
            UNION ALL
            SELECT a.place_id, similarity(a.alias_normalized, v_norm)::numeric, 'alias'
              FROM geo.place_alias a WHERE a.alias_normalized % v_norm
            UNION ALL
            SELECT p.id, similarity(p.label_normalized, v_norm)::numeric, 'place'
              FROM geo.place p
             WHERE p.label_normalized % v_norm
               AND (p_municipality_id IS NULL OR p.municipality_id = p_municipality_id)
        ),
        best AS (
            SELECT pid, max(score) AS score, min(res) AS res FROM cand GROUP BY pid
        ),
        places AS (
            SELECT 'place'::text AS result_kind, p.id AS place_id,
                   NULL::bigint AS street_id, NULL::bigint AS intersection_id,
                   p.label,
                   concat_ws(', ', n.name, m.name) AS context,
                   ST_Y(p.geom)::double precision AS lat, ST_X(p.geom)::double precision AS lon,
                   p.municipality_id,
                   round(LEAST(1.0, b.score * (0.85 + 0.15 * p.precision_score)
                         * CASE WHEN p.is_verified THEN v_vf ELSE 1.00 END), 3) AS confidence,
                   b.res AS geocode_resolver_id, p.is_verified, p.geom, p.usage_count
              FROM best b
              JOIN geo.place p ON p.id = b.pid
              LEFT JOIN geo.neighborhood n ON n.id = p.neighborhood_id
              LEFT JOIN public.municipality m ON m.id = p.municipality_id
             WHERE b.score >= v_min
               AND ST_DWithin(p.geom, v_bias, v_deg)
        ),
        streets AS (
            SELECT 'street', NULL::bigint, s.id, NULL::bigint,
                   s.full_name, m.name,
                   ST_Y(ST_LineInterpolatePoint(ST_LineMerge(s.geom), 0.5))::double precision,
                   ST_X(ST_LineInterpolatePoint(ST_LineMerge(s.geom), 0.5))::double precision,
                   s.municipality_id,
                   round(similarity(s.search_text, v_norm)::numeric * v_stf, 3),
                   'street', false,
                   ST_LineInterpolatePoint(ST_LineMerge(s.geom), 0.5), 0
              FROM geo.street s
              LEFT JOIN public.municipality m ON m.id = s.municipality_id
             WHERE s.search_text % v_norm
               AND s.geom IS NOT NULL
               AND (p_municipality_id IS NULL OR s.municipality_id = p_municipality_id)
               AND similarity(s.search_text, v_norm) >= v_min
               AND ST_DWithin(s.geom, v_bias, v_deg)
        ),
        crossings AS (
            SELECT 'intersection', NULL::bigint, NULL::bigint, x.id,
                   concat_ws(' con ', a.full_name, b2.full_name), m.name,
                   ST_Y(x.geom)::double precision, ST_X(x.geom)::double precision,
                   a.municipality_id,
                   round(similarity(x.search_text, v_norm)::numeric, 3),
                   'street', false, x.geom, 0
              FROM geo.street_intersection x
              JOIN geo.street a  ON a.id  = x.street_a_id
              JOIN geo.street b2 ON b2.id = x.street_b_id
              LEFT JOIN public.municipality m ON m.id = a.municipality_id
             WHERE x.search_text % v_norm
               AND similarity(x.search_text, v_norm) >= v_min
               AND (p_municipality_id IS NULL OR a.municipality_id = p_municipality_id)
               AND ST_DWithin(x.geom, v_bias, v_deg)
        ),
        merged AS (
            SELECT * FROM places UNION ALL SELECT * FROM streets UNION ALL SELECT * FROM crossings
        )
        SELECT g.result_kind, g.place_id, g.street_id, g.intersection_id, g.label, g.context,
               g.lat, g.lon, g.municipality_id, g.confidence, g.geocode_resolver_id, g.is_verified
        FROM merged g
        ORDER BY g.confidence DESC,
                 ST_Distance(g.geom::geography, v_bias::geography),
                 g.usage_count DESC
        LIMIT GREATEST(1, LEAST(p_limit, v_cap));

        IF FOUND THEN RETURN; END IF;
    END IF;

    -- ── PASO 2: NACIONAL. Sin sesgo, o cuando lo local no encontró (destino lejano).
    --    Es la consulta original, sin el filtro espacial.
    RETURN QUERY
    WITH cand AS (
        SELECT q.place_id AS pid, 1.000::numeric AS score, 'cache'::text AS res
          FROM geo.geocode_query q
         WHERE q.query_normalized = v_norm
           AND COALESCE(q.municipality_id,'') = COALESCE(p_municipality_id,'')
           AND q.place_id IS NOT NULL
           AND (q.expires_at IS NULL OR q.expires_at > now())
        UNION ALL
        SELECT a.place_id, similarity(a.alias_normalized, v_norm)::numeric, 'alias'
          FROM geo.place_alias a WHERE a.alias_normalized % v_norm
        UNION ALL
        SELECT p.id, similarity(p.label_normalized, v_norm)::numeric, 'place'
          FROM geo.place p
         WHERE p.label_normalized % v_norm
           AND (p_municipality_id IS NULL OR p.municipality_id = p_municipality_id)
    ),
    best AS (
        SELECT pid, max(score) AS score, min(res) AS res FROM cand GROUP BY pid
    ),
    places AS (
        SELECT 'place'::text AS result_kind, p.id AS place_id,
               NULL::bigint AS street_id, NULL::bigint AS intersection_id,
               p.label,
               concat_ws(', ', n.name, m.name) AS context,
               ST_Y(p.geom)::double precision AS lat, ST_X(p.geom)::double precision AS lon,
               p.municipality_id,
               round(LEAST(1.0, b.score * (0.85 + 0.15 * p.precision_score)
                     * CASE WHEN p.is_verified THEN v_vf ELSE 1.00 END), 3) AS confidence,
               b.res AS geocode_resolver_id, p.is_verified, p.geom, p.usage_count
          FROM best b
          JOIN geo.place p ON p.id = b.pid
          LEFT JOIN geo.neighborhood n ON n.id = p.neighborhood_id
          LEFT JOIN public.municipality m ON m.id = p.municipality_id
         WHERE b.score >= v_min
    ),
    streets AS (
        SELECT 'street', NULL::bigint, s.id, NULL::bigint,
               s.full_name, m.name,
               ST_Y(ST_LineInterpolatePoint(ST_LineMerge(s.geom), 0.5))::double precision,
               ST_X(ST_LineInterpolatePoint(ST_LineMerge(s.geom), 0.5))::double precision,
               s.municipality_id,
               round(similarity(s.search_text, v_norm)::numeric * v_stf, 3),
               'street', false,
               ST_LineInterpolatePoint(ST_LineMerge(s.geom), 0.5), 0
          FROM geo.street s
          LEFT JOIN public.municipality m ON m.id = s.municipality_id
         WHERE s.search_text % v_norm
           AND s.geom IS NOT NULL
           AND (p_municipality_id IS NULL OR s.municipality_id = p_municipality_id)
           AND similarity(s.search_text, v_norm) >= v_min
    ),
    crossings AS (
        SELECT 'intersection', NULL::bigint, NULL::bigint, x.id,
               concat_ws(' con ', a.full_name, b2.full_name), m.name,
               ST_Y(x.geom)::double precision, ST_X(x.geom)::double precision,
               a.municipality_id,
               round(similarity(x.search_text, v_norm)::numeric, 3),
               'street', false, x.geom, 0
          FROM geo.street_intersection x
          JOIN geo.street a  ON a.id  = x.street_a_id
          JOIN geo.street b2 ON b2.id = x.street_b_id
          LEFT JOIN public.municipality m ON m.id = a.municipality_id
         WHERE x.search_text % v_norm
           AND similarity(x.search_text, v_norm) >= v_min
           AND (p_municipality_id IS NULL OR a.municipality_id = p_municipality_id)
    ),
    merged AS (
        SELECT * FROM places UNION ALL SELECT * FROM streets UNION ALL SELECT * FROM crossings
    )
    SELECT g.result_kind, g.place_id, g.street_id, g.intersection_id, g.label, g.context,
           g.lat, g.lon, g.municipality_id, g.confidence, g.geocode_resolver_id, g.is_verified
    FROM merged g
    ORDER BY g.confidence DESC,
             CASE WHEN v_bias IS NULL THEN 0
                  ELSE ST_Distance(g.geom::geography, v_bias::geography) END,
             g.usage_count DESC
    LIMIT GREATEST(1, LEAST(p_limit, v_cap));
END $$;
