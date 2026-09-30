package httpapi

import (
	"testing"
	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
)

func TestRetentionChangesScoreWithoutChangingRepair(t *testing.T) {
	event := &content.Event{Battle: &content.BattleSpec{Waves: 3}}
	session := &model.EventSession{PuzzleScore: 100, PuzzleTotal: 100, BattleWaves: 3, BattleWon: true}
	player := &model.Player{}
	for i := 0; i < 10; i++ {
		player.MemoryLedger = append(player.MemoryLedger, model.LedgerEntry{MemoryID: string(rune('a' + i)), Action: "kept"})
	}
	player.Memories = make([]model.Memory, 7)
	full := calculateResult(session, event, player)
	player.Memories = make([]model.Memory, 1)
	reduced := calculateResult(session, event, player)
	if full.QualityScore != 91 || full.Stars != 3 || reduced.QualityScore != 73 || reduced.Stars != 2 {
		t.Fatalf("retention not scored: %+v / %+v", full, reduced)
	}
	if full.RepairPercent != 100 || reduced.RepairPercent != 100 || full.MemoryRetentionPercent != 70 {
		t.Fatal("repair mixed with quality")
	}
	// No-battle tasks get the neutral full clear component; duplicate ledger entries do not dilute retention.
	event.Battle = nil
	player.MemoryLedger = append(player.MemoryLedger, player.MemoryLedger[0])
	result := calculateResult(session, event, player)
	if result.BattleClearPercent != 100 || result.MemoriesAcquired != 10 {
		t.Fatal("no-battle or duplicate acquisition regression")
	}
	player.Memories = nil
	player.MemoryLedger = nil
	if calculateResult(session, event, player).MemoryRetentionPercent != 0 {
		t.Fatal("empty retention is not zero")
	}
}
