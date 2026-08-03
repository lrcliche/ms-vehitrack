#!/usr/bin/env bash
# =====================================================================================
# VehiTrack · scripts/import_streets_caribe.sh
# Corre import_streets_osm.sh para TODOS los municipios de la Costa Caribe (o los dptos
# que le pases), con pausa entre ciudades (respeta el rate-limit de Overpass) y sin
# abortar si una ciudad falla.
#
# OJO: son ~197 municipios = ~197 consultas Overpass. Puede tardar horas. Recomendado:
#   - Empezar por las capitales (correlas a mano primero).
#   - SLEEP alto (default 10s) o un Overpass propio (OVERPASS_URL=...).
#   - Correr por bloques (pasa 1-2 dptos por vez).
#
# Uso:
#   POSTGRES_DSN="postgres://DUENO:pass@host:5432/db?sslmode=disable" \
#     ./scripts/import_streets_caribe.sh                 # 7 dptos continentales
#   ./scripts/import_streets_caribe.sh co-atl co-bol     # solo esos dptos
#   SLEEP=20 DRYRUN=1 ./scripts/import_streets_caribe.sh # lista sin importar (prueba)
#
# Caribe continental por defecto: Atlantico, Bolivar, Cesar, Cordoba, La Guajira,
# Magdalena, Sucre. San Andres (co-sap, insular) NO entra por defecto; pasalo si lo quieres.
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
    echo "DRYRUN: ${HERE}/import_streets_osm.sh $id"
  else
    if POSTGRES_DSN="$DSN" "$HERE/import_streets_osm.sh" "$id"; then :; else
      FAILS+=("$id"); echo "!! FALLO: $id (continuo)"
    fi
    [ "$i" -lt "$TOTAL" ] && sleep "$SLEEP"
  fi
done

echo ">> Fin. OK: $((TOTAL-${#FAILS[@]}))/$TOTAL"
[ ${#FAILS[@]} -gt 0 ] && printf '   re-intentar: ./scripts/import_streets_osm.sh %s\n' "${FAILS[@]}"
exit 0
