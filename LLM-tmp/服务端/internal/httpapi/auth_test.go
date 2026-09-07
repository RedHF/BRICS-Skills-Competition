package httpapi

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"
	"yanxia-server/internal/content"
	"yanxia-server/internal/store"
)

func TestAuthenticationAndOwnership(t *testing.T) {
	catalog, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "save.json")
	db, err := store.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	api, err := New(catalog, db)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(api)
	defer server.Close()
	for _, route := range []string{"/api/v1/players", "/api/v1/sessions", "/api/v1/runs", "/api/v1/events/prologue/prologue_bridge/start"} {
		response := postJSONStatus(t, server.URL+route, map[string]any{"player_id": "victim"})
		if response.status != 401 {
			t.Fatalf("anonymous request accepted: %s %v", route, response)
		}
	}
	a := postJSON(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "Alice", "password": "correct-password-A"})
	b := postJSON(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "Bob", "password": "correct-password-B"})
	aID := a["player"].(map[string]any)["id"].(string)
	bID := b["player"].(map[string]any)["id"].(string)
	token := a["access_token"].(string)
	other := b["access_token"].(string)
	if aID == bID {
		t.Fatal("distinct users share player")
	}
	duplicate := postJSONStatus(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "ALICE", "password": "another-password"})
	if duplicate.status != 409 {
		t.Fatal("canonical username was not unique")
	}
	for _, username := range []string{"Alice", "Unknown"} {
		wrong := postJSONStatus(t, server.URL+"/api/v1/auth/login", map[string]any{"username": username, "password": "incorrect-password"})
		if wrong.status != 401 || wrong.body["error"].(map[string]any)["code"] != "invalid_credentials" {
			t.Fatalf("wrong password response: %+v", wrong)
		}
	}
	login := postJSON(t, server.URL+"/api/v1/auth/login", map[string]any{"username": "alice", "password": "correct-password-A"})
	if login["player"].(map[string]any)["id"] != aID {
		t.Fatal("login changed player identity")
	}
	if postJSONStatus(t, server.URL+"/api/v1/players", map[string]any{"player_id": bID}, token).status != 403 {
		t.Fatal("arbitrary ID claimed")
	}
	if postJSONStatus(t, server.URL+"/api/v1/events/prologue/prologue_bridge/start", map[string]any{"player_id": bID}, token).status != 403 {
		t.Fatal("foreign event started")
	}
	start := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"chapter_id": "prologue", "event_id": "prologue_bridge"}, token)
	sid := start["session_id"].(string)
	for _, prefix := range []string{"/api/v1/sessions/", "/api/v1/runs/"} {
		for _, action := range []string{"puzzle", "actions", "battle", "choice", "memory", "finish", "submit", "settle"} {
			if response := postJSONStatus(t, server.URL+prefix+sid+"/"+action, map[string]any{}, other); response.status != 403 {
				t.Fatalf("foreign mutation %s: %+v", action, response)
			}
		}
	}
	for _, route := range []string{"/api/v1/players/" + aID, "/api/v1/players/" + aID + "/ledger", "/api/v1/players/" + aID + "/save", "/api/v1/sessions/" + sid, "/api/v1/runs/" + sid} {
		request, err := http.NewRequest(http.MethodGet, server.URL+route, nil)
		if err != nil {
			t.Fatal(err)
		}
		request.Header.Set("Authorization", "Bearer "+other)
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if response.StatusCode != 403 {
			t.Fatalf("foreign read %s: %d", route, response.StatusCode)
		}
	}
	postJSON(t, server.URL+"/api/v1/auth/logout", map[string]any{}, token)
	if postJSONStatus(t, server.URL+"/api/v1/players", map[string]any{}, token).status != 401 {
		t.Fatal("logout token still valid")
	}
	api.authMu.Lock()
	key := sha256.Sum256([]byte(other))
	expired := api.tokens[key]
	expired.Expires = time.Now().Add(-time.Second)
	api.tokens[key] = expired
	api.authMu.Unlock()
	if postJSONStatus(t, server.URL+"/api/v1/players", map[string]any{}, other).status != 401 {
		t.Fatal("expired token still valid")
	}
	encoded, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "correct-password") || strings.Contains(string(encoded), token) {
		t.Fatal("password or bearer token persisted in plaintext")
	}
	reloaded, err := store.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	account, ok := reloaded.GetAccount("password:alice")
	if !ok || account.PlayerID != aID {
		t.Fatal("account binding not persistent")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(account.PasswordHash), []byte("correct-password-A")); err != nil {
		t.Fatal(err)
	}
	api2, err := New(catalog, reloaded)
	if err != nil {
		t.Fatal(err)
	}
	restarted := httptest.NewServer(api2)
	defer restarted.Close()
	if postJSONStatus(t, restarted.URL+"/api/v1/players", map[string]any{}, login["access_token"].(string)).status != 401 {
		t.Fatal("restart preserved ephemeral token")
	}
	login = postJSON(t, restarted.URL+"/api/v1/auth/login", map[string]any{"username": "alice", "password": "correct-password-A"})
	if login["player"].(map[string]any)["id"] != aID {
		t.Fatal("restart lost account")
	}
}

type testProvider struct{ name string }

func (p testProvider) Name() string { return p.name }
func (p testProvider) VerifyCredential(_ context.Context, credential string) (ExternalIdentity, error) {
	if credential != "verified-sdk-ticket" {
		return ExternalIdentity{}, ErrInvalidCredential
	}
	return ExternalIdentity{Subject: "provider-user-1", DisplayName: "第三方拓印师"}, nil
}

func TestThirdPartyAdapterAndRateLimit(t *testing.T) {
	catalog, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	db, err := store.Open(filepath.Join(t.TempDir(), "save.json"))
	if err != nil {
		t.Fatal(err)
	}
	api, err := New(catalog, db, testProvider{"sdk_a"}, testProvider{"sdk_b"})
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(api)
	defer server.Close()
	providers := getJSON(t, server.URL+"/api/v1/auth/providers")
	if len(providers["providers"].([]any)) != 2 {
		t.Fatal("adapters not discoverable")
	}
	for _, test := range []struct {
		provider, ticket string
		status           int
	}{{"unknown", "verified-sdk-ticket", 400}, {"sdk_a", "forged-player-id", 401}} {
		response := postJSONStatus(t, server.URL+"/api/v1/auth/external", map[string]any{"provider": test.provider, "credential": test.ticket})
		if response.status != test.status {
			t.Fatalf("credential accepted: %+v", response)
		}
	}
	first := postJSON(t, server.URL+"/api/v1/auth/external", map[string]any{"provider": "sdk_a", "credential": "verified-sdk-ticket"})
	again := postJSON(t, server.URL+"/api/v1/auth/external", map[string]any{"provider": "sdk_a", "credential": "verified-sdk-ticket"})
	second := postJSON(t, server.URL+"/api/v1/auth/external", map[string]any{"provider": "sdk_b", "credential": "verified-sdk-ticket"})
	if first["player"].(map[string]any)["id"] != again["player"].(map[string]any)["id"] || first["player"].(map[string]any)["id"] == second["player"].(map[string]any)["id"] {
		t.Fatal("provider subject binding incorrect")
	}
	for attempt := 0; attempt < 16; attempt++ {
		postJSONStatus(t, server.URL+"/api/v1/auth/login", map[string]any{"username": "bad", "password": "short"})
	}
	response := postJSONStatus(t, server.URL+"/api/v1/auth/login", map[string]any{"username": "bad", "password": "short"})
	if response.status != 429 {
		t.Fatalf("missing authentication rate limit: %+v", response)
	}
	encoded, err := json.Marshal(response.body)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "password") {
		t.Fatal("credential echoed in error")
	}
}
