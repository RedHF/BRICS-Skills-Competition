extends Control

signal investigated
var erosion := 0
var forgotten := false
var bridge := false
var interactive := false
var tint := Color("#a38c63")
var player := Vector2(0.48, 0.78)
var target := player
var ripple := 0.0
var joystick := Vector2.ZERO
var dragging_stick := false
var purification := 0.0

func _ready() -> void:
	custom_minimum_size.y = 240 if interactive else 140
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	ripple = fmod(ripple + delta, 2.0)
	if interactive:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down") + joystick
		if direction.length() > 0:
			player += Vector2(direction.x, direction.y * 0.65).limit_length() * delta * 0.5
			target = player
		else: player = player.move_toward(target, delta * 0.5)
		player = player.clamp(Vector2(0.08, 0.52), Vector2(0.92, 0.9))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.distance_to(Vector2(48, size.y - 45)) < 38:
				dragging_stick = true
			elif event.position.distance_to(size * Vector2(0.55, 0.50)) < 42:
				target = Vector2(0.55, 0.65)
				investigated.emit()
			else: target = (event.position / size).clamp(Vector2(0.08, 0.52), Vector2(0.92, 0.9))
		else:
			dragging_stick = false
			joystick = Vector2.ZERO
		accept_event()
	elif event is InputEventMouseMotion and dragging_stick:
		joystick = ((event.position - Vector2(48, size.y - 45)) / 30.0).limit_length()
		accept_event()

func _draw() -> void:
	var fade := float(erosion) / 100.0
	var ink := tint.lerp(Color("#888e8b"), 1.0 if forgotten else fade)
	var floor_points := PackedVector2Array([Vector2(.06,.68),Vector2(.5,.40),Vector2(.94,.68),Vector2(.5,.94)])
	for i in range(floor_points.size()): floor_points[i] *= size
	draw_colored_polygon(floor_points, Color("#344440").lerp(Color("#565953"), fade))
	for i in range(6):
		var x := size.x * (0.22 + i * 0.11)
		var drop := (sin(ripple * PI + i) + 1) * 4 if erosion >= 40 and i % 2 == 0 else 0.0
		if erosion >= 70 and i % 2 == 0:
			draw_line(Vector2(x, size.y * .73), Vector2(x + 18, size.y * .80), ink, 6)
		else:
			draw_line(Vector2(x, size.y * .34 + drop), Vector2(x, size.y * .67), ink, 7)
			if erosion >= 40:
				draw_polyline(PackedVector2Array([Vector2(x-4,size.y*.46),Vector2(x+4,size.y*.48),Vector2(x-3,size.y*.51)]), Color("#17282a"), 2)
	if erosion < 70:
		var roof := PackedVector2Array([Vector2(.12,.36),Vector2(.25,.26),Vector2(.49,.12),Vector2(.76,.25),Vector2(.9,.35),Vector2(.58,.4)])
		for i in range(roof.size()): roof[i] *= size
		draw_colored_polygon(roof, ink.darkened(.35))
		draw_polyline(roof, ink, 3, true)
	else:
		for i in range(7): draw_rect(Rect2(size * Vector2(.22+i*.085,.65+i%2*.05), Vector2(24,9)), ink.darkened(.3))
	if bridge:
		draw_line(size*Vector2(.12,.70),size*Vector2(.84,.70),ink,5)
		draw_line(size*Vector2(.18,.76),size*Vector2(.91,.76),ink,4)
	if purification > 0:
		for i in range(8): draw_circle(size*Vector2(.25+i*.065,.43+sin(i)*.1), 12, Color(0.05,0.08,0.09,purification*.85))
	if interactive:
		var point := size * Vector2(.55,.50)
		draw_circle(point, 12, Color("#e4c98a"))
		draw_arc(point, 18+ripple*10, 0, TAU, 40, Color(0.9,.78,.5,1-ripple/2),2,true)
		draw_string(ThemeDB.fallback_font, point + Vector2(-32,-22), "点击调查", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#f4e4bc"))
		draw_circle(player*size, 10, Color("#dce6d8"))
		draw_line(player*size,player*size+Vector2(12,15),Color("#e4c98a"),3)
		draw_circle(Vector2(48,size.y-45),34,Color(.8,.85,.8,.14))
		draw_circle(Vector2(48,size.y-45)+joystick*23,12,Color("#a9b9a5"))
