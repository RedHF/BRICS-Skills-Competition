// Package httpapi exposes the small JSON protocol consumed by the Godot
// client.  It deliberately keeps transport concerns separate from rules and
// persistence so new clients (or a WebSocket gateway) can reuse both.
package httpapi

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"yanxia-server/internal/content"
	"yanxia-server/internal/model"
	"yanxia-server/internal/rules"
	"yanxia-server/internal/store"
)

const (
	maxJSONBody = 512 << 10
	maxErosion  = 100
	maxCapacity = 7
)

type Server struct {
	catalog *content.Catalog
	store   *store.Store
	started time.Time
	buildID string
}

// Catalog returns the loaded content for embedding in a local admin tool or
// an integration test.  HTTP callers should use GET /api/v1/catalog.
func (s *Server) Catalog() *content.Catalog { return s.catalog }

// Store exposes the persistence handle for embedding applications that need
// to run maintenance jobs.  Gameplay requests should always go through the
// HTTP handlers so validation is applied consistently.
func (s *Server) Store() *store.Store { return s.store }

func New(catalog *content.Catalog, persistence *store.Store) (*Server, error) {
	if catalog == nil || persistence == nil {
		return nil, errors.New("catalog and persistence are required")
	}
	return &Server{catalog: catalog, store: persistence, started: time.Now().UTC(), buildID: "dev"}, nil
}

// ServeHTTP implements routing without a framework so the server remains a
// single static-binary-friendly standard-library service.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	path := strings.TrimSuffix(r.URL.Path, "/")
	switch {
	case path == "/healthz":
		s.handleHealth(w, r)
	case path == "/api/v1/catalog":
		s.handleCatalog(w, r)
	case path == "/api/v1/players":
		s.handlePlayers(w, r)
	case strings.HasPrefix(path, "/api/v1/players/"):
		s.handlePlayerPath(w, r, strings.TrimPrefix(path, "/api/v1/players/"))
	case path == "/api/v1/sessions" || path == "/api/v1/runs":
		s.handleSessionRoot(w, r)
	case strings.HasPrefix(path, "/api/v1/events/"):
		s.handleEventStartPath(w, r, strings.TrimPrefix(path, "/api/v1/events/"))
	case strings.HasPrefix(path, "/api/v1/sessions/"):
		s.handleSessionPath(w, r, strings.TrimPrefix(path, "/api/v1/sessions/"))
	case strings.HasPrefix(path, "/api/v1/runs/"):
		// /runs is retained as a backwards-compatible spelling for early
		// prototypes; the canonical route is /sessions.
		s.handleSessionPath(w, r, strings.TrimPrefix(path, "/api/v1/runs/"))
	default:
		writeError(w, http.StatusNotFound, "not_found", "route not found")
	}
}

func setCORS(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, X-Player-ID")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	w.Header().Set("Cache-Control", "no-store")
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	players, sessions := s.store.Snapshot()
	writeJSON(w, http.StatusOK, map[string]any{
		"status":          "ok",
		"service":         "yanxia-server",
		"game_id":         s.catalog.GameID,
		"content_version": s.catalog.Version,
		"build":           s.buildID,
		"uptime_seconds":  int(time.Since(s.started).Seconds()),
		"players":         players,
		"active_sessions": sessions,
	})
}

func (s *Server) handleCatalog(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	writeJSON(w, http.StatusOK, publicCatalog(s.catalog))
}

type publicCatalogResponse struct {
	Version  int                        `json:"version"`
	GameID   string                     `json:"game_id"`
	Art      map[string]content.ArtSpec `json:"art,omitempty"`
	Chapters []publicChapter            `json:"chapters"`
}

type publicChapter struct {
	ID          string        `json:"id"`
	Order       int           `json:"order"`
	Title       string        `json:"title"`
	Summary     string        `json:"summary"`
	UnlockCost  int           `json:"unlock_cost"`
	NextChapter string        `json:"next_chapter,omitempty"`
	Events      []publicEvent `json:"events"`
}

type publicEvent struct {
	ID         string              `json:"id"`
	Order      int                 `json:"order"`
	Title      string              `json:"title"`
	Scene      string              `json:"scene"`
	Intro      string              `json:"intro"`
	Objectives []string            `json:"objectives"`
	Puzzle     publicPuzzle        `json:"puzzle"`
	Battle     *content.BattleSpec `json:"battle,omitempty"`
	Memory     publicMemory        `json:"memory"`
}

type publicPuzzle struct {
	Type        string             `json:"type"`
	MaxAttempts int                `json:"max_attempts"`
	Steps       []publicPuzzleStep `json:"steps"`
}

type publicPuzzleStep struct {
	ID      string   `json:"id"`
	Kind    string   `json:"kind"`
	Prompt  string   `json:"prompt"`
	Options []string `json:"options,omitempty"`
	Points  int      `json:"points"`
}

type publicMemory struct {
	ID       string   `json:"id"`
	Title    string   `json:"title"`
	Summary  string   `json:"summary"`
	Skill    string   `json:"skill"`
	Capacity int      `json:"capacity"`
	Choices  []string `json:"choices"`
}

func publicCatalog(c *content.Catalog) publicCatalogResponse {
	response := publicCatalogResponse{Version: c.Version, GameID: c.GameID, Art: c.Art, Chapters: make([]publicChapter, 0, len(c.Chapters))}
	for _, chapter := range c.Chapters {
		pc := publicChapter{ID: chapter.ID, Order: chapter.Order, Title: chapter.Title, Summary: chapter.Summary, UnlockCost: chapter.UnlockCost, NextChapter: chapter.NextChapter, Events: make([]publicEvent, 0, len(chapter.Events))}
		for _, event := range chapter.Events {
			pe := publicEvent{ID: event.ID, Order: event.Order, Title: event.Title, Scene: event.Scene, Intro: event.Intro, Objectives: append([]string(nil), event.Objectives...), Puzzle: publicPuzzle{Type: event.Puzzle.Type, MaxAttempts: event.Puzzle.MaxAttempts, Steps: make([]publicPuzzleStep, 0, len(event.Puzzle.Steps))}, Memory: publicMemory{ID: event.Reward.Memory.ID, Title: event.Reward.Memory.Title, Summary: event.Reward.Memory.Summary, Skill: event.Reward.Memory.Skill, Capacity: event.Reward.Memory.Capacity, Choices: append([]string(nil), event.Reward.Memory.Choices...)}}
			for _, step := range event.Puzzle.Steps {
				pe.Puzzle.Steps = append(pe.Puzzle.Steps, publicPuzzleStep{ID: step.ID, Kind: step.Kind, Prompt: step.Prompt, Options: append([]string(nil), step.Options...), Points: step.Points})
			}
			if event.Battle != nil {
				battle := *event.Battle
				battle.RequiredSkills = append([]string(nil), event.Battle.RequiredSkills...)
				pe.Battle = &battle
			}
			pc.Events = append(pc.Events, pe)
		}
		response.Chapters = append(response.Chapters, pc)
	}
	return response
}

type createPlayerRequest struct {
	PlayerID    string `json:"player_id"`
	DisplayName string `json:"display_name"`
}

func (s *Server) handlePlayers(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, http.MethodPost)
		return
	}
	var request createPlayerRequest
	if !decodeJSON(w, r, &request) {
		return
	}
	request.PlayerID = strings.TrimSpace(request.PlayerID)
	if request.PlayerID != "" && !validID(request.PlayerID) {
		writeError(w, http.StatusBadRequest, "invalid_player_id", "player_id contains unsupported characters")
		return
	}
	player, created, err := s.store.EnsurePlayer(request.PlayerID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "store_error", err.Error())
		return
	}
	if request.DisplayName != "" && player.DisplayName != request.DisplayName {
		player, err = s.store.UpdatePlayer(player.ID, func(p *model.Player) error {
			p.DisplayName = strings.TrimSpace(request.DisplayName)
			return nil
		})
		if err != nil {
			writeError(w, http.StatusInternalServerError, "store_error", err.Error())
			return
		}
	}
	player, err = s.ensureInitialChapter(player)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "store_error", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"created": created, "player": playerPayload(player)})
}

// playerPayload is the public save view.  It makes empty collections JSON
// arrays instead of null, which simplifies Godot iteration and keeps the wire
// contract stable for a brand-new player.
func playerPayload(player model.Player) map[string]any {
	if player.UnlockedChapters == nil {
		player.UnlockedChapters = []string{}
	}
	if player.CompletedEvents == nil {
		player.CompletedEvents = map[string]model.EventResult{}
	}
	if player.Memories == nil {
		player.Memories = []model.Memory{}
	}
	if player.MemoryLedger == nil {
		player.MemoryLedger = []model.LedgerEntry{}
	}
	return map[string]any{
		"id": player.ID, "display_name": player.DisplayName, "created_at": player.CreatedAt, "updated_at": player.UpdatedAt,
		"ink_marks": player.InkMarks, "capacity": player.Capacity, "erosion": player.Erosion,
		"unlocked_chapters": player.UnlockedChapters, "completed_events": player.CompletedEvents,
		"memories": player.Memories, "memory_ledger": player.MemoryLedger, "last_sequence": player.LastSequence,
	}
}

func (s *Server) handlePlayerPath(w http.ResponseWriter, r *http.Request, remainder string) {
	parts := splitPath(remainder)
	if len(parts) == 0 || !validID(parts[0]) {
		writeError(w, http.StatusBadRequest, "invalid_player_id", "invalid player id")
		return
	}
	playerID := parts[0]
	if len(parts) > 2 || (len(parts) == 2 && parts[1] != "save" && parts[1] != "ledger") {
		writeError(w, http.StatusNotFound, "not_found", "player route not found")
		return
	}
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	player, ok := s.store.GetPlayer(playerID)
	if !ok {
		writeError(w, http.StatusNotFound, "player_not_found", "player not found")
		return
	}
	if len(parts) == 2 && parts[1] == "ledger" {
		ledger := player.MemoryLedger
		if ledger == nil {
			ledger = []model.LedgerEntry{}
		}
		writeJSON(w, http.StatusOK, map[string]any{"player_id": player.ID, "ledger": ledger})
		return
	}
	writeJSON(w, http.StatusOK, playerPayload(player))
}

func (s *Server) ensureInitialChapter(player model.Player) (model.Player, error) {
	if len(s.catalog.Chapters) == 0 {
		return player, nil
	}
	first := s.catalog.Chapters[0].ID
	for _, id := range player.UnlockedChapters {
		if id == first {
			return player, nil
		}
	}
	return s.store.UpdatePlayer(player.ID, func(p *model.Player) error {
		p.UnlockedChapters = append(p.UnlockedChapters, first)
		return nil
	})
}

type startSessionRequest struct {
	PlayerID  string `json:"player_id"`
	ChapterID string `json:"chapter_id"`
	EventID   string `json:"event_id"`
}

func (s *Server) handleSessionRoot(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, http.MethodPost)
		return
	}
	var request startSessionRequest
	if !decodeJSON(w, r, &request) {
		return
	}
	s.startSession(w, request)
}

func (s *Server) startSession(w http.ResponseWriter, request startSessionRequest) {
	request.PlayerID = strings.TrimSpace(request.PlayerID)
	request.ChapterID = strings.TrimSpace(request.ChapterID)
	request.EventID = strings.TrimSpace(request.EventID)
	if !validID(request.PlayerID) || !validID(request.ChapterID) || !validID(request.EventID) {
		writeError(w, http.StatusBadRequest, "invalid_request", "player_id, chapter_id and event_id are required")
		return
	}
	player, ok := s.store.GetPlayer(request.PlayerID)
	if !ok {
		writeError(w, http.StatusNotFound, "player_not_found", "create the player before starting a session")
		return
	}
	chapter, ok := s.catalog.Chapter(request.ChapterID)
	if !ok {
		writeError(w, http.StatusNotFound, "chapter_not_found", "chapter not found")
		return
	}
	event, ok := s.catalog.Event(request.ChapterID, request.EventID)
	if !ok {
		writeError(w, http.StatusNotFound, "event_not_found", "event not found")
		return
	}
	if !chapterUnlocked(player, chapter) {
		writeError(w, http.StatusForbidden, "chapter_locked", "chapter is not unlocked")
		return
	}
	if event.Puzzle.MaxAttempts <= 0 {
		event.Puzzle.MaxAttempts = 3
	}
	id, err := newID("s")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "id_error", err.Error())
		return
	}
	now := time.Now().UTC()
	duration := time.Duration(event.Puzzle.MaxAttempts*30+30) * time.Second
	if event.Battle != nil && time.Duration(event.Battle.DurationSec)*time.Second > duration {
		duration = time.Duration(event.Battle.DurationSec) * time.Second
	}
	session := model.EventSession{
		ID: id, PlayerID: player.ID, ChapterID: chapter.ID, EventID: event.ID,
		StartedAt: now, ExpiresAt: now.Add(duration + 2*time.Minute), LastSeenAt: now,
		Status: "active", PuzzleTotal: puzzleTotal(event), RepairPercent: 0,
		AcceptedSteps: make([]string, 0, len(event.Puzzle.Steps)), Actions: make([]model.ActionRecord, 0),
		PendingMemory: memoryFromEvent(event),
	}
	if err := s.store.CreateSession(session); err != nil {
		writeError(w, http.StatusInternalServerError, "store_error", err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, s.sessionStartResponse(session, event))
}

func (s *Server) handleSessionPath(w http.ResponseWriter, r *http.Request, remainder string) {
	parts := splitPath(remainder)
	if len(parts) == 0 || !validID(parts[0]) {
		writeError(w, http.StatusBadRequest, "invalid_session_id", "invalid session id")
		return
	}
	sessionID := parts[0]
	if len(parts) == 1 {
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		session, ok := s.store.GetSession(sessionID)
		if !ok {
			writeError(w, http.StatusNotFound, "session_not_found", "session not found")
			return
		}
		writeJSON(w, http.StatusOK, session)
		return
	}
	if len(parts) != 2 {
		writeError(w, http.StatusNotFound, "not_found", "session route not found")
		return
	}
	switch parts[1] {
	case "puzzle", "actions":
		if r.Method != http.MethodPost {
			methodNotAllowed(w, http.MethodPost)
			return
		}
		s.handlePuzzle(w, r, sessionID)
	case "battle":
		if r.Method != http.MethodPost {
			methodNotAllowed(w, http.MethodPost)
			return
		}
		s.handleBattle(w, r, sessionID)
	case "choice", "memory":
		if r.Method != http.MethodPost {
			methodNotAllowed(w, http.MethodPost)
			return
		}
		s.handleChoice(w, r, sessionID)
	case "finish", "submit", "settle":
		if r.Method != http.MethodPost {
			methodNotAllowed(w, http.MethodPost)
			return
		}
		s.handleFinish(w, r, sessionID)
	default:
		writeError(w, http.StatusNotFound, "not_found", "session route not found")
	}
}

type sessionStartResponse struct {
	RunID     string              `json:"run_id"`
	SessionID string              `json:"session_id"`
	PlayerID  string              `json:"player_id"`
	ChapterID string              `json:"chapter_id"`
	EventID   string              `json:"event_id"`
	StartedAt time.Time           `json:"started_at"`
	ExpiresAt time.Time           `json:"expires_at"`
	Puzzle    publicPuzzle        `json:"puzzle"`
	Battle    *content.BattleSpec `json:"battle,omitempty"`
	Memory    publicMemory        `json:"memory"`
	Rules     map[string]int      `json:"rules"`
}

func (s *Server) sessionStartResponse(session model.EventSession, event *content.Event) sessionStartResponse {
	public := publicCatalog(&content.Catalog{Version: s.catalog.Version, GameID: s.catalog.GameID, Chapters: []content.Chapter{{Events: []content.Event{*event}}}})
	var pe []publicEvent
	if len(public.Chapters) > 0 {
		pe = public.Chapters[0].Events
	}
	response := sessionStartResponse{RunID: session.ID, SessionID: session.ID, PlayerID: session.PlayerID, ChapterID: session.ChapterID, EventID: session.EventID, StartedAt: session.StartedAt, ExpiresAt: session.ExpiresAt, Rules: map[string]int{"puzzle_failure_erosion": rules.PuzzleFailureErosion, "battle_failure_erosion": rules.BattleFailureErosion, "hit_erosion": rules.HitErosion, "max_erosion": maxErosion}}
	if len(pe) > 0 {
		response.Puzzle = pe[0].Puzzle
		response.Battle = pe[0].Battle
		response.Memory = pe[0].Memory
	}
	return response
}

type puzzleRequest struct {
	PlayerID string `json:"player_id"`
	StepID   string `json:"step_id"`
	Answer   string `json:"answer"`
	Action   string `json:"action"`
}

func (s *Server) handlePuzzle(w http.ResponseWriter, r *http.Request, sessionID string) {
	var request puzzleRequest
	if !decodeJSON(w, r, &request) {
		return
	}
	session, ok := s.store.GetSession(sessionID)
	if !ok {
		writeError(w, http.StatusNotFound, "session_not_found", "session not found")
		return
	}
	if request.PlayerID != "" && request.PlayerID != session.PlayerID {
		writeError(w, http.StatusForbidden, "session_owner_mismatch", "session belongs to another player")
		return
	}
	if session.Status == "failed" {
		// A failed run is immutable. Clients must create a new event session
		// instead of appending telemetry to a run that already consumed its
		// attempts or erosion budget.
		writeError(w, http.StatusConflict, "session_failed", session.FailureReason)
		return
	}
	event, ok := s.catalog.Event(session.ChapterID, session.EventID)
	if !ok {
		writeError(w, http.StatusInternalServerError, "content_error", "session references missing event")
		return
	}
	if expired(session) {
		_, _, _ = s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
			current.Status = "failed"
			current.FailureReason = "session_expired"
			player.Erosion = maxInt(player.Erosion, maxErosion)
			return nil
		})
		writeError(w, http.StatusConflict, "session_expired", "session has expired")
		return
	}
	var evaluation rules.PuzzleEvaluation
	updated, player, err := s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
		evaluation = rules.EvaluatePuzzleStep(event, current, rules.PuzzleAttempt{StepID: strings.TrimSpace(request.StepID), Answer: request.Answer, Action: request.Action})
		current.Actions = append(current.Actions, evaluation.ActionRecord)
		if evaluation.ErosionDelta > 0 {
			player.Erosion = clamp(player.Erosion+evaluation.ErosionDelta, 0, maxErosion)
		}
		if player.Erosion >= maxErosion && current.Status != "completed" {
			current.Status = "failed"
			current.FailureReason = "erosion_limit"
		}
		if evaluation.Complete && current.Status == "active" {
			current.RepairPercent = halfPuzzlePercent(*current)
		}
		return nil
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "store_error", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"accepted": evaluation.Accepted, "correct": evaluation.Correct, "complete": evaluation.Complete,
		"reason": evaluation.Reason, "next_step_id": evaluation.NextStepID,
		"puzzle_score": updated.PuzzleScore, "puzzle_total": updated.PuzzleTotal,
		"attempt_count": updated.AttemptCount, "invalid_attempts": updated.InvalidAttempts,
		"erosion": player.Erosion, "status": updated.Status,
	})
}

type battleRequest struct {
	PlayerID     string         `json:"player_id"`
	Actions      []battleAction `json:"actions"`
	DurationMS   int            `json:"duration_ms"`
	WavesCleared int            `json:"waves_cleared,omitempty"`
	HitsTaken    int            `json:"hits_taken,omitempty"`
}

type battleAction struct {
	Skill string `json:"skill"`
	AtMS  int    `json:"at_ms"`
}

func (s *Server) handleBattle(w http.ResponseWriter, r *http.Request, sessionID string) {
	var request battleRequest
	if !decodeJSON(w, r, &request) {
		return
	}
	session, ok := s.store.GetSession(sessionID)
	if !ok {
		writeError(w, http.StatusNotFound, "session_not_found", "session not found")
		return
	}
	if request.PlayerID != "" && request.PlayerID != session.PlayerID {
		writeError(w, http.StatusForbidden, "session_owner_mismatch", "session belongs to another player")
		return
	}
	if session.Status == "failed" {
		writeError(w, http.StatusConflict, "session_failed", session.FailureReason)
		return
	}
	event, ok := s.catalog.Event(session.ChapterID, session.EventID)
	if !ok {
		writeError(w, http.StatusInternalServerError, "content_error", "session references missing event")
		return
	}
	if session.BattleChecked {
		player, _ := s.store.GetPlayer(session.PlayerID)
		writeJSON(w, http.StatusOK, battleResponse(session, player.Erosion, "already_checked"))
		return
	}
	if expired(session) {
		_, _, _ = s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
			current.Status = "failed"
			current.FailureReason = "session_expired"
			return nil
		})
		writeError(w, http.StatusConflict, "session_expired", "session has expired")
		return
	}
	if len(session.AcceptedSteps) != len(event.Puzzle.Steps) {
		writeError(w, http.StatusConflict, "puzzle_incomplete", "complete the puzzle before battle")
		return
	}
	player, ok := s.store.GetPlayer(session.PlayerID)
	if !ok {
		writeError(w, http.StatusNotFound, "player_not_found", "player not found")
		return
	}
	availableSkills := playerSkills(player)
	if session.PendingMemory != nil && session.PendingMemory.Skill != "" {
		availableSkills[session.PendingMemory.Skill] = true
	}
	for _, action := range request.Actions {
		if !availableSkills[strings.TrimSpace(action.Skill)] {
			writeError(w, http.StatusBadRequest, "skill_unavailable", "battle action uses a skill not held by the player")
			return
		}
	}
	input := rules.BattleInput{DurationMS: request.DurationMS, WavesCleared: request.WavesCleared, HitsTaken: request.HitsTaken, AllowedSkills: availableSkills, Actions: make([]rules.BattleAction, 0, len(request.Actions))}
	for _, action := range request.Actions {
		input.Actions = append(input.Actions, rules.BattleAction{Skill: strings.TrimSpace(action.Skill), AtMS: action.AtMS})
	}
	evaluation, err := rules.EvaluateBattle(event, input)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_battle", err.Error())
		return
	}
	updated, player, err := s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
		current.BattleChecked = true
		current.BattleWon = evaluation.Won
		current.BattleWaves = evaluation.Waves
		current.BattleHits = evaluation.HitsTaken
		current.RepairPercent = halfPuzzlePercent(*current)
		if evaluation.Won {
			current.RepairPercent += 50
		} else {
			current.Status = "failed"
			current.FailureReason = evaluation.Reason
		}
		player.Erosion = clamp(player.Erosion+evaluation.ErosionDelta, 0, maxErosion)
		if player.Erosion >= maxErosion {
			current.Status = "failed"
			current.FailureReason = "erosion_limit"
		}
		return nil
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "store_error", err.Error())
		return
	}
	response := battleResponse(updated, player.Erosion, evaluation.Reason)
	response["won"] = evaluation.Won
	response["waves"] = evaluation.Waves
	response["hits_taken"] = evaluation.HitsTaken
	response["erosion_delta"] = evaluation.ErosionDelta
	writeJSON(w, http.StatusOK, response)
}

func battleResponse(session model.EventSession, erosion int, reason string) map[string]any {
	return map[string]any{"won": session.BattleWon, "reason": reason, "battle_checked": session.BattleChecked, "repair_percent": session.RepairPercent, "erosion": erosion, "status": session.Status}
}

type choiceRequest struct {
	PlayerID       string `json:"player_id"`
	Action         string `json:"action"`
	ForgetMemoryID string `json:"forget_memory_id"`
}

func (s *Server) handleChoice(w http.ResponseWriter, r *http.Request, sessionID string) {
	var request choiceRequest
	if !decodeJSON(w, r, &request) {
		return
	}
	session, ok := s.store.GetSession(sessionID)
	if !ok {
		writeError(w, http.StatusNotFound, "session_not_found", "session not found")
		return
	}
	if request.PlayerID != "" && request.PlayerID != session.PlayerID {
		writeError(w, http.StatusForbidden, "session_owner_mismatch", "session belongs to another player")
		return
	}
	event, ok := s.catalog.Event(session.ChapterID, session.EventID)
	if !ok {
		writeError(w, http.StatusInternalServerError, "content_error", "session references missing event")
		return
	}
	if expired(session) {
		_, _, _ = s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
			if current.Status != "completed" {
				current.Status = "failed"
				current.FailureReason = "session_expired"
			}
			return nil
		})
		writeError(w, http.StatusConflict, "session_expired", "session has expired")
		return
	}
	if session.ChoiceDone {
		writeJSON(w, http.StatusOK, choiceResponse(session, "already_checked"))
		return
	}
	if session.Status == "failed" {
		writeError(w, http.StatusConflict, "session_failed", "cannot choose memory after a failed event")
		return
	}
	if len(session.AcceptedSteps) != len(event.Puzzle.Steps) {
		writeError(w, http.StatusConflict, "puzzle_incomplete", "complete the puzzle before choosing a memory")
		return
	}
	if event.Battle != nil && !session.BattleChecked {
		writeError(w, http.StatusConflict, "battle_incomplete", "submit battle telemetry before choosing a memory")
		return
	}
	if event.Battle != nil && !session.BattleWon {
		writeError(w, http.StatusConflict, "battle_failed", "a failed battle cannot apply a memory choice")
		return
	}
	action := strings.ToLower(strings.TrimSpace(request.Action))
	if action == "" {
		writeError(w, http.StatusBadRequest, "choice_required", "action is required")
		return
	}
	updated, player, err := s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
		if current.ChoiceDone {
			return nil
		}
		valid, forgotten, reason := validateChoice(action, request.ForgetMemoryID, current.PendingMemory, player, event.Reward.Memory.Choices)
		if !valid {
			return &choiceValidationError{reason: reason}
		}
		current.ChoiceDone = true
		current.ChoiceAction = action
		current.ForgottenMemory = forgotten
		return nil
	})
	if err != nil {
		var choiceErr *choiceValidationError
		if errors.As(err, &choiceErr) {
			writeError(w, http.StatusBadRequest, "invalid_choice", choiceErr.reason)
			return
		}
		writeError(w, http.StatusInternalServerError, "store_error", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"accepted": updated.ChoiceDone, "action": updated.ChoiceAction, "forgotten_memory_id": updated.ForgottenMemory, "memory": publicMemoryFromModel(updated.PendingMemory), "capacity": player.Capacity, "used_capacity": usedCapacity(player), "status": updated.Status})
}

type choiceValidationError struct{ reason string }

func (e *choiceValidationError) Error() string { return e.reason }

func validateChoice(action, forgetID string, pending *model.Memory, player *model.Player, choices []string) (bool, string, string) {
	if pending == nil {
		return false, "", "no pending memory"
	}
	allowed := make(map[string]bool, len(choices))
	for _, choice := range choices {
		allowed[strings.ToLower(strings.TrimSpace(choice))] = true
	}
	if action != "keep" && action != "forget" && !allowed[action] {
		return false, "", "choice is not offered by this event"
	}
	forgotten := ""
	if action == "forget" {
		forgetID = strings.TrimSpace(forgetID)
		if forgetID == "" {
			return false, "", "forget_memory_id is required"
		}
		for _, memory := range player.Memories {
			if memory.ID == forgetID {
				forgotten = forgetID
				break
			}
		}
		if forgotten == "" {
			return false, "", "forget_memory_id is not in the player's memory ledger"
		}
	} else if action != "keep" {
		// Content uses existing memory IDs as compact forget options (for
		// example the first capacity choice in temple_drum), while story-only
		// options such as restore_all are kept as narrative choices.
		for _, memory := range player.Memories {
			if memory.ID == action {
				forgotten = action
				break
			}
		}
	}
	available := player.Capacity - usedCapacity(*player)
	if forgotten != "" {
		for _, memory := range player.Memories {
			if memory.ID == forgotten {
				available += memory.Capacity
				break
			}
		}
	}
	if pending.Capacity > available {
		return false, "", "not enough memory capacity; forget an existing memory first"
	}
	return true, forgotten, ""
}

func choiceResponse(session model.EventSession, reason string) map[string]any {
	return map[string]any{"accepted": session.ChoiceDone, "action": session.ChoiceAction, "forgotten_memory_id": session.ForgottenMemory, "reason": reason, "status": session.Status}
}

func (s *Server) handleFinish(w http.ResponseWriter, r *http.Request, sessionID string) {
	var request struct {
		PlayerID string `json:"player_id"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	session, ok := s.store.GetSession(sessionID)
	if !ok {
		writeError(w, http.StatusNotFound, "session_not_found", "session not found")
		return
	}
	if request.PlayerID != "" && request.PlayerID != session.PlayerID {
		writeError(w, http.StatusForbidden, "session_owner_mismatch", "session belongs to another player")
		return
	}
	event, ok := s.catalog.Event(session.ChapterID, session.EventID)
	if !ok {
		writeError(w, http.StatusInternalServerError, "content_error", "session references missing event")
		return
	}
	if session.RewardApplied && session.PendingResult != nil {
		player, _ := s.store.GetPlayer(session.PlayerID)
		writeJSON(w, http.StatusOK, finishResponse(session, player, *session.PendingResult, "already_settled"))
		return
	}
	if expired(session) {
		_, _, _ = s.store.UpdateSessionAndPlayer(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
			if current.Status != "completed" {
				current.Status = "failed"
				current.FailureReason = "session_expired"
			}
			return nil
		})
		writeError(w, http.StatusConflict, "session_expired", "session has expired")
		return
	}
	if session.Status == "failed" {
		writeError(w, http.StatusConflict, "session_failed", session.FailureReason)
		return
	}
	if len(session.AcceptedSteps) != len(event.Puzzle.Steps) {
		writeError(w, http.StatusConflict, "puzzle_incomplete", "complete the puzzle before settling")
		return
	}
	if event.Battle != nil && (!session.BattleChecked || !session.BattleWon) {
		writeError(w, http.StatusConflict, "battle_incomplete", "win the battle before settling")
		return
	}
	if !session.ChoiceDone {
		writeError(w, http.StatusConflict, "choice_incomplete", "submit a memory choice before settling")
		return
	}

	var result model.EventResult
	updated, player, err := s.store.FinalizeSession(sessionID, session.PlayerID, func(current *model.EventSession, player *model.Player) error {
		if current.RewardApplied && current.PendingResult != nil {
			result = *current.PendingResult
			return nil
		}
		if current.Status == "failed" {
			return errors.New("session_failed")
		}
		key := eventKey(current.ChapterID, current.EventID)
		if existing, completed := player.CompletedEvents[key]; completed {
			result = existing
			current.PendingResult = &existing
			current.RewardApplied = true
			current.Status = "completed"
			return nil
		}
		result = calculateResult(current, event, player.Erosion)
		result.Sequence = player.LastSequence + 1
		result.CompletedAt = time.Now().UTC()
		player.LastSequence = result.Sequence
		player.InkMarks += result.InkMarksEarned
		if event.Reward.CapacityIncrease > 0 {
			player.Capacity = clamp(player.Capacity+event.Reward.CapacityIncrease, 1, maxCapacity)
		}
		if current.ForgottenMemory != "" {
			forgotten, ok := removeMemory(player, current.ForgottenMemory)
			if !ok {
				return errors.New("forgotten memory is no longer present")
			}
			player.MemoryLedger = append(player.MemoryLedger, model.LedgerEntry{MemoryID: forgotten.ID, Title: forgotten.Title, Action: "forgotten", ChapterID: current.ChapterID, EventID: current.EventID, OccurredAt: time.Now().UTC()})
		}
		if current.PendingMemory != nil && !containsMemory(player.Memories, current.PendingMemory.ID) {
			memory := *current.PendingMemory
			memory.AddedAt = time.Now().UTC()
			memory.Source = current.ChapterID + "/" + current.EventID
			player.Memories = append(player.Memories, memory)
			player.MemoryLedger = append(player.MemoryLedger, model.LedgerEntry{MemoryID: memory.ID, Title: memory.Title, Action: "kept", ChapterID: current.ChapterID, EventID: current.EventID, OccurredAt: memory.AddedAt})
		}
		player.CompletedEvents[key] = result
		unlockNextChapter(s.catalog, current.ChapterID, player)
		current.PendingResult = &result
		current.RewardApplied = true
		current.Status = "completed"
		return nil
	})
	if err != nil {
		if err.Error() == "session_failed" {
			writeError(w, http.StatusConflict, "session_failed", "session cannot be settled")
			return
		}
		writeError(w, http.StatusInternalServerError, "settlement_error", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, finishResponse(updated, player, result, "settled"))
}

func finishResponse(session model.EventSession, player model.Player, result model.EventResult, reason string) map[string]any {
	return map[string]any{
		"settled": true, "reason": reason, "session_id": session.ID, "status": session.Status,
		"result": result, "player": playerPayload(player),
	}
}

func calculateResult(session *model.EventSession, event *content.Event, erosion int) model.EventResult {
	puzzlePercent := 0
	if session.PuzzleTotal > 0 {
		puzzlePercent = session.PuzzleScore * 50 / session.PuzzleTotal
	}
	battlePercent := 50
	if event.Battle != nil {
		battlePercent = 0
		if session.BattleWon {
			battlePercent = 50
		}
	}
	quality := puzzlePercent + battlePercent
	if session.InvalidAttempts > 0 {
		quality -= minInt(20, session.InvalidAttempts*5)
	}
	if erosion >= 70 {
		quality -= 15
	}
	quality = clamp(quality, 0, 100)
	stars := 1
	if quality >= 85 {
		stars = 3
	} else if quality >= 60 {
		stars = 2
	}
	return model.EventResult{ChapterID: session.ChapterID, EventID: session.EventID, Stars: stars, PuzzleScore: session.PuzzleScore, PuzzleTotal: session.PuzzleTotal, BattleWon: session.BattleWon, RepairPercent: quality, ErosionAtEnd: erosion, InkMarksEarned: clamp(event.Reward.BaseInkMarks+stars-1, 1, 3)}
}

func (s *Server) handleEventStartPath(w http.ResponseWriter, r *http.Request, remainder string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, http.MethodPost)
		return
	}
	parts := splitPath(remainder)
	if len(parts) != 3 || parts[2] != "start" || !validID(parts[0]) || !validID(parts[1]) {
		writeError(w, http.StatusNotFound, "not_found", "event start route not found")
		return
	}
	var request struct {
		PlayerID string `json:"player_id"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	s.startSession(w, startSessionRequest{PlayerID: request.PlayerID, ChapterID: parts[0], EventID: parts[1]})
}

func memoryFromEvent(event *content.Event) *model.Memory {
	if event == nil {
		return nil
	}
	return &model.Memory{ID: event.Reward.Memory.ID, Title: event.Reward.Memory.Title, Summary: event.Reward.Memory.Summary, Skill: event.Reward.Memory.Skill, Capacity: event.Reward.Memory.Capacity, Source: event.ID}
}

func publicMemoryFromModel(memory *model.Memory) any {
	if memory == nil {
		return nil
	}
	return map[string]any{"id": memory.ID, "title": memory.Title, "summary": memory.Summary, "skill": memory.Skill, "capacity": memory.Capacity}
}

func usedCapacity(player model.Player) int {
	total := 0
	for _, memory := range player.Memories {
		total += memory.Capacity
	}
	return total
}

func playerSkills(player model.Player) map[string]bool {
	result := make(map[string]bool)
	for _, memory := range player.Memories {
		if memory.Skill != "" {
			result[memory.Skill] = true
		}
	}
	return result
}

func containsMemory(memories []model.Memory, id string) bool {
	for _, memory := range memories {
		if memory.ID == id {
			return true
		}
	}
	return false
}

func removeMemory(player *model.Player, id string) (model.Memory, bool) {
	for i, memory := range player.Memories {
		if memory.ID == id {
			player.Memories = append(player.Memories[:i], player.Memories[i+1:]...)
			return memory, true
		}
	}
	return model.Memory{}, false
}

func chapterUnlocked(player model.Player, chapter *content.Chapter) bool {
	for _, id := range player.UnlockedChapters {
		if id == chapter.ID {
			return true
		}
	}
	return false
}

func unlockNextChapter(catalog *content.Catalog, chapterID string, player *model.Player) {
	chapter, ok := catalog.Chapter(chapterID)
	if !ok || chapter.NextChapter == "" {
		return
	}
	for _, event := range chapter.Events {
		if _, done := player.CompletedEvents[eventKey(chapter.ID, event.ID)]; !done {
			return
		}
	}
	next, ok := catalog.Chapter(chapter.NextChapter)
	if !ok || player.InkMarks < next.UnlockCost || chapterAlreadyUnlocked(*player, next.ID) {
		return
	}
	player.UnlockedChapters = append(player.UnlockedChapters, next.ID)
}

func chapterAlreadyUnlocked(player model.Player, id string) bool {
	for _, current := range player.UnlockedChapters {
		if current == id {
			return true
		}
	}
	return false
}

func eventKey(chapterID, eventID string) string { return chapterID + ":" + eventID }

func halfPuzzlePercent(session model.EventSession) int {
	if session.PuzzleTotal <= 0 {
		return 0
	}
	return clamp(session.PuzzleScore*50/session.PuzzleTotal, 0, 50)
}

func puzzleTotal(event *content.Event) int {
	total := 0
	if event != nil {
		for _, step := range event.Puzzle.Steps {
			total += step.Points
		}
	}
	return total
}

func expired(session model.EventSession) bool {
	return !session.ExpiresAt.IsZero() && time.Now().UTC().After(session.ExpiresAt)
}

func splitPath(value string) []string {
	raw := strings.Split(strings.Trim(value, "/"), "/")
	result := make([]string, 0, len(raw))
	for _, part := range raw {
		if part != "" {
			result = append(result, part)
		}
	}
	return result
}

func validID(value string) bool {
	value = strings.TrimSpace(value)
	if value == "" || len(value) > 128 {
		return false
	}
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			continue
		}
		return false
	}
	return true
}

func newID(prefix string) (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return prefix + "_" + hex.EncodeToString(b), nil
}

func decodeJSON(w http.ResponseWriter, r *http.Request, destination any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxJSONBody)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		if errors.Is(err, io.EOF) {
			// Finish/settle accepts an empty body; handlers still validate the
			// session state before applying any reward.
			return true
		}
		writeError(w, http.StatusBadRequest, "invalid_json", err.Error())
		return false
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		writeError(w, http.StatusBadRequest, "invalid_json", "request must contain one JSON value")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		return
	}
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": message}})
}

func methodNotAllowed(w http.ResponseWriter, method string) {
	w.Header().Set("Allow", method)
	writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "use "+method)
}

func clamp(value, minimum, maximum int) int {
	if value < minimum {
		return minimum
	}
	if value > maximum {
		return maximum
	}
	return value
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
