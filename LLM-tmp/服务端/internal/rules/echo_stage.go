package rules

import (
	"fmt"
	"math"
	"time"

	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
)

func evaluateEchoStep(event *content.Event, session *model.EventSession, attempt PuzzleAttempt) PuzzleEvaluation {
	result := PuzzleEvaluation{PuzzleTotal: puzzleTotal(event)}
	record := model.ActionRecord{StepID: attempt.StepID, Action: attempt.Action, AnswerHash: hashAnswer(fmt.Sprintf("%s:%s:%d:%v:%v:%d", attempt.Answer, attempt.Target, attempt.Rotation, attempt.Position, attempt.Strokes, attempt.AssistMS)), OccurredAt: time.Now().UTC()}
	if session == nil || event.Stage == nil {
		result.Reason = "invalid_session"
		result.ActionRecord = record
		return result
	}
	result.PuzzleScore, result.AttemptCount = session.PuzzleScore, session.AttemptCount
	if session.Status == "failed" {
		result.Reason = "session_failed"
		result.ActionRecord = record
		return result
	}
	done := map[string]bool{}
	for _, id := range session.AcceptedSteps {
		done[id] = true
	}
	if done[attempt.StepID] {
		result.Accepted, result.Correct = true, true
		result.Complete = len(done) == len(event.Puzzle.Steps)
		result.Reason = "step_already_accepted"
		record.Accepted, record.Reason = true, result.Reason
		result.ActionRecord = record
		return result
	}
	if session.Status == "completed" || len(done) == len(event.Puzzle.Steps) {
		result.Accepted, result.Correct, result.Complete = true, true, true
		result.Reason = "puzzle_complete"
		record.Accepted = true
		result.ActionRecord = record
		return result
	}
	var step *content.PuzzleStep
	for i := range event.Puzzle.Steps {
		if event.Puzzle.Steps[i].ID == attempt.StepID {
			step = &event.Puzzle.Steps[i]
			break
		}
	}
	session.AttemptCount++
	result.AttemptCount = session.AttemptCount
	if step == nil {
		return rejectPuzzle(event, session, result, record, "unknown_step")
	}
	for _, required := range step.Requires {
		if !done[required] {
			return rejectPuzzle(event, session, result, record, "prerequisite_incomplete")
		}
	}
	if step.Target != "" && attempt.Target != step.Target {
		return rejectPuzzle(event, session, result, record, "target_incorrect")
	}
	switch step.Kind {
	case "joinery":
		if attempt.Rotation != step.Rotation {
			return rejectPuzzle(event, session, result, record, "rotation_incorrect")
		}
		if attempt.Answer != step.Answer {
			return rejectPuzzle(event, session, result, record, "piece_incorrect")
		}
	case "placement":
		if attempt.Answer != step.Answer || attempt.Position == nil || !ValidPlacement(event.Stage, *attempt.Position) {
			return rejectPuzzle(event, session, result, record, "placement_outside_shelter")
		}
	case "rubbing":
		if event.Stage.Rubbing == nil {
			return rejectPuzzle(event, session, result, record, "invalid_rubbing")
		}
		region, exists := RubbingRegion(event.Stage.Rubbing, step.Answer)
		if !exists {
			return rejectPuzzle(event, session, result, record, "invalid_rubbing_region")
		}
		if attempt.AssistMS > 0 {
			if attempt.AssistMS < 1500 || attempt.AssistMS > 60000 {
				return rejectPuzzle(event, session, result, record, "assist_incomplete")
			}
			result.Coverage = 1
		} else {
			result.Coverage = RubbingCoverage(event.Stage.Rubbing, region, attempt.Strokes)
		}
		if result.Coverage < event.Stage.Rubbing.Threshold {
			return rejectPuzzle(event, session, result, record, "rubbing_incomplete")
		}
	default:
		if normalize(attempt.Answer) != normalize(step.Answer) {
			return rejectPuzzle(event, session, result, record, "answer_incorrect")
		}
	}
	session.AcceptedSteps = append(session.AcceptedSteps, step.ID)
	session.PuzzleScore += step.Points
	result.Accepted, result.Correct = true, true
	result.ScoreDelta, result.PuzzleScore = step.Points, session.PuzzleScore
	result.Complete = len(session.AcceptedSteps) == len(event.Puzzle.Steps)
	result.Reason = "accepted"
	if result.Complete {
		result.Reason = "puzzle_complete"
	}
	record.Accepted, record.Reason = true, result.Reason
	result.ActionRecord = record
	return result
}

func ValidPlacement(stage *content.EchoStageSpec, p [2]float64) bool {
	if stage == nil || !unitPoint(p) || len(stage.DryArea) < 3 {
		return false
	}
	r := stage.BlockedArea
	if p[0] >= r[0] && p[0] <= r[0]+r[2] && p[1] >= r[1] && p[1] <= r[1]+r[3] {
		return false
	}
	inside := false
	for i, a := range stage.DryArea {
		b := stage.DryArea[(i+1)%len(stage.DryArea)]
		if pointSegmentDistanceSquared(p, a, b) < 1e-12 {
			return true
		}
		if (a[1] > p[1]) != (b[1] > p[1]) && p[0] < (b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0] {
			inside = !inside
		}
	}
	return inside
}

func RubbingRegion(spec *content.RubbingSpec, id string) (content.RubbingRegion, bool) {
	for _, region := range spec.Regions {
		if region.ID == id {
			return region, true
		}
	}
	return content.RubbingRegion{}, false
}

func PointInRubbing(region content.RubbingRegion, p [2]float64) bool {
	if region.Shape == "rect" {
		r := region.Rect
		return p[0] >= r[0] && p[0] <= r[0]+r[2] && p[1] >= r[1] && p[1] <= r[1]+r[3]
	}
	dx, dy := p[0]-region.Center[0], p[1]-region.Center[1]
	d := dx*dx + dy*dy
	return d <= region.Outer*region.Outer && (region.Shape != "ring" || d >= region.Inner*region.Inner)
}

func RubbingCoverage(spec *content.RubbingSpec, region content.RubbingRegion, strokes [][][2]float64) float64 {
	if spec == nil || spec.Resolution < 1 {
		return 0
	}
	for _, stroke := range strokes {
		for _, p := range stroke {
			if !unitPoint(p) {
				return 0
			}
		}
	}
	total, covered := 0, 0
	for y := 0; y < spec.Resolution; y++ {
		for x := 0; x < spec.Resolution; x++ {
			p := [2]float64{(float64(x) + .5) / float64(spec.Resolution), (float64(y) + .5) / float64(spec.Resolution)}
			if !PointInRubbing(region, p) {
				continue
			}
			total++
			hit := false
			for _, stroke := range strokes {
				for i, q := range stroke {
					if squared(p, q) <= spec.BrushRadius*spec.BrushRadius {
						hit = true
						break
					}
					// A cursor teleport is not a swept brush stroke.
					if i > 0 && squared(stroke[i-1], q) <= .12*.12 && pointSegmentDistanceSquared(p, stroke[i-1], q) <= spec.BrushRadius*spec.BrushRadius {
						hit = true
						break
					}
				}
				if hit {
					break
				}
			}
			if hit {
				covered++
			}
		}
	}
	if total == 0 {
		return 0
	}
	return float64(covered) / float64(total)
}

func unitPoint(p [2]float64) bool {
	return !math.IsNaN(p[0]) && !math.IsNaN(p[1]) && !math.IsInf(p[0], 0) && !math.IsInf(p[1], 0) && p[0] >= 0 && p[0] <= 1 && p[1] >= 0 && p[1] <= 1
}

func squared(a, b [2]float64) float64 { dx, dy := a[0]-b[0], a[1]-b[1]; return dx*dx + dy*dy }

func pointSegmentDistanceSquared(p, a, b [2]float64) float64 {
	dx, dy := b[0]-a[0], b[1]-a[1]
	length := dx*dx + dy*dy
	if length == 0 {
		return squared(p, a)
	}
	t := math.Max(0, math.Min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/length))
	return squared(p, [2]float64{a[0] + t*dx, a[1] + t*dy})
}
