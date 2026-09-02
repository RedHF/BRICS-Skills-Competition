// Package content loads the data-driven chapter and event definitions used by
// the server.  Designers can add chapters by editing content/chapters.json;
// the HTTP and scoring code does not need to change.
package content

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
)

const CurrentVersion = 1

// Catalog is the complete, versioned game content manifest.
type Catalog struct {
	Version  int                `json:"version"`
	GameID   string             `json:"game_id"`
	Art      map[string]ArtSpec `json:"art,omitempty"`
	Chapters []Chapter          `json:"chapters"`
}

type ArtSpec struct {
	Background    string `json:"background,omitempty"`
	BackdropColor string `json:"backdrop_color,omitempty"`
}

type Chapter struct {
	ID          string  `json:"id"`
	Order       int     `json:"order"`
	Title       string  `json:"title"`
	Summary     string  `json:"summary"`
	UnlockCost  int     `json:"unlock_cost"`
	Events      []Event `json:"events"`
	NextChapter string  `json:"next_chapter,omitempty"`
}

type Event struct {
	ID         string      `json:"id"`
	Order      int         `json:"order"`
	Title      string      `json:"title"`
	Scene      string      `json:"scene"`
	Intro      string      `json:"intro"`
	Objectives []string    `json:"objectives"`
	Puzzle     PuzzleSpec  `json:"puzzle"`
	Battle     *BattleSpec `json:"battle,omitempty"`
	Reward     RewardSpec  `json:"reward"`
}

type PuzzleSpec struct {
	Type        string       `json:"type"`
	MaxAttempts int          `json:"max_attempts"`
	Steps       []PuzzleStep `json:"steps"`
}

type PuzzleStep struct {
	ID      string   `json:"id"`
	Kind    string   `json:"kind"`
	Prompt  string   `json:"prompt"`
	Options []string `json:"options,omitempty"`
	Answer  string   `json:"answer"`
	Points  int      `json:"points"`
}

type BattleSpec struct {
	Waves          int      `json:"waves"`
	EnemyHP        int      `json:"enemy_hp"`
	DurationSec    int      `json:"duration_sec"`
	MaxHitsTaken   int      `json:"max_hits_taken"`
	RequiredSkills []string `json:"required_skills,omitempty"`
}

type RewardSpec struct {
	Memory           MemorySpec `json:"memory"`
	BaseInkMarks     int        `json:"base_ink_marks"`
	UnlockChapter    string     `json:"unlock_chapter,omitempty"`
	CapacityIncrease int        `json:"capacity_increase,omitempty"`
}

type MemorySpec struct {
	ID       string   `json:"id"`
	Title    string   `json:"title"`
	Summary  string   `json:"summary"`
	Skill    string   `json:"skill"`
	Capacity int      `json:"capacity"`
	Choices  []string `json:"choices"`
}

// Load reads and validates a catalog from disk.
func Load(path string) (*Catalog, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read content %q: %w", path, err)
	}
	var catalog Catalog
	if err := json.Unmarshal(b, &catalog); err != nil {
		return nil, fmt.Errorf("decode content %q: %w", path, err)
	}
	if err := catalog.Validate(); err != nil {
		return nil, fmt.Errorf("invalid content %q: %w", path, err)
	}
	return &catalog, nil
}

// Validate catches authoring mistakes at startup instead of during a run.
func (c *Catalog) Validate() error {
	if c == nil {
		return errors.New("catalog is nil")
	}
	if c.Version <= 0 {
		return errors.New("version must be positive")
	}
	if c.GameID == "" {
		return errors.New("game_id is required")
	}
	if len(c.Chapters) == 0 {
		return errors.New("at least one chapter is required")
	}
	chapterIDs := make(map[string]struct{}, len(c.Chapters))
	for _, chapter := range c.Chapters {
		if chapter.ID == "" || chapter.Title == "" {
			return errors.New("chapter id and title are required")
		}
		if _, exists := chapterIDs[chapter.ID]; exists {
			return fmt.Errorf("duplicate chapter id %q", chapter.ID)
		}
		chapterIDs[chapter.ID] = struct{}{}
		if chapter.UnlockCost < 0 {
			return fmt.Errorf("chapter %q has negative unlock cost", chapter.ID)
		}
		eventIDs := make(map[string]struct{}, len(chapter.Events))
		for _, event := range chapter.Events {
			if event.ID == "" || event.Title == "" {
				return fmt.Errorf("chapter %q has event without id/title", chapter.ID)
			}
			if _, exists := eventIDs[event.ID]; exists {
				return fmt.Errorf("chapter %q has duplicate event id %q", chapter.ID, event.ID)
			}
			eventIDs[event.ID] = struct{}{}
			if len(event.Puzzle.Steps) == 0 {
				return fmt.Errorf("event %q has no puzzle steps", event.ID)
			}
			stepIDs := make(map[string]struct{}, len(event.Puzzle.Steps))
			for _, step := range event.Puzzle.Steps {
				if step.ID == "" || step.Answer == "" {
					return fmt.Errorf("event %q has puzzle step without id/answer", event.ID)
				}
				if _, exists := stepIDs[step.ID]; exists {
					return fmt.Errorf("event %q has duplicate puzzle step id %q", event.ID, step.ID)
				}
				stepIDs[step.ID] = struct{}{}
				if step.Points < 0 {
					return fmt.Errorf("event %q step %q has negative points", event.ID, step.ID)
				}
			}
			if event.Reward.Memory.ID == "" {
				return fmt.Errorf("event %q has no reward memory id", event.ID)
			}
			if event.Reward.Memory.Capacity <= 0 {
				return fmt.Errorf("event %q reward memory capacity must be positive", event.ID)
			}
			if len(event.Reward.Memory.Choices) == 0 {
				return fmt.Errorf("event %q reward memory has no choices", event.ID)
			}
			if event.Battle != nil {
				if event.Battle.Waves <= 0 || event.Battle.DurationSec <= 0 {
					return fmt.Errorf("event %q battle waves/duration must be positive", event.ID)
				}
				if event.Battle.MaxHitsTaken < 0 {
					return fmt.Errorf("event %q battle max_hits_taken cannot be negative", event.ID)
				}
			}
		}
	}
	for _, chapter := range c.Chapters {
		if chapter.NextChapter != "" {
			if _, exists := chapterIDs[chapter.NextChapter]; !exists {
				return fmt.Errorf("chapter %q points to missing next chapter %q", chapter.ID, chapter.NextChapter)
			}
		}
	}
	return nil
}

func (c *Catalog) Chapter(id string) (*Chapter, bool) {
	for i := range c.Chapters {
		if c.Chapters[i].ID == id {
			return &c.Chapters[i], true
		}
	}
	return nil, false
}

func (c *Catalog) Event(chapterID, eventID string) (*Event, bool) {
	chapter, ok := c.Chapter(chapterID)
	if !ok {
		return nil, false
	}
	for i := range chapter.Events {
		if chapter.Events[i].ID == eventID {
			return &chapter.Events[i], true
		}
	}
	return nil, false
}
