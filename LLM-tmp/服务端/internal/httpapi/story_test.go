package httpapi

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"yanxia-server/internal/content"
	"yanxia-server/internal/store"
)

func TestSoloStoryJourneyAndEndingPersist(t *testing.T) {
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
	first := postJSON(t, server.URL+"/api/v1/players", map[string]any{})
	id := first["player"].(map[string]any)["id"].(string)
	public := getJSON(t, server.URL+"/api/v1/catalog")
	event := public["chapters"].([]any)[0].(map[string]any)["events"].([]any)[0].(map[string]any)
	if len(event["investigations"].([]any)) != 3 || len(event["story"].(map[string]any)["dialogue"].([]any)) != 6 {
		t.Fatal("story or investigations missing from public catalog")
	}
	if postJSONStatus(t, server.URL+"/api/v1/auth/login", map[string]any{}).status != http.StatusNotFound {
		t.Fatal("login route still exists")
	}
	for _, chapter := range catalog.Chapters {
		for _, event := range chapter.Events {
			started := postJSON(t, server.URL+"/api/v1/sessions", map[string]any{"chapter_id": chapter.ID, "event_id": event.ID})
			sid := started["session_id"].(string)
			url := server.URL + "/api/v1/sessions/" + sid
			for _, step := range event.Puzzle.Steps {
				input := map[string]any{"step_id": step.ID, "answer": step.Answer}
				if step.Kind == "trace" {
					input = traceRequest(step)
				}
				if step.Kind == "narrative" {
					input["answer"] = step.Options[2]
				}
				response := postJSON(t, url+"/puzzle", input)
				if response["accepted"] != true {
					t.Fatalf("%s rejected: %+v", step.ID, response)
				}
				if step.Kind == "narrative" {
					postJSON(t, url+"/puzzle", map[string]any{"step_id": step.ID, "answer": step.Options[0]})
				}
			}
			player, _ := db.GetPlayer(id)
			choice := map[string]any{"action": "keep"}
			if len(player.Memories) >= player.Capacity {
				choice = map[string]any{"action": "forget", "forget_memory_id": player.Memories[0].ID}
			}
			postJSON(t, url+"/choice", choice)
			if event.Battle != nil {
				// Use real cooldowns and damage to construct a playable full battle.
				hp, waves, at := event.Battle.EnemyHP, 0, 0
				ready := map[string]int{}
				actions := []map[string]any{}
				skills := []string{"斗拱", "藻井", "飞檐", "挥墨"}
				held := api.playerSkills(player)
				held[event.Reward.Memory.Skill] = true
				held["挥墨"] = true
				for waves < event.Battle.Waves && at < event.Battle.DurationSec*1000 {
					for _, name := range skills {
						if !held[name] || at < ready[name] {
							continue
						}
						spec := catalog.Skills[name]
						actions = append(actions, map[string]any{"skill": name, "at_ms": at})
						ready[name] = at + spec.CooldownMS
						hp -= spec.Damage
						if hp <= 0 {
							waves++
							hp = event.Battle.EnemyHP
						}
						if waves == event.Battle.Waves {
							break
						}
					}
					if waves == event.Battle.Waves {
						break
					}
					at += 500
				}
				result := postJSON(t, url+"/battle", map[string]any{"duration_ms": at + 1, "actions": actions})
				if result["won"] != true {
					t.Fatalf("%s is not winnable: %+v", event.ID, result)
				}
			}
			postJSON(t, url+"/finish", map[string]any{})
			postJSON(t, url+"/finish", map[string]any{})
		}
	}
	reloaded, err := store.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	restored, err := reloaded.LocalPlayer()
	if err != nil {
		t.Fatal(err)
	}
	if restored.ID != id || len(restored.CompletedEvents) != 10 || restored.LastSequence != 10 || restored.Capacity != 7 {
		t.Fatalf("journey did not persist: %+v", restored)
	}
	if restored.CompletedEvents["tower:tower_ledger"].NarrativeChoice != "留白让后来人续写" {
		t.Fatal("ending lost or overwritten by retry")
	}
}
