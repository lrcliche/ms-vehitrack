-- =====================================================================================
-- VehiTrack · seeds/dictionary_co.sql
-- Semilla del diccionario de normalizacion colombiano (Fase 1) + municipio de Barranquilla.
--
-- NO es una migracion: es data. Se aplica DESPUES de 001-004, como dueno.
--   psql "$POSTGRES_DSN" -f seeds/dictionary_co.sql
--
-- Publica la version 1 del diccionario via public.prc_publish_dictionary_version. Corregir o
-- ampliar el diccionario = volver a llamar el procedimiento (sube la version; la app pide el
-- delta por /v1/dictionary sin release en la Play Store).
--
-- El municipio de Barranquilla se siembra a mano aqui solo para que los city_alias no se
-- descarten (prc_publish exige que el municipio exista). El resto de municipios entran con el
-- import OSM.
-- =====================================================================================

BEGIN;

-- Municipio semilla (el geom real llega con el import OSM).
INSERT INTO public.municipality (id, department_id, name) VALUES
  ('co-atl-barranquilla', 'co-atl', 'Barranquilla'),
  ('co-atl-soledad',      'co-atl', 'Soledad')
ON CONFLICT (id) DO NOTHING;

CALL public.prc_publish_dictionary_version(
  -- p_entries: abreviaturas. input se normaliza dentro del procedimiento.
  '[
    {"input":"cra","output":"carrera","kind":"via_type"},
    {"input":"cr","output":"carrera","kind":"via_type"},
    {"input":"kra","output":"carrera","kind":"via_type"},
    {"input":"kr","output":"carrera","kind":"via_type"},
    {"input":"k","output":"carrera","kind":"via_type"},
    {"input":"cll","output":"calle","kind":"via_type"},
    {"input":"cl","output":"calle","kind":"via_type"},
    {"input":"cle","output":"calle","kind":"via_type"},
    {"input":"av","output":"avenida","kind":"via_type"},
    {"input":"avda","output":"avenida","kind":"via_type"},
    {"input":"ave","output":"avenida","kind":"via_type"},
    {"input":"dg","output":"diagonal","kind":"via_type"},
    {"input":"diag","output":"diagonal","kind":"via_type"},
    {"input":"tv","output":"transversal","kind":"via_type"},
    {"input":"trans","output":"transversal","kind":"via_type"},
    {"input":"tr","output":"transversal","kind":"via_type"},
    {"input":"autop","output":"autopista","kind":"via_type"},
    {"input":"circ","output":"circunvalar","kind":"via_type"},
    {"input":"peat","output":"peatonal","kind":"via_type"},
    {"input":"apto","output":"apartamento","kind":"unit"},
    {"input":"apt","output":"apartamento","kind":"unit"},
    {"input":"of","output":"oficina","kind":"unit"},
    {"input":"ofc","output":"oficina","kind":"unit"},
    {"input":"int","output":"interior","kind":"unit"},
    {"input":"bl","output":"bloque","kind":"unit"},
    {"input":"mz","output":"manzana","kind":"unit"},
    {"input":"lc","output":"local","kind":"unit"},
    {"input":"no","output":"#","kind":"ordinal"},
    {"input":"nro","output":"#","kind":"ordinal"},
    {"input":"num","output":"#","kind":"ordinal"},
    {"input":"barrio","output":"","kind":"noise"},
    {"input":"urb","output":"","kind":"noise"},
    {"input":"urbanizacion","output":"","kind":"noise"},
    {"input":"conj","output":"","kind":"noise"},
    {"input":"conjunto","output":"","kind":"noise"},
    {"input":"edif","output":"","kind":"noise"},
    {"input":"edificio","output":"","kind":"noise"}
  ]'::jsonb,
  -- p_aliases: como la gente escribe la ciudad.
  '[
    {"alias":"bquilla","municipality_id":"co-atl-barranquilla"},
    {"alias":"b/quilla","municipality_id":"co-atl-barranquilla"},
    {"alias":"barranqilla","municipality_id":"co-atl-barranquilla"},
    {"alias":"barranquila","municipality_id":"co-atl-barranquilla"}
  ]'::jsonb,
  'semilla inicial CO — Fase 1',
  NULL
);

COMMIT;

-- =====================================================================================
-- VERIFICACION
--   SELECT public.fnc_expand_abbreviation(public.fnc_normalize_text('Cra15 No 45-30 Apto 302'));
--   -- esperado: carrera 15 # 45-30 apartamento 302
--   SELECT * FROM public.fnc_dictionary_delta(NULL);
-- =====================================================================================
