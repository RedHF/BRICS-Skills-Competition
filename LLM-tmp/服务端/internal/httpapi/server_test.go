package httpapi

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
	"yanxia-server/internal/store"
)

func TestValidateChoiceTreatsHeldMemoryAsForgetOption(t *testing.T) {
	player := &model.Player{Capacity: 3, Memories: []model.Memory{{ID: "old", Capacity: 1}}}
	pending := &model.Memory{ID: "new", Capacity: 2}
	valid, forgotten, reason := validateChoice("old", "", pending, player, []string{"old"})
	if !valid || forgotten != "old" || reason != "" {
		t.Fatalf("held-memory choice was not treated as forget option: valid=%v forgotten=%q reason=%q", valid, forgotten, reason)
	}
}

func TestSessionFlowAndIdempotentFinish(t *testing.T) {
	catalog, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	persistence, err := store.Open(filepath.Join(t.TempDir(), "save.json"))
	if err != nil {
		t.Fatal(err)
	}
	api, err := New(catalog, persistence)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(api)
	defer server.Close()

	player := postJSON(t, server.URL+"/api/v1/players", map[string]any{"player_id": "flow"})
	if player["player"].(map[string]any)["id"] != "flow" {
		t.Fatalf("unexpected player response: %+v", player)
	}
	public := getJSON(t, server.URL+"/api/v1/catalog")
	encoded, _ := json.Marshal(public)
	if bytes.Contains(encoded, []byte(`"answer"`)) {
		t.Fatal("catalog leaked puzzle answer")
	}
	session := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": "flow", "chapter_id": "prologue", "event_id": "prologue_bridge"})
	sid := session["session_id"].(string)
	wrong := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", map[string]any{"step_id": "bridge_trace", "answer": "错"})
	if wrong["erosion"].(float64) != 10 {
		t.Fatalf("wrong answer did not increase erosion: %+v", wrong)
	}
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", map[string]any{"step_id": "bridge_trace", "answer": "平安"})
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/battle", map[string]any{"actions": []map[string]any{{"skill": "斗拱", "at_ms": 1000}}, "duration_ms": 30000})
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", map[string]any{"action": "keep"})
	first := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{})
	second := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{})
	if first["reason"] != "settled" || second["reason"] != "already_settled" {
		t.Fatalf("finish is not idempotent: first=%+v second=%+v", first, second)
	}
	firstResult := first["result"].(map[string]any)
	secondResult := second["result"].(map[string]any)
	if firstResult["sequence"] != secondResult["sequence"] {
		t.Fatalf("repeat finish changed sequence: %v vs %v", firstResult["sequence"], secondResult["sequence"])
	}
}

func TestFailedSessionIsImmutableAndRetryUsesNewSession(t *testing.T) {
	catalog, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	persistence, err := store.Open(filepath.Join(t.TempDir(), "save.json"))
	if err != nil {
		t.Fatal(err)
	}
	api, err := New(catalog, persistence)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(api)
	defer server.Close()

	postJSON(t, server.URL+"/api/v1/players", map[string]any{"player_id": "retry-flow"})
	session := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": "retry-flow", "chapter_id": "prologue", "event_id": "prologue_bridge"})
	sid := session["session_id"].(string)
	for attempt := 0; attempt < 3; attempt++ {
		postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", map[string]any{"step_id": "bridge_trace", "answer": "错误"})
	}
	failed := postJSONStatus(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", map[string]any{"step_id": "bridge_trace", "answer": "平安"})
	if failed.status != http.StatusConflict || failed.body["error"].(map[string]any)["code"] != "session_failed" {
		t.Fatalf("failed puzzle session was reusable: status=%d body=%+v", failed.status, failed.body)
	}

	newSession := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": "retry-flow", "chapter_id": "prologue", "event_id": "prologue_bridge"})
	newSID := newSession["session_id"].(string)
	if newSID == sid {
		t.Fatal("retry unexpectedly reused the failed session id")
	}
	postJSON(t, server.URL+"/api/v1/sessions/"+newSID+"/puzzle", map[string]any{"step_id": "bridge_trace", "answer": "平安"})
	failedBattle := postJSON(t, server.URL+"/api/v1/sessions/"+newSID+"/battle", map[string]any{"duration_ms": 1000, "waves_cleared": 0, "hits_taken": 0, "actions": []map[string]any{}})
	if failedBattle["won"].(bool) || failedBattle["status"] != "failed" {
		t.Fatalf("expected failed battle session: %+v", failedBattle)
	}
	reusedBattle := postJSONStatus(t, server.URL+"/api/v1/sessions/"+newSID+"/battle", map[string]any{"duration_ms": 30000, "waves_cleared": 1, "hits_taken": 0, "actions": []map[string]any{{"skill": "斗拱", "at_ms": 1000}}})
	if reusedBattle.status != http.StatusConflict || reusedBattle.body["error"].(map[string]any)["code"] != "session_failed" {
		t.Fatalf("failed battle session was reusable: status=%d body=%+v", reusedBattle.status, reusedBattle.body)
	}
}

func TestExpiredSessionCannotChooseOrSettle(t *testing.T) {
	catalog, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	persistence, err := store.Open(filepath.Join(t.TempDir(), "save.json"))
	if err != nil {
		t.Fatal(err)
	}
	api, err := New(catalog, persistence)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(api)
	defer server.Close()

	postJSON(t, server.URL+"/api/v1/players", map[string]any{"player_id": "expiry-flow"})
	session := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": "expiry-flow", "chapter_id": "prologue", "event_id": "prologue_bridge"})
	sid := session["session_id"].(string)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", map[string]any{"step_id": "bridge_trace", "answer": "平安"})
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/battle", map[string]any{"duration_ms": 30000, "waves_cleared": 1, "hits_taken": 0, "actions": []map[string]any{{"skill": "斗拱", "at_ms": 1000}}})
	if _, err := persistence.UpdateSession(sid, func(current *model.EventSession) error {
		current.ExpiresAt = time.Now().UTC().Add(-time.Minute)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	choice := postJSONStatus(t, server.URL+"/api/v1/sessions/"+sid+"/choice", map[string]any{"action": "keep"})
	if choice.status != http.StatusConflict || choice.body["error"].(map[string]any)["code"] != "session_expired" {
		t.Fatalf("expired choice was accepted: status=%d body=%+v", choice.status, choice.body)
	}
	finish := postJSONStatus(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{})
	code := finish.body["error"].(map[string]any)["code"]
	if finish.status != http.StatusConflict || (code != "session_failed" && code != "session_expired") {
		t.Fatalf("expired session was not frozen before finish: status=%d body=%+v", finish.status, finish.body)
	}
	stored := getJSON(t, server.URL+"/api/v1/sessions/"+sid)
	if stored["status"] != "failed" || stored["failure_reason"] != "session_expired" {
		t.Fatalf("expired session was not persisted as failed: %+v", stored)
	}
}

func TestBattleAcceptsNewCatalogSkillThroughHTTP(t *testing.T) {
	catalog, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	custom := catalog.Chapters[0].Events[0]
	custom.ID = "custom_skill_event"
	battleSpec := *custom.Battle
	battleSpec.RequiredSkills = []string{"木榫"}
	custom.Battle = &battleSpec
	custom.Reward.Memory.ID = "custom_skill_memory"
	custom.Reward.Memory.Skill = "木榫"
	catalog.Chapters[0].Events = append(catalog.Chapters[0].Events, custom)
	persistence, err := store.Open(filepath.Join(t.TempDir(), "save.json"))
	if err != nil {
		t.Fatal(err)
	}
	api, err := New(catalog, persistence)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(api)
	defer server.Close()

	postJSON(t, server.URL+"/api/v1/players", map[string]any{"player_id": "custom-skill-flow"})
	session := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": "custom-skill-flow", "chapter_id": "prologue", "event_id": "custom_skill_event"})
	sid := session["session_id"].(string)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", map[string]any{"step_id": "bridge_trace", "answer": "平安"})
	battle := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/battle", map[string]any{"duration_ms": 30000, "waves_cleared": 1, "hits_taken": 0, "actions": []map[string]any{{"skill": "木榫", "at_ms": 1000}}})
	if !battle["won"].(bool) {
		t.Fatalf("catalog-defined skill was rejected by HTTP flow: %+v", battle)
	}
}

func postJSON(t *testing.T, url string, body map[string]any) map[string]any {
	t.Helper()
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	response, err := http.Post(url, "application/json", bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	data, _ := io.ReadAll(response.Body)
	var result map[string]any
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatalf("decode %s (%d): %s", url, response.StatusCode, data)
	}
	if response.StatusCode >= 400 {
		t.Fatalf("request %s failed (%d): %s", url, response.StatusCode, data)
	}
	return result
}

type jsonResponse struct {
	status int
	body   map[string]any
}

func postJSONStatus(t *testing.T, url string, body map[string]any) jsonResponse {
	t.Helper()
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	response, err := http.Post(url, "application/json", bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	data, _ := io.ReadAll(response.Body)
	var result map[string]any
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatalf("decode %s (%d): %s", url, response.StatusCode, data)
	}
	return jsonResponse{status: response.StatusCode, body: result}
}

func getJSON(t *testing.T, url string) map[string]any {
	t.Helper()
	response, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	data, _ := io.ReadAll(response.Body)
	var result map[string]any
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatalf("decode %s: %s", url, data)
	}
	if response.StatusCode >= 400 {
		t.Fatalf("GET %s failed (%d): %s", url, response.StatusCode, data)
	}
	return result
}
