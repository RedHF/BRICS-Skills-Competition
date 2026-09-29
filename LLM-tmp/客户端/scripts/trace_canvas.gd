extends Control

signal stroke_finished
var spec: Dictionary
var step_id := ""
var strokes: Array = []
var failed: Array = []
var active := 0
var drawing := false
var locked := false
var canvas_rect := Rect2()
var view_x := 0.0
var characters := 1
var brush_position := Vector2.ZERO
var brush_visible := false
var glyph: Texture2D

const PAPER = preload("res://assets/puzzles/xuan_paper.png")
const HINT = preload("res://assets/puzzles/hint_plaque.png")
const BRUSH = preload("res://assets/puzzles/brush_cursor.png")
const CINNABAR = preload("res://assets/puzzles/cinnabar_seal.png")
const JADE = preload("res://assets/puzzles/jade_seal.png")

func _ready() -> void:
	custom_minimum_size = Vector2(0, 350)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	characters = ceili(float(spec.aspect_ratio) / 1.2)
	glyph = load("res://assets/puzzles/glyph_" + step_id + ".png") as Texture2D
	for stroke in spec.strokes: strokes.append([])
	select_stroke(0)

func select_stroke(index: int) -> void:
	active = index
	drawing = false
	view_x = floorf(float(spec.strokes[index][0][0]) * characters) / characters
	queue_redraw()
	stroke_finished.emit()

func _draw() -> void:
	var height := minf(size.y - 58, (size.x - 54) / (float(spec.aspect_ratio) / characters))
	canvas_rect = Rect2((size - Vector2(height * float(spec.aspect_ratio) / characters, height)) / 2, Vector2(height * float(spec.aspect_ratio) / characters, height))
	draw_style_box(preload("res://scripts/ink_theme.gd").surface("paper"), Rect2(Vector2.ZERO, size))
	draw_texture_rect(PAPER, canvas_rect, false)
	var plaque := Rect2(Vector2(canvas_rect.position.x, canvas_rect.position.y - 37), Vector2(minf(canvas_rect.size.x, 380), 31))
	draw_texture_rect(HINT, plaque, false, Color(1, 1, 1, .35))
	draw_string(ThemeDB.fallback_font, plaque.position + Vector2(12, 22), "第 %02d 笔 · 青印起笔，朱印收锋" % [active + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#6d6860"))
	if glyph != null:
		var source := Rect2(Vector2(glyph.get_width() * view_x, 0), Vector2(glyph.get_width() / characters, glyph.get_height()))
		draw_texture_rect_region(glyph, canvas_rect, source, Color(1, 1, 1, .63))
	for i in range(spec.strokes.size()):
		if floorf(float(spec.strokes[i][0][0]) * characters) / characters != view_x: continue
		if i == active:
			var first: Array = spec.strokes[i][0]
			var last: Array = spec.strokes[i][-1]
			var start := canvas_rect.position + Vector2((float(first[0]) - view_x) * characters, float(first[1])) * canvas_rect.size
			var finish := canvas_rect.position + Vector2((float(last[0]) - view_x) * characters, float(last[1])) * canvas_rect.size
			draw_texture_rect(JADE, Rect2(start - Vector2.ONE * 17, Vector2.ONE * 34), false)
			draw_texture_rect(CINNABAR, Rect2(finish - Vector2.ONE * 16, Vector2.ONE * 32), false, Color(1, 1, 1, .85))
		var ink := PackedVector2Array()
		for sample in strokes[i]:
			ink.append(canvas_rect.position + Vector2((float(sample[0]) - view_x) * characters, float(sample[1])) * canvas_rect.size)
		if ink.size() > 1:
			draw_polyline(ink, Color(0.05, 0.11, 0.12, 0.18), 8, true)
			draw_polyline(ink, Color("#a83f3f") if failed.has(i) else Color("#203b3b"), 5, true)
	if brush_visible and canvas_rect.has_point(brush_position):
		# The tip of the painted brush sits at the pointer's bottom-left corner.
		draw_texture_rect(BRUSH, Rect2(brush_position + Vector2(-2, -88), Vector2(86, 86)), false)

func _gui_input(event: InputEvent) -> void:
	if locked: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		brush_position = event.position
		brush_visible = canvas_rect.has_point(event.position)
		if event.pressed and canvas_rect.has_point(event.position):
			drawing = true
			strokes[active] = []
			failed.erase(active)
			_sample(event.position)
		elif not event.pressed and drawing:
			_sample(event.position)
			drawing = false
			for i in range(strokes.size()):
				if strokes[i].is_empty():
					select_stroke(i)
					break
			stroke_finished.emit()
			queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		brush_position = event.position
		brush_visible = canvas_rect.has_point(event.position)
		if drawing: _sample(event.position)
		else: queue_redraw()
		accept_event()

func _sample(position: Vector2) -> void:
	var point := (position - canvas_rect.position) / canvas_rect.size
	point.x = point.x / characters + view_x
	var stroke: Array = strokes[active]
	if not stroke.is_empty():
		var previous := Vector2(stroke[-1][0], stroke[-1][1])
		var count := ceili(previous.distance_to(point) / 0.012)
		for i in range(1, count):
			var between := previous.lerp(point, float(i) / count)
			stroke.append([between.x, between.y])
	stroke.append([point.x, point.y])
	queue_redraw()
