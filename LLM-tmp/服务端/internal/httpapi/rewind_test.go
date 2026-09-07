package httpapi

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
	"yanxia-server/internal/store"
)

func TestCheckpointPaymentOwnershipAndRetainedChoice(t *testing.T) {
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
	login := postJSON(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "rewind_test", "password": "test-password-123"})
	token := login["access_token"].(string)
	id := login["player"].(map[string]any)["id"].(string)
	if _, err := db.UpdatePlayer(id, func(p *model.Player) error { p.Erosion = 35; p.InkMarks = 5; return nil }); err != nil {
		t.Fatal(err)
	}
	start := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"chapter_id": "prologue", "event_id": "prologue_bridge"}, token)
	sid := start["session_id"].(string)
	url := server.URL + "/api/v1/sessions/" + sid
	postJSON(t, url+"/puzzle", traceRequest(catalog.Chapters[0].Events[0].Puzzle.Steps[0]), token)
	beforeChoice := postJSONStatus(t, url+"/battle", winningBattle(catalog.Chapters[0].Events[0]), token)
	if beforeChoice.status != http.StatusConflict {
		t.Fatal("battle bypassed memory choice")
	}
	postJSON(t, url+"/choice", map[string]any{"action": "keep"}, token)
	if _, _, err := db.UpdateSessionAndPlayer(sid, id, func(run *model.EventSession, p *model.Player) error {
		run.Status = "failed"
		run.FailureReason = "erosion_limit"
		p.Erosion = 100
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	postJSON(t, url+"/rewind", map[string]any{"retries": 0}, token)
	postJSON(t, url+"/rewind", map[string]any{"retries": 0}, token)
	other := postJSON(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "foreign_retry", "password": "test-password-123"})
	if postJSONStatus(t, url+"/rewind", map[string]any{"retries": 1}, other["access_token"].(string)).status != http.StatusForbidden {
		t.Fatal("foreign rewind allowed")
	}
	reloaded, err := store.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	p, _ := reloaded.GetPlayer(id)
	run, _ := reloaded.GetSession(sid)
	if p.InkMarks != 4 || p.Erosion != 35 || len(p.Memories) != 1 || len(p.MemoryLedger) != 1 || !run.ChoiceDone || run.Retries != 1 || len(run.AcceptedSteps) != 0 {
		t.Fatalf("bad rewind: %+v %+v", p, run)
	}
	current := getJSON(t, server.URL+"/api/v1/sessions", token)["session"].(map[string]any)
	if current["id"] != sid {
		t.Fatal("reconnect lost active session")
	}
	postJSON(t, url+"/puzzle", traceRequest(catalog.Chapters[0].Events[0].Puzzle.Steps[0]), token)
	postJSON(t, url+"/battle", winningBattle(catalog.Chapters[0].Events[0]), token)
	postJSON(t, url+"/finish", map[string]any{}, token)
	if getJSON(t, server.URL+"/api/v1/sessions", token)["session"] != nil {
		t.Fatal("completed event still pending")
	}
	// Tutorial grace applies only with no ink; later events must not silently waive payment.
	start = postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"chapter_id": "temple", "event_id": "temple_incense"}, token)
	sid = start["session_id"].(string)
	if _, _, err := db.UpdateSessionAndPlayer(sid, id, func(run *model.EventSession, p *model.Player) error {
		run.Status = "failed"
		p.InkMarks = 0
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if postJSONStatus(t, server.URL+"/api/v1/sessions/"+sid+"/rewind", map[string]any{"retries": 0}, token).status != http.StatusConflict {
		t.Fatal("non-tutorial rewind was free")
	}
}
