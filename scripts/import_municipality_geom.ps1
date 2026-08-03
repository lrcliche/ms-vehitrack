<#
=====================================================================================
 VehiTrack · scripts/import_municipality_geom.ps1   (Windows / PowerShell 5.1+)
 Rellena public.municipality.geom (MultiPolygon 4326) con los limites municipales del
 DANE MGN desde un GeoPackage, casando por DIVIPOLA (mpio_cdpmp). NO inventa geometrias.

 Requisitos previos (en orden):
   1. migrations/001..004 aplicadas.
   2. seeds/municipality_co.sql        (los 1104 municipios).
   3. seeds/municipality_divipola.sql  (la columna/llave divipola).
   4. ogr2ogr + psql (vienen con PostgreSQL 17; el script los autodetecta).

 La cadena de conexion se toma del backend (.env -> POSTGRES_DSN) salvo que pases -Dsn.
 El rol debe ser el DUENO (usermaster), no vehitrack_app (necesita ALTER/DDL en staging).

 Uso:
   .\scripts\import_municipality_geom.ps1 -Gpkg C:\ruta\municipios_co.gpkg
   .\scripts\import_municipality_geom.ps1 -Gpkg .\municipios_co.gpkg -Layer municipio -Dsn "postgres://..."
=====================================================================================
#>
[CmdletBinding()]
param(
  [string]$Gpkg = (Join-Path $PSScriptRoot "..\data\municipios_co.gpkg"),
  [string]$Layer = "",
  [string]$Dsn   = "",
  [string]$CdpmpCol = "mpio_cdpmp",   # campo DIVIPOLA en el MGN (ajusta si tu version difiere)
  [string]$Staging  = "stg_mgn_municipio"
)
$ErrorActionPreference = "Stop"

# --- 0. localizar ogr2ogr / psql (PATH o C:\Program Files\PostgreSQL\*\bin) ------------
function Resolve-Tool([string]$name) {
  $c = Get-Command $name -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $hit = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\$name.exe" -ErrorAction SilentlyContinue |
         Sort-Object FullName -Descending | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  throw "No encuentro $name. Instala PostgreSQL/PostGIS o agregalo al PATH."
}
$ogr     = Resolve-Tool "ogr2ogr"
$ogrinfo = Resolve-Tool "ogrinfo"
$psql    = Resolve-Tool "psql"

# --- 1. resolver DSN (parametro o .env del backend) -----------------------------------
if ([string]::IsNullOrWhiteSpace($Dsn)) {
  $envFile = Join-Path $PSScriptRoot "..\.env"
  if (-not (Test-Path $envFile)) { throw "No hay -Dsn y no encuentro $envFile" }
  $line = Select-String -Path $envFile -Pattern '^\s*POSTGRES_DSN\s*=' | Select-Object -First 1
  if (-not $line) { throw "POSTGRES_DSN no esta en $envFile; pasa -Dsn" }
  $Dsn = ($line.Line -replace '^\s*POSTGRES_DSN\s*=', '').Trim().Trim('"')
}
if ([string]::IsNullOrWhiteSpace($Dsn)) { throw "DSN vacio." }

if (-not (Test-Path $Gpkg)) { throw "No existe el GeoPackage: $Gpkg" }
$Gpkg = (Resolve-Path $Gpkg).Path

# ogr2ogr (PGDump) y los .sql se escriben en UTF-8, pero psql en Windows asume el encoding
# de la consola (WIN1252/cp1252) y falla al leer los acentos. Forzamos cliente UTF-8.
$env:PGCLIENTENCODING = "UTF8"

# El GDAL que trae PostgreSQL no incluye el driver PostgreSQL en vivo, pero si PGDUMP:
# ogr2ogr escribe el staging como .sql y psql lo carga. psql acepta el DSN uri tal cual.
$u = [System.Uri]$Dsn
$pgDb = $u.AbsolutePath.TrimStart('/')

# --- 3. capa: autodetecta si no se paso -----------------------------------------------
if ([string]::IsNullOrWhiteSpace($Layer)) {
  $info = & $ogrinfo -q $Gpkg 2>$null | Select-String -Pattern '^\s*\d+:\s*(\S+)' | Select-Object -First 1
  if ($info) { $Layer = ($info.Matches[0].Groups[1].Value) }
  if ([string]::IsNullOrWhiteSpace($Layer)) { throw "No pude autodetectar la capa; pasa -Layer" }
}
Write-Host ">> Herramientas: $ogr ; $psql"
Write-Host ">> Destino: $pgDb@$($u.Host):$pgPort como $pgUser | capa='$Layer' | DIVIPOLA='$CdpmpCol'"

# --- 4. ogr2ogr: gpkg -> SQL dump (PGDUMP), luego psql lo carga en staging ------------
Write-Host ">> 1/3  ogr2ogr -f PGDump: generando SQL del staging '$Staging' ..."
$stgSql = Join-Path $env:TEMP ("vehitrack_stg_{0}.sql" -f ([guid]::NewGuid().ToString('N')))
& $ogr -f PGDump $stgSql $Gpkg $Layer `
  -nln $Staging -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI -dim 2 `
  -lco GEOMETRY_NAME=geom -lco SRID=4326 `
  -lco CREATE_SCHEMA=OFF -lco DROP_TABLE=IF_EXISTS -lco SPATIAL_INDEX=NONE
if ($LASTEXITCODE -ne 0) { Remove-Item $stgSql -ErrorAction SilentlyContinue; throw "ogr2ogr fallo (exit $LASTEXITCODE)" }

Write-Host ">> 2/3  psql: cargando el staging ..."
try {
  & $psql $Dsn -v ON_ERROR_STOP=1 -q -f $stgSql
  if ($LASTEXITCODE -ne 0) { throw "psql (staging) fallo (exit $LASTEXITCODE)" }
} finally {
  Remove-Item $stgSql -ErrorAction SilentlyContinue
}

# --- 5. UPDATE geom por DIVIPOLA (transaccional) --------------------------------------
Write-Host ">> 3/3  UPDATE municipality.geom por DIVIPOLA ..."
$sql = @"
BEGIN;
-- ST_MakeValid corrige self-intersections de cartografia oficial; CollectionExtract(...,3)
-- se queda solo con poligonos; ST_Multi + cast fija el tipo exacto (MultiPolygon,4326).
UPDATE public.municipality m
   SET geom = ST_Multi(
                ST_CollectionExtract(
                  ST_MakeValid(ST_Force2D(s.geom)), 3
                ))::geometry(MultiPolygon,4326)
  FROM $Staging s
 WHERE s.$CdpmpCol::char(5) = m.divipola;

\echo '== conteo con/sin geom =='
SELECT count(*) FILTER (WHERE geom IS NOT NULL) AS con_geom,
       count(*) FILTER (WHERE geom IS NULL)     AS sin_geom
  FROM public.municipality;

\echo '== municipios sin geom =='
SELECT m.divipola, m.id, m.name
  FROM public.municipality m
 WHERE m.geom IS NULL
 ORDER BY m.divipola;

DROP TABLE $Staging;
COMMIT;
"@
$tmp = Join-Path $env:TEMP ("vehitrack_geom_{0}.sql" -f ([guid]::NewGuid().ToString('N')))
Set-Content -Path $tmp -Value $sql -Encoding UTF8
try {
  & $psql $Dsn -v ON_ERROR_STOP=1 -f $tmp
  if ($LASTEXITCODE -ne 0) { throw "psql fallo (exit $LASTEXITCODE)" }
} finally {
  Remove-Item $tmp -ErrorAction SilentlyContinue
}
Write-Host ">> Listo. Si 'sin geom' > 0, son municipios que el MGN no incluye (p.ej. Nuevo"
Write-Host ">> Belen de Bajira, 27493, en disputa) o un nombre de campo DIVIPOLA distinto (-CdpmpCol)."
