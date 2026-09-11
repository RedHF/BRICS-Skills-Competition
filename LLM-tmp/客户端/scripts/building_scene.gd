extends Control

signal investigated(label: String, found: int, total: int)
var erosion := 0
var forgotten := false
var bridge := false
var interactive := false
var tint := Color("#a38c63")
var background: Texture2D
var investigations: Array = []
var discovered: Array = []
var player := Vector2(0.48, 0.78)
var target := player
var pending_investigation := -1
var ripple := 0.0
var joystick := Vector2.ZERO
var dragging_stick := false
var purification := 0.0

func _ready() -> void:
	custom_minimum_size.y = 430 if interactive else 240
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if investigations.is_empty(): investigations = [{"label":"古建遗痕", "position":[0.55, 0.50]}]

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	ripple = fmod(ripple + delta, 2.0)
	if interactive:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down") + joystick
		if direction.length() > 0:
			pending_investigation = -1
			player += Vector2(direction.x, direction.y * 0.65).limit_length() * delta * 0.5
			target = player
		else: player = player.move_toward(target, delta * 0.5)
		player = player.clamp(Vector2(0.05, 0.16), Vector2(0.95, 0.94))
		if pending_investigation >= 0 and player.distance_to(_investigation_point(pending_investigation)) < 0.035:
			_discover(pending_investigation)
		if Input.is_action_just_pressed("advance"): _investigate_nearest()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.distance_to(Vector2(48, size.y - 45)) < 38:
				dragging_stick = true
			else:
				var selected := -1
				for i in range(investigations.size()):
					if event.position.distance_to(size * _investigation_point(i)) < 38:
						selected = i
						break
				if selected >= 0:
					target = _investigation_point(selected)
					pending_investigation = selected
				else:
					target = (event.position / size).clamp(Vector2(0.05, 0.16), Vector2(0.95, 0.94))
					pending_investigation = -1
		else:
			dragging_stick = false
			joystick = Vector2.ZERO
		accept_event()
	elif event is InputEventMouseMotion and dragging_stick:
		joystick = ((event.position - Vector2(48, size.y - 45)) / 30.0).limit_length()
		accept_event()

func _investigation_point(index: int) -> Vector2:
	var raw: Array = investigations[index].position
	return Vector2(float(raw[0]), float(raw[1]))

func _investigate_nearest() -> void:
	var nearest := -1
	var nearest_distance := 0.12
	for i in range(investigations.size()):
		if discovered.has(i): continue
		var distance := player.distance_to(_investigation_point(i))
		if distance < nearest_distance:
			nearest = i
			nearest_distance = distance
	if nearest >= 0: _discover(nearest)

func _discover(index: int) -> void:
	pending_investigation = -1
	if discovered.has(index): return
	discovered.append(index)
	investigated.emit(str(investigations[index].label), discovered.size(), investigations.size())
	queue_redraw()

func _draw() -> void:
	var fade := float(erosion) / 100.0
	var ink := tint.lerp(Color("#888e8b"), 1.0 if forgotten else fade)
	if background != null:
		_draw_background(fade)
	else:
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
		var walk_rect := Rect2(size * Vector2(0.05, 0.16), size * Vector2(0.90, 0.78))
		draw_rect(walk_rect, Color(0.72, 0.88, 0.82, 0.28), false, 1.5)
		draw_string(ThemeDB.fallback_font, walk_rect.position + Vector2(8, 20), "可探索区域", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.86, 0.92, 0.86, 0.72))
		for i in range(investigations.size()):
			var point := size * _investigation_point(i)
			var found := discovered.has(i)
			var marker_color := Color("#79c9a5") if found else Color("#e4c98a")
			draw_circle(point, 9 if found else 12, marker_color)
			if not found: draw_arc(point, 18+ripple*8, 0, TAU, 40, Color(0.9,.78,.5,1-ripple/2),2,true)
			var caption := "已调查 · " if found else "调查 · "
			draw_string(ThemeDB.fallback_font, point + Vector2(-42,-22), caption + str(investigations[i].label), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#dff0df") if found else Color("#f4e4bc"))
		draw_circle(player*size, 10, Color("#dce6d8"))
		draw_line(player*size,player*size+Vector2(12,15),Color("#e4c98a"),3)
		draw_circle(Vector2(48,size.y-45),34,Color(.8,.85,.8,.14))
		draw_circle(Vector2(48,size.y-45)+joystick*23,12,Color("#a9b9a5"))

func _draw_background(fade: float) -> void:
	var texture_size := Vector2(background.get_width(), background.get_height())
	var source_size := texture_size
	var target_aspect := size.x / maxf(size.y, 1.0)
	var source_aspect := texture_size.x / maxf(texture_size.y, 1.0)
	if source_aspect > target_aspect:
		source_size.x = texture_size.y * target_aspect
	else:
		source_size.y = texture_size.x / target_aspect
	var source_rect := Rect2((texture_size - source_size) * 0.5, source_size)
	draw_texture_rect_region(background, Rect2(Vector2.ZERO, size), source_rect)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.09, 0.10, 0.12))
	var whiteout := 0.64 if forgotten else fade * 0.38
	if whiteout > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.82, 0.84, 0.81, whiteout))
	if erosion >= 40 or forgotten:
		var crack_alpha := 0.82 if forgotten else clampf((fade - 0.35) * 1.4, 0.2, 0.82)
		for i in range(5):
			var x := size.x * (0.12 + i * 0.19)
			var points := PackedVector2Array([
				Vector2(x, size.y * 0.08),
				Vector2(x + 18, size.y * 0.27),
				Vector2(x - 10, size.y * 0.48),
				Vector2(x + 24, size.y * 0.72)
			])
			draw_polyline(points, Color(0.94, 0.96, 0.94, crack_alpha), 2.0)
