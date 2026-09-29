extends VBoxContainer

# Keeps the investigation scene alive; opening or closing a story never resets clues.
var host: Node
var beats: Array = []
var event_id := ""
var cursor := 0
var panel: VBoxContainer
var caption: Label
var counter: Label
var previous: Button
var following: Button

func _ready() -> void:
	host._button(self, "聆听往事（可选）", open_story)
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	add_child(panel)
	counter = host._label(panel, "", 16, Color("#e4c98a"))
	caption = host._label(panel, "", 21)
	var paging := HBoxContainer.new()
	panel.add_child(paging)
	previous = host._button(paging, "上一段", func(): show_beat(cursor - 1))
	following = host._button(paging, "下一段", func(): show_beat(cursor + 1))
	var playback := HBoxContainer.new()
	panel.add_child(playback)
	host._button(playback, "重听本段", func(): show_beat(cursor))
	host._button(playback, "收起往事", func():
		host._stop_voice()
		panel.hide())
	panel.hide()

func open_story() -> void:
	panel.show()
	show_beat(cursor)
	host.scroll.ensure_control_visible(caption)

func show_beat(index: int) -> void:
	if beats.is_empty():
		caption.text = "这段往事尚未记入檐下谱。"
		previous.disabled = true
		following.disabled = true
		return
	cursor = clampi(index, 0, beats.size() - 1)
	caption.text = str(beats[cursor])
	counter.text = "往事 · %d / %d　（可随时收起）" % [cursor + 1, beats.size()]
	previous.disabled = cursor == 0
	following.disabled = cursor == beats.size() - 1
	var cue := event_id + "_beat_%02d" % (cursor + 1)
	host._play_cues([cue])
	if not host.event_audio.playing:
		counter.text += " · 文字阅读"
