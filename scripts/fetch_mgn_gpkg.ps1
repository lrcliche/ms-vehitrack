<#
=====================================================================================
 VehiTrack · scripts/fetch_mgn_gpkg.ps1   (Windows / PowerShell 5.1+)
 Descarga los limites municipales del MGN 2023 (mirror ArcGIS de RMBC, capa nacional)
 y arma data\municipios_co.gpkg listo para import_municipality_geom.ps1.

 Se usa esta fuente porque el portal DANE no permite descarga directa scripteable.
 Campos que trae: mpio_cdpmp (DIVIPOLA), mpio_cnmbr (nombre), mpio_tipo. EPSG:4326.

 Uso:
   .\scripts\fetch_mgn_gpkg.ps1                 # -> data\municipios_co.gpkg
   .\scripts\fetch_mgn_gpkg.ps1 -Out C:\otra\ruta.gpkg
=====================================================================================
#>
[CmdletBinding()]
param(
  [string]$Out = (Join-Path $PSScriptRoot "..\data\municipios_co.gpkg")
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Resolve-Tool([string]$name) {
  $c = Get-Command $name -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $hit = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\$name.exe" -ErrorAction SilentlyContinue |
         Sort-Object FullName -Descending | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  throw "No encuentro $name (instala PostgreSQL/PostGIS o agregalo al PATH)."
}
$ogr = Resolve-Tool "ogr2ogr"

$layer = "https://portalgis.rmbc.gov.co/server/rest/services/DANE/Marco_Geoestadistico_Nacional_2023/MapServer/1"
$query = "$layer/query?where=1%3D1&outFields=mpio_cdpmp,mpio_cnmbr,mpio_tipo&outSR=4326&returnGeometry=true&f=geojson"

$outDir = Split-Path $Out -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$tmp = Join-Path $env:TEMP ("mgn_mpio_{0}.geojson" -f ([guid]::NewGuid().ToString('N')))

Write-Host ">> 1/2  Descargando municipios del MGN (RMBC) ..."
Invoke-WebRequest -Uri $query -OutFile $tmp -UseBasicParsing
$fc = Get-Content $tmp -Raw | ConvertFrom-Json
$n = @($fc.features).Count
if ($fc.exceededTransferLimit) {
  Remove-Item $tmp -ErrorAction SilentlyContinue
  throw "El servidor truncó el resultado (exceededTransferLimit). Habría que paginar con resultOffset."
}
Write-Host "   features recibidos: $n (esperado ~1121)"

Write-Host ">> 2/2  ogr2ogr GeoJSON -> $Out (capa 'municipio', MultiPolygon 4326) ..."
& $ogr -f GPKG $Out $tmp -nln municipio -nlt PROMOTE_TO_MULTI -a_srs EPSG:4326 -overwrite
$code = $LASTEXITCODE
Remove-Item $tmp -ErrorAction SilentlyContinue
if ($code -ne 0) { throw "ogr2ogr fallo (exit $code)" }

Write-Host ">> Listo: $Out"
Write-Host ">> Ahora: .\scripts\import_municipality_geom.ps1"
