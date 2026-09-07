extends Control

signal placed(answer: String)
var options: Array = []
var dragging := false
var piece := Vector2.ZERO
var snapped := false
var locked := false

func _ready() -> void:
	custom_minimum_size.y = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func():
		if not dragging and not snapped: piece = Vector2(size.x / 2, 168)
		queue_redraw())
	piece = Vector2(size.x / 2, 168)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#192f33"))
	draw_rect(Rect2(12,55,size.x-24,22),Color("#796649"))
	for i in range(options.size()):
		var center := Vector2(size.x * (i + 0.5) / options.size(), 65)
		draw_rect(Rect2(center-Vector2(33,22),Vector2(66,44)),Color("#d6bd85"),false,3)
		var caption: String = {"left":"左榫口","center":"中央承重","right":"右榫口"}[options[i]]
		draw_string(ThemeDB.fallback_font,center+Vector2(-33,-31),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("#e4c98a"))
	var shape := PackedVector2Array([Vector2(-27,-17),Vector2(-14,-17),Vector2(-20,-29),Vector2(20,-29),Vector2(14,-17),Vector2(27,-17),Vector2(27,17),Vector2(-27,17)])
	for i in range(shape.size()): shape[i] += piece
	draw_colored_polygon(shape,Color("#9ad5ad") if snapped else Color("#c9a36b"))
	draw_string(ThemeDB.fallback_font,Vector2(16,207),"拖动构件到榫口，松手吸附；放到外侧可取消。",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("#cbd9cf"))

func _gui_input(event: InputEvent) -> void:
	if locked: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Rect2(piece-Vector2(38,38),Vector2(76,76)).has_point(event.position):
			dragging = true
			snapped = false
		elif not event.pressed and dragging:
			dragging = false
			for i in range(options.size()):
				var center := Vector2(size.x * (i + .5) / options.size(),65)
				if event.position.distance_to(center) <= 44:
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
