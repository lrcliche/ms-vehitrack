#!/usr/bin/env bash
# =====================================================================================
# VehiTrack · scripts/import_streets_osm.sh
# Importa las calles (y sus cruces) de UN municipio desde OpenStreetMap (Overpass) a
# geo.street / geo.street_intersection. Enciende la busqueda de direcciones LOCAL:
# sin esto, /v1/geocode/search cae a Nominatim.
#
# Es demanda-dirigido: se corre por ciudad donde hay usuarios, NO para las 1104. El
# resto del pais se autopobla via aprendizaje de Nominatim (geo.place).
#
# Requisitos: municipality.geom del municipio ya cargado (import_municipality_geom),
#   y en el PATH: curl, python3, ogr2ogr (gdal-bin), psql. Internet (Overpass).
#
# Uso:
#   POSTGRES_DSN="postgres://DUENO:pass@host:5432/db?sslmode=disable" \
#     ./scripts/import_streets_osm.sh [municipality_id]
#   (municipality_id por defecto: co-atl-barranquilla)
#
# Idempotente: borra y reinserta las calles/cruces del municipio (DELETE por scope).
# =====================================================================================
set -euo pipefail

MID="${1:-co-atl-barranquilla}"
DSN="${POSTGRES_DSN:?Exporta POSTGRES_DSN con el rol dueno (no vehitrack_app)}"
OVERPASS="${OVERPASS_URL:-https://overpass-api.de/api/interpreter}"
export PGCLIENTENCODING=UTF8

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/vt_streets_$$")"; mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

echo ">> 1/5  bbox de $MID (de municipality.geom)"
BBOX="$(psql "$DSN" -tA -F' ' -c \
  "SELECT ST_YMin(geom),ST_XMin(geom),ST_YMax(geom),ST_XMax(geom)
     FROM public.municipality WHERE id='$MID' AND geom IS NOT NULL")"
[ -n "$BBOX" ] || { echo "ERROR: $MID no existe o no tiene geom (corre import_municipality_geom primero)"; exit 1; }
read -r S W N E <<< "$BBOX"
echo "   S=$S W=$W N=$N E=$E"

echo ">> 2/5  Overpass: vias con nombre en el bbox"
Q="[out:json][timeout:240];way[\"highway\"][\"name\"]($S,$W,$N,$E);out geom;"
curl -s --max-time 300 -G "$OVERPASS" --data-urlencode "data=$Q" -o "$WORK/osm.json"
grep -q '"elements"' "$WORK/osm.json" || { echo "ERROR: respuesta Overpass invalida"; head -c 300 "$WORK/osm.json"; exit 1; }

echo ">> 3/5  Overpass JSON -> GeoJSON (solo vias manejables)"
python3 - "$WORK/osm.json" "$WORK/streets.geojson" <<'PY'
import json,sys
inp,out=sys.argv[1],sys.argv[2]
DRIVE={'motorway','trunk','primary','secondary','tertiary','unclassified','residential',
       'living_street','road','busway','motorway_link','trunk_link','primary_link',
       'secondary_link','tertiary_link'}
d=json.load(open(inp,encoding='utf-8'))
feats=[]
for w in d.get('elements',[]):
    if w.get('type')!='way': continue
    t=w.get('tags',{})
    if t.get('highway') not in DRIVE or not t.get('name'): continue
    c=[[g['lon'],g['lat']] for g in w.get('geometry',[])]
    if len(c)<2: continue
    feats.append({"type":"Feature","properties":{
        "osm_id":str(w['id']),"name":t['name'],"highway":t['highway'],
        "oneway":t.get('oneway'),"maxspeed":t.get('maxspeed')},
        "geometry":{"type":"LineString","coordinates":c}})
json.dump({"type":"FeatureCollection","features":feats},
          open(out,'w',encoding='utf-8'),ensure_ascii=False)
print(f"   vias manejables: {len(feats)}")
PY

echo ">> 4/5  ogr2ogr -f PGDump -> psql (staging stg_osm_street)"
ogr2ogr -f PGDump "$WORK/stg.sql" "$WORK/streets.geojson" \
  -nln stg_osm_street -nlt LINESTRING -lco GEOMETRY_NAME=geom -lco SRID=4326 \
  -lco CREATE_SCHEMA=OFF -lco DROP_TABLE=IF_EXISTS -lco SPATIAL_INDEX=NONE
psql "$DSN" -q -v ON_ERROR_STOP=1 -f "$WORK/stg.sql"

echo ">> 5/5  transform -> geo.street + geo.street_intersection (recorte por el poligono)"
psql "$DSN" -v ON_ERROR_STOP=1 -v mid="$MID" <<'SQL'
BEGIN;
-- CALLES: una fila por via OSM (geom de una linea, para que ST_LineMerge de fnc_search_place
-- devuelva LineString). full_name/search_text para el trigram; via_type/numero best-effort.
DELETE FROM geo.street WHERE municipality_id = :'mid';
WITH muni AS (SELECT geom FROM public.municipality WHERE id = :'mid'),
w AS (
  SELECT s.osm_id, s.name, s.maxspeed, s.oneway,
         public.fnc_expand_abbreviation(public.fnc_normalize_text(s.name)) AS norm,
         ST_Multi(s.geom)::geometry(MultiLineString,4326) AS geom
  FROM stg_osm_street s, muni
  WHERE ST_Intersects(s.geom, muni.geom)
)
INSERT INTO geo.street (municipality_id, osm_way_id, via_type_id, via_number,
                        full_name, search_text, oneway_kind_id, speed_limit_kmh, geom)
SELECT :'mid', w.osm_id,
       (SELECT vt.id FROM public.via_type vt
         WHERE w.norm=vt.id OR w.norm LIKE vt.id||' %' ORDER BY length(vt.id) DESC LIMIT 1),
       substring(w.norm from '^[a-z]+ (#?[0-9][0-9a-z]*)'),
       w.name, w.norm,
       CASE lower(coalesce(w.oneway,'')) WHEN 'yes' THEN 'yes' WHEN '-1' THEN 'reverse'
            WHEN 'no' THEN 'no' ELSE 'unknown' END,
       NULLIF(regexp_replace(coalesce(w.maxspeed,''),'[^0-9]','','g'),'')::int,
       w.geom
FROM w WHERE w.norm <> ''
ON CONFLICT (municipality_id, osm_way_id) DO UPDATE SET
   full_name=EXCLUDED.full_name, search_text=EXCLUDED.search_text,
   via_type_id=EXCLUDED.via_type_id, via_number=EXCLUDED.via_number,
   oneway_kind_id=EXCLUDED.oneway_kind_id, speed_limit_kmh=EXCLUDED.speed_limit_kmh,
   geom=EXCLUDED.geom;

-- CRUCES: un punto representativo por par de NOMBRES de calle que se cruzan.
DELETE FROM geo.street_intersection x USING geo.street a
 WHERE x.street_a_id=a.id AND a.municipality_id = :'mid';
WITH raw AS (
  SELECT a.id aid, b.id bid, a.full_name fa, b.full_name fb,
         a.search_text sa, b.search_text sb,
         ST_CollectionExtract(ST_Intersection(a.geom,b.geom),1) AS pts
  FROM geo.street a
  JOIN geo.street b ON a.id<b.id AND a.full_name<>b.full_name AND ST_Intersects(a.geom,b.geom)
  WHERE a.municipality_id = :'mid' AND b.municipality_id = :'mid'
),
ded AS (
  SELECT DISTINCT ON (LEAST(fa,fb), GREATEST(fa,fb)) aid, bid, sa, sb, ST_Centroid(pts) pt
  FROM raw WHERE NOT ST_IsEmpty(pts)
  ORDER BY LEAST(fa,fb), GREATEST(fa,fb)
)
INSERT INTO geo.street_intersection (street_a_id, street_b_id, search_text, geom)
SELECT aid, bid, sa||' con '||sb, pt FROM ded
ON CONFLICT (street_a_id, street_b_id) DO NOTHING;

DROP TABLE stg_osm_street;
COMMIT;
SQL

echo ">> Resumen:"
psql "$DSN" -c "
SELECT
  (SELECT count(*) FROM geo.street s WHERE s.municipality_id='$MID')            AS calles,
  (SELECT count(*) FROM geo.street_intersection x JOIN geo.street a ON a.id=x.street_a_id
     WHERE a.municipality_id='$MID')                                            AS cruces;"
echo ">> Listo. Prueba: SELECT * FROM geo.fnc_search_place('cra 43','$MID',NULL,NULL,5);"
