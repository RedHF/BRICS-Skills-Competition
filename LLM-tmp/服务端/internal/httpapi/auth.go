package httpapi

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"net"
	"net/http"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"
	"yanxia-server/internal/store"
)

// SDK adapters must verify the credential with the provider, including the
// application audience and expiry. A client-supplied user ID is not evidence.
type IdentityProvider interface {
	Name() string
	VerifyCredential(context.Context, string) (ExternalIdentity, error)
}

type ExternalIdentity struct{ Subject, DisplayName string }

var ErrInvalidCredential = errors.New("invalid external credential")

type playerContextKey struct{}
type loginSession struct {
	PlayerID string
	Expires  time.Time
}
type loginWindow struct {
	Count int
	Until time.Time
}

func (s *Server) authenticate(w http.ResponseWriter, r *http.Request) (string, bool) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		writeError(w, 401, "login_required", "请先登录")
		return "", false
	}
	key := sha256.Sum256([]byte(strings.TrimPrefix(header, "Bearer ")))
	s.authMu.Lock()
	session, ok := s.tokens[key]
	if ok && !time.Now().Before(session.Expires) {
		delete(s.tokens, key)
		ok = false
	}
	s.authMu.Unlock()
	if !ok {
		writeError(w, 401, "login_expired", "登录已失效，请重新登录")
		return "", false
	}
	return session.PlayerID, true
}

func (s *Server) issueLogin(w http.ResponseWriter, account store.Account) {
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		writeError(w, 500, "token_error", err.Error())
		return
	}
	token := base64.RawURLEncoding.EncodeToString(secret)
	expires := time.Now().Add(24 * time.Hour)
	s.authMu.Lock()
	for key, session := range s.tokens {
		if !time.Now().Before(session.Expires) {
			delete(s.tokens, key)
		}
	}
	s.tokens[sha256.Sum256([]byte(token))] = loginSession{account.PlayerID, expires}
	s.authMu.Unlock()
	player, _ := s.store.GetPlayer(account.PlayerID)
	writeJSON(w, 200, map[string]any{"access_token": token, "expires_at": expires, "player": playerPayload(player)})
}

func (s *Server) handleAuth(w http.ResponseWriter, r *http.Request, action string) {
	if action == "providers" {
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		names := []string{}
		for name := range s.providers {
			names = append(names, name)
		}
		sort.Strings(names)
		writeJSON(w, 200, map[string]any{"providers": names})
		return
	}
	if action == "me" || action == "logout" {
		method := http.MethodGet
		if action == "logout" {
			method = http.MethodPost
		}
		if r.Method != method {
			methodNotAllowed(w, method)
			return
		}
		id, ok := s.authenticate(w, r)
		if !ok {
			return
		}
		if action == "me" {
			player, _ := s.store.GetPlayer(id)
			writeJSON(w, 200, map[string]any{"player": playerPayload(player)})
			return
		}
		key := sha256.Sum256([]byte(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")))
		s.authMu.Lock()
		delete(s.tokens, key)
		s.authMu.Unlock()
		writeJSON(w, 200, map[string]any{"logged_out": true})
		return
	}
	if action != "register" && action != "login" && action != "external" {
		writeError(w, 404, "not_found", "登录接口不存在")
		return
	}
	if r.Method != http.MethodPost {
		methodNotAllowed(w, http.MethodPost)
		return
	}
	// Rate limits apply before password hashing / provider network calls.
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		writeError(w, 400, "invalid_remote", err.Error())
		return
	}
	s.authMu.Lock()
	now := time.Now()
	for key, window := range s.attempts {
		if !now.Before(window.Until) {
			delete(s.attempts, key)
		}
	}
	window := s.attempts[ip]
	if window.Count == 0 {
		window.Until = now.Add(time.Minute)
	}
	window.Count++
	s.attempts[ip] = window
	s.authMu.Unlock()
	if window.Count > 20 {
		w.Header().Set("Retry-After", "60")
		writeError(w, 429, "too_many_attempts", "请求过于频繁，请一分钟后重试")
		return
	}
	if action == "external" {
		var request struct {
			Provider   string `json:"provider"`
			Credential string `json:"credential"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}
		provider, ok := s.providers[request.Provider]
		if !ok {
			writeError(w, 400, "provider_unavailable", "该登录方式尚未开放")
			return
		}
		if request.Credential == "" || len(request.Credential) > 16384 {
			writeError(w, 400, "invalid_credential", "登录凭证无效")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		identity, err := provider.VerifyCredential(ctx, request.Credential)
		if errors.Is(err, ErrInvalidCredential) {
			writeError(w, 401, "invalid_credential", "第三方登录凭证无效")
			return
		}
		if err != nil {
			writeError(w, 502, "provider_error", "第三方登录服务失败："+err.Error())
			return
		}
		if identity.Subject == "" || len(identity.Subject) > 256 || len(identity.DisplayName) > 256 {
			writeError(w, 502, "provider_identity_error", "第三方服务未返回有效身份")
			return
		}
		key := "external:" + request.Provider + ":" + identity.Subject
		account, ok := s.store.GetAccount(key)
		if !ok {
			account, err = s.store.CreateAccount(key, store.Account{Provider: request.Provider, Subject: identity.Subject}, identity.DisplayName)
			if errors.Is(err, store.ErrAccountExists) {
				account, _ = s.store.GetAccount(key)
			} else if err != nil {
				writeError(w, 500, "store_error", err.Error())
				return
			}
		}
		s.issueLogin(w, account)
		return
	}
	var request struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	username := strings.ToLower(strings.TrimSpace(request.Username))
	if utf8.RuneCountInString(username) < 3 || utf8.RuneCountInString(username) > 24 || len(request.Password) < 8 || len(request.Password) > 72 {
		writeError(w, 400, "invalid_credentials_format", "用户名需 3–24 个字母、汉字、数字或下划线；密码需 8–72 字节")
		return
	}
	for _, char := range username {
		if !unicode.IsLetter(char) && !unicode.IsDigit(char) && char != '_' {
			writeError(w, 400, "invalid_username", "用户名只能包含字母、汉字、数字和下划线")
			return
		}
	}
	key := "password:" + username
	if action == "register" {
		hash, err := bcrypt.GenerateFromPassword([]byte(request.Password), 12)
		if err != nil {
			writeError(w, 500, "password_error", err.Error())
			return
		}
		account, err := s.store.CreateAccount(key, store.Account{Username: username, PasswordHash: string(hash)}, username)
		if errors.Is(err, store.ErrAccountExists) {
			writeError(w, 409, "username_taken", "用户名已被使用")
			return
		}
		if err != nil {
			writeError(w, 500, "store_error", err.Error())
			return
		}
		s.issueLogin(w, account)
		return
	}
	account, exists := s.store.GetAccount(key)
	hash := s.dummyHash
	if exists {
		hash = []byte(account.PasswordHash)
	}
	err = bcrypt.CompareHashAndPassword(hash, []byte(request.Password))
	if errors.Is(err, bcrypt.ErrMismatchedHashAndPassword) || !exists {
		writeError(w, 401, "invalid_credentials", "用户名或密码错误")
		return
	}
	if err != nil {
		writeError(w, 500, "password_error", err.Error())
		return
	}
	s.issueLogin(w, account)
}
