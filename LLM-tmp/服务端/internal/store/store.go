// Package store provides small, durable server-side persistence for the demo.
// It intentionally uses a JSON file so the project has no database dependency
// during judging; the interface can later be backed by PostgreSQL or Redis.
package store

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"yanxia-server/internal/model"
)

const databaseVersion = 1

type database struct {
	Version  int                           `json:"version"`
	Players  map[string]model.Player       `json:"players"`
	Sessions map[string]model.EventSession `json:"sessions"`
}

type Store struct {
	mu   sync.RWMutex
	path string
	db   database
}

func Open(path string) (*Store, error) {
	if path == "" {
		return nil, errors.New("store path is required")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("create store directory: %w", err)
	}
	s := &Store{path: path}
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		s.db = newDatabase()
		if err := s.persistLocked(); err != nil {
			return nil, err
		}
		return s, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read store: %w", err)
	}
	if len(b) == 0 {
		s.db = newDatabase()
		if err := s.persistLocked(); err != nil {
			return nil, err
		}
		return s, nil
	}
	if err := json.Unmarshal(b, &s.db); err != nil {
		return nil, fmt.Errorf("decode store %q: %w", path, err)
	}
	if s.db.Version == 0 {
		s.db.Version = databaseVersion
	}
	if s.db.Version > databaseVersion {
		return nil, fmt.Errorf("store version %d is newer than supported version %d", s.db.Version, databaseVersion)
	}
	if s.db.Players == nil {
		s.db.Players = make(map[string]model.Player)
	}
	if s.db.Sessions == nil {
		s.db.Sessions = make(map[string]model.EventSession)
	}
	return s, nil
}

func newDatabase() database {
	return database{
		Version:  databaseVersion,
		Players:  make(map[string]model.Player),
		Sessions: make(map[string]model.EventSession),
	}
}

func (s *Store) persistLocked() error {
	b, err := json.MarshalIndent(s.db, "", "  ")
	if err != nil {
		return fmt.Errorf("encode store: %w", err)
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, append(b, '\n'), 0o600); err != nil {
		return fmt.Errorf("write store temp: %w", err)
	}
	if err := os.Rename(tmp, s.path); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("replace store: %w", err)
	}
	return nil
}

func (s *Store) GetPlayer(id string) (model.Player, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.db.Players[id]
	if !ok {
		return model.Player{}, false
	}
	return clonePlayer(p), true
}

// EnsurePlayer creates an anonymous player when id is empty or unknown.  The
// returned bool reports whether a new record was created.
func (s *Store) EnsurePlayer(id string) (model.Player, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if id != "" {
		if p, ok := s.db.Players[id]; ok {
			return clonePlayer(p), false, nil
		}
	}
	newID := id
	if newID == "" {
		var err error
		newID, err = newIDValue("p")
		if err != nil {
			return model.Player{}, false, err
		}
	}
	now := time.Now().UTC()
	p := model.Player{
		ID:               newID,
		CreatedAt:        now,
		UpdatedAt:        now,
		InkMarks:         0,
		Capacity:         5,
		Erosion:          0,
		UnlockedChapters: []string{"prologue"},
		CompletedEvents:  make(map[string]model.EventResult),
		Memories:         make([]model.Memory, 0),
		MemoryLedger:     make([]model.LedgerEntry, 0),
	}
	s.db.Players[newID] = p
	if err := s.persistLocked(); err != nil {
		delete(s.db.Players, newID)
		return model.Player{}, false, err
	}
	return clonePlayer(p), true, nil
}

func (s *Store) UpdatePlayer(id string, fn func(*model.Player) error) (model.Player, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.db.Players[id]
	if !ok {
		return model.Player{}, os.ErrNotExist
	}
	next := clonePlayer(p)
	if err := fn(&next); err != nil {
		return model.Player{}, err
	}
	next.UpdatedAt = time.Now().UTC()
	normalizePlayer(&next)
	s.db.Players[id] = next
	if err := s.persistLocked(); err != nil {
		s.db.Players[id] = p
		return model.Player{}, err
	}
	return clonePlayer(next), nil
}

func (s *Store) GetSession(id string) (model.EventSession, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	session, ok := s.db.Sessions[id]
	if !ok {
		return model.EventSession{}, false
	}
	return cloneSession(session), true
}

func (s *Store) CreateSession(session model.EventSession) error {
	if session.ID == "" || session.PlayerID == "" {
		return errors.New("session id and player id are required")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.db.Sessions[session.ID]; exists {
		return os.ErrExist
	}
	if session.Status == "" {
		session.Status = "active"
	}
	if session.LastSeenAt.IsZero() {
		session.LastSeenAt = session.StartedAt
	}
	s.db.Sessions[session.ID] = cloneSession(session)
	if err := s.persistLocked(); err != nil {
		delete(s.db.Sessions, session.ID)
		return err
	}
	return nil
}

func (s *Store) UpdateSession(id string, fn func(*model.EventSession) error) (model.EventSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	old, ok := s.db.Sessions[id]
	if !ok {
		return model.EventSession{}, os.ErrNotExist
	}
	next := cloneSession(old)
	if err := fn(&next); err != nil {
		return model.EventSession{}, err
	}
	next.LastSeenAt = time.Now().UTC()
	s.db.Sessions[id] = next
	if err := s.persistLocked(); err != nil {
		s.db.Sessions[id] = old
		return model.EventSession{}, err
	}
	return cloneSession(next), nil
}

// FinalizeSession applies the session transition and the corresponding player
// progression in one persisted transaction.  This prevents a power loss from
// recording rewards without recording the completed run (or vice versa).
func (s *Store) FinalizeSession(sessionID, playerID string, fn func(*model.EventSession, *model.Player) error) (model.EventSession, model.Player, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, ok := s.db.Sessions[sessionID]
	if !ok {
		return model.EventSession{}, model.Player{}, os.ErrNotExist
	}
	player, ok := s.db.Players[playerID]
	if !ok {
		return model.EventSession{}, model.Player{}, os.ErrNotExist
	}
	nextSession := cloneSession(session)
	nextPlayer := clonePlayer(player)
	if err := fn(&nextSession, &nextPlayer); err != nil {
		return model.EventSession{}, model.Player{}, err
	}
	nextSession.LastSeenAt = time.Now().UTC()
	nextPlayer.UpdatedAt = time.Now().UTC()
	normalizePlayer(&nextPlayer)
	s.db.Sessions[sessionID] = nextSession
	s.db.Players[playerID] = nextPlayer
	if err := s.persistLocked(); err != nil {
		s.db.Sessions[sessionID] = session
		s.db.Players[playerID] = player
		return model.EventSession{}, model.Player{}, err
	}
	return cloneSession(nextSession), clonePlayer(nextPlayer), nil
}

// UpdateSessionAndPlayer runs a guarded state transition against both records.
// It is used for incremental actions (puzzle attempts and battle submission)
// where the server must update erosion and session progress together.
func (s *Store) UpdateSessionAndPlayer(sessionID, playerID string, fn func(*model.EventSession, *model.Player) error) (model.EventSession, model.Player, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, ok := s.db.Sessions[sessionID]
	if !ok {
		return model.EventSession{}, model.Player{}, os.ErrNotExist
	}
	player, ok := s.db.Players[playerID]
	if !ok {
		return model.EventSession{}, model.Player{}, os.ErrNotExist
	}
	nextSession := cloneSession(session)
	nextPlayer := clonePlayer(player)
	if err := fn(&nextSession, &nextPlayer); err != nil {
		return model.EventSession{}, model.Player{}, err
	}
	nextSession.LastSeenAt = time.Now().UTC()
	nextPlayer.UpdatedAt = time.Now().UTC()
	normalizePlayer(&nextPlayer)
	s.db.Sessions[sessionID] = nextSession
	s.db.Players[playerID] = nextPlayer
	if err := s.persistLocked(); err != nil {
		s.db.Sessions[sessionID] = session
		s.db.Players[playerID] = player
		return model.EventSession{}, model.Player{}, err
	}
	return cloneSession(nextSession), clonePlayer(nextPlayer), nil
}

func (s *Store) Snapshot() (players int, activeSessions int) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, session := range s.db.Sessions {
		if session.Status == "active" || session.Status == "awaiting_choice" {
			activeSessions++
		}
	}
	return len(s.db.Players), activeSessions
}

func newIDValue(prefix string) (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("generate id: %w", err)
	}
	return fmt.Sprintf("%s_%s", prefix, hex.EncodeToString(buf)), nil
}

func normalizePlayer(p *model.Player) {
	if p.Capacity <= 0 {
		p.Capacity = 5
	}
	if p.InkMarks < 0 {
		p.InkMarks = 0
	}
	if p.Erosion < 0 {
		p.Erosion = 0
	}
	if p.Erosion > 100 {
		p.Erosion = 100
	}
	if p.UnlockedChapters == nil {
		p.UnlockedChapters = []string{"prologue"}
	}
	if p.CompletedEvents == nil {
		p.CompletedEvents = make(map[string]model.EventResult)
	}
	if p.Memories == nil {
		p.Memories = make([]model.Memory, 0)
	}
	if p.MemoryLedger == nil {
		p.MemoryLedger = make([]model.LedgerEntry, 0)
	}
}

func clonePlayer(p model.Player) model.Player {
	normalizePlayer(&p)
	if p.UnlockedChapters != nil {
		p.UnlockedChapters = append([]string{}, p.UnlockedChapters...)
	}
	if p.CompletedEvents != nil {
		p.CompletedEvents = make(map[string]model.EventResult, len(p.CompletedEvents))
		for k, v := range p.CompletedEvents {
			p.CompletedEvents[k] = v
		}
	}
	if p.Memories != nil {
		p.Memories = append([]model.Memory{}, p.Memories...)
	}
	if p.MemoryLedger != nil {
		p.MemoryLedger = append([]model.LedgerEntry{}, p.MemoryLedger...)
	}
	return p
}

func cloneSession(s model.EventSession) model.EventSession {
	if s.PendingMemory != nil {
		m := *s.PendingMemory
		s.PendingMemory = &m
	}
	if s.PendingResult != nil {
		r := *s.PendingResult
		s.PendingResult = &r
	}
	return s
}
