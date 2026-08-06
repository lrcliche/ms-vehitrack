#!/usr/bin/env bash
# =====================================================================================
# VehiTrack · scripts/import_pois_colombia.sh
# Importa POIs de OSM para TODOS los municipios del país (los que tienen geom). Pensado
# para un run LARGO en `screen`/`tmux` en el VPS: reanudable, resiliente y con pausa.
#
#   - REANUDABLE: por defecto salta el municipio que YA tiene POIs (SKIP_DONE=1). Si el
#     proceso se corta, lo vuelves a lanzar y continúa donde quedó. FORCE=1 reimporta todo.
#   - RESILIENTE: un fallo de ciudad no aborta (set -uo pipefail, sin -e); los fallidos se
#     listan al final para reintentar.
#   - AMABLE con Overpass: pausa SLEEP s entre ciudades; import_pois_osm.sh ya rota mirrors
#     ante 504. Puedes fijar tu propio Overpass con OVERPASS_URL=...
#
# Son ~1104 municipios = ~1104 consultas Overpass -> HORAS. Corre en screen:
#   screen -S pois
#   POSTGRES_DSN="postgres://DUENO:pass@host:5432/db?sslmode=disable" \
#     ./scripts/import_pois_colombia.sh
#   (Ctrl+A, D para soltar; `screen -r pois` para volver)
#
# Opciones:
#   SLEEP=15 ./scripts/import_pois_colombia.sh     # más pausa (Overpass público)
#   FORCE=1  ./scripts/import_pois_colombia.sh     # reimporta también los ya hechos
#   DRYRUN=1 ./scripts/import_pois_colombia.sh     # lista lo que haría, sin importar
#   ./scripts/import_pois_colombia.sh co-atl co-bol   # limita a esos departamentos
# =====================================================================================
set -uo pipefail   # sin -e a proposito: un fallo de ciudad no mata el loop

DSN="${POSTGRES_DSN:?Exporta POSTGRES_DSN con el rol dueno (no vehitrack_app)}"
SLEEP="${SLEEP:-8}"
export PGCLIENTENCODING=UTF8
HERE="$(cd "$(dirname "$0")" && pwd)"

# Filtro opcional por departamento(s); sin argumentos = TODO el país.
DEPTS=("$@")
if [ ${#DEPTS[@]} -gt 0 ]; then
  IN=$(printf "'%s'," "${DEPTS[@]}" | sed 's/,$//')
  WHERE="geom IS NOT NULL AND department_id IN ($IN)"
else
  WHERE="geom IS NOT NULL"
fi

mapfile -t IDS < <(psql "$DSN" -tA -c \
  "SELECT id FROM public.municipality WHERE $WHERE ORDER BY department_id, id")
TOTAL=${#IDS[@]}
[ "$TOTAL" -gt 0 ] || { echo "ERROR: 0 municipios (¿corriste import_municipality_geom?)"; exit 1; }

echo ">> $TOTAL municipios | pausa ${SLEEP}s | SKIP_DONE=${SKIP_DONE:-1} FORCE=${FORCE:-0}${DRYRUN:+ | DRYRUN}"
i=0; DONE=0; SKIP=0; FAILS=()
for id in "${IDS[@]}"; do
  i=$((i+1))
  # Reanudable: saltar los que ya tienen POIs (salvo FORCE).
  if [ "${FORCE:-0}" != "1" ] && [ "${SKIP_DONE:-1}" = "1" ]; then
    have=$(psql "$DSN" -tA -c \
      "SELECT count(*) FROM geo.place WHERE municipality_id='$id' AND place_kind_id='poi'" 2>/dev/null || echo 0)
    if [ "${have:-0}" -gt 0 ]; then
      SKIP=$((SKIP+1)); echo "[$i/$TOTAL] $id — ya tiene $have POIs, salto"; continue
    fi
  fi
  echo "==================== [$i/$TOTAL] $id ===================="
  if [ "${DRYRUN:-}" = "1" ]; then
    echo "DRYRUN: ${HERE}/import_pois_osm.sh $id"
  else
    if POSTGRES_DSN="$DSN" "$HERE/import_pois_osm.sh" "$id"; then
      DONE=$((DONE+1))
    else
      FAILS+=("$id"); echo "!! FALLO: $id (continuo)"
    fi
    [ "$i" -lt "$TOTAL" ] && sleep "$SLEEP"
  fi
done

echo ">> Fin. importados: $DONE | saltados(ya hechos): $SKIP | fallidos: ${#FAILS[@]} / $TOTAL"
[ ${#FAILS[@]} -gt 0 ] && printf '   re-intentar: ./scripts/import_pois_osm.sh %s\n' "${FAILS[@]}"
echo ">> Total POIs en el país:"
psql "$DSN" -c "SELECT count(*) AS pois_nacional FROM geo.place WHERE place_kind_id='poi';"
exit 0
