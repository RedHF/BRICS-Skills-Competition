package content

import (
	"path/filepath"
	"testing"
)

func TestMemoryReferencesAndStoryFailAtLoadBoundary(t *testing.T) {
	for _, which := range []string{"missing_memory", "wrong_source", "missing_story", "bad_trace"} {
		t.Run(which, func(t *testing.T) {
			c, err := Load(filepath.Join("..", "..", "content", "chapters.json"))
			if err != nil {
				t.Fatal(err)
			}
			event := &c.Chapters[0].Events[0]
			switch which {
			case "missing_memory":
				event.Reward.MemoryID = "missing"
			case "wrong_source":
				m := c.Memories[event.Reward.MemoryID]
				m.Source = "temple/wrong"
				c.Memories[m.ID] = m
			case "missing_story":
				event.Story.Beats = nil
			case "bad_trace":
				event.Puzzle.Steps[0].Trace.Strokes[0][0][0] = 2
			}
			if err := c.Validate(); err == nil {
				t.Fatal("broken content accepted")
			}
		})
	}
}

func TestCatalogValidatesAndHidesNoAuthoringErrors(t *testing.T) {
	path := filepath.Join("..", "..", "content", "chapters.json")
	catalog, err := Load(path)
	if err != nil {
		t.Fatalf("load catalog: %v", err)
	}
	if catalog.GameID != "yanxia-qianqiu" || len(catalog.Chapters) < 4 {
		t.Fatalf("unexpected catalog: %+v", catalog)
	}
	if _, ok := catalog.Event("temple", "temple_drum"); !ok {
		t.Fatal("expected temple drum event")
	}
	if catalog.Art["prologue_bridge"].BackdropColor == "" {
		t.Fatal("expected data-driven art configuration")
	}
}
