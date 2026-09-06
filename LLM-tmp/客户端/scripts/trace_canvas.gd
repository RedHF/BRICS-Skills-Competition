extends Control

signal stroke_finished
var spec: Dictionary
var strokes: Array = []
var drawing := false
var locked := false
var canvas_rect := Rect2()

func _ready() -> void:
	custom_minimum_size = Vector2(620, 300)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	var height := minf(size.y - 36, (size.x - 40) / float(spec.aspect_ratio))
	var canvas_size := Vector2(height * float(spec.aspect_ratio), height)
	canvas_rect = Rect2((size - canvas_size) / 2, canvas_size)
	draw_style_box(get_theme_stylebox("normal", "TextEdit"), Rect2(Vector2.ZERO, size))
	for i in range(spec.strokes.size()):
		var color := Color("#758079")
		if i == strokes.size() - (1 if drawing else 0): color = Color("#e4c98a")
		var points := PackedVector2Array()
		for p in spec.strokes[i]: points.append(canvas_rect.position + Vector2(p[0], p[1]) * canvas_rect.size)
		if i == strokes.size() - (1 if drawing else 0):
			var radius := float(spec.tolerance) * canvas_rect.size.y
			draw_polyline(points, Color(0.9, 0.77, 0.5, 0.16), radius * 2, true)
			for point in points: draw_circle(point, radius, Color(0.9, 0.77, 0.5, 0.16))
		draw_polyline(points, color, 4, true)
		if i == strokes.size() - (1 if drawing else 0):
			draw_circle(points[0], 9, Color("#9ad5ad"))
			draw_circle(points[-1], 5, Color("#e6a275"))
	for stroke in strokes:
		var points := PackedVector2Array()
		for p in stroke: points.append(canvas_rect.position + Vector2(p[0], p[1]) * canvas_rect.size)
		if points.size() > 1: draw_polyline(points, Color("#f0dfb0"), 3, true)

func _gui_input(event: InputEvent) -> void:
	if locked: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and strokes.size() < spec.strokes.size() and canvas_rect.has_point(event.position):
			drawing = true
			strokes.append([])
			_sample(event.position)
		elif not event.pressed and drawing:
			_sample(event.position)
			drawing = false
			stroke_finished.emit()
		accept_event()
	elif event is InputEventMouseMotion and drawing:
		_sample(event.position)
		accept_event()

func _sample(position: Vector2) -> void:
	var p := (position - canvas_rect.position) / canvas_rect.size
	# Preserve out-of-bounds input; the server must see the deviation.
	var stroke: Array = strokes[-1]
	if not stroke.is_empty():
		var previous := Vector2(stroke[-1][0], stroke[-1][1])
		var count := ceili(previous.distance_to(p) / 0.012)
		for i in range(1, count):
			var between := previous.lerp(p, float(i) / count)
			stroke.append([between.x, between.y])
	stroke.append([p.x, p.y])
	queue_redraw()
