package middleware

import (
	"net"
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/responses"
	"golang.org/x/time/rate"
)

// RateLimit applies a per-client IP token bucket limiter.
func RateLimit(rps float64, burst int) gin.HandlerFunc {
	limiterSet := newIPRateLimiter(rps, burst)

	return func(c *gin.Context) {
		ip := clientIP(c)
		if !limiterSet.get(ip).Allow() {
			responses.ErrorFromApp(c, presentationerrors.New(http.StatusTooManyRequests, "rate-limit-exceeded", "Too many requests"))
			c.Abort()
			return
		}
		c.Next()
	}
}

type ipRateLimiter struct {
	mu       sync.Mutex
	limiters map[string]*rate.Limiter
	rps      rate.Limit
	burst    int
}

func newIPRateLimiter(rps float64, burst int) *ipRateLimiter {
	return &ipRateLimiter{
		limiters: make(map[string]*rate.Limiter),
		rps:      rate.Limit(rps),
		burst:    burst,
	}
}

func (l *ipRateLimiter) get(ip string) *rate.Limiter {
	l.mu.Lock()
	defer l.mu.Unlock()

	limiter, ok := l.limiters[ip]
	if !ok {
		limiter = rate.NewLimiter(l.rps, l.burst)
		l.limiters[ip] = limiter
	}
	return limiter
}

func clientIP(c *gin.Context) string {
	ip := c.ClientIP()
	if host, _, err := net.SplitHostPort(ip); err == nil {
		return host
	}
	if ip == "" {
		return "unknown"
	}
	return ip
}

// BodyLimit rejects request bodies larger than maxBytes.
func BodyLimit(maxBytes int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		if maxBytes > 0 && c.Request.Body != nil {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes)
		}
		c.Next()
	}
}

// SecurityHeaders adds conservative HTTP security headers.
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		c.Header("Referrer-Policy", "no-referrer")
		c.Header("Cache-Control", "no-store")
		c.Next()
	}
}
