package businessauth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"

	jose "github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

const (
	accessTokenTTL  = 15 * time.Minute
	refreshTokenTTL = 30 * 24 * time.Hour
	tokenAudience   = "vehitrack-api-v2"
	minimumKeySize  = 32
)

var ErrTokenServiceUnavailable = errors.New("business auth: token service is not configured")
var ErrInvalidPasswordResetToken = errors.New("business auth: invalid or expired password reset token")

type Service struct {
	store       ports.BusinessAuthStore
	emailSender ports.EmailSender
	key         []byte
	issuer      string
	keyReady    bool
}

type TokenClaims struct {
	jwt.Claims
	TenantID     string `json:"tenant_id"`
	TenantUserID string `json:"tenant_user_id"`
}

type LoginResult struct {
	AccessToken      string
	RefreshToken     string
	ExpiresIn        int64
	RefreshExpiresIn int64
	UserID           string
	TenantID         string
}

func NewService(store ports.BusinessAuthStore, signingKey, issuer string, emailSenders ...ports.EmailSender) *Service {
	key := []byte(signingKey)
	var emailSender ports.EmailSender
	if len(emailSenders) > 0 {
		emailSender = emailSenders[0]
	}
	return &Service{store: store, emailSender: emailSender, key: key, issuer: issuer, keyReady: len(key) >= minimumKeySize && issuer != ""}
}

func (s *Service) RequestPasswordReset(ctx context.Context, email, tenantID string) error {
	if s.store == nil || s.emailSender == nil {
		return ErrTokenServiceUnavailable
	}
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || len(email) > 320 || uuid.Validate(tenantID) != nil {
		return entities.ErrInvalidBusinessCredentials
	}
	credential, err := s.store.FindActiveCredential(ctx, email, tenantID)
	if err != nil {
		return fmt.Errorf("find password reset account: %w", err)
	}
	if credential == nil {
		return nil
	}
	raw, err := secureRandomToken()
	if err != nil {
		return fmt.Errorf("generate password reset token: %w", err)
	}
	expiresAt := time.Now().UTC().Add(30 * time.Minute)
	hash := hashRefreshToken(raw)
	if err := s.store.CreatePasswordResetToken(ctx, credential.UserID, credential.TenantUserID, credential.TenantID, hash, expiresAt); err != nil {
		return fmt.Errorf("store password reset token: %w", err)
	}
	msg := buildPasswordResetEmail(credential.Email, raw, expiresAt)
	if err := s.emailSender.Send(ctx, msg); err != nil {
		return fmt.Errorf("send password reset email: %w", err)
	}
	return nil
}

func (s *Service) ResetPassword(ctx context.Context, tenantID, rawToken, password string) error {
	if s.store == nil {
		return ErrTokenServiceUnavailable
	}
	if uuid.Validate(tenantID) != nil || len(rawToken) < 32 || len(rawToken) > 256 || len(password) < 12 || len(password) > 72 {
		return ErrInvalidPasswordResetToken
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash reset password: %w", err)
	}
	used, err := s.store.ConsumePasswordResetToken(ctx, tenantID, hashRefreshToken(rawToken), string(hash))
	if err != nil {
		return fmt.Errorf("consume password reset token: %w", err)
	}
	if !used {
		return ErrInvalidPasswordResetToken
	}
	return nil
}

func secureRandomToken() (string, error) {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b[:]), nil
}

func (s *Service) Login(ctx context.Context, email, password, tenantID string) (*LoginResult, error) {
	if !s.keyReady || s.store == nil {
		return nil, ErrTokenServiceUnavailable
	}
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || password == "" || uuid.Validate(tenantID) != nil {
		return nil, entities.ErrInvalidBusinessCredentials
	}

	credential, err := s.store.FindActiveCredential(ctx, email, tenantID)
	if err != nil {
		return nil, fmt.Errorf("find business credential: %w", err)
	}
	if credential == nil || credential.PasswordHash == "" ||
		bcrypt.CompareHashAndPassword([]byte(credential.PasswordHash), []byte(password)) != nil {
		return nil, entities.ErrInvalidBusinessCredentials
	}

	return s.issueSession(ctx, credential, "")
}

func (s *Service) issueSession(ctx context.Context, credential *entities.BusinessUserCredential, refresh string) (*LoginResult, error) {
	if refresh == "" {
		refresh = randomRefreshToken()
		familyID := uuid.NewString()
		if err := s.store.CreateRefreshToken(ctx, credential.UserID, credential.TenantUserID, credential.TenantID, hashRefreshToken(refresh), familyID, time.Now().UTC().Add(refreshTokenTTL)); err != nil {
			return nil, fmt.Errorf("create refresh token: %w", err)
		}
	}
	access, err := s.signAccessToken(credential)
	if err != nil {
		return nil, err
	}
	return &LoginResult{AccessToken: access, RefreshToken: refresh, ExpiresIn: int64(accessTokenTTL.Seconds()), RefreshExpiresIn: int64(refreshTokenTTL.Seconds()), UserID: credential.UserID, TenantID: credential.TenantID}, nil
}

func (s *Service) Refresh(ctx context.Context, raw string) (*LoginResult, error) {
	if !s.keyReady || s.store == nil {
		return nil, ErrTokenServiceUnavailable
	}
	if len(raw) < 32 || len(raw) > 256 {
		return nil, entities.ErrInvalidBusinessCredentials
	}
	next := randomRefreshToken()
	credential, err := s.store.RotateRefreshToken(ctx, hashRefreshToken(raw), hashRefreshToken(next), time.Now().UTC().Add(refreshTokenTTL))
	if err != nil {
		return nil, fmt.Errorf("rotate refresh token: %w", err)
	}
	if credential == nil {
		return nil, entities.ErrInvalidBusinessCredentials
	}
	return s.issueSession(ctx, credential, next)
}

func (s *Service) Logout(ctx context.Context, raw string) error {
	if s.store == nil {
		return ErrTokenServiceUnavailable
	}
	if raw == "" {
		return entities.ErrInvalidBusinessCredentials
	}
	return s.store.RevokeRefreshToken(ctx, hashRefreshToken(raw))
}

func (s *Service) signAccessToken(credential *entities.BusinessUserCredential) (string, error) {
	now := time.Now().UTC()
	claims := TokenClaims{Claims: jwt.Claims{Issuer: s.issuer, Subject: credential.UserID, Audience: jwt.Audience{tokenAudience}, IssuedAt: jwt.NewNumericDate(now), Expiry: jwt.NewNumericDate(now.Add(accessTokenTTL)), ID: randomTokenID()}, TenantID: credential.TenantID, TenantUserID: credential.TenantUserID}
	signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.HS256, Key: s.key}, nil)
	if err != nil {
		return "", fmt.Errorf("create jwt signer: %w", err)
	}
	token, err := jwt.Signed(signer).Claims(claims).Serialize()
	if err != nil {
		return "", fmt.Errorf("sign access token: %w", err)
	}
	return token, nil
}

func randomRefreshToken() string {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("secure random source unavailable")
	}
	return base64.RawURLEncoding.EncodeToString(b[:])
}
func hashRefreshToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return fmt.Sprintf("%x", sum[:])
}

func (s *Service) CreateUser(
	ctx context.Context, tenantID, actorUserID, actorTenantUserID,
	email, fullName, password, roleCode string,
) (*entities.CreatedBusinessUser, error) {
	if s.store == nil {
		return nil, ErrTokenServiceUnavailable
	}
	email = strings.ToLower(strings.TrimSpace(email))
	fullName = strings.TrimSpace(fullName)
	roleCode = strings.ToLower(strings.TrimSpace(roleCode))
	if roleCode == "" {
		roleCode = "viewer"
	}
	if email == "" || fullName == "" || len(fullName) > 200 ||
		len(password) < 12 || len(password) > 72 || uuid.Validate(tenantID) != nil ||
		uuid.Validate(actorUserID) != nil || uuid.Validate(actorTenantUserID) != nil ||
		!validRoleCode(roleCode) {
		return nil, entities.ErrInvalidBusinessUser
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash business user password: %w", err)
	}
	return s.store.CreateUser(ctx, entities.CreateBusinessUserCommand{
		TenantID: tenantID, ActorUserID: actorUserID, ActorTenantUserID: actorTenantUserID,
		Email: email, FullName: fullName, PasswordHash: string(hash), RoleCode: roleCode,
	})
}

func validRoleCode(value string) bool {
	if value == "" || value[0] < 'a' || value[0] > 'z' || len(value) > 64 {
		return false
	}
	for _, r := range value[1:] {
		if (r < 'a' || r > 'z') && (r < '0' || r > '9') && r != '_' {
			return false
		}
	}
	return true
}

func (s *Service) ValidateToken(raw string) (*TokenClaims, error) {
	if !s.keyReady {
		return nil, ErrTokenServiceUnavailable
	}
	parsed, err := jwt.ParseSigned(raw, []jose.SignatureAlgorithm{jose.HS256})
	if err != nil {
		return nil, err
	}
	var claims TokenClaims
	if err := parsed.Claims(s.key, &claims); err != nil {
		return nil, err
	}
	if err := claims.Claims.Validate(jwt.Expected{Issuer: s.issuer, Time: time.Now().UTC()}); err != nil {
		return nil, err
	}
	if claims.Expiry == nil || claims.IssuedAt == nil ||
		!hasAudience(claims.Audience, tokenAudience) || uuid.Validate(claims.Subject) != nil ||
		uuid.Validate(claims.TenantID) != nil || uuid.Validate(claims.TenantUserID) != nil {
		return nil, errors.New("business auth: invalid token claims")
	}
	return &claims, nil
}

func hasAudience(audiences jwt.Audience, expected string) bool {
	found := 0
	for _, audience := range audiences {
		if subtle.ConstantTimeCompare([]byte(audience), []byte(expected)) == 1 {
			found = 1
		}
	}
	return found == 1
}

func randomTokenID() string {
	var value [18]byte
	if _, err := rand.Read(value[:]); err != nil {
		return uuid.NewString()
	}
	return base64.RawURLEncoding.EncodeToString(value[:])
}
