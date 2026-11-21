package businessauth

import (
	"context"
	"crypto/rand"
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
	accessTokenTTL = 15 * time.Minute
	tokenAudience  = "vehitrack-api-v2"
	minimumKeySize = 32
)

var ErrTokenServiceUnavailable = errors.New("business auth: token service is not configured")

type Service struct {
	store    ports.BusinessAuthStore
	key      []byte
	issuer   string
	keyReady bool
}

type TokenClaims struct {
	jwt.Claims
	TenantID     string `json:"tenant_id"`
	TenantUserID string `json:"tenant_user_id"`
}

type LoginResult struct {
	AccessToken string
	ExpiresIn   int64
	UserID      string
	TenantID    string
}

func NewService(store ports.BusinessAuthStore, signingKey, issuer string) *Service {
	key := []byte(signingKey)
	return &Service{store: store, key: key, issuer: issuer, keyReady: len(key) >= minimumKeySize && issuer != ""}
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

	now := time.Now().UTC()
	claims := TokenClaims{
		Claims: jwt.Claims{
			Issuer:   s.issuer,
			Subject:  credential.UserID,
			Audience: jwt.Audience{tokenAudience},
			IssuedAt: jwt.NewNumericDate(now),
			Expiry:   jwt.NewNumericDate(now.Add(accessTokenTTL)),
			ID:       randomTokenID(),
		},
		TenantID:     credential.TenantID,
		TenantUserID: credential.TenantUserID,
	}
	signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.HS256, Key: s.key}, nil)
	if err != nil {
		return nil, fmt.Errorf("create jwt signer: %w", err)
	}
	token, err := jwt.Signed(signer).Claims(claims).Serialize()
	if err != nil {
		return nil, fmt.Errorf("sign access token: %w", err)
	}
	return &LoginResult{
		AccessToken: token,
		ExpiresIn:   int64(accessTokenTTL.Seconds()),
		UserID:      credential.UserID,
		TenantID:    credential.TenantID,
	}, nil
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
