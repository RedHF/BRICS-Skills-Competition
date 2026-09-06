class_name DataRepository
extends RefCounted

var catalog: Dictionary

func memory(id: String) -> Dictionary:
	return catalog.memories[id]

func event(chapter_id: String, event_id: String) -> Dictionary:
	for chapter in catalog.chapters:
		if chapter.id == chapter_id:
			for item in chapter.events:
				if item.id == event_id: return item
	assert(false, "Unknown event: %s/%s" % [chapter_id, event_id])
	return {}
