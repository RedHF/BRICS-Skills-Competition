package store

import (
	"path/filepath"
	"testing"

	"yanxia-server/internal/model"
)

func TestStoreRoundTripsPlayerAndSession(t *testing.T) {
	path := filepath.Join(t.TempDir(), "save.json")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	player, created, err := s.EnsurePlayer("test")
	if err != nil || !created {
		t.Fatalf("create player: %+v %v", player, err)
	}
	if _, created, err = s.EnsurePlayer("test"); err != nil || created {
		t.Fatal("player creation is not idempotent")
	}
	session := model.EventSession{ID: "session", PlayerID: player.ID, ChapterID: "prologue", EventID: "bridge", Status: "active"}
	if err := s.CreateSession(session); err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.UpdateSessionAndPlayer(session.ID, player.ID, func(run *model.EventSession, p *model.Player) error {
		run.Status = "completed"
		p.InkMarks = 2
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	got, ok := s.GetPlayer(player.ID)
	if !ok || got.InkMarks != 2 {
		t.Fatalf("player did not persist: %+v", got)
	}
	reloaded, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if got, ok := reloaded.GetSession(session.ID); !ok || got.Status != "completed" {
		t.Fatalf("session did not round trip: %+v", got)
	}
}
