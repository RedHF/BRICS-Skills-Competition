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
	StepID string
	Answer string
	Action string
}

type PuzzleEvaluation struct {
	Accepted     bool
	Correct      bool
	Complete     bool
	ScoreDelta   int
	PuzzleScore  int
	PuzzleTotal  int
	ErosionDelta int
	AttemptCount int
	NextStepID   string
	Reason       string
	ActionRecord model.ActionRecord
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
	session.AttemptCount++
	result.AttemptCount = session.AttemptCount
	if attempt.StepID != expected.ID {
		return rejectPuzzle(event, session, result, record, "step_out_of_order")
	}
	if normalize(attempt.Answer) != normalize(expected.Answer) {
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
	if event.Puzzle.MaxAttempts > 0 && session.AttemptCount >= event.Puzzle.MaxAttempts {
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
	if input.DurationMS <= 0 {
		return BattleEvaluation{}, errors.New("duration_ms must be positive")
	}
	if input.DurationMS > battle.DurationSec*1000 {
		return BattleEvaluation{}, fmt.Errorf("duration_ms exceeds event limit (%d ms)", battle.DurationSec*1000)
	}
	if input.WavesCleared < 0 || input.WavesCleared > battle.Waves {
		return BattleEvaluation{}, errors.New("waves_cleared is outside event bounds")
	}
	if input.HitsTaken < 0 || input.HitsTaken > battle.MaxHitsTaken+10 {
		return BattleEvaluation{}, errors.New("hits_taken is outside event bounds")
	}
	seenSkills := make(map[string]bool)
	lastAt := -1
	for _, action := range input.Actions {
		action.Skill = strings.TrimSpace(action.Skill)
		if action.Skill == "" {
			return BattleEvaluation{}, errors.New("battle action skill is required")
		}
		// A nil map means the pure rules caller did not provide ownership
		// context. The HTTP layer always passes a non-nil map resolved from the
		// player's memories, so unowned skills are rejected in live play.
		if input.AllowedSkills != nil && !input.AllowedSkills[action.Skill] {
			return BattleEvaluation{}, fmt.Errorf("unknown or unavailable battle skill %q", action.Skill)
		}
		if action.AtMS < 0 || action.AtMS > input.DurationMS {
			return BattleEvaluation{}, errors.New("battle action timestamp outside duration")
		}
		if action.AtMS < lastAt {
			return BattleEvaluation{}, errors.New("battle actions must be chronological")
		}
		lastAt = action.AtMS
		seenSkills[action.Skill] = true
	}
	// The client may omit optional counters for compatibility.  In that case
	// derive a conservative wave count from the number of timestamped actions;
	// it can never exceed the server-defined wave count.
	waves := input.WavesCleared
	if waves == 0 && len(input.Actions) > 0 {
		waves = len(input.Actions)
		if waves > battle.Waves {
			waves = battle.Waves
		}
	}
	if input.HitsTaken > 0 {
		// Hits are client telemetry, but still bounded and always penalize the
		// result.  A forged lower value cannot create a score above the no-hit
		// baseline.
	}
	missingSkill := ""
	for _, required := range battle.RequiredSkills {
		if !seenSkills[required] {
			missingSkill = required
			break
		}
	}
	minDuration := battle.Waves * 1000
	won := waves == battle.Waves && missingSkill == "" && len(input.Actions) >= battle.Waves && input.DurationMS >= minDuration && input.HitsTaken <= battle.MaxHitsTaken
	eval := BattleEvaluation{Won: won, Waves: waves, HitsTaken: input.HitsTaken}
	if !won {
		eval.ErosionDelta = BattleFailureErosion
		eval.Reason = "battle_requirements_not_met"
	} else {
		eval.Reason = "battle_cleared"
	}
	if input.HitsTaken > 0 {
		eval.ErosionDelta += input.HitsTaken * HitErosion
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
