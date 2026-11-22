package businessauth

import (
	"fmt"
	"html/template"
	"strings"
	"time"

	"ms-vehitrack/domain/ports"
)

func buildPasswordResetEmail(recipient, token string, expiresAt time.Time) ports.EmailMessage {
	const subject = "Restablece tu contraseña de Vehitrack"
	text := fmt.Sprintf("Recibimos una solicitud para cambiar la contraseña de tu cuenta Vehitrack.\n\nCopia este código en la app para continuar:\n%s\n\nEl código vence en 30 minutos. Si no solicitaste el cambio, ignora este correo.", token)
	const page = `<!doctype html><html lang="es"><head><meta charset="utf-8"></head><body style="margin:0;background:#f3f6fb;font-family:Arial,sans-serif;color:#172033"><main style="max-width:560px;margin:32px auto;padding:32px;background:#fff;border:1px solid #e5e9f0;border-radius:14px"><h1 style="font-size:24px;margin:0 0 16px">Restablece tu contraseña</h1><p>Recibimos una solicitud para cambiar la contraseña de tu cuenta Vehitrack.</p><p>Copia este código en la app:</p><div style="padding:18px;text-align:center;background:#f3f6fb;border-radius:10px;font-size:22px;letter-spacing:2px;font-weight:bold">{{.Token}}</div><p style="color:#596579">El código vence el {{.Expiry}} (hora de Bogotá). Si no solicitaste el cambio, ignora este correo.</p><p style="font-size:12px;color:#788397">Por seguridad, nunca compartas este código.</p></main></body></html>`
	tpl := template.Must(template.New("password-reset").Parse(page))
	var html strings.Builder
	_ = tpl.Execute(&html, struct{ Token, Expiry string }{Token: token, Expiry: expiresAt.In(time.FixedZone("Bogota", -5*60*60)).Format("02/01/2006 03:04 PM")})
	return ports.EmailMessage{To: recipient, Subject: subject, Text: text, HTML: html.String(), IdempotencyKey: hashRefreshToken(token)}
}
