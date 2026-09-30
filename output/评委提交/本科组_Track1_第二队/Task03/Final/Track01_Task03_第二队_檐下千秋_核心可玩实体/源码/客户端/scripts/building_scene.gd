extends Control

signal investigated(label: String, found: int, total: int)
var erosion := 0
var forgotten := false
var bridge := false
var interactive := false
var tint := Color("#a38c63")
var background: Texture2D
var eroded_background: Texture2D
var investigations: Array = []
var discovered: Array = []
var player := Vector2(0.48, 0.78)
var target := player
var pending_investigation := -1
var ripple := 0.0
var joystick := Vector2.ZERO
var dragging_stick := false
var purification := 0.0
var character_time := 0.0
var character_moving := false
var character_facing_left := false

const FALLBACK_SCENE = preload("res://assets/ink_ui/background.png")
const INK_CARD = preload("res://assets/ink_ui/ink.png")
const JADE_SEAL = preload("res://assets/puzzles/jade_seal.png")
const CINNABAR_SEAL = preload("res://assets/puzzles/cinnabar_seal.png")
const EROSION_ART = preload("res://assets/vfx/erosion_burst.png")

func _ready() -> void:
	custom_minimum_size.y = 310 if interactive else 240
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if investigations.is_empty(): investigations = [{"label":"古建遗痕", "position":[0.55, 0.50]}]

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	ripple = fmod(ripple + delta, 2.0)
	character_time += delta
	character_moving = false
	if interactive:
		var previous_position := player
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down") + joystick
		if direction.length() > 0:
			pending_investigation = -1
			player += Vector2(direction.x, direction.y * 0.65).limit_length() * delta * 0.5
			target = player
		else: player = player.move_toward(target, delta * 0.5)
		player = player.clamp(Vector2(0.05, 0.16), Vector2(0.95, 0.94))
		character_moving = player.distance_to(previous_position) > 0.0001
		if absf(player.x - previous_position.x) > 0.0001:
			character_facing_left = player.x < previous_position.x
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
	if background != null:
		_draw_background(fade)
	else:
		draw_texture_rect(FALLBACK_SCENE, Rect2(Vector2.ZERO, size), false)
	if purification > 0:
		for i in range(5):
			var place := size * Vector2(.21 + i * .13, .34 + sin(i) * .1)
			draw_texture_rect(EROSION_ART, Rect2(place - Vector2.ONE * 27, Vector2.ONE * 54), false, Color(1, 1, 1, purification * .38))
	if interactive:
		for i in range(investigations.size()):
			var point := size * _investigation_point(i)
			var found := discovered.has(i)
			var stamp := JADE_SEAL if found else CINNABAR_SEAL
			draw_texture_rect(stamp, Rect2(point - Vector2.ONE * 15, Vector2.ONE * 30), false)
			if not found:
				draw_texture_rect(stamp, Rect2(point - Vector2.ONE * (22 + ripple * 4), Vector2.ONE * (44 + ripple * 8)), false, Color(1, 1, 1, .22))
			var caption := "已调查 · " if found else "调查 · "
			var text := caption + str(investigations[i].label)
			var width := preload("res://scripts/ink_theme.gd").font().get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x + 16
			var origin := Vector2(clampf(point.x-width/2,4,size.x-width-4),point.y-54)
			draw_texture_rect(INK_CARD, Rect2(origin, Vector2(width, 30)), false)
			draw_string(preload("res://scripts/ink_theme.gd").font(),origin+Vector2(8,22),text,HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("#f4e4bc"))
		preload("res://scripts/ink_figure.gd").paint(self, player*size, .72, character_time, "walk" if character_moving else "idle", 0.0, Color.WHITE, character_facing_left)
		draw_texture_rect(JADE_SEAL, Rect2(Vector2(14, size.y - 79), Vector2.ONE * 68), false, Color(1, 1, 1, .48))
		draw_texture_rect(JADE_SEAL, Rect2(Vector2(36, size.y - 57) + joystick * 23, Vector2.ONE * 24), false)

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
	if eroded_background != null:
		var erosion_mix := 1.0 if forgotten else fade
		draw_texture_rect_region(eroded_background, Rect2(Vector2.ZERO, size), source_rect, Color(1,1,1,erosion_mix))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.09, 0.10, 0.12))
	var whiteout := 0.64 if forgotten else fade * 0.38
	if whiteout > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.82, 0.84, 0.81, whiteout))
	if erosion >= 40 or forgotten:
		var crack_alpha := 0.82 if forgotten else clampf((fade - 0.35) * 1.4, 0.2, 0.82)
		for i in range(5):
			var x := size.x * (0.12 + i * 0.19)
			draw_texture_rect(EROSION_ART, Rect2(Vector2(x - 45, size.y * .14), Vector2(90, size.y * .55)), false, Color(1, 1, 1, crack_alpha * .28))
