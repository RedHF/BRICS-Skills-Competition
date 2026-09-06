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
	custom_minimum_size = Vector2(0, 330)
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
	var height := minf(size.y - 32, (size.x - 32) / (float(spec.aspect_ratio) / characters))
	canvas_rect = Rect2((size - Vector2(height * float(spec.aspect_ratio) / characters, height)) / 2, Vector2(height * float(spec.aspect_ratio) / characters, height))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#192f33"))
	for i in range(spec.strokes.size()):
		if floorf(float(spec.strokes[i][0][0]) * characters) / characters != view_x: continue
		var points := PackedVector2Array()
		for point in spec.strokes[i]: points.append(canvas_rect.position + Vector2((point[0] - view_x) * characters, point[1]) * canvas_rect.size)
		var color := Color("#687d79")
		if failed.has(i): color = Color("#ff8078")
		elif not strokes[i].is_empty(): color = Color("#9ad5ad")
		if i == active:
			var radius := float(spec.tolerance) * canvas_rect.size.y
			draw_polyline(points, Color(0.9, 0.77, 0.5, 0.14), radius * 2, true)
			for point in points: draw_circle(point, radius, Color(0.9, 0.77, 0.5, 0.12))
			color = Color("#ff8078") if failed.has(i) else Color("#e4c98a")
		draw_polyline(points, color, 3, true)
		if i == active:
			draw_circle(points[0], 8, Color("#9ad5ad"))
			draw_circle(points[-1], 5, Color("#e6a275"))
		var ink := PackedVector2Array()
		for point in strokes[i]: ink.append(canvas_rect.position + Vector2((point[0] - view_x) * characters, point[1]) * canvas_rect.size)
		if ink.size() > 1: draw_polyline(ink, Color("#ff8078") if failed.has(i) else Color("#f0dfb0"), 3, true)

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
