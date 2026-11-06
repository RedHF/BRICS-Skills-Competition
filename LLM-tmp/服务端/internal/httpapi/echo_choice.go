package httpapi

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"yanxia-server/internal/model"
)

func learnSkill(player *model.Player, skill string) {
	if skill == "" {
		return
	}
	for _, learned := range player.LearnedSkills {
		if learned == skill {
			return
		}
	}
	player.LearnedSkills = append(player.LearnedSkills, skill)
}

// Sounding the real drum is a saved action after the irreversible choice.
// The acoustic object always remains; the private echo follows living memory.
func (s *Server) handleEchoResponse(w http.ResponseWriter, r *http.Request, sessionID string) {
	if !s.catalog.IsEcho() {
		writeError(w, http.StatusNotFound, "not_found", "response is part of the echo edition")
		return
	}
	var request struct{}
	if !decodeJSON(w, r, &request) {
		return
	}
	session, _ := s.store.GetSession(sessionID)
	if session.EventID != "temple_drum" {
		writeError(w, http.StatusBadRequest, "invalid_response", "this scene has no drum response")
		return
	}
	event, _ := s.catalog.Event(session.ChapterID, session.EventID)
	updated, player, err := s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
		if !current.ChoiceDone || current.Status == "failed" || len(current.AcceptedSteps) != len(event.Puzzle.Steps) {
			return &choiceValidationError{reason: "complete repair and choice before sounding the drum"}
		}
		current.WorldResponse = true
		return nil
	})
	if err != nil {
		var validation *choiceValidationError
		if errors.As(err, &validation) {
			writeError(w, http.StatusConflict, "response_unavailable", validation.reason)
		} else {
			writeError(w, http.StatusInternalServerError, "store_error", err.Error())
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"accepted": updated.WorldResponse, "drum_sounds": true, "child_echo": containsMemory(player.Memories, "she_hui_chun")})
}

// All memory edits, the immutable record and the session choice share one
// store commit. A lost HTTP response cannot archive twice or grant it again.
func (s *Server) handleEchoChoice(w http.ResponseWriter, sessionID string, request choiceRequest) {
	session, ok := s.store.GetSession(sessionID)
	if !ok {
		writeError(w, http.StatusNotFound, "session_not_found", "session not found")
		return
	}
	if session.PlayerID != s.playerID || (request.PlayerID != "" && request.PlayerID != s.playerID) {
		writeError(w, http.StatusForbidden, "session_owner_mismatch", "session belongs to another player")
		return
	}
	event, ok := s.catalog.Event(session.ChapterID, session.EventID)
	if !ok {
		writeError(w, http.StatusInternalServerError, "content_error", "missing event")
		return
	}
	action := strings.ToLower(strings.TrimSpace(request.Action))
	if action == "forget" {
		action = "replace"
	}
	forgetID := strings.TrimSpace(request.ForgetMemoryID)
	updated, player, err := s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
		if current.ChoiceDone {
			return nil
		}
		if current.Status == "failed" {
			return &choiceValidationError{reason: "session_failed"}
		}
		if len(current.AcceptedSteps) != len(event.Puzzle.Steps) {
			return &choiceValidationError{reason: "puzzle_incomplete"}
		}
		// Revisit is a replay of the recorded journey, never a new acquisition.
		if previous, completed := player.CompletedEvents[eventKey(current.ChapterID, current.EventID)]; completed {
			current.ChoiceDone = true
			current.ChoiceAction = previous.MemoryAction
			current.ForgottenMemory = previous.ArchivedMemoryID
			return nil
		}
		if action != "keep" && action != "archive" && action != "replace" {
			return &choiceValidationError{reason: "choose keep, archive or replace"}
		}
		pending := current.PendingMemory
		if pending == nil {
			return errors.New("pending memory missing")
		}
		if containsMemory(player.RecordedMemories, pending.ID) {
			return &choiceValidationError{reason: "memory already recorded"}
		}
		if event.Reward.Memory.Epilogue {
			if action != "keep" || forgetID != "" {
				return &choiceValidationError{reason: "the final page does not replace a memory"}
			}
		} else if action == "replace" {
			if forgetID == "" || forgetID == pending.ID || !containsMemory(player.Memories, forgetID) {
				return &choiceValidationError{reason: "select a currently living echo to archive"}
			}
		} else if forgetID != "" {
			return &choiceValidationError{reason: "only replace may archive an old echo"}
		}
		available := player.Capacity - usedCapacity(*player)
		if action == "replace" {
			for _, memory := range player.Memories {
				if memory.ID == forgetID {
					available += memory.Capacity
				}
			}
		}
		if !event.Reward.Memory.Epilogue && action != "archive" && pending.Capacity > available {
			return &choiceValidationError{reason: "heart room full; archive this new echo or select an old one"}
		}
		now := time.Now().UTC()
		memory := *pending
		memory.AddedAt = now
		player.RecordedMemories = append(player.RecordedMemories, memory)
		appendLedger := func(m model.Memory, kind string) {
			player.MemoryLedger = append(player.MemoryLedger, model.LedgerEntry{MemoryID: m.ID, Title: m.Title, Action: kind, ChapterID: current.ChapterID, EventID: current.EventID, OccurredAt: now})
		}
		current.ForgottenMemory = ""
		if event.Reward.Memory.Epilogue {
			appendLedger(memory, "epilogue")
		} else if action == "archive" {
			current.ForgottenMemory = memory.ID
			appendLedger(memory, "archived")
		} else {
			if action == "replace" {
				old, found := removeMemory(player, forgetID)
				if !found {
					return errors.New("selected echo no longer present")
				}
				appendLedger(old, "archived")
				current.ForgottenMemory = old.ID
			}
			player.Memories = append(player.Memories, memory)
			appendLedger(memory, "kept")
		}
		current.ChoiceDone = true
		current.ChoiceAction = action
		return nil
	})
	if err != nil {
		var validation *choiceValidationError
		if errors.As(err, &validation) {
			writeError(w, http.StatusBadRequest, "invalid_choice", validation.reason)
		} else {
			writeError(w, http.StatusInternalServerError, "store_error", err.Error())
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"accepted": updated.ChoiceDone, "action": updated.ChoiceAction, "forgotten_memory_id": updated.ForgottenMemory,
		"player": playerPayload(player), "memory": publicMemoryFromModel(updated.PendingMemory),
		"capacity": player.Capacity, "used_capacity": usedCapacity(player), "status": updated.Status,
	})
}
