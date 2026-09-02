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

func TestEvaluateBattleRejectsForgedTimeline(t *testing.T) {
	event := &content.Event{Battle: &content.BattleSpec{Waves: 1, DurationSec: 30, MaxHitsTaken: 2, RequiredSkills: []string{"斗拱"}}}
	if _, err := EvaluateBattle(event, BattleInput{DurationMS: 30000, Actions: []BattleAction{{Skill: "斗拱", AtMS: 30001}}}); err == nil {
		t.Fatal("expected timestamp validation error")
	}
	eval, err := EvaluateBattle(event, BattleInput{DurationMS: 30000, Actions: []BattleAction{{Skill: "斗拱", AtMS: 1000}}, WavesCleared: 1})
	if err != nil || !eval.Won || eval.ErosionDelta != 0 {
		t.Fatalf("unexpected battle result: %+v err=%v", eval, err)
	}
}

func TestEvaluateBattleAcceptsCatalogSkillWhenAllowed(t *testing.T) {
	event := &content.Event{Battle: &content.BattleSpec{Waves: 1, DurationSec: 30, MaxHitsTaken: 2, RequiredSkills: []string{"木榫"}}}
	eval, err := EvaluateBattle(event, BattleInput{
		DurationMS: 30000, WavesCleared: 1,
		Actions:       []BattleAction{{Skill: "木榫", AtMS: 1000}},
		AllowedSkills: map[string]bool{"木榫": true},
	})
	if err != nil || !eval.Won {
		t.Fatalf("catalog-defined skill was not accepted: %+v err=%v", eval, err)
	}
	if _, err := EvaluateBattle(event, BattleInput{
		DurationMS: 30000, WavesCleared: 1,
		Actions:       []BattleAction{{Skill: "伪造", AtMS: 1000}},
		AllowedSkills: map[string]bool{"木榫": true},
	}); err == nil {
		t.Fatal("unowned battle skill was accepted")
	}
}
