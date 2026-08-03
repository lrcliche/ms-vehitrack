#!/usr/bin/env bash
# =====================================================================================
# VehiTrack · scripts/import_municipality_geom.sh
# Rellena public.municipality.geom (MultiPolygon 4326) con los limites municipales del
# DANE MGN, casando por DIVIPOLA. NO inventa geometrias: solo carga las oficiales.
#
# Requisitos previos (en orden):
#   1. migrations/001..004 aplicadas.
#   2. seeds/municipality_co.sql        (los 1104 municipios).
#   3. seeds/municipality_divipola.sql  (la columna/llave divipola).
#   4. ogr2ogr + psql en el PATH (vienen con PostgreSQL 17 / PostGIS).
#
# La descarga del MGN es interactiva (geoportal DANE). Bajas el paquete de MUNICIPIOS
# 2023 en Shapefile o GeoPackage y le pasas la ruta a este script:
#   https://geoportal.dane.gov.co/servicios/descarga-y-metadatos/descarga-mgn/
#
# Uso:
#   POSTGRES_DSN="postgresql://user:pass@host:5432/vehitrack" \
#     ./scripts/import_municipality_geom.sh /ruta/MGN_MPIO_POLITICO.shp
#
# El segundo argumento puede ser .shp o .gpkg (con -l capa). Ver NOTA de campos abajo.
# =====================================================================================
set -euo pipefail

SRC="${1:?Pasa la ruta al shapefile/gpkg de municipios del MGN}"
DSN="${POSTGRES_DSN:?Exporta POSTGRES_DSN con el rol dueno (no vehitrack_app)}"
STG="stg_mgn_municipio"

# NOTA de campos: en el MGN 2023 la capa de municipios trae el codigo DIVIPOLA en
# MPIO_CDPMP (5 chars) y el nombre en MPIO_CNMBR. ogr2ogr baja los nombres a minuscula
# al cargar a PostGIS -> mpio_cdpmp. Confirma con:  ogrinfo -so -al "$SRC"
# Si tu version del MGN usa otro nombre de campo, ajusta MPIO_CDPMP_COL abajo.
MPIO_CDPMP_COL="mpio_cdpmp"

echo ">> 1/3  ogrinfo — campos disponibles en la fuente:"
ogrinfo -so -al "$SRC" | grep -iE 'cdpmp|cnmbr|dpto|Geometry|Feature Count' || true

# NOTA: el GDAL que trae PostgreSQL puede no incluir el driver 'PostgreSQL' en vivo (probado:
# solo trae PGDUMP de salida). Por eso se genera un SQL dump y se carga con psql — funciona
# igual con .shp o .gpkg. Verifica con:  ogr2ogr --formats | grep -i postgres
echo ">> 2/3  ogr2ogr -f PGDump -> staging ${STG}, luego psql lo carga (reproyecta a 4326)..."
STG_SQL="$(mktemp --suffix=.sql 2>/dev/null || echo "${TMPDIR:-/tmp}/vehitrack_stg_$$.sql")"
ogr2ogr -f PGDump "$STG_SQL" "$SRC" \
  -nln "$STG" \
  -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI -dim 2 \
  -lco GEOMETRY_NAME=geom -lco SRID=4326 \
  -lco CREATE_SCHEMA=OFF -lco DROP_TABLE=IF_EXISTS -lco SPATIAL_INDEX=NONE
psql "$DSN" -v ON_ERROR_STOP=1 -q -f "$STG_SQL"
rm -f "$STG_SQL"

echo ">> 3/3  UPDATE municipality.geom por DIVIPOLA (dentro de una transaccion)..."
psql "$DSN" -v ON_ERROR_STOP=1 <<SQL
BEGIN;

-- ST_MakeValid corrige poligonos con self-intersection (comunes en cartografia oficial);
-- CollectionExtract(...,3) se queda SOLO con poligonos si MakeValid devolvio una coleccion;
-- ST_Multi + cast garantiza el tipo exacto de la columna (MultiPolygon,4326).
UPDATE public.municipality m
   SET geom = ST_Multi(
                ST_CollectionExtract(
                  ST_MakeValid(ST_Force2D(s.geom)), 3
                ))::geometry(MultiPolygon,4326)
  FROM ${STG} s
 WHERE s.${MPIO_CDPMP_COL}::char(5) = m.divipola;

\echo '== conteo con/sin geom =='
SELECT count(*) FILTER (WHERE geom IS NOT NULL) AS con_geom,
       count(*) FILTER (WHERE geom IS NULL)     AS sin_geom
  FROM public.municipality;

\echo '== municipios sin geom =='
SELECT m.divipola, m.id, m.name
  FROM public.municipality m
 WHERE m.geom IS NULL
 ORDER BY m.divipola;

DROP TABLE ${STG};
COMMIT;
SQL

echo ">> Listo. Si 'sin geom' > 0, revisa el nombre del campo DIVIPOLA (MPIO_CDPMP_COL)"
echo ">> o si esa version del MGN no incluye esos municipios."
