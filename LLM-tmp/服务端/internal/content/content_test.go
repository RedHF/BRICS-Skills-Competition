package content

import (
	"path/filepath"
	"testing"
)

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
