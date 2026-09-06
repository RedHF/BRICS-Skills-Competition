package rules

import (
	"testing"

	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
)

func TestEvaluatePuzzleStepIsOrderedAndPenalizesWrongAnswer(t *testing.T) {
	event := &content.Event{Puzzle: content.PuzzleSpec{MaxAttempts: 3, Steps: []content.PuzzleStep{
		{ID: "a", Answer: "甲", Points: 40},
		{ID: "b", Answer: "乙", Points: 60},
	}}}
	session := &model.EventSession{Status: "active", PuzzleTotal: 100, AcceptedSteps: []string{}}
	wrong := EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "b", Answer: "乙"})
	if wrong.Accepted || wrong.ErosionDelta != 10 || wrong.Reason != "step_out_of_order" {
		t.Fatalf("unexpected out-of-order result: %+v", wrong)
	}
	good := EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "a", Answer: "甲"})
	if !good.Accepted || !good.Correct || good.ScoreDelta != 40 {
		t.Fatalf("unexpected accepted result: %+v", good)
	}
	last := EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "b", Answer: "乙"})
	if !last.Complete || session.PuzzleScore != 100 || len(session.AcceptedSteps) != 2 {
		t.Fatalf("puzzle did not complete: result=%+v session=%+v", last, session)
	}
}

func TestBattleReplaysDamageShieldHealingAndCooldown(t *testing.T) {
	skills := map[string]content.SkillSpec{
		"挥墨": {CooldownMS: 500, Damage: 10}, "斗拱": {CooldownMS: 6000, Shield: 2},
		"藻井": {CooldownMS: 6000, Damage: 18, Heal: 1}, "木榫": {CooldownMS: 1000, Damage: 30},
	}
	allowed := map[string]bool{"挥墨": true, "斗拱": true, "藻井": true, "木榫": true}
	event := &content.Event{Battle: &content.BattleSpec{Waves: 1, EnemyHP: 30, DurationSec: 30, MaxHitsTaken: 2, RequiredSkills: []string{"斗拱"}}}
	cases := []struct {
		name     string
		actions  []BattleAction
		duration int
		won      bool
		hits     int
		invalid  bool
	}{
		{"shield and attack", []BattleAction{{"斗拱", 0}, {"挥墨", 3000}, {"挥墨", 3500}, {"挥墨", 4000}}, 4000, true, 0, false},
		{"forged victory without damage", []BattleAction{{"斗拱", 0}}, 1000, false, 0, false},
		{"idle loses", nil, 30000, false, 3, false},
		{"missing required skill", []BattleAction{{"木榫", 0}}, 1000, false, 0, false},
		{"healing", []BattleAction{{"斗拱", 0}, {"藻井", 9000}, {"挥墨", 9000}, {"挥墨", 9500}}, 9500, true, 0, false},
		{"cooldown spam", []BattleAction{{"挥墨", 0}, {"挥墨", 100}}, 1000, false, 0, true},
		{"outside timeline", []BattleAction{{"斗拱", 30001}}, 30000, false, 0, true},
		{"unknown skill", []BattleAction{{"伪造", 0}}, 1000, false, 0, true},
		{"late action", []BattleAction{{"挥墨", 12000}}, 15000, false, 0, true},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			eval, err := EvaluateBattle(event, BattleInput{Skills: skills, AllowedSkills: allowed, Actions: test.actions, DurationMS: test.duration, WavesCleared: 1, HitsTaken: 0})
			if (err != nil) != test.invalid {
				t.Fatalf("error=%v", err)
			}
			if err == nil && (eval.Won != test.won || eval.HitsTaken != test.hits) {
				t.Fatalf("unexpected replay: %+v", eval)
			}
		})
	}
	event.Battle.RequiredSkills = []string{"木榫"}
	eval, err := EvaluateBattle(event, BattleInput{Skills: skills, AllowedSkills: allowed, Actions: []BattleAction{{"木榫", 0}}, DurationMS: 1})
	if err != nil || !eval.Won {
		t.Fatalf("new data-defined skill failed: %+v %v", eval, err)
	}
	event.Battle.Waves = 2
	eval, err = EvaluateBattle(event, BattleInput{Skills: skills, AllowedSkills: allowed, Actions: []BattleAction{{"木榫", 0}, {"木榫", 1000}}, DurationMS: 1000})
	if err != nil || !eval.Won || eval.Waves != 2 {
		t.Fatalf("multiple enemies did not advance waves: %+v %v", eval, err)
	}
}
