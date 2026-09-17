package rules

import (
	"testing"
	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
)

func TestNarrativeChoicesAreEquallyValidAndCannotBeRewritten(t *testing.T) {
	event := &content.Event{Puzzle: content.PuzzleSpec{Steps: []content.PuzzleStep{{ID: "ending", Kind: "narrative", Options: []string{"传艺", "记事", "留白"}, Points: 100}}}}
	for _, answer := range event.Puzzle.Steps[0].Options {
		session := &model.EventSession{Status: "active"}
		result := EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "ending", Answer: answer})
		if !result.Accepted || session.PuzzleScore != 100 || session.NarrativeChoice != answer || result.ErosionDelta != 0 {
			t.Fatalf("valid choice rejected: %+v", result)
		}
		EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "ending", Answer: "invalid"})
		if session.NarrativeChoice != answer || session.PuzzleScore != 100 {
			t.Fatal("replay changed ending")
		}
	}
	session := &model.EventSession{Status: "active"}
	result := EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "ending", Answer: "not authored"})
	if result.Accepted || session.NarrativeChoice != "" {
		t.Fatal("unknown choice accepted")
	}
}
