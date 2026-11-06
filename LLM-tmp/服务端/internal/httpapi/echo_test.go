package httpapi

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
	"yanxia-server/internal/store"
)

func newEchoTestServer(t *testing.T) (*Server, *httptest.Server, string) {
	t.Helper()
	original, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	catalog, err := original.ForEdition(content.EchoEdition)
	if err != nil {
		t.Fatal(err)
	}
	if original.IsEcho() || original.Memories["tower_epilogue"].Capacity != 1 {
		t.Fatal("echo configuration changed original catalog")
	}
	path := filepath.Join(t.TempDir(), "echo.json")
	persistence, err := store.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	api, err := New(catalog, persistence)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(api)
	t.Cleanup(server.Close)
	return api, server, path
}

func solveEchoPuzzle(t *testing.T, server *httptest.Server, chapter string, event content.Event) string {
	t.Helper()
	start := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"chapter_id": chapter, "event_id": event.ID})
	sid := start["session_id"].(string)
	for _, step := range event.Puzzle.Steps {
		request := map[string]any{"step_id": step.ID, "answer": step.Answer, "target": step.Target}
		if step.Kind == "joinery" {
			request["rotation"] = step.Rotation
		}
		if step.Kind == "placement" {
			request["position"] = []float64{.60, .81}
		}
		if step.Kind == "rubbing" {
			request["strokes"] = rubbingSweep()
		}
		if step.Kind == "trace" {
			request = traceRequest(step)
		}
		if step.Kind == "narrative" {
			request["answer"] = step.Options[0]
		}
		result := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", request)
		if result["accepted"] != true {
			t.Fatalf("puzzle %s: %+v", step.ID, result)
		}
	}
	return sid
}

func rubbingSweep() [][][2]float64 {
	var result [][][2]float64
	for y := .04; y < .97; y += .035 {
		var stroke [][2]float64
		for x := .04; x < .97; x += .035 {
			stroke = append(stroke, [2]float64{x, y})
		}
		result = append(result, stroke)
	}
	return result
}

func finishEchoEvent(t *testing.T, api *Server, server *httptest.Server, event content.Event, sid string) model.Player {
	t.Helper()
	if event.ID == "temple_drum" {
		response := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/respond", map[string]any{})
		player, _ := api.store.GetPlayer(api.playerID)
		if response["drum_sounds"] != true || response["child_echo"] != containsMemory(player.Memories, "she_hui_chun") {
			t.Fatalf("real drum or private child echo mismatched: %+v", response)
		}
	}
	if event.Battle != nil {
		battle := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/battle", winningBattle(event))
		if battle["won"] != true {
			t.Fatalf("battle failed: %+v", battle)
		}
	}
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{})
	player, _ := api.store.GetPlayer(api.playerID)
	session, _ := api.store.GetSession(sid)
	result := player.CompletedEvents[eventKey(session.ChapterID, event.ID)]
	if result.Stars != 0 || result.QualityScore != 0 || result.InkMarksEarned != 0 || result.ScoringVersion != 3 || player.InkMarks != 0 {
		t.Fatalf("new journey must record facts without value scores: %+v", result)
	}
	return player
}

func TestEchoFirstChoiceFourBranchesAndReload(t *testing.T) {
	for _, archive := range []string{"yan_ping_an", "she_cheng_xiang", "she_ning_an", "she_hui_chun"} {
		t.Run(archive, func(t *testing.T) {
			api, server, path := newEchoTestServer(t)
			for _, chapter := range api.catalog.Chapters[:2] {
				for _, event := range chapter.Events {
					sid := solveEchoPuzzle(t, server, chapter.ID, event)
					choice := map[string]any{"action": "keep"}
					if event.ID == "temple_drum" {
						player, _ := api.store.GetPlayer(api.playerID)
						if player.Capacity != 3 || usedCapacity(player) != 3 {
							t.Fatalf("first choice too late: %+v", player)
						}
						if archive == "she_hui_chun" {
							choice["action"] = "archive"
						} else {
							choice["action"], choice["forget_memory_id"] = "replace", archive
						}
					}
					postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", choice)
					postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", choice)
					if event.ID == "temple_drum" {
						blocked := postJSONStatus(t, server.URL+"/api/v1/sessions/"+sid+"/finish", map[string]any{})
						if blocked.status != http.StatusConflict || blocked.body["error"].(map[string]any)["code"] != "response_incomplete" {
							t.Fatalf("chapter settled without a saved drum response: %+v", blocked)
						}
						checkpoint, err := store.Open(path)
						if err != nil {
							t.Fatal(err)
						}
						saved, _ := checkpoint.GetSession(sid)
						p, _ := checkpoint.GetPlayer(api.playerID)
						if !saved.ChoiceDone || saved.WorldResponse || p.Capacity != 3 || containsMemory(p.Memories, archive) {
							t.Fatal("post-choice restart would lose the irreversible choice or expand too soon")
						}
					}
					finishEchoEvent(t, api, server, event, sid)
					if event.ID == "temple_drum" {
						checkpoint, err := store.Open(path)
						if err != nil {
							t.Fatal(err)
						}
						saved, _ := checkpoint.GetSession(sid)
						if !saved.WorldResponse {
							t.Fatal("drum response did not persist")
						}
					}
				}
			}
			reloaded, err := store.Open(path)
			if err != nil {
				t.Fatal(err)
			}
			restored, err := New(api.catalog, reloaded)
			if err != nil {
				t.Fatal(err)
			}
			player, _ := restored.store.GetPlayer(restored.playerID)
			if player.Capacity != 4 || len(player.Memories) != 3 || len(player.RecordedMemories) != 4 || containsMemory(player.Memories, archive) {
				t.Fatalf("archive or reload state incorrect: %+v", player)
			}
			if !restored.playerSkills(player)["斗拱"] || !restored.playerSkills(player)["藻井"] {
				t.Fatal("archiving removed learned skills")
			}
			// A new replay session cannot undo the earlier choice.
			replayServer := httptest.NewServer(restored)
			defer replayServer.Close()
			event := restored.catalog.Chapters[1].Events[2]
			sid := solveEchoPuzzle(t, replayServer, "temple", event)
			postJSON(t, replayServer.URL+"/api/v1/sessions/"+sid+"/choice", map[string]any{"action": "keep"})
			player, _ = restored.store.GetPlayer(restored.playerID)
			if containsMemory(player.Memories, archive) || len(player.RecordedMemories) != 4 {
				t.Fatal("revisit changed a committed memory choice")
			}
		})
	}
}

func TestEchoPracticeAndSkillBeforeArchive(t *testing.T) {
	api, server, _ := newEchoTestServer(t)
	start := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"chapter_id": "prologue", "event_id": "prologue_bridge"})
	sid := start["session_id"].(string)
	for i := 0; i < 20; i++ {
		wrong := postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", map[string]any{"step_id": "wrong", "answer": "wrong"})
		if wrong["status"] == "failed" || wrong["erosion"].(float64) != 0 {
			t.Fatal("practice punished experimentation")
		}
	}
	event := api.catalog.Chapters[0].Events[0]
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/puzzle", traceRequest(event.Puzzle.Steps[0]))
	player, _ := api.store.GetPlayer(api.playerID)
	if !api.playerSkills(player)["斗拱"] || len(player.Memories) != 0 {
		t.Fatal("skill must be learned from repair before choosing memory")
	}
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", map[string]any{"action": "archive"})
	player = finishEchoEvent(t, api, server, event, sid)
	if len(player.Memories) != 0 || len(player.RecordedMemories) != 1 || !api.playerSkills(player)["斗拱"] {
		t.Fatal("archive new echo lost evidence or skills")
	}
	if player.CompletedEvents["prologue:prologue_bridge"].MemoriesAcquired != 1 {
		t.Fatal("archived discoveries must still count as recorded facts")
	}
}

func TestEchoCompleteJourneyCapacityAndFinalPage(t *testing.T) {
	api, server, _ := newEchoTestServer(t)
	for _, chapter := range api.catalog.Chapters {
		for _, event := range chapter.Events {
			sid := solveEchoPuzzle(t, server, chapter.ID, event)
			player, _ := api.store.GetPlayer(api.playerID)
			choice := map[string]any{"action": "keep"}
			if !event.Reward.Memory.Epilogue && usedCapacity(player) == player.Capacity {
				choice["action"], choice["forget_memory_id"] = "replace", player.Memories[0].ID
			}
			postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", choice)
			finishEchoEvent(t, api, server, event, sid)
		}
	}
	player, _ := api.store.GetPlayer(api.playerID)
	if player.Capacity != 5 || len(player.Memories) != 5 || len(player.RecordedMemories) != 10 || len(player.CompletedEvents) != 10 {
		t.Fatalf("full journey did not meet capacity contract: %+v", player)
	}
	if containsMemory(player.Memories, "tower_epilogue") {
		t.Fatal("final page consumed living capacity")
	}
}

func TestEchoBattleRetryPreservesRepairAndChoice(t *testing.T) {
	api, server, _ := newEchoTestServer(t)
	event := api.catalog.Chapters[0].Events[0]
	sid := solveEchoPuzzle(t, server, "prologue", event)
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/choice", map[string]any{"action": "archive"})
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/battle", map[string]any{"duration_ms": 1000, "actions": []any{}})
	postJSON(t, server.URL+"/api/v1/sessions/"+sid+"/rewind", map[string]any{"retries": 0})
	session, _ := api.store.GetSession(sid)
	if len(session.AcceptedSteps) != len(event.Puzzle.Steps) || !session.ChoiceDone || session.ChoiceAction != "archive" {
		t.Fatal("retry lost repair or choice")
	}
	finishEchoEvent(t, api, server, event, sid)
}

func TestEchoRejectsOriginalSaveWithoutMutation(t *testing.T) {
	original, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "original.json")
	database, err := store.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	api, err := New(original, database)
	if err != nil {
		t.Fatal(err)
	}
	_, err = database.UpdatePlayer(api.playerID, func(player *model.Player) error { player.Capacity = 7; return nil })
	if err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(path)
	echo, err := original.ForEdition(content.EchoEdition)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = New(echo, database); err == nil {
		t.Fatal("echo accepted original save")
	}
	after, _ := os.ReadFile(path)
	if !bytes.Equal(before, after) {
		t.Fatal("mismatched edition mutated original save")
	}
	server := httptest.NewServer(api)
	defer server.Close()
	if getJSON(t, server.URL+"/healthz")["edition"] != content.OriginalEdition {
		t.Fatal("original service changed edition")
	}
	if postJSONStatus(t, server.URL+"/api/v1/sessions", map[string]any{"chapter_id": "missing", "event_id": "missing"}).status != http.StatusNotFound {
		t.Fatal("original API no longer working")
	}
}
