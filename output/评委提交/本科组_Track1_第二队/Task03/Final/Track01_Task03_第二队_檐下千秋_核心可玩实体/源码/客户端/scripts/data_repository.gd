class_name DataRepository
extends RefCounted

var catalog: Dictionary

const RUBBING_DIR := "res://assets/rubbings/"

func _memory_catalog(id: String) -> Dictionary:
	if catalog.is_empty(): return {}
	var memories = catalog.get("memories", {})
	if memories is Dictionary and memories.has(id) and memories[id] is Dictionary:
		return memories[id]
	return {}

func memory(id: String) -> Dictionary:
	return _memory_catalog(id)

func memory_image_path(id: String) -> String:
	var item := _memory_catalog(id)
	var declared := str(item.get("image", ""))
	if not declared.is_empty() and ResourceLoader.exists(declared): return declared
	var fallback := RUBBING_DIR + id + ".svg"
	if ResourceLoader.exists(fallback): return fallback
	return ""

func event(chapter_id: String, event_id: String) -> Dictionary:
	for chapter in catalog.get("chapters", []):
		if chapter.id == chapter_id:
			for item in chapter.events:
				if item.id == event_id: return item
	push_error("Unknown event: %s/%s" % [chapter_id, event_id])
	return {}
