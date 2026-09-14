package rules

import (
	"path/filepath"
	"testing"
	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
)

func TestSkillRequiresCorrectTargetAndPriorSupport(t *testing.T) {
	event := &content.Event{Puzzle: content.PuzzleSpec{MaxAttempts: 10, Steps: []content.PuzzleStep{
		{ID: "anchor", Kind: "skill", Answer: "斗拱", Target: "beam", Points: 50},
		{ID: "trigger", Kind: "skill", Answer: "飞檐", Target: "bell", Points: 50},
	}}}
	session := &model.EventSession{Status: "active"}
	if EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "trigger", Answer: "飞檐", Target: "bell"}).Accepted {
		t.Fatal("bell worked before support")
	}
	if EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "anchor", Answer: "斗拱", Target: "bell"}).Accepted {
		t.Fatal("wrong target accepted")
	}
	if !EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "anchor", Answer: "斗拱", Target: "beam"}).Accepted {
		t.Fatal("support rejected")
	}
	if !EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "trigger", Answer: "飞檐", Target: "bell"}).Complete {
		t.Fatal("linked mechanism incomplete")
	}
}

func TestAllBattlesPacingAndDelayedInputs(t *testing.T) {
	catalog, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	learned := map[string]bool{"挥墨": true}
	for _, chapter := range catalog.Chapters {
		for _, event := range chapter.Events {
			learned[event.Reward.Memory.Skill] = true
			if event.Battle == nil {
				continue
			}
			for _, tick := range []int{500, 750} {
				hp, waves, at := event.Battle.EnemyHP, 0, 0
				ready := map[string]int{}
				actions := []BattleAction{}
				for waves < event.Battle.Waves && at < 60000 {
					for _, name := range []string{"斗拱", "藻井", "飞檐", "挥墨"} {
						if !learned[name] || at < ready[name] {
							continue
						}
						spec := catalog.Skills[name]
						ready[name] = at + spec.CooldownMS
						actions = append(actions, BattleAction{Skill: name, AtMS: at})
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
					at += tick
				}
				result, err := EvaluateBattle(&event, BattleInput{Skills: catalog.Skills, AllowedSkills: learned, Actions: actions, DurationMS: at + 1, StartErosion: 50})
				if err != nil || !result.Won || at < 30000 || at >= 60000 {
					t.Fatalf("%s tick %d ms not playable in 30-60 sec: %d %+v %v", event.ID, tick, at, result, err)
				}
				t.Logf("%s input=%d ms duration=%.2fs hits=%d", event.ID, tick, float64(at)/1000, result.HitsTaken)
			}
		}
	}
}
