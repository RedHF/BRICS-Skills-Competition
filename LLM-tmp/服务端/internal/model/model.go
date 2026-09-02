package model

import "time"

// Player is the server-owned progression record.  Clients never submit a
// replacement Player object; handlers mutate this record through Store.
type Player struct {
	ID               string                 `json:"id"`
	DisplayName      string                 `json:"display_name,omitempty"`
	CreatedAt        time.Time              `json:"created_at"`
	UpdatedAt        time.Time              `json:"updated_at"`
	InkMarks         int                    `json:"ink_marks"`
	Capacity         int                    `json:"capacity"`
	Erosion          int                    `json:"erosion"`
	UnlockedChapters []string               `json:"unlocked_chapters"`
	CompletedEvents  map[string]EventResult `json:"completed_events"`
	Memories         []Memory               `json:"memories"`
	MemoryLedger     []LedgerEntry          `json:"memory_ledger"`
	LastSequence     uint64                 `json:"last_sequence"`
}

type Memory struct {
	ID       string    `json:"id"`
	Title    string    `json:"title"`
	Summary  string    `json:"summary"`
	Skill    string    `json:"skill"`
	Capacity int       `json:"capacity"`
	Source   string    `json:"source"`
	AddedAt  time.Time `json:"added_at"`
}

type LedgerEntry struct {
	MemoryID   string    `json:"memory_id"`
	Title      string    `json:"title"`
	Action     string    `json:"action"` // kept, forgotten, or restored
	ChapterID  string    `json:"chapter_id"`
	EventID    string    `json:"event_id"`
	OccurredAt time.Time `json:"occurred_at"`
}

type EventResult struct {
	ChapterID      string    `json:"chapter_id"`
	EventID        string    `json:"event_id"`
	Stars          int       `json:"stars"`
	PuzzleScore    int       `json:"puzzle_score"`
	PuzzleTotal    int       `json:"puzzle_total"`
	BattleWon      bool      `json:"battle_won"`
	RepairPercent  int       `json:"repair_percent"`
	ErosionAtEnd   int       `json:"erosion_at_end"`
	InkMarksEarned int       `json:"ink_marks_earned"`
	CompletedAt    time.Time `json:"completed_at"`
	Sequence       uint64    `json:"sequence"`
}

// EventSession is persisted server state for one event attempt.  Answers are
// looked up from the content catalog at verification time and are never sent
// to the client.
type EventSession struct {
	ID              string         `json:"id"`
	PlayerID        string         `json:"player_id"`
	ChapterID       string         `json:"chapter_id"`
	EventID         string         `json:"event_id"`
	StartedAt       time.Time      `json:"started_at"`
	ExpiresAt       time.Time      `json:"expires_at"`
	LastSeenAt      time.Time      `json:"last_seen_at"`
	Status          string         `json:"status"` // active, awaiting_choice, completed, failed
	AttemptCount    int            `json:"attempt_count"`
	InvalidAttempts int            `json:"invalid_attempts"`
	PuzzleScore     int            `json:"puzzle_score"`
	PuzzleTotal     int            `json:"puzzle_total"`
	AcceptedSteps   []string       `json:"accepted_steps"`
	Actions         []ActionRecord `json:"actions"`
	BattleWon       bool           `json:"battle_won"`
	BattleChecked   bool           `json:"battle_checked"`
	BattleWaves     int            `json:"battle_waves"`
	BattleHits      int            `json:"battle_hits"`
	RepairPercent   int            `json:"repair_percent"`
	ChoiceDone      bool           `json:"choice_done"`
	ChoiceAction    string         `json:"choice_action,omitempty"`
	ForgottenMemory string         `json:"forgotten_memory,omitempty"`
	RewardApplied   bool           `json:"reward_applied"`
	PendingMemory   *Memory        `json:"pending_memory,omitempty"`
	PendingResult   *EventResult   `json:"pending_result,omitempty"`
	FailureReason   string         `json:"failure_reason,omitempty"`
}

type ActionRecord struct {
	StepID     string    `json:"step_id"`
	Action     string    `json:"action"`
	AnswerHash string    `json:"answer_hash,omitempty"`
	Accepted   bool      `json:"accepted"`
	Reason     string    `json:"reason,omitempty"`
	OccurredAt time.Time `json:"occurred_at"`
}
