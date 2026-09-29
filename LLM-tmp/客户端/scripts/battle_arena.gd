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
var boss_name := ""
const ENEMY_TEXTURE = preload("res://assets/imported/white_erosion.png")
var active := false
var player_position := Vector2(0.50, 0.78)
var enemy_position := Vector2(0.50, 0.28)
var joystick := Vector2.ZERO
var dragging_stick := false
var dodge_armed := false
var motion_time := 0.0
const FIGURE = preload("res://scripts/ink_figure.gd")
var effects: Array[Dictionary] = []
var pose := "idle"
var pose_time := 0.0
var impact := 0.0
var combo := 0
var combo_timeout := 0.0
var strike_number := 0
var last_guard := "斗拱"
var spawn_time := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(0, 250)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	FIGURE.prepare()

func cast(skill: String, text: String, color: Color) -> void:
	var attacking := skill in ["挥墨", "飞檐", "藻井"]
	pose = "attack" if attacking else ("dash" if skill == "闪身" else "guard")
	pose_time = .45
	if attacking:
		combo = combo + 1 if combo_timeout > 0 else 1
		combo_timeout = 1.4
		impact = .22
	else: last_guard = skill
	_add_effect(skill, player_position, enemy_position, color, text)

func enemy_strike(blocked: bool) -> void:
	strike_number += 1
	var kind := "格挡" if blocked else "受击"
	var text := ("闪身 · 避开侵袭" if last_guard == "闪身" else "斗拱 · 护阵承击") if blocked else "侵蚀 +5"
	_add_effect(kind, enemy_position, player_position, Color("#a8eadb") if blocked else Color("#ff8078"), text)
	pose = "guard" if blocked else "hurt"
	pose_time = .4

func disperse() -> void:
	_add_effect("消散", enemy_position, enemy_position, Color("#e4c98a"), "白蚀驱散")
	spawn_time = .65

func _add_effect(kind: String, source: Vector2, target: Vector2, color: Color, text: String) -> void:
	effects.append({"kind": kind, "source": source, "target": target, "color": color, "text": text, "age": 0.0, "variant": combo % 3})
	if effects.size() > 18: effects.pop_front()

func flash(text: String, color: Color) -> void:
	effect_text = text
	effect_color = color
	effect = 0.7

func _process(delta: float) -> void:
	motion_time += delta
	pose_time = maxf(0, pose_time - delta)
	impact = maxf(0, impact - delta)
	combo_timeout = maxf(0, combo_timeout - delta)
	spawn_time = maxf(0, spawn_time - delta)
	for item in effects: item.age += delta
	effects = effects.filter(func(item): return item.age < 1.15)
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
	var enemy := enemy_position * size + Vector2(sin(motion_time * 75) * impact * 25, 0)
	var player := player_position * size
	var font := ThemeDB.fallback_font
	if not defeated:
		var extent := (126.0 if not boss_name.is_empty() else 76.0) * (1.0 + sin(motion_time * 3.0) * .04)
		var tint := Color.WHITE if phase < .7 else Color("#ffa78d")
		tint.a = 1.0 - spawn_time
		draw_texture_rect(ENEMY_TEXTURE, Rect2(enemy-Vector2.ONE*extent*.5,Vector2.ONE*extent),false,tint)
		if not boss_name.is_empty():
			draw_arc(enemy, extent*.54, motion_time*.4, motion_time*.4+TAU*.86, 48, Color("#c6ac78"), 2, true)
		draw_rect(Rect2(Vector2(size.x * 0.2, 16), Vector2(size.x * 0.6, 7)), Color("#394448"))
		draw_rect(Rect2(Vector2(size.x * 0.2, 16), Vector2(size.x * 0.6 * float(hp) / max_hp, 7)), Color("#e6a275"))
		draw_string(font, Vector2(12, 48), (boss_name if not boss_name.is_empty() else "白蚀") + " %d/%d" % [hp, max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#e4c98a"))
		if phase > 0.7:
			var warning := clampf((phase - .7) / .3, 0, 1)
			draw_circle(player, 48, Color(1, .25, .2, .08 + .12 * warning))
			draw_arc(player, 52, -PI / 2, -PI / 2 + TAU * warning, 64, Color("#ff8078"), 3, true)
			for i in range(6):
				var mark := enemy.lerp(player, float(i) / 6)
				draw_line(mark, mark + (player - enemy).normalized() * 12, Color(1, .4, .3, .5), 2, true)
			draw_string(font, Vector2(12, size.y * 0.45), "白蚀蓄力 · 移动闪身 / 斗拱承击", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#ffb39c"))
	if shield > 0:
		_draw_seal(player - Vector2(0, 20), 58, motion_time * .25, Color(.55, .9, .78, .5), shield)
	var action_offset := Vector2.ZERO
	if pose_time > 0:
		var impulse := sin(pose_time / .45 * PI)
		if pose == "attack": action_offset = (enemy - player).normalized() * impulse * 18
		elif pose == "dash": action_offset = Vector2(impulse * 32, 0)
		elif pose == "hurt": action_offset = Vector2(sin(motion_time * 70) * 5, impulse * 8)
	FIGURE.paint(self, player + action_offset, 1.0, motion_time, pose if pose_time > 0 else "idle", pose_time / .45)
	for item in effects: _draw_effect(item)
	if combo > 1 and combo_timeout > 0:
		draw_string(font, Vector2(size.x - 150, 52), "%d 连墨" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#e4c98a"))
	draw_string(font, Vector2(12, size.y - 15), "拓印师 · 护盾 %d · 受蚀 %d" % [shield, hits], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#d9e5df"))
	var stick_center := Vector2(52, size.y - 54)
	draw_circle(stick_center, 36, Color(0.76, 0.86, 0.82, 0.16))
	draw_circle(stick_center + joystick * 25, 13, Color("#a9c8bb"))
	if effect > 0:
		draw_string(font, Vector2(size.x * 0.5 - 70, size.y * 0.62), effect_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, effect_color)

func _draw_seal(center: Vector2, radius: float, rotation: float, color: Color, layers: int = 2) -> void:
	draw_arc(center, radius, 0, TAU, 64, color, 2, true)
	for layer in range(layers):
		var points := PackedVector2Array()
		for i in range(9):
			points.append(center + Vector2.from_angle(TAU * i / 8 + rotation + layer * .4) * (radius - layer * 9))
		draw_polyline(points, color, 2, true)

func _burst(center: Vector2, age: float, color: Color, count: int = 18) -> void:
	for i in range(count):
		var direction := Vector2.from_angle(i * 2.399)
		var radius := 15 + age * (45 + (i % 5) * 22)
		draw_line(center + direction * radius, center + direction * (radius + 9 * (1 - age)), color, 2 + i % 3, true)

func _draw_effect(item: Dictionary) -> void:
	var age: float = item.age
	var t := clampf(age / .7, 0, 1)
	var color := Color(item.color, clampf((1.15 - age) * 1.6, 0, 1))
	var source: Vector2 = item.source * size - Vector2(0, 20)
	var target: Vector2 = item.target * size - Vector2(0, 20)
	var direction := (target - source).normalized()
	var center := source.lerp(target, minf(1, age / .24))
	match item.kind:
		"挥墨":
			var angle := direction.angle() + float(item.variant - 1) * .35
			for layer in range(3):
				draw_arc(center, 22 + layer * 8 + t * 18, angle - 1.1, angle + 1.1, 24, color if layer == 1 else Color(.05, .16, .17, color.a), 7 - layer * 2, true)
			if age > .22: _burst(target, age - .22, color)
		"飞檐":
			for blade in range(3):
				var side := direction.orthogonal() * (blade - 1) * sin(t * PI) * 65
				var tip := source.lerp(target, minf(1, age / .38)) + side
				draw_line(tip - direction * 48, tip, Color(color, color.a * .25), 13, true)
				draw_line(tip - direction * 35, tip, color, 4, true)
			if age > .32: _burst(target, age - .32, color, 30)
		"藻井":
			_draw_seal(target, 32 + t * 60, -age, color, 3)
			_draw_seal(source, 22 + t * 36, age, Color(color, color.a * .6), 2)
			for i in range(8):
				var petal := target + Vector2.from_angle(TAU * i / 8 + age) * (24 + t * 40)
				draw_arc(petal, 18, age, age + PI, 16, color, 2, true)
		"斗拱":
			_draw_seal(source, 25 + sin(t * PI / 2) * 40, .0, color, 3)
			for i in range(3):
				var y := source.y - 35 + i * 18
				draw_polyline(PackedVector2Array([Vector2(source.x - 45 + i * 8, y - 8), Vector2(source.x - 30 + i * 6, y), Vector2(source.x + 30 - i * 6, y), Vector2(source.x + 45 - i * 8, y - 8)]), color, 4, true)
		"闪身":
			for i in range(4):
				FIGURE.paint(self, source + Vector2(-18 - i * 19 - t * 20, 20), 1, motion_time, "dash", .8, Color(color, color.a * (4 - i) * .12))
			draw_arc(source, 35 + t * 45, .3, 2.8, 32, color, 2, true)
		"格挡", "受击":
			var tip := source.lerp(target, minf(1, age / .13))
			for i in range(3):
				var offset := direction.orthogonal() * (i - 1) * 14
				draw_line(source + offset, tip + offset, Color(.95, .45, .38, color.a * .45), 4, true)
			if age > .12:
				_burst(target, age - .12, color, 24)
				if item.kind == "格挡": _draw_seal(target, 58 + t * 12, .0, color, 2)
				else: draw_rect(Rect2(Vector2.ZERO, size), Color(.8, .14, .1, maxf(0, .15 - age * .3)))
		"消散":
			var texture_size := ENEMY_TEXTURE.get_size()
			for y in range(4):
				for x in range(4):
					var shard := Vector2(x - 1.5, y - 1.5)
					var position := target + Vector2(0, 20) + shard * (19 + age * 55)
					draw_texture_rect_region(ENEMY_TEXTURE, Rect2(position - Vector2.ONE * 10, Vector2.ONE * 20), Rect2(Vector2(x, y) * texture_size / 4, texture_size / 4), Color(1, 1, 1, 1 - t))
			_burst(target, age, color, 36)
			draw_arc(target, 15 + age * 95, age, age + TAU * .9, 48, color, 3, true)
	if age > .12:
		var label_at := source if item.kind in ["斗拱", "闪身"] else target
		label_at += Vector2(-65, -58 - age * 25)
		label_at.x = clampf(label_at.x, 8, maxf(8, size.x - 210))
		label_at.y = maxf(70, label_at.y)
		draw_string(ThemeDB.fallback_font, label_at, item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, color)

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
