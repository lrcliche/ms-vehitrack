#!/usr/bin/env bash
# =====================================================================================
# import_pois_osm.sh — importa PUNTOS DE INTERÉS (POIs) de OSM a geo.place.
#
# Enciende la búsqueda por NOMBRE: parques, malecones, centros comerciales, plazas,
# estadios, universidades, hospitales, etc. Sin esto el geocode solo tiene calles y
# cruces, y buscar "malecon" o "buenavista" no encuentra el lugar.
#
# Requisitos (mismos que import_streets_osm.sh):
#   - En el PATH: curl, python3, ogr2ogr (gdal-bin), psql. Internet (Overpass).
#   - POSTGRES_DSN con el rol DUEÑO (no vehitrack_app):
#       POSTGRES_DSN="postgres://DUENO:pass@host:5432/db?sslmode=disable" \
#         ./scripts/import_pois_osm.sh co-atl-barranquilla
#   - El municipio debe tener geom (corre import_municipality_geom primero).
#
# Idempotente: ON CONFLICT (external_ref) actualiza. Reejecutable.
# =====================================================================================
set -euo pipefail

MID="${1:-co-atl-barranquilla}"
DSN="${POSTGRES_DSN:?Exporta POSTGRES_DSN con el rol dueno (no vehitrack_app)}"
# Varios mirrors: el público (overpass-api.de) suele dar 504 (dispatcher saturado);
# kumi.systems aguanta mejor. OVERPASS_URL, si se pasa, va primero.
OVERPASS_MIRRORS=(
  "${OVERPASS_URL:-}"
  "https://overpass.kumi.systems/api/interpreter"
  "https://overpass-api.de/api/interpreter"
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo ">> 1/5  bbox de $MID (de municipality.geom)"
BBOX="$(psql "$DSN" -tA -F' ' -c \
  "SELECT ST_YMin(geom), ST_XMin(geom), ST_YMax(geom), ST_XMax(geom) \
     FROM public.municipality WHERE id='$MID' AND geom IS NOT NULL")"
[ -n "$BBOX" ] || { echo "ERROR: $MID no existe o no tiene geom (corre import_municipality_geom primero)"; exit 1; }
read -r S W N E <<< "$BBOX"
echo "   S=$S W=$W N=$N E=$E"

echo ">> 2/5  Overpass: POIs con nombre en el bbox"
# nwr = node+way+relation. 'out center' da el centroide de ways/relations.
# En una sola línea (algunos mirrors se atragantan con saltos de línea).
Q="[out:json][timeout:180];(nwr[\"name\"][\"amenity\"]($S,$W,$N,$E);nwr[\"name\"][\"tourism\"]($S,$W,$N,$E);nwr[\"name\"][\"leisure\"]($S,$W,$N,$E);nwr[\"name\"][\"shop\"]($S,$W,$N,$E);nwr[\"name\"][\"historic\"]($S,$W,$N,$E);nwr[\"name\"][\"office\"]($S,$W,$N,$E););out center;"
OK=0
for M in "${OVERPASS_MIRRORS[@]}"; do
  [ -n "$M" ] || continue
  echo "   probando $M"
  curl -s --max-time 300 -G "$M" --data-urlencode "data=$Q" -o "$WORK/osm.json" || true
  if grep -q '"elements"' "$WORK/osm.json" 2>/dev/null; then OK=1; break; fi
  echo "   (mirror no respondió JSON, probando el siguiente)"
done
[ "$OK" = 1 ] || { echo "ERROR: ningun mirror de Overpass respondio JSON"; head -c 300 "$WORK/osm.json"; exit 1; }

echo ">> 3/5  Overpass JSON -> GeoJSON de puntos"
python3 - "$WORK/osm.json" "$WORK/pois.geojson" <<'PY'
import json, sys
inp, out = sys.argv[1], sys.argv[2]
KEYS = ('amenity', 'tourism', 'leisure', 'shop', 'historic', 'office')
d = json.load(open(inp, encoding='utf-8'))
feats, seen = [], set()
for el in d.get('elements', []):
    t = el.get('tags', {})
    name = t.get('name')
    if not name:
        continue
    if el.get('type') == 'node':
        lat, lon = el.get('lat'), el.get('lon')
    else:  # way / relation -> center
        c = el.get('center') or {}
        lat, lon = c.get('lat'), c.get('lon')
    if lat is None or lon is None:
        continue
    ref = 'osm:%s%s' % (el['type'][0], el['id'])
    if ref in seen:
        continue
    seen.add(ref)
    cat = next((t[k] for k in KEYS if t.get(k)), 'poi')
    feats.append({"type": "Feature",
                  "properties": {"external_ref": ref, "name": name, "category": cat},
                  "geometry": {"type": "Point", "coordinates": [lon, lat]}})
json.dump({"type": "FeatureCollection", "features": feats},
          open(out, 'w', encoding='utf-8'), ensure_ascii=False)
print(f"   POIs con nombre: {len(feats)}")
PY

echo ">> 4/5  ogr2ogr -f PGDump -> psql (staging stg_osm_poi)"
ogr2ogr -f PGDump "$WORK/stg.sql" "$WORK/pois.geojson" \
  -nln stg_osm_poi -nlt POINT -lco GEOMETRY_NAME=geom -lco SRID=4326 \
  -lco CREATE_SCHEMA=OFF -lco DROP_TABLE=IF_EXISTS -lco SPATIAL_INDEX=NONE
psql "$DSN" -q -v ON_ERROR_STOP=1 -f "$WORK/stg.sql"

echo ">> 5/5  transform -> geo.place (place_kind='poi', source='osm_import')"
psql "$DSN" -v ON_ERROR_STOP=1 -v mid="$MID" <<'SQL'
INSERT INTO geo.place (place_kind_id, place_source_id, label, label_normalized,
                       municipality_id, external_ref, geom, precision_score, is_verified)
SELECT 'poi', 'osm_import',
       s.name,
       public.fnc_expand_abbreviation(public.fnc_normalize_text(s.name)),
       :'mid', s.external_ref,
       ST_SetSRID(s.geom, 4326)::geometry(Point,4326),
       0.900, false
  FROM stg_osm_poi s
 WHERE s.name IS NOT NULL AND s.name <> ''
ON CONFLICT (external_ref) DO UPDATE SET
   label            = EXCLUDED.label,
   label_normalized = EXCLUDED.label_normalized,
   municipality_id  = EXCLUDED.municipality_id,
   geom             = EXCLUDED.geom,
   last_seen_at     = now();

DROP TABLE stg_osm_poi;
SQL

echo ">> Resumen:"
psql "$DSN" -c "
SELECT count(*) AS pois_del_municipio
  FROM geo.place
 WHERE municipality_id = '$MID' AND place_kind_id = 'poi';"
echo ">> Listo. Prueba:  SELECT label, label_normalized FROM geo.place WHERE label_normalized % 'malecon' LIMIT 5;"
