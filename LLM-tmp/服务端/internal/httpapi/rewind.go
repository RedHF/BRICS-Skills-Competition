package httpapi

import (
	"errors"
	"net/http"
	"time"

	"yanxia-server/internal/model"
)

// The retry number makes a retried network request safe even if its first
// response was lost. Checkpoint restoration and payment are one JSON commit.
func (s *Server) handleRewind(w http.ResponseWriter, r *http.Request, sessionID string) {
	var request struct {
		Retries *int `json:"retries"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	if request.Retries == nil || *request.Retries < 0 {
		writeError(w, http.StatusBadRequest, "invalid_retry", "retries is required")
		return
	}
	session, _ := s.store.GetSession(sessionID)
	var invalid = errors.New("invalid_retry")
	var insufficient = errors.New("insufficient_ink")
	updated, player, err := s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
		if current.Retries == *request.Retries+1 {
			return nil
		}
		if current.Status != "failed" || current.Retries != *request.Retries {
			return invalid
		}
		if player.InkMarks == 0 && current.ChapterID != "prologue" {
			return insufficient
		}
		if player.InkMarks > 0 {
			player.InkMarks--
		}
		player.Erosion = current.StartErosion
		event, _ := s.catalog.Event(current.ChapterID, current.EventID)
		// Keep the already-committed choice, so retained rewards cannot force a
		// second capacity choice or create a duplicate ledger entry on retry.
		*current = model.EventSession{
			ID: current.ID, PlayerID: current.PlayerID, ChapterID: current.ChapterID, EventID: current.EventID,
			StartedAt: current.StartedAt, LastSeenAt: time.Now().UTC(), StartErosion: current.StartErosion,
			Retries: current.Retries + 1, Status: "active", PuzzleTotal: puzzleTotal(event),
			AcceptedSteps: []string{}, Actions: []model.ActionRecord{}, PendingMemory: memoryFromEvent(event),
			ChoiceDone: current.ChoiceDone, ChoiceAction: current.ChoiceAction, ForgottenMemory: current.ForgottenMemory,
		}
		return nil
	})
	if err != nil {
		if errors.Is(err, insufficient) {
			writeError(w, http.StatusConflict, "insufficient_ink", "回溯需要 1 墨痕；仅序章可在墨痕不足时免费重试")
		} else if errors.Is(err, invalid) {
			writeError(w, http.StatusConflict, "invalid_retry", "事件状态已变化，请刷新后重试")
		} else {
			writeError(w, http.StatusInternalServerError, "store_error", err.Error())
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"session": updated, "player": playerPayload(player)})
}
