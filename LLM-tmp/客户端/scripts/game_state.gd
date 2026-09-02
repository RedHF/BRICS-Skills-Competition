extends Node

## Runtime progression owned by the server when online. The local values are
## intentionally in-memory only: they make the demo playable without a server
## while avoiding a second client-side save format that could diverge from the
## authoritative model.

signal player_changed(player: Dictionary)
signal connection_changed(online: bool, message: String)

var online := false
var connection_message := "等待连接"
var player: Dictionary = {}
var session_id := ""
var current_chapter_id := "prologue"
var current_event_id := "prologue_bridge"
var memory_ledger: Array = []

func _ready() -> void:
	reset_local()

func reset_local() -> void:
	player = {
		"id": "offline-demo",
		"display_name": "无名拓印师",
		"ink_marks": 0,
		"capacity": 5,
		"erosion": 0,
		"unlocked_chapters": ["prologue", "temple"],
		"completed_events": {},
		"memories": [],
		"memory_ledger": [],
		"last_sequence": 0
	}
	memory_ledger = []
	session_id = ""

func set_connection(is_online: bool, message: String) -> void:
	online = is_online
	connection_message = message
	connection_changed.emit(is_online, message)

func apply_player(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	player = snapshot.duplicate(true)
	memory_ledger = player.get("memory_ledger", []).duplicate(true)
	player_changed.emit(player)

func memories() -> Array:
	return player.get("memories", [])

func has_memory(memory_id: String) -> bool:
	for item in memories():
		if str(item.get("id", "")) == memory_id:
			return true
	return false

func forget_memory(memory_id: String, chapter_id: String, event_id: String) -> void:
	var kept: Array = []
	var forgotten_title := memory_id
	var found := false
	for item in memories():
		if str(item.get("id", "")) == memory_id:
			forgotten_title = str(item.get("title", memory_id))
			found = true
		else:
			kept.append(item)
	if not found:
		return
	player["memories"] = kept
	append_ledger(memory_id, forgotten_title, "forgotten", chapter_id, event_id)
	player_changed.emit(player)

func keep_memory(memory: Dictionary, chapter_id: String, event_id: String) -> void:
	var memory_id := str(memory.get("id", ""))
	if memory_id.is_empty() or has_memory(memory_id):
		return
	player["memories"].append(memory)
	append_ledger(memory_id, str(memory.get("title", memory_id)), "kept", chapter_id, event_id)
	player_changed.emit(player)

func append_ledger(memory_id: String, title: String, action: String, chapter_id: String, event_id: String) -> void:
	var entry := {
		"memory_id": memory_id,
		"title": title,
		"action": action,
		"chapter_id": chapter_id,
		"event_id": event_id,
		"occurred_at": Time.get_datetime_string_from_system(true)
	}
	memory_ledger.append(entry)
	player["memory_ledger"] = memory_ledger

func apply_local_reward(event: Dictionary, choice: String) -> void:
	var reward: Dictionary = event.get("reward", {})
	var memory: Dictionary = reward.get("memory", {})
	var capacity := int(player.get("capacity", 5))
	var memory_cost := int(memory.get("capacity", 1))
	var forget_id := ""
	if choice.begins_with("forget:"):
		forget_id = choice.trim_prefix("forget:")
	elif has_memory(choice):
		forget_id = choice
	if not forget_id.is_empty():
		forget_memory(forget_id, current_chapter_id, current_event_id)
	var used := 0
	for held in memories():
		used += int(held.get("capacity", 1))
	if used + memory_cost <= capacity:
		keep_memory(memory, current_chapter_id, current_event_id)
	player["ink_marks"] = int(player.get("ink_marks", 0)) + int(reward.get("base_ink_marks", 0))
	player["capacity"] = capacity + int(reward.get("capacity_increase", 0))
	player_changed.emit(player)
