package rules

import (
	"path/filepath"
	"testing"
	"yanxia-server/internal/content"
)

func TestBossBeginsWithThirdDistinctLearnedSkill(t *testing.T) {
	c, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	learned := map[string]bool{}
	bosses := 0
	for _, chapter := range c.Chapters {
		for _, event := range chapter.Events {
			before := len(learned)
			if skill := event.Reward.Memory.Skill; skill != "" {
				learned[skill] = true
			}
			if event.Battle != nil && event.Battle.BossName != "" {
				bosses++
				if before != 2 || len(learned) != 3 || event.ID != "opera_opening" {
					t.Fatalf("boss at wrong acquisition: %s", event.ID)
				}
				for _, name := range event.Battle.RequiredSkills {
					if !learned[name] {
						t.Fatal("boss requires unavailable skill", name)
					}
				}
			}
		}
	}
	if bosses != 1 {
		t.Fatalf("expected exactly one miniboss, got %d", bosses)
	}
}

func TestBossWaveHealthCadenceAndAuthoritativeSettlement(t *testing.T) {
	event := &content.Event{Battle: &content.BattleSpec{Waves: 2, EnemyHP: 10, BossName: "test boss", BossHP: 20, BossAttackIntervalMS: 2400, DurationSec: 60, MaxHitsTaken: 4}}
	input := BattleInput{Skills: map[string]content.SkillSpec{"挥墨": {CooldownMS: 500, Damage: 10}}, AllowedSkills: map[string]bool{"挥墨": true}, DurationMS: 4800, Actions: []BattleAction{{Skill: "挥墨", AtMS: 0}, {Skill: "挥墨", AtMS: 2400}, {Skill: "挥墨", AtMS: 4800}}, WavesCleared: 99, HitsTaken: 0}
	eval, err := EvaluateBattle(event, input)
	if err != nil || !eval.Won || eval.Waves != 2 || eval.HitsTaken != 2 {
		t.Fatalf("boss timeline mismatch: %+v %v", eval, err)
	}
	input.Actions = input.Actions[:1]
	eval, err = EvaluateBattle(event, input)
	if err != nil || eval.Won || eval.Waves != 1 {
		t.Fatalf("client claimed a boss victory: %+v %v", eval, err)
	}
	input.Actions = append(input.Actions, BattleAction{Skill: "挥墨", AtMS: 2400}, BattleAction{Skill: "挥墨", AtMS: 4800})
	event.Battle.RequiredSkills = []string{"飞檐"}
	eval, err = EvaluateBattle(event, input)
	if err != nil || eval.Won {
		t.Fatalf("missing required skill accepted: %+v %v", eval, err)
	}
	event.Battle.RequiredSkills = nil
	input.Actions = nil
	input.DurationMS = 60000
	eval, err = EvaluateBattle(event, input)
	if err != nil || eval.Won || eval.Reason != "battle_requirements_not_met" {
		t.Fatalf("idle defeat mismatch: %+v %v", eval, err)
	}
}
