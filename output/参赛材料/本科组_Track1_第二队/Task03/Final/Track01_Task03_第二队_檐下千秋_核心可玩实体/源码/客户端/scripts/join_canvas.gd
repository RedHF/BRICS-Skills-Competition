extends Control

signal placed(answer: String)
var options: Array = []
var step_id := ""
var dragging := false
var piece := Vector2.ZERO
var snapped := false
var locked := false

const PAPER = preload("res://assets/puzzles/xuan_paper.png")
const BEAM = preload("res://assets/puzzles/mortise_beam.png")
const TENON = preload("res://assets/puzzles/tenon_piece.png")
const SOCKET = preload("res://assets/puzzles/mortise_marker.png")
const HINT = preload("res://assets/puzzles/hint_plaque.png")
const STAGE_FLOOR = preload("res://assets/puzzles/stage_floor.png")
const STAGE_PIECE = preload("res://assets/puzzles/stage_step_piece.png")
const BACKDROP_RAIL = preload("res://assets/puzzles/backdrop_rail.png")
const BROCADE = preload("res://assets/puzzles/brocade_panel.png")
const LOTUS = preload("res://assets/puzzles/lotus_marker.png")

func _ready() -> void:
	custom_minimum_size.y = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func():
		if not dragging and not snapped: piece = Vector2(size.x / 2, 168)
		queue_redraw())
	piece = Vector2(size.x / 2, 168)

func _draw() -> void:
	draw_texture_rect(PAPER, Rect2(Vector2.ZERO, size), false)
	var stage := step_id in ["stage_step", "stage_backdrop"]
	var base_art := (STAGE_FLOOR if step_id == "stage_step" else BACKDROP_RAIL) if stage else BEAM
	var piece_art := (STAGE_PIECE if step_id == "stage_step" else BROCADE) if stage else TENON
	var marker_art := LOTUS if stage else SOCKET
	draw_texture_rect(base_art, Rect2(Vector2(12, 12), Vector2(size.x - 24, 116)), false)
	for i in range(options.size()):
		var center := _socket_center(i)
		draw_texture_rect(marker_art, Rect2(center - Vector2(34, 25), Vector2(68, 50)), false, Color(1, 1, 1, .62))
		var caption: String = {"left":"左榫口","center":"中央承重","right":"右榫口"}.get(options[i], options[i])
		draw_string(preload("res://scripts/ink_theme.gd").font(), center + Vector2(-34, -33), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#303832"))
	draw_texture_rect(piece_art, Rect2(piece - Vector2(54, 45), Vector2(108, 90)), false, Color("#e2f3df") if snapped else Color.WHITE)
	draw_texture_rect(HINT, Rect2(Vector2(12, size.y - 35), Vector2(size.x - 24, 30)), false, Color(1, 1, 1, .3))
	var instruction := "拖动戏台构件到对应位置，松手吸附。" if stage else "拖动木榫到榫口，松手吸附；放到外侧可取消。"
	draw_string(preload("res://scripts/ink_theme.gd").font(), Vector2(22, size.y - 15), instruction, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#60564b"))

func _gui_input(event: InputEvent) -> void:
	if locked: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Rect2(piece-Vector2(54,45),Vector2(108,90)).has_point(event.position):
			dragging = true
			snapped = false
		elif not event.pressed and dragging:
			dragging = false
			for i in range(options.size()):
				var center := _socket_center(i)
				if event.position.distance_to(center) <= 52:
					piece = center
					snapped = true
					locked = true
					placed.emit(options[i])
					break
			if not snapped: piece = Vector2(size.x/2,168)
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		piece = event.position.clamp(Vector2(30,30),size-Vector2(30,30))
		queue_redraw()
		accept_event()

func _socket_center(index: int) -> Vector2:
	var name := str(options[index])
	var x := 0.52
	if name in ["left", "左"]: x = .34
	elif name in ["right", "右"]: x = .72
	elif name in ["center", "中"]: x = .53
	elif options.size() > 1: x = [.25, .52, .78][mini(index, 2)] if step_id == "stage_step" else [.34, .53, .72][mini(index, 2)]
	return Vector2(size.x * x, 65)
