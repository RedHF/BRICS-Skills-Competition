package content

import (
	"encoding/json"
	"fmt"
)

const (
	OriginalEdition = "original"
	EchoEdition     = "echo-v1"
)

func (c *Catalog) EditionID() string {
	if c.Edition == "" {
		return OriginalEdition
	}
	return c.Edition
}

func (c *Catalog) IsEcho() bool { return c.EditionID() == EchoEdition }

func (c *Catalog) InitialCapacity() int {
	if c.IsEcho() {
		return 3
	}
	return 5
}

func (c *Catalog) CapacityLimit() int {
	if c.IsEcho() {
		return 5
	}
	return 7
}

// ForEdition creates an independent catalog so an echo run cannot mutate the
// original release definitions or change a historical save's rules.
func (c *Catalog) ForEdition(edition string) (*Catalog, error) {
	if edition == "" {
		edition = OriginalEdition
	}
	if edition != OriginalEdition && edition != EchoEdition {
		return nil, fmt.Errorf("unknown edition %q", edition)
	}
	if c.EditionID() != OriginalEdition && edition != c.EditionID() {
		return nil, fmt.Errorf("cannot derive %s from %s", edition, c.EditionID())
	}
	encoded, err := json.Marshal(c)
	if err != nil {
		return nil, err
	}
	var result Catalog
	if err := json.Unmarshal(encoded, &result); err != nil {
		return nil, err
	}
	result.Edition = edition
	if edition == EchoEdition {
		last := result.Memories["tower_epilogue"]
		last.Capacity, last.Epilogue = 0, true
		result.Memories[last.ID] = last
		for ci := range result.Chapters {
			chapter := &result.Chapters[ci]
			chapter.UnlockCost = 0
			for ei := range chapter.Events {
				event := &chapter.Events[ei]
				event.Puzzle.Practice = true
				for si := range event.Puzzle.Steps {
					if event.Puzzle.Steps[si].ID == "opera_role" {
						event.Puzzle.Steps[si].Prompt = "比对旧戏单的衣袖轮廓，找出能接续纹样的一片。"
					}
				}
				event.Puzzle.MaxAttempts = 0
				event.Reward.Choices = []string{"keep", "replace", "archive"}
				event.Reward.CapacityIncrease = 0
				if event.Battle != nil {
					event.Battle.RequiredSkills = nil
					event.Battle.DurationSec = 90
					event.Battle.MaxHitsTaken = 12
				}
				if event.ID == "temple_drum" || event.ID == "archway_craftsman" {
					event.Reward.CapacityIncrease = 1
				}
				if chapter.ID == "temple" {
					event.Battle = nil
					configureTempleStage(event)
				}
				if event.ID == "temple_drum" {
					event.Story.Outro = "鼓仍能被后来的人敲响。你记下本次取舍，心舍多展开一格。远处的戏楼以一声锣响回应。"
				}
				if event.ID == "tower_ledger" {
					event.Reward.Choices = []string{"keep"}
				}
			}
		}
		art := result.Art["temple_incense"]
		art.Background = "res://assets/echo_v1/temple_hall_master.png"
		art.BackdropColor = "#302c28"
		result.Art["temple_incense"] = art
	}
	if err := result.Validate(); err != nil {
		return nil, err
	}
	return &result, nil
}
