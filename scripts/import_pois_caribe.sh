#!/usr/bin/env bash
# =====================================================================================
# VehiTrack · scripts/import_pois_caribe.sh
# Corre import_pois_osm.sh para TODOS los municipios de los dptos que le pases (o la Costa
# Caribe por defecto), con pausa entre ciudades (respeta el rate-limit de Overpass) y sin
# abortar si una ciudad falla. Espeja a import_streets_caribe.sh.
#
# OJO: una consulta Overpass por municipio. Recomendado:
#   - Correr primero las capitales a mano con import_pois_osm.sh.
#   - SLEEP alto (default 10s) o un Overpass propio (OVERPASS_URL=...).
#   - Por bloques (1-2 dptos por vez).
#
# Uso:
#   POSTGRES_DSN="postgres://DUENO:pass@host:5432/db?sslmode=disable" \
#     ./scripts/import_pois_caribe.sh                 # 7 dptos del Caribe continental
#   ./scripts/import_pois_caribe.sh co-atl co-bol     # solo esos dptos
#   SLEEP=20 DRYRUN=1 ./scripts/import_pois_caribe.sh # lista sin importar (prueba)
# =====================================================================================
set -uo pipefail   # sin -e a proposito: un fallo de ciudad no mata el loop

DSN="${POSTGRES_DSN:?Exporta POSTGRES_DSN con el rol dueno (no vehitrack_app)}"
SLEEP="${SLEEP:-10}"
export PGCLIENTENCODING=UTF8
HERE="$(cd "$(dirname "$0")" && pwd)"

DEPTS=("$@")
[ ${#DEPTS[@]} -eq 0 ] && DEPTS=(co-atl co-bol co-ces co-cor co-lag co-mag co-suc)
IN=$(printf "'%s'," "${DEPTS[@]}" | sed 's/,$//')

mapfile -t IDS < <(psql "$DSN" -tA -c \
  "SELECT id FROM public.municipality WHERE department_id IN ($IN) ORDER BY department_id, id")
TOTAL=${#IDS[@]}
[ "$TOTAL" -gt 0 ] || { echo "ERROR: 0 municipios para: ${DEPTS[*]}"; exit 1; }

echo ">> $TOTAL municipios | dptos: ${DEPTS[*]} | pausa ${SLEEP}s${DRYRUN:+ | DRYRUN}"
i=0; FAILS=()
for id in "${IDS[@]}"; do
  i=$((i+1))
  echo "==================== [$i/$TOTAL] $id ===================="
  if [ "${DRYRUN:-}" = "1" ]; then
    echo "DRYRUN: ${HERE}/import_pois_osm.sh $id"
  else
    if POSTGRES_DSN="$DSN" "$HERE/import_pois_osm.sh" "$id"; then :; else
      FAILS+=("$id"); echo "!! FALLO: $id (continuo)"
    fi
    [ "$i" -lt "$TOTAL" ] && sleep "$SLEEP"
  fi
done

echo ">> Fin. OK: $((TOTAL-${#FAILS[@]}))/$TOTAL"
[ ${#FAILS[@]} -gt 0 ] && printf '   re-intentar: ./scripts/import_pois_osm.sh %s\n' "${FAILS[@]}"
exit 0
