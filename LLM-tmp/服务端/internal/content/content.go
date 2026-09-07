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

const CurrentVersion = 6

// Catalog is the complete, versioned game content manifest.
type SkillSpec struct {
	Description string `json:"description"`
	CooldownMS  int    `json:"cooldown_ms"`
	Damage      int    `json:"damage"`
	Shield      int    `json:"shield"`
	Heal        int    `json:"heal"`
	Color       string `json:"color"`
}

type Catalog struct {
	Skills   map[string]SkillSpec  `json:"skills"`
	Memories map[string]MemorySpec `json:"memories"`
	Version  int                   `json:"version"`
	GameID   string                `json:"game_id"`
	Art      map[string]ArtSpec    `json:"art,omitempty"`
	Chapters []Chapter             `json:"chapters"`
}

type ArtSpec struct {
	WhisperAudio  string `json:"whisper_audio,omitempty"`
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

type StorySpec struct {
	Beats        []string `json:"beats"`
	Outro        string   `json:"outro"`
	ChapterOutro string   `json:"chapter_outro,omitempty"`
}

type Event struct {
	Story      StorySpec   `json:"story"`
	Draft      bool        `json:"draft"`
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

type TraceSpec struct {
	AspectRatio float64        `json:"aspect_ratio"`
	Strokes     [][][2]float64 `json:"strokes"`
	Tolerance   float64        `json:"tolerance"`
}

type PuzzleStep struct {
	Trace   *TraceSpec `json:"trace,omitempty"`
	ID      string     `json:"id"`
	Kind    string     `json:"kind"`
	Prompt  string     `json:"prompt"`
	Options []string   `json:"options,omitempty"`
	Answer  string     `json:"answer,omitempty"`
	Points  int        `json:"points"`
}

type BattleSpec struct {
	Waves          int      `json:"waves"`
	EnemyHP        int      `json:"enemy_hp"`
	DurationSec    int      `json:"duration_sec"`
	MaxHitsTaken   int      `json:"max_hits_taken"`
	RequiredSkills []string `json:"required_skills,omitempty"`
}

type RewardSpec struct {
	MemoryID         string     `json:"memory_id"`
	Choices          []string   `json:"choices"`
	Memory           MemorySpec `json:"-"`
	UnlockChapter    string     `json:"unlock_chapter,omitempty"`
	CapacityIncrease int        `json:"capacity_increase,omitempty"`
}

type MemorySpec struct {
	EchoAudio      string  `json:"echo_audio"`
	Source         string  `json:"source"`
	RememberedText string  `json:"remembered_text"`
	ForgottenText  string  `json:"forgotten_text"`
	Color          string  `json:"color"`
	ToneHz         float64 `json:"tone_hz"`
	ID             string  `json:"id"`
	Title          string  `json:"title"`
	Summary        string  `json:"summary"`
	Skill          string  `json:"skill"`
	Capacity       int     `json:"capacity"`
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
	if c.Version != CurrentVersion {
		return fmt.Errorf("content version must be %d", CurrentVersion)
	}
	if c.GameID == "" {
		return errors.New("game_id is required")
	}
	if len(c.Chapters) == 0 {
		return errors.New("at least one chapter is required")
	}
	if _, ok := c.Skills["挥墨"]; !ok {
		return errors.New("basic attack skill 挥墨 is required")
	}
	for name, skill := range c.Skills {
		if name == "" || skill.Description == "" || skill.CooldownMS <= 0 || skill.Damage < 0 || skill.Shield < 0 || skill.Heal < 0 {
			return fmt.Errorf("invalid skill %q", name)
		}
	}
	for ci := range c.Chapters {
		for ei := range c.Chapters[ci].Events {
			event := &c.Chapters[ci].Events[ei]
			if !event.Draft {
				art, ok := c.Art[event.ID]
				if !ok || art.BackdropColor == "" || art.WhisperAudio == "" {
					return fmt.Errorf("playable event %q missing backdrop or whisper audio", event.ID)
				}
			}
			memory, ok := c.Memories[event.Reward.MemoryID]
			if !ok {
				return fmt.Errorf("event %q references missing memory %q", event.ID, event.Reward.MemoryID)
			}
			if memory.ID != event.Reward.MemoryID || memory.Source != c.Chapters[ci].ID+"/"+event.ID {
				return fmt.Errorf("memory %q source does not match event", memory.ID)
			}
			if memory.Title == "" || memory.Summary == "" || memory.RememberedText == "" || memory.ForgottenText == "" {
				return fmt.Errorf("memory %q missing narrative text", memory.ID)
			}
			if len(event.Story.Beats) == 0 || event.Story.Outro == "" {
				return fmt.Errorf("event %q missing story", event.ID)
			}
			if _, ok := c.Skills[memory.Skill]; memory.Skill != "" && !ok {
				return fmt.Errorf("memory %q references missing skill %q", memory.ID, memory.Skill)
			}
			if memory.EchoAudio == "" {
				return fmt.Errorf("memory %q missing echo audio", memory.ID)
			}
			event.Reward.Memory = memory
		}
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
				if step.ID == "" || (step.Kind != "trace" && step.Answer == "") {
					return fmt.Errorf("event %q has puzzle step without id/answer", event.ID)
				}
				if _, exists := stepIDs[step.ID]; exists {
					return fmt.Errorf("event %q has duplicate puzzle step id %q", event.ID, step.ID)
				}
				stepIDs[step.ID] = struct{}{}
				if step.Kind == "trace" {
					if step.Trace == nil || len(step.Trace.Strokes) == 0 || step.Trace.Tolerance <= 0 || step.Trace.Tolerance > .2 || step.Trace.AspectRatio <= 0 {
						return fmt.Errorf("step %q has invalid trace specification", step.ID)
					}
					for _, stroke := range step.Trace.Strokes {
						if len(stroke) < 2 {
							return fmt.Errorf("step %q has empty stroke", step.ID)
						}
						for i, p := range stroke {
							if p[0] < 0 || p[0] > 1 || p[1] < 0 || p[1] > 1 {
								return fmt.Errorf("step %q trace outside canvas", step.ID)
							}
							if i > 0 && p == stroke[i-1] {
								return fmt.Errorf("step %q duplicate trace vertex", step.ID)
							}
						}
					}
				}
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
			if len(event.Reward.Choices) == 0 {
				return fmt.Errorf("event %q reward memory has no choices", event.ID)
			}
			if event.Battle != nil {
				for _, skill := range event.Battle.RequiredSkills {
					if _, ok := c.Skills[skill]; !ok {
						return fmt.Errorf("event %q references missing battle skill %q", event.ID, skill)
					}
				}
				if event.Battle.Waves <= 0 || event.Battle.DurationSec <= 0 || event.Battle.EnemyHP <= 0 {
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
