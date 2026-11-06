package rules

import (
	"path/filepath"
	"testing"

	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
)

func echoStage(t *testing.T, id string) *content.Event {
	t.Helper()
	base, err := content.Load(filepath.Join("..", "..", "content", "chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	catalog, err := base.ForEdition(content.EchoEdition)
	if err != nil {
		t.Fatal(err)
	}
	event, ok := catalog.Event("temple", id)
	if !ok {
		t.Fatal(id)
	}
	return event
}

func TestJoineryChecksDependenciesRotationAndBothOrders(t *testing.T) {
	event := echoStage(t, "temple_incense")
	for _, reverse := range []bool{false, true} {
		session := &model.EventSession{Status: "active"}
		attempt := func(id, answer, target string, rotation int) PuzzleEvaluation {
			return EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: id, Answer: answer, Target: target, Rotation: rotation})
		}
		if attempt("hall_left", "JOIN-L", "SLOT-L", 180).Accepted {
			t.Fatal("installed without inspection and support")
		}
		if !attempt("inspect_marks", "marks", "", 0).Accepted || !attempt("inspect_join", "join", "", 0).Accepted {
			t.Fatal("inspection order was unnecessarily fixed")
		}
		if !attempt("hall_support", "斗拱", "beam", 0).Accepted {
			t.Fatal("support rejected")
		}
		if attempt("hall_left", "JOIN-L", "SLOT-L", 0).Accepted {
			t.Fatal("wrong rotation passed")
		}
		if attempt("hall_center", "JOIN-C", "SLOT-C", 0).Accepted {
			t.Fatal("middle installed before both ends")
		}
		ids := []string{"hall_left", "hall_right"}
		if reverse {
			ids[0], ids[1] = ids[1], ids[0]
		}
		for _, id := range ids {
			answer, target, rotation := "JOIN-L", "SLOT-L", 180
			if id == "hall_right" {
				answer, target, rotation = "JOIN-R", "SLOT-R", 0
			}
			if !attempt(id, answer, target, rotation).Accepted {
				t.Fatal("valid end order rejected")
			}
		}
		if !attempt("hall_center", "JOIN-C", "SLOT-C", 0).Accepted {
			t.Fatal("middle failed after both ends")
		}
		if !attempt("hall_release", "release", "support", 0).Complete {
			t.Fatal("completed frame did not settle")
		}
		before := len(session.AcceptedSteps)
		if !attempt("hall_left", "JOIN-L", "SLOT-L", 180).Accepted || len(session.AcceptedSteps) != before {
			t.Fatal("accepted request replay was not idempotent")
		}
		if session.InvalidAttempts != 0 || session.Status == "failed" {
			t.Fatal("practice was punished")
		}
	}
}

func TestBowlPlacementUsesAreaInsteadOfOnePoint(t *testing.T) {
	event := echoStage(t, "temple_guest")
	for _, p := range [][2]float64{{.55, .80}, {.60, .81}, {.66, .83}} {
		if !ValidPlacement(event.Stage, p) {
			t.Fatalf("valid sheltered floor rejected: %v", p)
		}
	}
	for _, p := range [][2]float64{{.15, .80}, {.77, .88}, {0, 0}, {1.1, .8}} {
		if ValidPlacement(event.Stage, p) {
			t.Fatalf("wet or occupied floor accepted: %v", p)
		}
	}
	position := [2]float64{.60, .81}
	session := &model.EventSession{Status: "active", AcceptedSteps: []string{"inspect_bowl", "inspect_cape"}}
	if !EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "guest_place", Answer: "bowl", Target: "dry_floor", Position: &position}).Complete {
		t.Fatal("valid bowl placement did not complete")
	}
}

func TestRubbingRequiresRealCoverageOrCompletedAssistance(t *testing.T) {
	event := echoStage(t, "temple_drum")
	spec := event.Stage.Rubbing
	var sweep [][][2]float64
	for y := .02; y < 1; y += .03 {
		var stroke [][2]float64
		for x := .02; x < 1; x += .03 {
			stroke = append(stroke, [2]float64{x, y})
		}
		sweep = append(sweep, stroke)
	}
	for _, region := range spec.Regions {
		if coverage := RubbingCoverage(spec, region, sweep); coverage < .99 {
			t.Fatalf("real sweep did not cover %s: %f", region.ID, coverage)
		}
		if RubbingCoverage(spec, region, [][][2]float64{{{.01, .01}, {.02, .02}}}) != 0 {
			t.Fatal("outside strokes created progress")
		}
		if RubbingCoverage(spec, region, [][][2]float64{{{.02, .5}, {.98, .5}}}) >= spec.Threshold {
			t.Fatal("cursor teleport completed a region")
		}
	}
	session := &model.EventSession{Status: "active", AcceptedSteps: []string{"inspect_drum", "inspect_rope", "drum_reveal"}}
	if EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "rub_outer", AssistMS: 1499}).Accepted {
		t.Fatal("incomplete assisted hold accepted")
	}
	if !EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "rub_outer", AssistMS: 1500}).Accepted {
		t.Fatal("accessible assisted path rejected")
	}
	if EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "rub_center", Strokes: [][][2]float64{{{.5, .5}}}}).Accepted {
		t.Fatal("single stationary dab completed center")
	}
	if len(session.AcceptedSteps) != 4 {
		t.Fatal("partial coverage changed a completed region")
	}
	if !EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "rub_seam", Strokes: sweep}).Accepted {
		t.Fatal("seam sweep rejected")
	}
	if !EvaluatePuzzleStep(event, session, PuzzleAttempt{StepID: "rub_center", Strokes: sweep}).Complete {
		t.Fatal("three completed regions did not finish")
	}
}
