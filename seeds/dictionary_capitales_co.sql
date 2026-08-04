-- =====================================================================================
-- VehiTrack · seeds/dictionary_capitales_co.sql
-- Publica una version nueva del diccionario agregando city_alias para capitales cuyo
-- nombre oficial DANE es compuesto y difiere del nombre comun con que la gente busca:
--   Santiago de Cali      -> cali
--   San Jose de Cucuta    -> cucuta
--   San Andres de Tumaco  -> tumaco
--   Cartagena de Indias   -> cartagena
--   (+ bogota -> co-dc-bogota, por comodidad)
--
-- NO es migracion: es data. Aplicar DESPUES de:
--   1. municipality_co.sql  (los municipality_id referenciados DEBEN existir; prc_publish
--      descarta en silencio cualquier alias cuyo municipio no exista)
--   2. dictionary_co.sql    (de aqui hereda las abreviaturas y los alias ya publicados)
--   psql "$POSTGRES_DSN" -f seeds/dictionary_capitales_co.sql
--
-- Idempotente: si la version vigente ya trae estos alias, no republica (no sube version).
-- Como el diccionario es append-only (cada publish sube version), correrlo repetido SIN el
-- guard inflaria las versiones; el guard lo evita.
-- =====================================================================================

BEGIN;
SET client_encoding TO 'UTF8';

DO $$
DECLARE
  v_cur     int;
  v_entries jsonb;
  v_aliases jsonb;
  v_result  jsonb;   -- INOUT de prc_publish: CALL exige variable escribible, no NULL literal
BEGIN
  SELECT id INTO v_cur FROM public.dictionary_version WHERE is_current;
  IF v_cur IS NULL THEN
    RAISE EXCEPTION 'No hay dictionary_version vigente; corre primero dictionary_co.sql';
  END IF;

  -- guard de idempotencia: si 'cali' ya apunta a Santiago de Cali en la version vigente, salir.
  IF EXISTS (
    SELECT 1 FROM public.city_alias
     WHERE dictionary_version_id = v_cur
       AND alias = 'cali' AND municipality_id = 'co-vac-santiago-de-cali'
  ) THEN
    RAISE NOTICE 'Los alias de capitales ya estan en la version vigente; no se republica.';
    RETURN;
  END IF;

  -- arrastra las abreviaturas vigentes tal cual (p_entries es obligatorio y no vacio).
  SELECT jsonb_agg(jsonb_build_object(
           'input', a.input, 'output', a.output,
           'kind',  a.abbreviation_kind_id, 'priority', a.priority))
    INTO v_entries
    FROM public.abbreviation a
   WHERE a.dictionary_version_id = v_cur;

  -- arrastra los alias vigentes + agrega los de capitales (DISTINCT evita duplicados).
  SELECT jsonb_agg(DISTINCT jsonb_build_object('alias', t.alias, 'municipality_id', t.mid))
    INTO v_aliases
  FROM (
    SELECT c.alias AS alias, c.municipality_id AS mid
      FROM public.city_alias c
     WHERE c.dictionary_version_id = v_cur
    UNION ALL
    SELECT * FROM (VALUES
      ('cali',      'co-vac-santiago-de-cali'),
      ('cucuta',    'co-nsa-san-jose-de-cucuta'),
      ('tumaco',    'co-nar-san-andres-de-tumaco'),
      ('cartagena', 'co-bol-cartagena-de-indias'),
      ('bogota',    'co-dc-bogota')
    ) AS n(alias, mid)
  ) t;

  CALL public.prc_publish_dictionary_version(
    v_entries, v_aliases, 'agrega city_alias de capitales de nombre compuesto', v_result);
END $$;

COMMIT;

-- =====================================================================================
-- VERIFICACION
--   SELECT c.alias, c.municipality_id
--     FROM public.city_alias c JOIN public.dictionary_version v ON v.id=c.dictionary_version_id
--    WHERE v.is_current AND c.alias IN ('cali','cucuta','tumaco','cartagena','bogota')
--    ORDER BY c.alias;
--   SELECT * FROM public.fnc_dictionary_delta(NULL) -> city_aliases[];
-- =====================================================================================
