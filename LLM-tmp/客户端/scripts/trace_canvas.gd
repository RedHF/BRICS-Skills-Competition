extends Control

signal stroke_finished
signal brush_touched
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
var glyph_strokes: Array[Texture2D] = []

const PAPER = preload("res://assets/puzzles/xuan_paper.png")
const HINT = preload("res://assets/puzzles/hint_plaque.png")
const BRUSH = preload("res://assets/puzzles/brush_cursor.png")
const CINNABAR = preload("res://assets/puzzles/cinnabar_seal.png")
const JADE = preload("res://assets/puzzles/jade_seal.png")
const INK_DAB = preload("res://assets/puzzles/ink_dab.png")
const INK_DAB_RED = preload("res://assets/puzzles/ink_dab_red.png")

func _ready() -> void:
	custom_minimum_size = Vector2(0, 220)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	characters = ceili(float(spec.aspect_ratio) / 1.2)
	glyph = load("res://assets/puzzles/glyph_" + step_id + ".png") as Texture2D
	for i in range(spec.strokes.size()):
		glyph_strokes.append(load("res://assets/puzzles/glyph_%s_%d.png" % [step_id, i]) as Texture2D)
	for stroke in spec.strokes: strokes.append([])
	select_stroke(0)

func _guide_samples(index: int) -> Array:
	var samples: Array = []
	var guide: Array = spec.strokes[index]
	for segment in range(1,guide.size()):
		var a := Vector2(float(guide[segment-1][0]),float(guide[segment-1][1]))
		var b := Vector2(float(guide[segment][0]),float(guide[segment][1]))
		var steps := maxi(2,ceili(a.distance_to(b)/.008))
		for point in range(steps):
			var p := a.lerp(b,float(point)/steps)
			samples.append([p.x,p.y])
	var last: Array = guide[-1]
	samples.append([float(last[0]),float(last[1])])
	return samples

func auto_complete() -> void:
	for i in range(strokes.size()): strokes[i] = _guide_samples(i)
	queue_redraw()

func completed_strokes() -> int:
	var count := 0
	for stroke in strokes:
		if not stroke.is_empty(): count += 1
	return count

func select_adjacent(direction: int) -> void:
	select_stroke(clampi(active+direction,0,strokes.size()-1))

func select_stroke(index: int) -> void:
	active = index
	drawing = false
	view_x = floorf(float(spec.strokes[index][0][0]) * characters) / characters
	queue_redraw()
	stroke_finished.emit()

func _draw() -> void:
	var height := minf(size.y - 90, (size.x - 54) / (float(spec.aspect_ratio) / characters))
	canvas_rect = Rect2((size - Vector2(height * float(spec.aspect_ratio) / characters, height)) / 2, Vector2(height * float(spec.aspect_ratio) / characters, height))
	draw_style_box(preload("res://scripts/ink_theme.gd").surface("paper"), Rect2(Vector2.ZERO, size))
	draw_texture_rect(PAPER, canvas_rect, false)
	var plaque := Rect2(Vector2(canvas_rect.position.x, canvas_rect.position.y - 37), Vector2(minf(canvas_rect.size.x, 380), 31))
	draw_texture_rect(HINT, plaque, false, Color(1, 1, 1, .35))
	draw_string(preload("res://scripts/ink_theme.gd").font(), plaque.position + Vector2(12, 22), "%s · 第 %d / %d 笔 · 青印起笔，朱印收锋" % [str(spec.get("glyph", "拓印")),active+1,strokes.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#5c5145"))
	var untouched := completed_strokes() == 0
	if untouched and glyph != null:
		_draw_glyph(glyph)
	for i in range(spec.strokes.size()):
		if floorf(float(spec.strokes[i][0][0]) * characters) / characters != view_x: continue
		if not untouched and strokes[i].is_empty() and i < glyph_strokes.size() and glyph_strokes[i] != null:
			_draw_glyph(glyph_strokes[i])
		if drawing and i == active and not strokes[i].is_empty():
			var guide := PackedVector2Array()
			for vertex in spec.strokes[i]:
				guide.append(canvas_rect.position + Vector2((float(vertex[0])-view_x)*characters,float(vertex[1]))*canvas_rect.size)
			var last: Array = strokes[i][-1]
			var tip := canvas_rect.position + Vector2((float(last[0])-view_x)*characters,float(last[1]))*canvas_rect.size
			var tail := _remaining_guide(guide, tip)
			if tail.size() > 1: _draw_guide_stroke(tail, true)
		if i == active and strokes[i].is_empty():
			var first: Array = spec.strokes[i][0]
			var last: Array = spec.strokes[i][-1]
			var start := canvas_rect.position + Vector2((float(first[0]) - view_x) * characters, float(first[1])) * canvas_rect.size
			var finish := canvas_rect.position + Vector2((float(last[0]) - view_x) * characters, float(last[1])) * canvas_rect.size
			draw_texture_rect(JADE, Rect2(start - Vector2.ONE * 11, Vector2.ONE * 22), false, Color(1, 1, 1, .8))
			draw_texture_rect(CINNABAR, Rect2(finish - Vector2.ONE * 10, Vector2.ONE * 20), false, Color(1, 1, 1, .75))
		var ink := PackedVector2Array()
		for sample in strokes[i]:
			ink.append(canvas_rect.position + Vector2((float(sample[0]) - view_x) * characters, float(sample[1])) * canvas_rect.size)
		if ink.size() > 1:
			_draw_ink_stroke(ink, failed.has(i))
	if brush_visible and canvas_rect.has_point(brush_position):
		# The tip of the painted brush sits at the pointer's bottom-left corner.
		draw_texture_rect(BRUSH, Rect2(brush_position + Vector2(-2, -88), Vector2(86, 86)), false)

func _draw_glyph(texture: Texture2D) -> void:
	var source := Rect2(Vector2(texture.get_width() * view_x, 0), Vector2(texture.get_width() / characters, texture.get_height()))
	draw_texture_rect_region(texture, canvas_rect, source, Color(1, 1, 1, .63))

func _draw_guide_stroke(points: PackedVector2Array, selected: bool) -> void:
	draw_polyline(points, Color("#746b60", .16 if selected else .1), 3, true)
	_draw_brush_marks(points, INK_DAB, .18 if selected else .11, 1.12)

func _draw_ink_stroke(points: PackedVector2Array, invalid: bool) -> void:
	var texture := INK_DAB_RED if invalid else INK_DAB
	draw_polyline(points, Color("#a83f3f", .24) if invalid else Color("#203b3b", .24), 5, true)
	_draw_brush_marks(points, texture, .52, 1.0)

func _draw_brush_marks(points: PackedVector2Array, texture: Texture2D, opacity: float, scale: float) -> void:
	var length_total := 0.0
	for j in range(1, points.size()): length_total += points[j - 1].distance_to(points[j])
	var distance := 0.0
	for j in range(1, points.size()):
		var start := points[j - 1]
		var finish := points[j]
		var length := start.distance_to(finish)
		if length < .1: continue
		var angle := (finish - start).angle() + .95
		var stamps := maxi(1, ceili(length / 3.0))
		for k in range(stamps):
			var along := distance + length * float(k) / float(stamps)
			var taper := minf(1.0, minf(along / 18.0 + .55, (length_total - along) / 24.0 + .4))
			var variation := 1.0 + .1 * sin(along * .18)
			var extent := Vector2(17, 24) * taper * variation * scale
			draw_set_transform(start.lerp(finish, float(k) / float(stamps)), angle)
			draw_texture_rect(texture, Rect2(-extent * .5, extent), false, Color(1, 1, 1, opacity))
		distance += length
	draw_set_transform(Vector2.ZERO)

func _remaining_guide(guide: PackedVector2Array, tip: Vector2) -> PackedVector2Array:
	var nearest_segment := 0
	var nearest_point := guide[0]
	var nearest_distance := INF
	for j in range(1, guide.size()):
		var point := Geometry2D.get_closest_point_to_segment(tip, guide[j - 1], guide[j])
		var distance := tip.distance_squared_to(point)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_segment = j
			nearest_point = point
	var tail := PackedVector2Array([nearest_point])
	for j in range(nearest_segment, guide.size()): tail.append(guide[j])
	return tail

func _gui_input(event: InputEvent) -> void:
	if locked: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		brush_position = event.position
		brush_visible = canvas_rect.has_point(event.position)
		if event.pressed and canvas_rect.has_point(event.position):
			drawing = true
			brush_touched.emit()
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
