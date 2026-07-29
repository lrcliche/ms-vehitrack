@echo off
setlocal EnableDelayedExpansion
cd /d %~dp0\..

echo.
echo ==^> Hexagonal architecture guard

findstr /S /N /I "infrastructure/" domain\*.go >nul 2>&1
if %errorlevel%==0 (
  echo [FAIL] domain must not depend on infrastructure
  exit /b 1
) else (
  echo [PASS] domain does not import infrastructure
)

findstr /S /N /I "pgxpool sql.DB gorm bun." presentation\*.go >nul 2>&1
if %errorlevel%==0 (
  echo [FAIL] presentation must not access database implementations
  exit /b 1
) else (
  echo [PASS] presentation does not access database implementations
)

findstr /S /N /I "infrastructure/" application\*.go >nul 2>&1
if %errorlevel%==0 (
  echo [FAIL] application must not depend on infrastructure
  exit /b 1
) else (
  echo [PASS] application does not import infrastructure
)

findstr /S /N /I "domain/ports" application\*.go >nul 2>&1
if not %errorlevel%==0 (
  echo [FAIL] application layer must depend on domain ports
  exit /b 1
) else (
  echo [PASS] application layer depends on domain ports
)

findstr /S /N /C:"var _ ports.TelemetryPublisherPort" infrastructure\publishers\*.go >nul 2>&1
if not %errorlevel%==0 (
  echo [FAIL] infrastructure publishers should assert interface compliance
  exit /b 1
) else (
  echo [PASS] publisher implementation asserts port compliance
)

go test ./...
if not %errorlevel%==0 (
  echo [FAIL] go test ./...
  exit /b 1
)

echo [PASS] go test ./...
echo Architecture checks completed successfully.
