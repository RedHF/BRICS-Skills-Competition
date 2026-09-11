extends Control

signal dodge_triggered

var hp := 30
var max_hp := 30
var shield := 0
var hits := 0
var phase := 0.0
var effect := 0.0
var effect_color := Color.WHITE
var effect_text := ""
var defeated := false
var background: Texture2D
var active := false
var player_position := Vector2(0.50, 0.78)
var enemy_position := Vector2(0.50, 0.28)
var joystick := Vector2.ZERO
var dragging_stick := false
var dodge_armed := false
var motion_time := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(0, 330)
	mouse_filter = Control.MOUSE_FILTER_STOP

func flash(text: String, color: Color) -> void:
	effect_text = text
	effect_color = color
	effect = 0.7

func _process(delta: float) -> void:
	motion_time += delta
	if active and not defeated:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down") + joystick
		if direction.length() > 0:
			player_position += Vector2(direction.x, direction.y * 0.72).limit_length() * delta * 0.52
			player_position = player_position.clamp(Vector2(0.08, 0.38), Vector2(0.92, 0.90))
			if phase > 0.68 and not dodge_armed:
				dodge_armed = true
				dodge_triggered.emit()
		var chase_target := Vector2(player_position.x + sin(motion_time * 1.7) * 0.10, maxf(0.20, player_position.y - 0.34))
		enemy_position = enemy_position.move_toward(chase_target, delta * 0.13)
		enemy_position = enemy_position.clamp(Vector2(0.14, 0.18), Vector2(0.86, 0.56))
		if phase < 0.32: dodge_armed = false
	effect = maxf(0, effect - delta)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var stick_center := Vector2(52, size.y - 54)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.distance_to(stick_center) < 42:
			dragging_stick = true
			joystick = ((event.position - stick_center) / 32.0).limit_length()
		elif not event.pressed:
			dragging_stick = false
			joystick = Vector2.ZERO
		accept_event()
	elif event is InputEventMouseMotion and dragging_stick:
		joystick = ((event.position - stick_center) / 32.0).limit_length()
		accept_event()

func _draw() -> void:
	if background != null:
		_draw_background()
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#101f28"))
	var enemy := enemy_position * size
	var player := player_position * size
	var font := ThemeDB.fallback_font
	if not defeated:
		var body := PackedVector2Array()
		for i in range(12):
			var angle := TAU * i / 12
			var pulse := 1.0 + sin(motion_time * 4.0 + i) * 0.08
			body.append(enemy + Vector2(cos(angle), sin(angle)) * (38 if i % 2 == 0 else 28) * pulse)
		draw_colored_polygon(body, Color("#f0eae0") if phase < 0.7 else Color("#ff8078"))
		for i in range(4):
			var tail_end := enemy + Vector2(sin(motion_time * 2.0 + i) * 54, -34 - i * 8)
			draw_line(enemy, tail_end, Color(0.88, 0.90, 0.88, 0.42), 3.0)
		draw_circle(enemy + Vector2(-12, -3), 4, Color("#243840"))
		draw_circle(enemy + Vector2(12, -3), 4, Color("#243840"))
		draw_line(enemy + Vector2(-8, 14), enemy + Vector2(8, 14), Color("#243840"), 3)
		draw_rect(Rect2(Vector2(size.x * 0.2, 16), Vector2(size.x * 0.6, 7)), Color("#394448"))
		draw_rect(Rect2(Vector2(size.x * 0.2, 16), Vector2(size.x * 0.6 * float(hp) / max_hp, 7)), Color("#e6a275"))
		draw_string(font, Vector2(12, 48), "白蚀 %d/%d" % [hp, max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#e4c98a"))
		if phase > 0.7:
			draw_line(enemy, player, Color(1.0, 0.36, 0.34, 0.58), 3.0, true)
			draw_string(font, Vector2(12, size.y * 0.52), "白蚀锁定 · 保持移动即可闪身", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#ff8078"))
	draw_circle(player, 20, Color("#e4c98a"))
	draw_line(player + Vector2(-10, 10), player + Vector2(10, -12), Color("#243840"), 5)
	if shield > 0: draw_arc(player, 30, 0, TAU, 48, Color("#9ad5ad"), 4, true)
	draw_string(font, Vector2(12, size.y - 15), "拓印师 · 护盾 %d · 受蚀 %d" % [shield, hits], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#d9e5df"))
	var stick_center := Vector2(52, size.y - 54)
	draw_circle(stick_center, 36, Color(0.76, 0.86, 0.82, 0.16))
	draw_circle(stick_center + joystick * 25, 13, Color("#a9c8bb"))
	if effect > 0:
		draw_line(player, enemy, Color(effect_color, effect / 0.7), 6, true)
		draw_string(font, Vector2(size.x * 0.5 - 70, size.y * 0.62), effect_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, effect_color)

func _draw_background() -> void:
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.07, 0.09, 0.42))
