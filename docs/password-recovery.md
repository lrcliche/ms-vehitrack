# Recuperación de contraseña del conductor

El flujo usa el endpoint interno de `ms-messaging-api` (`POST /api/messaging/email`)
y una plantilla HTML propia del backend. No requiere que la app tenga una API key
de correo.

## Configuración de `ms-vehitrack`

Definir en el `EnvironmentFile` del servicio:

```env
FACTRA_EMAIL_URL=https://api.system-one-fact.com/9/api/messaging/email
FACTRA_EMAIL_API_KEY=<misma credencial interna que espera ms-messaging-api>
FACTRA_EMAIL_EMPRESA_ID=<empresa-id-numérico; obligatorio>
```

`FACTRA_EMAIL_URL` debe apuntar a la ruta de envío completa. En la configuración
observada del repo de correo, `/9/` es un segmento de enrutamiento del proxy y no
representa el ID de empresa. El valor de `FACTRA_EMAIL_EMPRESA_ID` se envía en el
header `X-Factra-Empresa-Id`; ese header es obligatorio para que
`ms-messaging-api` seleccione las credenciales Gmail de la empresa. Si el proxy
usa otra ruta, configurar esa URL completa y mantener el ID de empresa
confirmado por Factra. Mantener la API key fuera de Git y fuera de la app.

## API pública de la app

Solicitar el correo; la respuesta es igual si el correo no pertenece a una cuenta
activa de esa empresa:

```http
POST /api/v2/auth/password/forgot
Content-Type: application/json

{"email":"conductor@empresa.com","tenant_id":"<tenant-uuid>"}
```

La respuesta HTTP es `202 Accepted`. Si hay una cuenta activa, llega un token de
un solo uso; vence en 30 minutos. Completar el cambio:

```http
POST /api/v2/auth/password/reset
Content-Type: application/json

{"tenant_id":"<tenant-uuid>","token":"<token-del-correo>","new_password":"<nueva-clave-de-12-o-mas-caracteres>"}
```

El token se guarda solo como hash. Al cambiar la clave se consumen las solicitudes
de recuperación pendientes y se revocan los refresh tokens activos de la cuenta.
La app debe usar `DRIVER_TENANT_ID` para enviar el tenant configurado.

## Preparación de base de datos

Aplicar como dueño de base de datos, en orden:

```text
migrations/022_business_auth_refresh_tokens.sql
migrations/023_business_auth_password_reset.sql
```

La contraseña y el token no se escriben en logs del ms-vehitrack. `ms-messaging-api`
sanitiza secuencias token-like de longitud larga al guardar los campos del mensaje
en el registro de transacción.
