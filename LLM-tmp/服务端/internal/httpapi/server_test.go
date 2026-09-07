package httpapi

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
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

	player := postJSON(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "flow", "password": "test-password-123"})
	token := player["access_token"].(string)
	playerID := player["player"].(map[string]any)["id"].(string)
	if player["player"].(map[string]any)["id"] != playerID {
		t.Fatalf("unexpected player response: %+v", player)
	}
	public := getJSON(t, server.URL+"/api/v1/catalog", token)
	encoded, _ := json.Marshal(public)
	if bytes.Contains(encoded, []byte(`"answer"`)) {
		t.Fatal("catalog leaked puzzle answer")
	}
	session := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": playerID, "chapter_id": "prologue", "event_id": "prologue_bridge"}, token)
	sid := session["session_id"].(string)
	wrong := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", map[string]any{"step_id": "bridge_trace", "answer": "错"}, token)
	if wrong["erosion"].(float64) != 0 || len(wrong["failed_strokes"].([]any)) != 11 {
		t.Fatalf("trace practice must report missing strokes without erosion: %+v", wrong)
	}
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", traceRequest(catalog.Chapters[0].Events[0].Puzzle.Steps[0]), token)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", map[string]any{"action": "keep"}, token)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/battle", winningBattle(catalog.Chapters[0].Events[0]), token)
	first := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{}, token)
	second := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{}, token)
	if first["reason"] != "settled" || second["reason"] != "already_settled" {
		t.Fatalf("finish is not idempotent: first=%+v second=%+v", first, second)
	}
	firstResult := first["result"].(map[string]any)
	secondResult := second["result"].(map[string]any)
	if firstResult["sequence"] != secondResult["sequence"] {
		t.Fatalf("repeat finish changed sequence: %v vs %v", firstResult["sequence"], secondResult["sequence"])
	}
}

func TestFailedSessionRequiresExplicitRewind(t *testing.T) {
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

	login := postJSON(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "retry_flow", "password": "test-password-123"})
	token := login["access_token"].(string)
	playerID := login["player"].(map[string]any)["id"].(string)
	session := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": playerID, "chapter_id": "prologue", "event_id": "prologue_bridge"}, token)
	sid := session["session_id"].(string)
	for attempt := 0; attempt < 3; attempt++ {
		postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", map[string]any{"step_id": "out_of_order", "answer": "错误"}, token)
	}
	failed := postJSONStatus(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", traceRequest(catalog.Chapters[0].Events[0].Puzzle.Steps[0]), token)
	if failed.status != http.StatusConflict || failed.body["error"].(map[string]any)["code"] != "session_failed" {
		t.Fatalf("failed puzzle session was reusable: status=%d body=%+v", failed.status, failed.body)
	}

	newSession := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": playerID, "chapter_id": "prologue", "event_id": "prologue_bridge"}, token)
	newSID := newSession["session_id"].(string)
	if newSID != sid {
		t.Fatal("start bypassed failed session")
	}
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/rewind", map[string]any{"retries": 0}, token)
	postJSON(t, server.URL+"/api/v1/sessions/"+newSID+"/puzzle", traceRequest(catalog.Chapters[0].Events[0].Puzzle.Steps[0]), token)
	postJSON(t, server.URL+"/api/v1/sessions/"+newSID+"/choice", map[string]any{"action": "keep"}, token)
	failedBattle := postJSON(t, server.URL+"/api/v1/sessions/"+newSID+"/battle", map[string]any{"duration_ms": 1000, "waves_cleared": 0, "hits_taken": 0, "actions": []map[string]any{}}, token)
	if failedBattle["won"].(bool) || failedBattle["status"] != "failed" {
		t.Fatalf("expected failed battle session: %+v", failedBattle)
	}
	reusedBattle := postJSONStatus(t, server.URL+"/api/v1/sessions/"+newSID+"/battle", winningBattle(catalog.Chapters[0].Events[0]), token)
	if reusedBattle.status != http.StatusConflict || reusedBattle.body["error"].(map[string]any)["code"] != "session_failed" {
		t.Fatalf("failed battle session was reusable: status=%d body=%+v", reusedBattle.status, reusedBattle.body)
	}
}

func TestReadingAndOldDeadlineDoNotFailEvent(t *testing.T) {
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

	login := postJSON(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "expiry_flow", "password": "test-password-123"})
	token := login["access_token"].(string)
	playerID := login["player"].(map[string]any)["id"].(string)
	session := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": playerID, "chapter_id": "prologue", "event_id": "prologue_bridge"}, token)
	sid := session["session_id"].(string)
	if _, err := persistence.UpdateSession(sid, func(current *model.EventSession) error {
		current.ExpiresAt = time.Now().UTC().Add(-time.Minute)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", traceRequest(catalog.Chapters[0].Events[0].Puzzle.Steps[0]), token)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", map[string]any{"action": "keep"}, token)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/battle", winningBattle(catalog.Chapters[0].Events[0]), token)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{}, token)
	p, _ := persistence.GetPlayer(playerID)
	if p.Erosion != 0 {
		t.Fatalf("reading caused erosion: %d", p.Erosion)
	}

}

func TestBattleAcceptsNewCatalogSkillThroughHTTP(t *testing.T) {
	catalog, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	catalog.Skills["木榫"] = catalog.Skills["斗拱"]
	custom := catalog.Chapters[0].Events[0]
	custom.ID = "custom_skill_event"
	catalog.Art[custom.ID] = catalog.Art["prologue_bridge"]
	battleSpec := *custom.Battle
	battleSpec.RequiredSkills = []string{"木榫"}
	custom.Battle = &battleSpec
	custom.Reward.Memory.ID = "custom_skill_memory"
	custom.Reward.Memory.Skill = "木榫"
	custom.Reward.MemoryID = "custom_skill_memory"
	custom.Reward.Memory.Source = "prologue/custom_skill_event"
	catalog.Memories[custom.Reward.MemoryID] = custom.Reward.Memory
	catalog.Chapters[0].Events = []content.Event{custom}
	contentPath := filepath.Join(t.TempDir(), "chapters.json")
	encoded, err := json.Marshal(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(contentPath, encoded, 0600); err != nil {
		t.Fatal(err)
	}
	catalog, err = content.Load(contentPath)
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

	login := postJSON(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "custom_skill_flow", "password": "test-password-123"})
	token := login["access_token"].(string)
	playerID := login["player"].(map[string]any)["id"].(string)
	session := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": playerID, "chapter_id": "prologue", "event_id": "custom_skill_event"}, token)
	sid := session["session_id"].(string)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", traceRequest(catalog.Chapters[0].Events[0].Puzzle.Steps[0]), token)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", map[string]any{"action": "keep"}, token)
	battle := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/battle", winningBattle(custom), token)
	if !battle["won"].(bool) {
		t.Fatalf("catalog-defined skill was rejected by HTTP flow: %+v", battle)
	}
}

func postJSON(t *testing.T, url string, body map[string]any, token ...string) map[string]any {
	t.Helper()
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	request, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Content-Type", "application/json")
	if len(token) > 0 {
		request.Header.Set("Authorization", "Bearer "+token[0])
	}
	response, err := http.DefaultClient.Do(request)
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

func postJSONStatus(t *testing.T, url string, body map[string]any, token ...string) jsonResponse {
	t.Helper()
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	request, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Content-Type", "application/json")
	if len(token) > 0 {
		request.Header.Set("Authorization", "Bearer "+token[0])
	}
	response, err := http.DefaultClient.Do(request)
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

func getJSON(t *testing.T, url string, token ...string) map[string]any {
	t.Helper()
	request, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(token) > 0 {
		request.Header.Set("Authorization", "Bearer "+token[0])
	}
	response, err := http.DefaultClient.Do(request)
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

func traceRequest(step content.PuzzleStep) map[string]any {
	strokes := make([][][2]float64, len(step.Trace.Strokes))
	for i, stroke := range step.Trace.Strokes {
		strokes[i] = append(strokes[i], stroke[0])
		for j := 1; j < len(stroke); j++ {
			for k := 1; k <= 50; k++ {
				t := float64(k) / 50
				strokes[i] = append(strokes[i], [2]float64{stroke[j-1][0] + t*(stroke[j][0]-stroke[j-1][0]), stroke[j-1][1] + t*(stroke[j][1]-stroke[j-1][1])})
			}
		}
	}
	return map[string]any{"step_id": step.ID, "strokes": strokes}
}

func TestFullDemoSurvivesReloadWithoutDuplicateRewards(t *testing.T) {
	catalog, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "save.json")
	persistence, err := store.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	api, err := New(catalog, persistence)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(api)
	defer server.Close()
	login := postJSON(t, server.URL+"/api/v1/auth/register", map[string]any{"username": "full_demo", "password": "test-password-123"})
	token := login["access_token"].(string)
	playerID := login["player"].(map[string]any)["id"].(string)
	lastSID := ""
	for _, chapter := range catalog.Chapters[:2] {
		for _, event := range chapter.Events {
			start := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"player_id": playerID, "chapter_id": chapter.ID, "event_id": event.ID}, token)
			sid := start["session_id"].(string)
			lastSID = sid
			for _, step := range event.Puzzle.Steps {
				input := map[string]any{"step_id": step.ID, "answer": step.Answer}
				if step.Kind == "trace" {
					input = traceRequest(step)
				}
				response := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", input, token)
				if response["accepted"] != true {
					t.Fatalf("step %s rejected: %+v", step.ID, response)
				}
			}
			input := map[string]any{"action": "keep"}
			if event.ID == "temple_drum" {
				input = map[string]any{"action": "forget", "forget_memory_id": "yan_ping_an"}
			}
			postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", input, token)
			postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", input, token)
			if event.Battle != nil {
				postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/battle", winningBattle(event), token)
			}
			postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{}, token)
			postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{}, token)
		}
	}
	reloaded, err := store.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	player, _ := reloaded.GetPlayer(playerID)
	if player.InkMarks != 12 {
		t.Fatal("draft chapter consumed ink marks")
	}
	if len(player.CompletedEvents) != 4 || len(player.Memories) != 3 || len(player.MemoryLedger) != 5 || player.Capacity != 6 || player.LastSequence != 4 {
		t.Fatalf("progress lost or duplicated: %+v", player)
	}
	if player.MemoryLedger[3].Action != "forgotten" || player.MemoryLedger[3].MemoryID != "yan_ping_an" || player.MemoryLedger[3].EventID != "temple_drum" {
		t.Fatalf("wrong narrative link: %+v", player.MemoryLedger)
	}
	session, _ := reloaded.GetSession(lastSID)
	if session.Status != "completed" || session.PendingResult == nil {
		t.Fatal("settlement not persisted")
	}
	if !api.playerSkills(player)["斗拱"] || !api.playerSkills(player)["藻井"] {
		t.Fatal("learned skill lost after erasure")
	}
}

func winningBattle(event content.Event) map[string]any {
	actions := []map[string]any{}
	damage := 0
	for _, skill := range event.Battle.RequiredSkills {
		actions = append(actions, map[string]any{"skill": skill, "at_ms": 0})
		if skill == "藻井" {
			damage += 18
		}
	}
	at := 0
	for damage < event.Battle.EnemyHP {
		actions = append(actions, map[string]any{"skill": "挥墨", "at_ms": at})
		damage += 10
		at += 500
	}
	return map[string]any{"duration_ms": at, "actions": actions}
}
