package rules

import (
	"testing"
	"yanxia-server/internal/content"
)

func TestGuardCanClearAfterTakingAHit(t *testing.T) {
	event := &content.Event{Battle: &content.BattleSpec{Waves: 1, EnemyHP: 10, DurationSec: 90, MaxHitsTaken: 12}}
	result, err := EvaluateBattle(event, BattleInput{
		Skills:        map[string]content.SkillSpec{"挥墨": {Damage: 10, CooldownMS: 500}},
		AllowedSkills: map[string]bool{"挥墨": true},
		Actions:       []BattleAction{{Skill: "挥墨", AtMS: 3100}}, DurationMS: 3100,
	})
	if err != nil || !result.Won || result.HitsTaken != 1 {
		t.Fatalf("one hit must not turn a clear into failure: %+v, %v", result, err)
	}
	timeout, err := EvaluateBattle(event, BattleInput{DurationMS: 90000})
	if err != nil || timeout.Won {
		t.Fatalf("unfinished guard must remain retryable failure: %+v, %v", timeout, err)
	}
}
