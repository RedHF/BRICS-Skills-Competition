// Package rules contains server-authoritative puzzle, battle, and settlement
// calculations.  It has no HTTP or persistence dependencies, which keeps the
// rules easy to test and allows future clients to share the protocol.
package rules

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
)

const (
	PuzzleFailureErosion = 10
	BattleFailureErosion = 15
	HitErosion           = 5
)

type PuzzleAttempt struct {
	StepID  string
	Answer  string
	Action  string
	Strokes [][][2]float64
}

type PuzzleEvaluation struct {
	FailedStrokes []int
	Accepted      bool
	Correct       bool
	Complete      bool
	ScoreDelta    int
	PuzzleScore   int
	PuzzleTotal   int
	ErosionDelta  int
	AttemptCount  int
	NextStepID    string
	Reason        string
	ActionRecord  model.ActionRecord
}

// EvaluatePuzzleStep validates exactly one next puzzle step.  Sequence is
// checked against the content catalog, so a client cannot submit a later step
// or claim a score without solving earlier steps.
func EvaluatePuzzleStep(event *content.Event, session *model.EventSession, attempt PuzzleAttempt) PuzzleEvaluation {
	result := PuzzleEvaluation{PuzzleTotal: puzzleTotal(event)}
	now := time.Now().UTC()
	record := model.ActionRecord{StepID: attempt.StepID, Action: attempt.Action, AnswerHash: hashAnswer(attempt.Answer), OccurredAt: now}
	if event == nil || session == nil {
		result.Reason = "invalid_session"
		record.Reason = result.Reason
		result.ActionRecord = record
		return result
	}
	result.PuzzleScore = session.PuzzleScore
	result.AttemptCount = session.AttemptCount
	if session.Status == "completed" {
		result.Accepted = true
		result.Correct = true
		result.Complete = true
		result.Reason = "already_completed"
		result.ActionRecord.Accepted = true
		result.ActionRecord.Reason = result.Reason
		return result
	}
	if session.Status == "failed" {
		result.Reason = "session_failed"
		record.Reason = result.Reason
		result.ActionRecord = record
		return result
	}
	if len(session.AcceptedSteps) >= len(event.Puzzle.Steps) {
		result.Accepted = true
		result.Correct = true
		result.Complete = true
		result.Reason = "puzzle_complete"
		result.ActionRecord.Accepted = true
		result.ActionRecord.Reason = result.Reason
		return result
	}

	// A replay of an accepted request is idempotent.  This matters when a
	// mobile client retries after a network timeout.
	for _, acceptedID := range session.AcceptedSteps {
		if acceptedID == attempt.StepID {
			result.Accepted = true
			result.Correct = true
			result.Complete = len(session.AcceptedSteps) == len(event.Puzzle.Steps)
			result.Reason = "step_already_accepted"
			result.ActionRecord.Accepted = true
			result.ActionRecord.Reason = result.Reason
			result.NextStepID = nextStepID(event, len(session.AcceptedSteps))
			return result
		}
	}

	expected := event.Puzzle.Steps[len(session.AcceptedSteps)]
	if expected.Kind == "trace" {
		record.Action = "trace"
		record.AnswerHash = hashAnswer(fmt.Sprint(attempt.Strokes))
	}
	session.AttemptCount++
	result.AttemptCount = session.AttemptCount
	if attempt.StepID != expected.ID {
		return rejectPuzzle(event, session, result, record, "step_out_of_order")
	}
	if expected.Kind == "trace" {
		result.FailedStrokes = FailedTraceStrokes(expected.Trace, attempt.Strokes)
	}
	if expected.Kind == "trace" && len(result.FailedStrokes) > 0 {
		result.Reason = "trace_incomplete"
		record.Reason = result.Reason
		result.ActionRecord = record
		return result
	}
	if expected.Kind != "trace" && normalize(attempt.Answer) != normalize(expected.Answer) {
		return rejectPuzzle(event, session, result, record, "answer_incorrect")
	}

	result.Accepted = true
	result.Correct = true
	result.ScoreDelta = expected.Points
	result.PuzzleScore = session.PuzzleScore + expected.Points
	result.PuzzleTotal = puzzleTotal(event)
	session.PuzzleScore = result.PuzzleScore
	session.AcceptedSteps = append(session.AcceptedSteps, expected.ID)
	record.Accepted = true
	record.Reason = "accepted"
	result.ActionRecord = record
	result.Complete = len(session.AcceptedSteps) == len(event.Puzzle.Steps)
	result.NextStepID = nextStepID(event, len(session.AcceptedSteps))
	if result.Complete {
		result.Reason = "puzzle_complete"
	} else {
		result.Reason = "accepted"
	}
	return result
}

func rejectPuzzle(event *content.Event, session *model.EventSession, result PuzzleEvaluation, record model.ActionRecord, reason string) PuzzleEvaluation {
	session.InvalidAttempts++
	result.ErosionDelta = PuzzleFailureErosion
	result.Reason = reason
	record.Reason = reason
	if event.Puzzle.MaxAttempts > 0 && session.InvalidAttempts >= event.Puzzle.MaxAttempts {
		session.Status = "failed"
		session.FailureReason = "puzzle_attempt_limit"
		result.Reason = session.FailureReason
		record.Reason = result.Reason
	}
	result.ActionRecord = record
	return result
}

type BattleAction struct {
	Skill string
	AtMS  int
}

type BattleInput struct {
	Skills       map[string]content.SkillSpec
	Actions      []BattleAction
	DurationMS   int
	WavesCleared int
	HitsTaken    int
	// AllowedSkills is supplied by the server after resolving the player's
	// owned memories and the event's pending reward. Keeping it in the input
	// makes the pure rules package reusable while preserving ownership checks.
	AllowedSkills map[string]bool
}

type BattleEvaluation struct {
	Won          bool
	ErosionDelta int
	Waves        int
	HitsTaken    int
	Reason       string
}

func EvaluateBattle(event *content.Event, input BattleInput) (BattleEvaluation, error) {
	if event == nil || event.Battle == nil {
		return BattleEvaluation{Won: true, Reason: "no_battle"}, nil
	}
	battle := event.Battle
	if input.DurationMS <= 0 || input.DurationMS > battle.DurationSec*1000 {
		return BattleEvaluation{}, errors.New("duration_ms outside event bounds")
	}
	hp, waves, hits, shield, nextAttack := battle.EnemyHP, 0, 0, 0, 3000
	ready := map[string]int{}
	seen := map[string]bool{}
	lastAt := -1
	for _, action := range input.Actions {
		skill, ok := input.Skills[action.Skill]
		if !ok || !input.AllowedSkills[action.Skill] {
			return BattleEvaluation{}, fmt.Errorf("unavailable skill %q", action.Skill)
		}
		if action.AtMS < lastAt || action.AtMS < 0 || action.AtMS > input.DurationMS {
			return BattleEvaluation{}, errors.New("battle action timestamp outside chronological timeline")
		}
		if waves == battle.Waves || hits > battle.MaxHitsTaken {
			return BattleEvaluation{}, errors.New("action after battle ended")
		}
		if action.AtMS < ready[action.Skill] {
			return BattleEvaluation{}, errors.New("skill used during cooldown")
		}
		for nextAttack <= action.AtMS && hits <= battle.MaxHitsTaken {
			if shield > 0 {
				shield--
			} else {
				hits++
			}
			nextAttack += 3000
		}
		if hits > battle.MaxHitsTaken {
			return BattleEvaluation{}, errors.New("action after player defeat")
		}
		ready[action.Skill] = action.AtMS + skill.CooldownMS
		lastAt = action.AtMS
		seen[action.Skill] = true
		hp -= skill.Damage
		if skill.Shield > 0 {
			shield = skill.Shield
		}
		hits = max(0, hits-skill.Heal)
		if hp <= 0 {
			waves++
			hp = battle.EnemyHP
		}
	}
	for nextAttack <= input.DurationMS && waves < battle.Waves && hits <= battle.MaxHitsTaken {
		if shield > 0 {
			shield--
		} else {
			hits++
		}
		nextAttack += 3000
	}
	won := waves == battle.Waves && hits <= battle.MaxHitsTaken
	for _, required := range battle.RequiredSkills {
		won = won && seen[required]
	}
	eval := BattleEvaluation{Won: won, Waves: waves, HitsTaken: hits, ErosionDelta: hits * HitErosion, Reason: "battle_cleared"}
	if !won {
		eval.ErosionDelta += BattleFailureErosion
		eval.Reason = "battle_requirements_not_met"
	}
	return eval, nil
}

func puzzleTotal(event *content.Event) int {
	if event == nil {
		return 0
	}
	total := 0
	for _, step := range event.Puzzle.Steps {
		total += step.Points
	}
	return total
}

func nextStepID(event *content.Event, index int) string {
	if event == nil || index < 0 || index >= len(event.Puzzle.Steps) {
		return ""
	}
	return event.Puzzle.Steps[index].ID
}

func normalize(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func hashAnswer(answer string) string {
	digest := sha256.Sum256([]byte(answer))
	return hex.EncodeToString(digest[:])
}
