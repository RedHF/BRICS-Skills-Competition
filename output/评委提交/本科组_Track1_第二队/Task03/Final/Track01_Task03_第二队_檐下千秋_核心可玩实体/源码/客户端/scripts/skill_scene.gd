extends Control

signal applied(skill: String, target: String)
var selected := ""
var accepted: Array = []
var locked := false
var anchors := {"beam": Vector2(.24, .57), "bell": Vector2(.79, .31), "inscription": Vector2(.66, .75)}

const PAPER = preload("res://assets/puzzles/xuan_paper.png")
const BEAM = preload("res://assets/puzzles/mortise_beam.png")
const BRACKET = preload("res://assets/puzzles/dougong_bracket.png")
const BELL = preload("res://assets/puzzles/wind_bell.png")
const TABLET = preload("res://assets/puzzles/stone_tablet.png")
const MARKER = preload("res://assets/puzzles/mortise_marker.png")
const CAISSON = preload("res://assets/vfx/caisson_rosette.png")

func _ready() -> void:
	custom_minimum_size.y = 280
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if locked or selected.is_empty(): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for target in anchors:
			if event.position.distance_to(anchors[target] * size) < 49:
				applied.emit(selected, target)
				accept_event()
				return

func _draw() -> void:
	draw_texture_rect(PAPER, Rect2(Vector2.ZERO, size), false)
	var supported := accepted.has("craftsman_anchor") or accepted.has("tower_anchor")
	var triggered := accepted.has("craftsman_trigger")
	var purged := accepted.has("tower_purify") or accepted.has("drum_purify")
	var beam: Vector2 = anchors.beam * size
	var bell: Vector2 = anchors.bell * size
	var tablet: Vector2 = anchors.inscription * size
	draw_texture_rect(BEAM, Rect2(beam + Vector2(-100, -105 if supported else -86), Vector2(210, 95)), false)
	draw_texture_rect(BRACKET, Rect2(beam - Vector2(53, 42), Vector2(106, 105)), false, Color(1, 1, 1, 1.0 if supported else .58))
	draw_texture_rect(BELL, Rect2(bell - Vector2(42, 65), Vector2(84, 113)), false, Color(1, 1, 1, 1.0 if triggered else .58))
	draw_texture_rect(TABLET, Rect2(tablet - Vector2(48, 58), Vector2(96, 115)), false)
	if purged: draw_texture_rect(CAISSON, Rect2(tablet - Vector2(55, 55), Vector2(110, 110)), false, Color(1, 1, 1, .54))
	for target in anchors:
		var point: Vector2 = anchors[target] * size
		draw_texture_rect(MARKER, Rect2(point - Vector2.ONE * 46, Vector2.ONE * 92), false, Color(1, 1, 1, .25))
		var caption: String = {"beam":"承重斗拱", "bell":"远端风铃", "inscription":"白蚀碑面"}[target]
		draw_string(preload("res://scripts/ink_theme.gd").font(), point + Vector2(-48, 69), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#303832"))
	var state := "梁架已稳，连杆接通" if supported else "梁架倾斜，连杆尚未受力"
	if triggered: state = "风铃已响，匠人的刻痕重现"
	if purged: state = "白斑消退，刻痕显影"
	draw_string(preload("res://scripts/ink_theme.gd").font(), Vector2(14, 25), state, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#303832"))
