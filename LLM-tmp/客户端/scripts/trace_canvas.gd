extends Control

signal stroke_finished
var spec: Dictionary
var strokes: Array = []
var failed: Array = []
var active := 0
var drawing := false
var locked := false
var canvas_rect := Rect2()
var view_x := 0.0
var characters := 1

func _ready() -> void:
	custom_minimum_size = Vector2(0, 350)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	characters = ceili(float(spec.aspect_ratio) / 1.2)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color("#10272b"))
	draw_rect(Rect2(canvas_rect.position + Vector2(7, 8), canvas_rect.size), Color(0.01, 0.04, 0.05, 0.34))
	draw_rect(canvas_rect, Color("#eee1bf"))
	draw_rect(canvas_rect.grow(-7), Color("#b69557"), false, 2.0)
	for i in range(1, 4):
		var grid_color := Color(0.34, 0.42, 0.39, 0.11)
		draw_line(Vector2(canvas_rect.position.x + canvas_rect.size.x * i / 4.0, canvas_rect.position.y + 8), Vector2(canvas_rect.position.x + canvas_rect.size.x * i / 4.0, canvas_rect.end.y - 8), grid_color, 1.0)
		draw_line(Vector2(canvas_rect.position.x + 8, canvas_rect.position.y + canvas_rect.size.y * i / 4.0), Vector2(canvas_rect.end.x - 8, canvas_rect.position.y + canvas_rect.size.y * i / 4.0), grid_color, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(canvas_rect.position.x, canvas_rect.position.y - 12), "当前第 %02d 笔 · 由青印起笔，向朱印收锋" % [active + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#e4c98a"))
	for i in range(spec.strokes.size()):
		if floorf(float(spec.strokes[i][0][0]) * characters) / characters != view_x: continue
		var points := PackedVector2Array()
		for point in spec.strokes[i]: points.append(canvas_rect.position + Vector2((point[0] - view_x) * characters, point[1]) * canvas_rect.size)
		var color := Color(0.24, 0.31, 0.29, 0.30)
		if failed.has(i): color = Color("#b94c49")
		elif not strokes[i].is_empty(): color = Color("#67967d")
		if i == active:
			var radius := float(spec.tolerance) * canvas_rect.size.y
			draw_polyline(points, Color(0.70, 0.56, 0.28, 0.18), radius * 2, true)
			color = Color("#b94c49") if failed.has(i) else Color("#98753a")
		draw_polyline(points, color, 3, true)
		if i == active:
			draw_circle(points[0], 10, Color("#4f9b78"))
			draw_circle(points[0], 4, Color("#edf1d8"))
			draw_circle(points[-1], 9, Color("#b85e48"))
			draw_circle(points[-1], 3, Color("#f5dfbd"))
		var ink := PackedVector2Array()
		for point in strokes[i]: ink.append(canvas_rect.position + Vector2((point[0] - view_x) * characters, point[1]) * canvas_rect.size)
		if ink.size() > 1:
			draw_polyline(ink, Color(0.05, 0.11, 0.12, 0.18), 8, true)
			draw_polyline(ink, Color("#a83f3f") if failed.has(i) else Color("#203b3b"), 5, true)

func _gui_input(event: InputEvent) -> void:
	if locked: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
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
	elif event is InputEventMouseMotion and drawing:
		_sample(event.position)
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
