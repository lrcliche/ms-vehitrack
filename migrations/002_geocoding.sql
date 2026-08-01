-- =====================================================================================
-- VehiTrack · migrations/002_geocoding.sql
-- Geocoding propio sobre PG + diccionario de normalizacion versionado.
--
-- Depende de 001_vehitrack.sql.
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/002_geocoding.sql
--
-- -------------------------------------------------------------------------------------
-- LA IDEA DE FONDO
-- -------------------------------------------------------------------------------------
-- /v1/geocode/search NO le pega a Nominatim primero. El ms llama a geo.fnc_search_place;
-- si devuelve filas, ahi murio la peticion. Solo con cero resultados consulta Nominatim
-- (127.0.0.1:21001), responde al usuario Y persiste con geo.prc_resolve_from_provider.
-- La siguiente vez sale de PG.
--
-- Cada busqueda hace mas rapida a la siguiente. Con el tiempo Nominatim deja de ser el
-- camino normal y pasa a ser el caso raro. Ese es todo el producto.
--
-- SIN tenant_id: el conocimiento geografico es GLOBAL a proposito. Una direccion resuelta
-- por un usuario le sirve a todos. Lo unico atribuido a un device es quien pidio primero
-- una query (geocode_query.first_device_id), para auditoria — no para filtrar.
--
-- geo.street cierra el gancho que dejaste: street_segment.street_id era un bigint suelto.
-- =====================================================================================

BEGIN;

SET LOCAL client_min_messages = WARNING;

-- =====================================================================================
-- 0. PREFLIGHT — fallar temprano y ruidoso
-- =====================================================================================

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['public.db_routine','public.app_setting','public.municipality',
                             'geo.street_segment','public.tenant']
    LOOP
        IF to_regclass(t) IS NULL THEN
            RAISE EXCEPTION 'Falta % — aplica primero 001_vehitrack.sql', t;
        END IF;
    END LOOP;

    -- RLS no aplica al dueno de la tabla: si la app es duena, el aislamiento es decorativo
    -- y no da error. Se detecta aqui o no se detecta nunca.
    IF EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('device','tracking','traffic')
          AND c.relkind = 'r' AND pg_get_userbyid(c.relowner) = 'vehitrack_app')
    THEN
        RAISE EXCEPTION 'vehitrack_app es dueno de tablas con RLS: el aislamiento por tenant NO esta activo.';
    END IF;
END $$;

-- =====================================================================================
-- 1. CONFIGURACION (C5) — ningun numero magico en las rutinas
-- =====================================================================================

INSERT INTO public.app_setting (key, value, description) VALUES
  ('geocode.min_similarity',            '0.35', 'Umbral trigram minimo. Mas bajo = mas ruido en autocompletado.'),
  ('geocode.max_results',               '25',   'Tope duro de resultados por busqueda, sin importar lo que pida el ms.'),
  ('geocode.hit_ttl_days',              '180',  'Vigencia de un acierto de geocoding en cache.'),
  ('geocode.miss_ttl_days',             '7',    'Vigencia de un fallo cacheado. Corto: el dato puede aparecer en OSM.'),
  ('geocode.cold_purge_days',           '90',   'Antiguedad para purgar queries de un solo uso.'),
  ('geocode.verify_radius_m',           '50',   'Distancia al destino para marcar un place como verificado.'),
  ('geocode.verify_score_bonus',        '0.100','Cuanto sube precision_score cada verificacion real.'),
  ('geocode.reverse_precision',         '7',    'Precision del geohash del cache de reverse (7 = ~76 m).'),
  ('geocode.reverse_max_distance_m',    '120',  'Radio maximo para resolver "estas en...".'),
  ('geocode.street_score_factor',       '0.90', 'Penalizacion de un match de via frente a una direccion exacta.'),
  ('geocode.verified_score_factor',     '1.10', 'Premio de ranking a un lugar verificado por un viaje real.')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.pipeline_job (id, name, expected_interval_min) VALUES
  ('geocode_purge','Purga de cache frio de geocoding',1440)
ON CONFLICT (id) DO NOTHING;

-- =====================================================================================
-- 2. DICCIONARIOS (C4) — ninguna columna de valores cerrados sin catalogo
-- =====================================================================================

CREATE TABLE IF NOT EXISTS public.place_kind (
    id text PRIMARY KEY, name text NOT NULL, sort_order smallint NOT NULL);
INSERT INTO public.place_kind (id, name, sort_order) VALUES
  ('address','Direccion con placa',1),
  ('street','Via completa',2),
  ('intersection','Cruce de vias',3),
  ('poi','Punto de interes',4),
  ('neighborhood','Barrio',5),
  ('municipality','Municipio',6)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.place_source (
    id text PRIMARY KEY, name text NOT NULL, base_precision numeric(4,3) NOT NULL);
COMMENT ON COLUMN public.place_source.base_precision IS
    'Precision inicial segun de donde salio el dato. Una direccion interpolada NO puede
     competir de entrada con una que existe con placa real en OSM.';
INSERT INTO public.place_source (id, name, base_precision) VALUES
  ('osm_import','Import OSM directo',0.900),
  ('nominatim','Resuelto por Nominatim',0.700),
  ('user','Corregido o creado por el usuario',0.950),
  ('interpolated','Interpolado sobre el tramo de via',0.400)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.geocode_resolver (
    id text PRIMARY KEY, name text NOT NULL, is_local boolean NOT NULL);
COMMENT ON TABLE public.geocode_resolver IS
    'Quien resolvio la busqueda. is_local=false es la metrica que importa: cuanto todavia
     dependes de Nominatim.';
INSERT INTO public.geocode_resolver (id, name, is_local) VALUES
  ('cache','Cache exacto de query',true),
  ('alias','Alias del lugar',true),
  ('place','Similitud sobre el lugar',true),
  ('street','Via o interseccion',true),
  ('nominatim','Proveedor externo',false),
  ('miss','Sin resultado',false)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.oneway_kind (
    id text PRIMARY KEY, name text NOT NULL);
INSERT INTO public.oneway_kind (id, name) VALUES
  ('no','Doble sentido'),('yes','Un sentido'),
  ('reverse','Un sentido invertido'),('unknown','Desconocido')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.via_type (
    id              text     PRIMARY KEY,
    canonical_label text     NOT NULL,
    short_label     text     NOT NULL,
    sort_order      smallint NOT NULL
);
COMMENT ON TABLE public.via_type IS
    'Tipos de via colombianos. El diccionario de abreviaturas apunta aqui: cra/cr/kra/k -> carrera.';
INSERT INTO public.via_type (id, canonical_label, short_label, sort_order) VALUES
  ('carrera','Carrera','Cra',1),('calle','Calle','Cll',2),('avenida','Avenida','Av',3),
  ('diagonal','Diagonal','Dg',4),('transversal','Transversal','Tv',5),
  ('circunvalar','Circunvalar','Circ',6),('autopista','Autopista','Auto',7),
  ('via','Via','Via',8),('peatonal','Peatonal','Peat',9),('anillo','Anillo vial','Anillo',10)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.abbreviation_kind (
    id text PRIMARY KEY, name text NOT NULL, sort_order smallint NOT NULL);
INSERT INTO public.abbreviation_kind (id, name, sort_order) VALUES
  ('via_type','Tipo de via',1),('unit','Unidad interior',2),
  ('ordinal','Ordinal o numeral',3),('direction','Direccion cardinal',4),
  ('noise','Ruido que se elimina',9)
ON CONFLICT (id) DO NOTHING;

-- =====================================================================================
-- 3. DICCIONARIO DE NORMALIZACION VERSIONADO — lo consume /v1/dictionary
-- =====================================================================================

CREATE TABLE IF NOT EXISTS public.dictionary_version (
    id           int         GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    version      int         NOT NULL UNIQUE,
    checksum     text        NOT NULL,
    is_current   boolean     NOT NULL DEFAULT false,
    note         text,
    published_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.dictionary_version IS
    'Version monotona del diccionario. La app guarda la suya y pide /v1/dictionary?since_version=N.
     Corregir una abreviatura NO requiere release en la Play Store.';
CREATE UNIQUE INDEX IF NOT EXISTS ux_dictionary_version_current
    ON public.dictionary_version (is_current) WHERE is_current;

CREATE TABLE IF NOT EXISTS public.abbreviation (
    id                    bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    dictionary_version_id int    NOT NULL REFERENCES public.dictionary_version(id) ON DELETE CASCADE,
    abbreviation_kind_id  text   NOT NULL REFERENCES public.abbreviation_kind(id),
    input                 text   NOT NULL,
    output                text   NOT NULL,
    priority              smallint NOT NULL DEFAULT 100,
    UNIQUE (dictionary_version_id, input)
);
COMMENT ON COLUMN public.abbreviation.input IS
    'Siempre normalizado (minuscula, sin tildes): se compara contra el texto ya pasado por
     fnc_normalize_text. Guardarlo crudo aqui haria que nunca haga match.';
CREATE INDEX IF NOT EXISTS ix_abbreviation_version
    ON public.abbreviation (dictionary_version_id, priority);

CREATE TABLE IF NOT EXISTS public.city_alias (
    id                    bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    dictionary_version_id int  NOT NULL REFERENCES public.dictionary_version(id) ON DELETE CASCADE,
    municipality_id       text NOT NULL REFERENCES public.municipality(id),
    alias                 text NOT NULL,
    UNIQUE (dictionary_version_id, alias)
);
COMMENT ON TABLE public.city_alias IS 'bqlla, b/quilla, barranqilla -> co-atl-barranquilla.';

-- =====================================================================================
-- 4. GEOGRAFIA CONSULTABLE
-- =====================================================================================

CREATE TABLE IF NOT EXISTS geo.neighborhood (
    id              bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    municipality_id text   NOT NULL REFERENCES public.municipality(id),
    name            text   NOT NULL,
    name_normalized text   NOT NULL,
    geom            geometry(MultiPolygon, 4326),
    UNIQUE (municipality_id, name_normalized)
);
COMMENT ON TABLE geo.neighborhood IS
    'Barrio. En Barranquilla la cobertura de OSM es irregular: arranca incompleto y se
     completa a mano. Es contexto del resultado, no clave de busqueda.';
CREATE INDEX IF NOT EXISTS ix_neighborhood_geom ON geo.neighborhood USING gist (geom);

CREATE TABLE IF NOT EXISTS geo.street (
    id              bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    municipality_id text   NOT NULL REFERENCES public.municipality(id),
    osm_way_id      text,
    via_type_id     text   REFERENCES public.via_type(id),
    via_number      text,
    full_name       text   NOT NULL,
    search_text     text   NOT NULL,
    oneway_kind_id  text   NOT NULL REFERENCES public.oneway_kind(id) DEFAULT 'unknown',
    speed_limit_kmh smallint,
    geom            geometry(MultiLineString, 4326),
    UNIQUE (municipality_id, osm_way_id)
);
COMMENT ON TABLE geo.street IS
    'Via completa. geo.street_segment es su unidad direccional para map matching y trafico:
     esta tabla cierra el street_id que quedo suelto en 001.';
COMMENT ON COLUMN geo.street.search_text IS
    'Texto ya normalizado y expandido. Se MATERIALIZA: es lo unico que hace viable el indice trigram.';
CREATE INDEX IF NOT EXISTS gin_street_search ON geo.street USING gin (search_text gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ix_street_municipality ON geo.street (municipality_id);
CREATE INDEX IF NOT EXISTS gist_street_geom ON geo.street USING gist (geom);

-- cierra el gancho de 001
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_street_segment_street') THEN
        ALTER TABLE geo.street_segment
            ADD CONSTRAINT fk_street_segment_street
            FOREIGN KEY (street_id) REFERENCES geo.street(id) ON DELETE CASCADE;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS geo.street_intersection (
    id          bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    street_a_id bigint NOT NULL REFERENCES geo.street(id) ON DELETE CASCADE,
    street_b_id bigint NOT NULL REFERENCES geo.street(id) ON DELETE CASCADE,
    search_text text   NOT NULL,
    geom        geometry(Point, 4326) NOT NULL,
    UNIQUE (street_a_id, street_b_id)
);
COMMENT ON TABLE geo.street_intersection IS
    'En Barranquilla la gente ubica por cruce ("carrera 43 con 76") mas que por placa.
     Es un caso de busqueda de primera clase, no un extra.';
CREATE INDEX IF NOT EXISTS gin_intersection_search
    ON geo.street_intersection USING gin (search_text gin_trgm_ops);
CREATE INDEX IF NOT EXISTS gist_intersection_geom
    ON geo.street_intersection USING gist (geom);

-- =====================================================================================
-- 5. LUGARES Y CACHE DE GEOCODING
-- =====================================================================================

CREATE TABLE IF NOT EXISTS geo.place (
    id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    place_kind_id    text   NOT NULL REFERENCES public.place_kind(id),
    place_source_id  text   NOT NULL REFERENCES public.place_source(id),
    label            text   NOT NULL,
    label_normalized text   NOT NULL,
    municipality_id  text   REFERENCES public.municipality(id),
    neighborhood_id  bigint REFERENCES geo.neighborhood(id),
    street_id        bigint REFERENCES geo.street(id),
    house_number     text,
    external_ref     text,
    geom             geometry(Point, 4326) NOT NULL,
    precision_score  numeric(4,3) NOT NULL,
    is_verified      boolean NOT NULL DEFAULT false,
    usage_count      int     NOT NULL DEFAULT 0,
    first_seen_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (external_ref)
);
COMMENT ON TABLE geo.place IS
    'Lugar canonico. N queries distintas apuntan a 1 place: corriges la coordenada una vez
     y todas las formas de escribir esa direccion mejoran.';
COMMENT ON COLUMN geo.place.is_verified IS
    'Se marca cuando un viaje real termino cerca. Es la senal mas honesta de que la
     coordenada sirve, y es lo que con el tiempo hace este geocoder mejor que Nominatim en CO.';
CREATE INDEX IF NOT EXISTS gin_place_label ON geo.place USING gin (label_normalized gin_trgm_ops);
CREATE INDEX IF NOT EXISTS gist_place_geom ON geo.place USING gist (geom);
CREATE INDEX IF NOT EXISTS ix_place_municipality ON geo.place (municipality_id);

CREATE TABLE IF NOT EXISTS geo.place_alias (
    id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    place_id         bigint NOT NULL REFERENCES geo.place(id) ON DELETE CASCADE,
    alias_normalized text   NOT NULL,
    place_source_id  text   NOT NULL REFERENCES public.place_source(id),
    hit_count        int    NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (place_id, alias_normalized)
);
CREATE INDEX IF NOT EXISTS gin_place_alias ON geo.place_alias USING gin (alias_normalized gin_trgm_ops);

CREATE TABLE IF NOT EXISTS geo.geocode_query (
    id                  bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    query_raw           text   NOT NULL,
    query_normalized    text   NOT NULL,
    municipality_id     text   REFERENCES public.municipality(id),
    place_id            bigint REFERENCES geo.place(id) ON DELETE SET NULL,
    geocode_resolver_id text   NOT NULL REFERENCES public.geocode_resolver(id),
    confidence          numeric(4,3),
    hit_count           int    NOT NULL DEFAULT 1,
    first_device_id     uuid   REFERENCES device.device(id) ON DELETE SET NULL,
    first_requested_at  timestamptz NOT NULL DEFAULT now(),
    last_requested_at   timestamptz NOT NULL DEFAULT now(),
    expires_at          timestamptz
);
COMMENT ON COLUMN geo.geocode_query.place_id IS
    'NULL = no se encontro. Los fallos TAMBIEN se cachean, con TTL corto: sin eso, cada
     dedazo le pega a Nominatim para siempre.';
COMMENT ON COLUMN geo.geocode_query.first_device_id IS
    'Auditoria, no filtro: esta tabla es global y no lleva tenant_id.';
CREATE UNIQUE INDEX IF NOT EXISTS ux_geocode_query
    ON geo.geocode_query (query_normalized, COALESCE(municipality_id, ''));
CREATE INDEX IF NOT EXISTS ix_geocode_query_cold
    ON geo.geocode_query (last_requested_at) WHERE hit_count = 1;

CREATE TABLE IF NOT EXISTS geo.reverse_cache (
    id         bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    geohash    text   NOT NULL UNIQUE,
    place_id   bigint NOT NULL REFERENCES geo.place(id) ON DELETE CASCADE,
    distance_m numeric(8,2),
    hit_count  int    NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz
);

-- =====================================================================================
-- 6. NORMALIZACION
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_normalize_text
-- Proposito : Texto canonico para comparar e indexar: sin tildes, minusculas, sin
--             puntuacion irrelevante y con espacios colapsados.
-- Parametros: p_text
-- Retorna   : text
-- Errores   : ninguno
-- Nota      : IMMUTABLE a proposito — se usa en indices funcionales. Por eso invoca
--             unaccent con diccionario explicito: la forma de un solo argumento NO es
--             inmutable y hace fallar el CREATE INDEX. Es el error #1 de este tipo de
--             geocoder y no da sintoma hasta que hay volumen (seq scan silencioso).
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_normalize_text(p_text text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
    -- El borde letra->digito se separa ('cra15' -> 'cra 15', 'cll84' -> 'cll 84',
    -- 'k15' -> 'k 15'): en Colombia la via y su numero se escriben pegados y sin esto el
    -- token queda sin expandir. Solo letra->digito, NO digito->letra, para no partir
    -- designadores como '15b' ni placas '45b-30'. Sigue IMMUTABLE (determinista).
    SELECT btrim(regexp_replace(
             regexp_replace(
               regexp_replace(
                 lower(unaccent('unaccent'::regdictionary, p_text)),
                 '[^a-z0-9#\- ]', ' ', 'g'),
               '([a-z])([0-9])', '\1 \2', 'g'),
             '\s+', ' ', 'g'));
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_expand_abbreviation
-- Proposito : Aplica el diccionario vigente token por token: cra->carrera, apto->
--             apartamento, y elimina el ruido. El normalizador de Dart implementa la misma
--             logica pero lee LOS MISMOS DATOS via /v1/dictionary.
-- Parametros: p_text (ya normalizado), p_version (NULL = vigente)
-- Retorna   : text
-- Errores   : ninguno
-- Nota      : STABLE, no IMMUTABLE: lee tabla. No usar en indices — se indexa el resultado
--             materializado en las columnas *_normalized / search_text.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_expand_abbreviation(
    p_text text, p_version int DEFAULT NULL
) RETURNS text LANGUAGE sql STABLE AS $$
    WITH v AS (
        SELECT id FROM public.dictionary_version
         WHERE (p_version IS NULL AND is_current) OR version = p_version
         LIMIT 1),
    w AS (
        SELECT ordinality AS pos, token
        FROM regexp_split_to_table(COALESCE(p_text,''), ' ') WITH ORDINALITY AS x(token, ordinality))
    SELECT btrim(regexp_replace(
             string_agg(CASE WHEN a.abbreviation_kind_id = 'noise' THEN ''
                             ELSE COALESCE(a.output, w.token) END, ' ' ORDER BY w.pos),
             '\s+', ' ', 'g'))
    FROM w LEFT JOIN v ON true
    LEFT JOIN public.abbreviation a
           ON a.dictionary_version_id = v.id AND a.input = w.token;
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_dictionary_delta
-- Proposito : Payload de /v1/dictionary. Con p_since_version NULL devuelve todo; con un
--             numero devuelve up_to_date si la app ya esta al dia.
-- Parametros: p_since_version
-- Retorna   : jsonb {version, checksum, up_to_date, via_types[], abbreviations[], city_aliases[]}
-- Errores   : VT030 no hay version vigente publicada
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_dictionary_delta(p_since_version int DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE v record;
BEGIN
    SELECT * INTO v FROM public.dictionary_version WHERE is_current LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no hay dictionary_version vigente' USING ERRCODE = 'VT030';
    END IF;

    IF p_since_version IS NOT NULL AND p_since_version >= v.version THEN
        RETURN jsonb_build_object('version', v.version, 'up_to_date', true);
    END IF;

    RETURN jsonb_build_object(
        'version', v.version, 'checksum', v.checksum,
        'published_at', v.published_at, 'up_to_date', false,
        'via_types', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('id',id,'label',canonical_label,'short',short_label)
                   ORDER BY sort_order) FROM public.via_type), '[]'::jsonb),
        'abbreviations', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('input',a.input,'output',a.output,
                                                'kind',a.abbreviation_kind_id,'priority',a.priority)
                   ORDER BY a.priority, a.input)
            FROM public.abbreviation a WHERE a.dictionary_version_id = v.id), '[]'::jsonb),
        'city_aliases', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('alias',c.alias,'municipality_id',c.municipality_id)
                   ORDER BY c.alias)
            FROM public.city_alias c WHERE c.dictionary_version_id = v.id), '[]'::jsonb));
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.prc_publish_dictionary_version
-- Proposito : Publica una version nueva del diccionario y la marca vigente, en una sola
--             transaccion. Las versiones son inmutables: no se edita una publicada.
-- Parametros: p_entries jsonb [{input,output,kind,priority}], p_aliases jsonb
--             [{alias,municipality_id}], p_note, p_result INOUT
-- Errores   : VT031 payload vacio o mal formado
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE public.prc_publish_dictionary_version(
    p_entries jsonb,
    p_aliases jsonb DEFAULT '[]'::jsonb,
    p_note    text  DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_version int; v_id int; v_checksum text; v_n int; v_a int;
BEGIN
    IF p_entries IS NULL OR jsonb_typeof(p_entries) <> 'array' OR jsonb_array_length(p_entries) = 0 THEN
        RAISE EXCEPTION 'p_entries debe ser un array no vacio' USING ERRCODE = 'VT031';
    END IF;

    SELECT COALESCE(max(version), 0) + 1 INTO v_version FROM public.dictionary_version;
    v_checksum := encode(digest(p_entries::text || p_aliases::text, 'sha256'), 'hex');

    UPDATE public.dictionary_version SET is_current = false WHERE is_current;

    INSERT INTO public.dictionary_version (version, checksum, is_current, note)
    VALUES (v_version, v_checksum, true, p_note) RETURNING id INTO v_id;

    INSERT INTO public.abbreviation (dictionary_version_id, abbreviation_kind_id, input, output, priority)
    SELECT v_id, COALESCE(e.kind,'via_type'), public.fnc_normalize_text(e.input),
           lower(COALESCE(e.output,'')), COALESCE(e.priority, 100)
    FROM jsonb_to_recordset(p_entries) AS e(input text, output text, kind text, priority smallint)
    WHERE e.input IS NOT NULL
    ON CONFLICT (dictionary_version_id, input) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    INSERT INTO public.city_alias (dictionary_version_id, municipality_id, alias)
    SELECT v_id, a.municipality_id, public.fnc_normalize_text(a.alias)
    FROM jsonb_to_recordset(p_aliases) AS a(alias text, municipality_id text)
    WHERE a.alias IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.municipality m WHERE m.id = a.municipality_id)
    ON CONFLICT (dictionary_version_id, alias) DO NOTHING;
    GET DIAGNOSTICS v_a = ROW_COUNT;

    p_result := jsonb_build_object('version', v_version, 'checksum', v_checksum,
                                   'abbreviation_count', v_n, 'alias_count', v_a);
END $$;

-- =====================================================================================
-- 7. BUSQUEDA
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.fnc_search_place
-- Proposito : Busqueda local en cascada, en un solo viaje a la BD:
--               1 cache exacto  2 alias  3 similitud sobre place  4 via  5 interseccion
--             El ms llama SOLO a esto. Si devuelve 0 filas, entonces (y solo entonces)
--             consulta Nominatim y persiste con geo.prc_resolve_from_provider.
-- Parametros: p_query, p_municipality_id, p_lat, p_lon (sesgo), p_limit
-- Retorna   : SETOF (result_kind, place_id, street_id, intersection_id, label, context,
--                    lat, lon, municipality_id, confidence, geocode_resolver_id, is_verified)
-- Errores   : ninguno — sin resultados son 0 filas, no una excepcion
-- Nota      : el sesgo por distancia solo DESEMPATA. No reordena por encima del match
--             textual: el usuario busca lo que escribio, no lo que tiene cerca.
--             Las vias e intersecciones NO devuelven place_id: no se inventan lugares
--             falsos para poder cachearlos. Son rapidas por indice y no necesitan cache.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
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
BEGIN
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

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.fnc_reverse_lookup
-- Proposito : Reverse geocoding local: lugar mas cercano dentro del radio, sirviendose del
--             cache por geohash cuando existe.
-- Parametros: p_lat, p_lon, p_max_distance_m (NULL = geocode.reverse_max_distance_m)
-- Retorna   : jsonb {place_id, label, distance_m, geocode_resolver_id} o NULL
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION geo.fnc_reverse_lookup(
    p_lat double precision, p_lon double precision, p_max_distance_m numeric DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_pt   geometry := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326);
    v_prec int      := public.fnc_setting_num('geocode.reverse_precision')::int;
    v_max  numeric  := COALESCE(p_max_distance_m, public.fnc_setting_num('geocode.reverse_max_distance_m'));
    v_hash text;
    v_out  jsonb;
BEGIN
    v_hash := ST_GeoHash(v_pt, v_prec);

    SELECT jsonb_build_object('place_id', p.id, 'label', p.label,
                              'distance_m', r.distance_m, 'geocode_resolver_id', 'cache')
      INTO v_out
      FROM geo.reverse_cache r JOIN geo.place p ON p.id = r.place_id
     WHERE r.geohash = v_hash AND (r.expires_at IS NULL OR r.expires_at > now());
    IF v_out IS NOT NULL THEN RETURN v_out; END IF;

    SELECT jsonb_build_object('place_id', p.id, 'label', p.label,
             'distance_m', round(ST_Distance(p.geom::geography, v_pt::geography)::numeric, 2),
             'geocode_resolver_id', 'place')
      INTO v_out
      FROM geo.place p
     WHERE ST_DWithin(p.geom::geography, v_pt::geography, v_max)
     ORDER BY p.geom <-> v_pt
     LIMIT 1;

    RETURN v_out;
END $$;

-- =====================================================================================
-- 8. APRENDIZAJE — lo que resuelve el proveedor se queda
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.prc_resolve_from_provider
-- Proposito : Persiste el resultado OK de Nominatim: upsert del lugar canonico, registro
--             del par query->place y alias. Es el mecanismo por el cual el sistema aprende
--             y deja de depender del proveedor externo.
-- Parametros: p_device_id, p_query_raw, p_municipality_id,
--             p_provider jsonb {label, lat, lon, kind, external_ref, confidence}
--             p_result INOUT {place_id, created, query_cached}
-- Errores   : VT032 payload del proveedor sin lat/lon · VT034 place_kind invalido
-- Nota      : idempotente por external_ref. Si el proveedor devuelve el mismo osm ref con
--             otra etiqueta, se conserva el lugar y la etiqueta nueva entra como alias:
--             ninguna forma de escribir una direccion se pierde.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE geo.prc_resolve_from_provider(
    p_device_id       uuid,
    p_query_raw       text,
    p_municipality_id text,
    p_provider        jsonb,
    INOUT p_result    jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_lat   double precision := (p_provider ->> 'lat')::double precision;
    v_lon   double precision := (p_provider ->> 'lon')::double precision;
    v_label text := p_provider ->> 'label';
    v_ref   text := p_provider ->> 'external_ref';
    v_kind  text := COALESCE(p_provider ->> 'kind', 'address');
    v_base  numeric;
    v_conf  numeric;
    v_norm  text := public.fnc_expand_abbreviation(public.fnc_normalize_text(p_query_raw));
    v_lnorm text := public.fnc_expand_abbreviation(public.fnc_normalize_text(v_label));
    v_ttl   interval := (public.fnc_setting_num('geocode.hit_ttl_days') || ' day')::interval;
    v_place bigint;
    v_created boolean := false;
BEGIN
    IF v_lat IS NULL OR v_lon IS NULL THEN
        RAISE EXCEPTION 'provider sin lat/lon: %', p_provider USING ERRCODE = 'VT032';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.place_kind WHERE id = v_kind) THEN
        RAISE EXCEPTION 'place_kind % invalido', v_kind USING ERRCODE = 'VT034';
    END IF;

    SELECT base_precision INTO v_base FROM public.place_source WHERE id = 'nominatim';
    v_conf := COALESCE((p_provider ->> 'confidence')::numeric, v_base);

    IF v_ref IS NOT NULL THEN
        SELECT id INTO v_place FROM geo.place WHERE external_ref = v_ref;
    END IF;

    IF v_place IS NULL THEN
        INSERT INTO geo.place (place_kind_id, place_source_id, label, label_normalized,
                               municipality_id, external_ref, geom, precision_score, usage_count)
        VALUES (v_kind, 'nominatim', v_label, v_lnorm, p_municipality_id, v_ref,
                ST_SetSRID(ST_MakePoint(v_lon, v_lat), 4326), v_base, 1)
        RETURNING id INTO v_place;
        v_created := true;
    ELSE
        UPDATE geo.place
           SET usage_count = usage_count + 1, last_seen_at = now()
         WHERE id = v_place;

        INSERT INTO geo.place_alias (place_id, alias_normalized, place_source_id)
        SELECT v_place, v_lnorm, 'nominatim'
         WHERE v_lnorm IS NOT NULL
           AND v_lnorm <> (SELECT label_normalized FROM geo.place WHERE id = v_place)
        ON CONFLICT (place_id, alias_normalized)
        DO UPDATE SET hit_count = place_alias.hit_count + 1;
    END IF;

    INSERT INTO geo.geocode_query (query_raw, query_normalized, municipality_id, place_id,
                                   geocode_resolver_id, confidence, first_device_id, expires_at)
    VALUES (p_query_raw, v_norm, p_municipality_id, v_place, 'nominatim', v_conf,
            p_device_id, now() + v_ttl)
    ON CONFLICT (query_normalized, COALESCE(municipality_id, '')) DO UPDATE SET
        place_id            = EXCLUDED.place_id,
        geocode_resolver_id = EXCLUDED.geocode_resolver_id,
        confidence          = EXCLUDED.confidence,
        hit_count           = geocode_query.hit_count + 1,
        last_requested_at   = now(),
        expires_at          = EXCLUDED.expires_at;

    p_result := jsonb_build_object('place_id', v_place, 'created', v_created, 'query_cached', true);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.prc_record_geocode_hit
-- Proposito : Contabiliza una busqueda resuelta localmente: sube usage_count del lugar y
--             refresca el cache de query. Alimenta el ranking y la metrica de cuanto te
--             ahorras de Nominatim.
-- Parametros: p_place_id (NULL = no cachear, caso via/interseccion), p_query_raw,
--             p_municipality_id, p_device_id, p_resolver
-- Errores   : VT035 resolver invalido
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE geo.prc_record_geocode_hit(
    p_place_id        bigint,
    p_query_raw       text,
    p_municipality_id text DEFAULT NULL,
    p_device_id       uuid DEFAULT NULL,
    p_resolver        text DEFAULT 'place'
) LANGUAGE plpgsql AS $$
DECLARE v_norm text := public.fnc_expand_abbreviation(public.fnc_normalize_text(p_query_raw));
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.geocode_resolver WHERE id = p_resolver) THEN
        RAISE EXCEPTION 'geocode_resolver % invalido', p_resolver USING ERRCODE = 'VT035';
    END IF;
    IF p_place_id IS NULL THEN RETURN; END IF;

    UPDATE geo.place SET usage_count = usage_count + 1, last_seen_at = now() WHERE id = p_place_id;

    INSERT INTO geo.geocode_query (query_raw, query_normalized, municipality_id, place_id,
                                   geocode_resolver_id, first_device_id)
    VALUES (p_query_raw, v_norm, p_municipality_id, p_place_id, p_resolver, p_device_id)
    ON CONFLICT (query_normalized, COALESCE(municipality_id, '')) DO UPDATE SET
        hit_count = geocode_query.hit_count + 1, last_requested_at = now();
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.prc_record_geocode_miss
-- Proposito : Cachea el fallo con TTL corto. Sin esto, cada dedazo interroga a Nominatim
--             para siempre y el usuario paga la latencia cada vez.
-- Parametros: p_device_id, p_query_raw, p_municipality_id
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE geo.prc_record_geocode_miss(
    p_device_id uuid, p_query_raw text, p_municipality_id text DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_norm text := public.fnc_expand_abbreviation(public.fnc_normalize_text(p_query_raw));
    v_ttl  interval := (public.fnc_setting_num('geocode.miss_ttl_days') || ' day')::interval;
BEGIN
    INSERT INTO geo.geocode_query (query_raw, query_normalized, municipality_id, place_id,
                                   geocode_resolver_id, first_device_id, expires_at)
    VALUES (p_query_raw, v_norm, p_municipality_id, NULL, 'miss', p_device_id, now() + v_ttl)
    ON CONFLICT (query_normalized, COALESCE(municipality_id, '')) DO UPDATE SET
        hit_count = geocode_query.hit_count + 1,
        last_requested_at = now(), expires_at = EXCLUDED.expires_at;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.prc_verify_place
-- Proposito : Marca un lugar como verificado cuando un viaje real termino cerca, y le sube
--             la precision. Es la senal que con el tiempo hace este geocoder mejor que
--             Nominatim para Colombia.
-- Parametros: p_place_id, p_trip_id, p_end_geom, p_result INOUT {verified, distance_m}
-- Errores   : VT033 place inexistente
-- Nota      : un lugar verificado deja de expirar en el cache. Contrapartida conocida: si
--             OSM corrige la coordenada, la vieja se queda. Ver prc_refresh_stale_place.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE geo.prc_verify_place(
    p_place_id bigint, p_trip_id uuid, p_end_geom geometry,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_geom geometry; v_dist numeric;
    v_rad   numeric := public.fnc_setting_num('geocode.verify_radius_m');
    v_bonus numeric := public.fnc_setting_num('geocode.verify_score_bonus');
BEGIN
    SELECT geom INTO v_geom FROM geo.place WHERE id = p_place_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'place % inexistente', p_place_id USING ERRCODE = 'VT033';
    END IF;

    v_dist := round(ST_Distance(v_geom::geography, p_end_geom::geography)::numeric, 2);

    IF v_dist <= v_rad THEN
        UPDATE geo.place
           SET is_verified = true,
               precision_score = LEAST(1.000, precision_score + v_bonus),
               last_seen_at = now()
         WHERE id = p_place_id;
        UPDATE geo.geocode_query SET expires_at = NULL WHERE place_id = p_place_id;
    END IF;

    p_result := jsonb_build_object('verified', v_dist <= v_rad, 'distance_m', v_dist);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.prc_refresh_stale_place
-- Proposito : Devuelve los lugares verificados que llevan mas de p_days sin revisarse,
--             para que el ms los revalide contra Nominatim. Cierra el agujero de "un lugar
--             verificado nunca vuelve a compararse con la realidad".
-- Parametros: p_days, p_limit, p_result INOUT {candidates:[{place_id,label,lat,lon}]}
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE geo.prc_refresh_stale_place(
    p_days int DEFAULT 180, p_limit int DEFAULT 200, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
    p_result := jsonb_build_object('candidates', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('place_id', p.id, 'label', p.label,
                                            'external_ref', p.external_ref,
                                            'lat', ST_Y(p.geom), 'lon', ST_X(p.geom)))
        FROM (SELECT * FROM geo.place
               WHERE is_verified AND external_ref IS NOT NULL
                 AND last_seen_at < now() - (p_days || ' day')::interval
               ORDER BY usage_count DESC LIMIT p_limit) p), '[]'::jsonb));
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.prc_purge_geocode_query
-- Proposito : Contiene la tabla que mas puede crecer: borra queries frias de un solo uso y
--             cache vencido. La llama el mantenimiento diario.
-- Parametros: p_result INOUT {deleted_cold, deleted_expired, deleted_reverse}
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE geo.prc_purge_geocode_query(INOUT p_result jsonb DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_run  bigint;
    v_days int := public.fnc_setting_num('geocode.cold_purge_days')::int;
    v_cold int; v_exp int; v_rev int;
BEGIN
    INSERT INTO ops.pipeline_run (pipeline_job_id, run_status_id)
    VALUES ('geocode_purge','running') RETURNING id INTO v_run;

    DELETE FROM geo.geocode_query
     WHERE hit_count = 1 AND last_requested_at < now() - (v_days || ' day')::interval;
    GET DIAGNOSTICS v_cold = ROW_COUNT;

    DELETE FROM geo.geocode_query
     WHERE expires_at IS NOT NULL AND expires_at < now() - interval '7 day';
    GET DIAGNOSTICS v_exp = ROW_COUNT;

    DELETE FROM geo.reverse_cache WHERE expires_at IS NOT NULL AND expires_at < now();
    GET DIAGNOSTICS v_rev = ROW_COUNT;

    UPDATE ops.pipeline_run
       SET run_status_id='success', finished_at=now(), row_count = v_cold + v_exp + v_rev
     WHERE id = v_run;

    p_result := jsonb_build_object('deleted_cold', v_cold, 'deleted_expired', v_exp,
                                   'deleted_reverse', v_rev);
END $$;

-- =====================================================================================
-- 9. LECTURA DE METRICAS
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.fnc_geocode_stats
-- Proposito : Cuanto resuelve PG solo y cuanto sigue dependiendo de Nominatim. Es el KPI
--             que dice si el geocoder propio esta funcionando.
-- Parametros: p_from, p_to
-- Retorna   : SETOF (geocode_resolver_id, is_local, query_count, hit_count)
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION geo.fnc_geocode_stats(p_from timestamptz, p_to timestamptz)
RETURNS TABLE (geocode_resolver_id text, is_local boolean, query_count bigint, hit_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT r.id, r.is_local, count(q.id), COALESCE(sum(q.hit_count), 0)
    FROM public.geocode_resolver r
    LEFT JOIN geo.geocode_query q
           ON q.geocode_resolver_id = r.id
          AND q.last_requested_at >= p_from AND q.last_requested_at < p_to
    GROUP BY r.id, r.is_local
    ORDER BY r.is_local DESC, 3 DESC;
$$;

-- =====================================================================================
-- 10. REGISTRO Y PERMISOS
-- =====================================================================================

INSERT INTO public.db_routine (schema_name, routine_name, routine_type, purpose, author, version, migration) VALUES
 ('public','fnc_normalize_text','function','Texto canonico inmutable para indices y comparacion','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('public','fnc_expand_abbreviation','function','Expansion de abreviaturas del diccionario vigente','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('public','fnc_dictionary_delta','function','Payload de /v1/dictionary','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('public','prc_publish_dictionary_version','procedure','Publica version nueva del diccionario','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('geo','fnc_search_place','function','Busqueda local en cascada de direcciones','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('geo','fnc_reverse_lookup','function','Reverse geocoding local con cache por geohash','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('geo','prc_resolve_from_provider','procedure','Persiste el resultado OK de Nominatim','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('geo','prc_record_geocode_hit','procedure','Contabiliza acierto local y alimenta el ranking','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('geo','prc_record_geocode_miss','procedure','Cachea busquedas sin resultado','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('geo','prc_verify_place','procedure','Verifica un lugar con el final de un viaje real','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('geo','prc_refresh_stale_place','procedure','Candidatos verificados a revalidar contra el proveedor','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('geo','prc_purge_geocode_query','procedure','Purga de cache frio de geocoding','Lucho · Devitech','1.0.0','002_geocoding.sql'),
 ('geo','fnc_geocode_stats','function','KPI de dependencia de Nominatim','Lucho · Devitech','1.0.0','002_geocoding.sql')
ON CONFLICT (schema_name, routine_name) DO UPDATE SET
    purpose = EXCLUDED.purpose, author = EXCLUDED.author,
    version = EXCLUDED.version, migration = EXCLUDED.migration, updated_at = now();

GRANT SELECT ON
    public.municipality,
    public.place_kind, public.place_source, public.geocode_resolver, public.via_type,
    public.oneway_kind, public.abbreviation_kind, public.dictionary_version,
    public.abbreviation, public.city_alias,
    geo.place, geo.place_alias, geo.geocode_query, geo.reverse_cache,
    geo.street, geo.street_intersection, geo.neighborhood
TO vehitrack_app;

-- DML del conocimiento geografico: la app aprende (Nominatim -> geo.place) y contabiliza
-- aciertos/fallos SOLO a traves de las prc_ (SECURITY INVOKER). Por eso el rol necesita DML
-- sobre las tablas de cache que esas rutinas modifican; sin esto, prc_record_geocode_hit/miss
-- y prc_resolve_from_provider fallan con "permission denied". La disciplina de "cero DML crudo
-- en infrastructure/postgres" la sostiene el code review (ADR-004), no la falta de privilegio.
-- geo.* es GLOBAL (sin RLS): estas escrituras no cruzan tenants.
GRANT INSERT, UPDATE         ON geo.place, geo.place_alias      TO vehitrack_app;
GRANT INSERT, UPDATE, DELETE ON geo.geocode_query, geo.reverse_cache TO vehitrack_app;

GRANT EXECUTE ON FUNCTION
    public.fnc_normalize_text(text),
    public.fnc_expand_abbreviation(text, int),
    public.fnc_dictionary_delta(int),
    geo.fnc_search_place(text, text, double precision, double precision, int),
    geo.fnc_reverse_lookup(double precision, double precision, numeric)
TO vehitrack_app;

GRANT EXECUTE ON PROCEDURE
    geo.prc_resolve_from_provider(uuid, text, text, jsonb, jsonb),
    geo.prc_record_geocode_hit(bigint, text, text, uuid, text),
    geo.prc_record_geocode_miss(uuid, text, text),
    geo.prc_verify_place(bigint, uuid, geometry, jsonb)
TO vehitrack_app;

-- administracion: no van al rol de la app
REVOKE EXECUTE ON PROCEDURE public.prc_publish_dictionary_version(jsonb, jsonb, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE geo.prc_purge_geocode_query(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE geo.prc_refresh_stale_place(int, int, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION geo.fnc_geocode_stats(timestamptz, timestamptz) FROM PUBLIC;

COMMIT;

-- =====================================================================================
-- 11. SEMILLA Y VERIFICACION
--
-- CALL public.prc_publish_dictionary_version('[
--   {"input":"cra","output":"carrera","kind":"via_type"},
--   {"input":"cr","output":"carrera","kind":"via_type"},
--   {"input":"kra","output":"carrera","kind":"via_type"},
--   {"input":"k","output":"carrera","kind":"via_type"},
--   {"input":"cll","output":"calle","kind":"via_type"},
--   {"input":"cl","output":"calle","kind":"via_type"},
--   {"input":"av","output":"avenida","kind":"via_type"},
--   {"input":"dg","output":"diagonal","kind":"via_type"},
--   {"input":"tv","output":"transversal","kind":"via_type"},
--   {"input":"apto","output":"apartamento","kind":"unit"},
--   {"input":"of","output":"oficina","kind":"unit"},
--   {"input":"no","output":"#","kind":"ordinal"},
--   {"input":"nro","output":"#","kind":"ordinal"},
--   {"input":"barrio","output":"","kind":"noise"},
--   {"input":"urb","output":"","kind":"noise"}
-- ]'::jsonb, '[]'::jsonb, 'semilla inicial', NULL);
--
--   SELECT public.fnc_expand_abbreviation(public.fnc_normalize_text('Cra15 No 45-30 Apto 302'));
--   -- esperado: carrera 15 # 45-30 apartamento 302
--
--   SELECT * FROM geo.fnc_search_place('cra 15 45', 'co-atl-barranquilla', NULL, NULL, 8);
--   SELECT * FROM geo.fnc_geocode_stats(now() - interval '7 day', now());
--
-- El set de 100 direcciones reales de Barranquilla escritas COMO LAS ESCRIBE LA GENTE es
-- el test de regresion permanente. Sin el, no vas a saber si un cambio de ranking mejoro
-- o empeoro las cosas.
-- =====================================================================================
