class_name DataRepository
extends RefCounted

## Loads the versioned content catalog. Designers can add chapters, events,
## puzzle kinds, and text in JSON without changing the presentation code.

var catalog: Dictionary = {}
var source_path := ""

func load_catalog(path: String) -> bool:
	source_path = path
	if not FileAccess.file_exists(path):
		push_error("Content catalog not found: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open content catalog: %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or not parsed.has("chapters"):
		push_error("Content catalog has an invalid shape")
		return false
	catalog = parsed
	return true

func chapters() -> Array:
	return catalog.get("chapters", [])

func chapter(chapter_id: String) -> Dictionary:
	for item in chapters():
		if str(item.get("id", "")) == chapter_id:
			return item
	return {}

func event(chapter_id: String, event_id: String) -> Dictionary:
	var current := chapter(chapter_id)
	for item in current.get("events", []):
		if str(item.get("id", "")) == event_id:
			return item
	return {}

func first_chapter() -> Dictionary:
	var sorted := chapters().duplicate()
	sorted.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return sorted[0] if not sorted.is_empty() else {}

func first_event(chapter_id: String) -> Dictionary:
	var current := chapter(chapter_id)
	var events: Array = current.get("events", []).duplicate()
	events.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return events[0] if not events.is_empty() else {}

func next_event(chapter_id: String, event_id: String) -> Dictionary:
	var current := chapter(chapter_id)
	var events: Array = current.get("events", []).duplicate()
	events.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for index in range(events.size()):
		if str(events[index].get("id", "")) == event_id and index + 1 < events.size():
			return events[index + 1]
	return {}

func next_chapter(chapter_id: String) -> Dictionary:
	var current := chapter(chapter_id)
	var next_id := str(current.get("next_chapter", ""))
	return chapter(next_id) if not next_id.is_empty() else {}

func art(event_id: String) -> Dictionary:
	var configured = catalog.get("art", {}).get(event_id, {})
	return configured if configured is Dictionary else {}
