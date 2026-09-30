extends RefCounted

static var texture: ImageTexture
static var frames: Dictionary = {}

static func prepare() -> void:
	if texture != null: return
	var idle := load("res://assets/characters/idle.png") as Texture2D
	texture = ImageTexture.create_from_image(idle.get_image())
	for action in ["walk", "attack", "hurt"]:
		var sequence: Array[Texture2D] = []
		for index in range(6):
			sequence.append(load("res://assets/characters/%s_%d.png" % [action, index]) as Texture2D)
		frames[action] = sequence

static func frame_index(pose: String, time: float, strength: float) -> int:
	if pose == "walk": return int(floor(time * 10.0)) % 6
	return clampi(int(floor((1.0 - clampf(strength, 0.0, 1.0)) * 6.0 + 0.00001)), 0, 5)

static func paint(canvas: CanvasItem, point: Vector2, scale: float, time: float, pose: String = "idle", strength: float = 0.0, tint: Color = Color.WHITE, facing_left: bool = false) -> void:
	prepare()
	var selected: Texture2D = texture
	if frames.has(pose): selected = frames[pose][frame_index(pose, time, strength)]
	var bob := sin(time * 3.0) * 0.8 if pose == "idle" else 0.0
	var lean := 0.0
	# Guard and dash retain brief transforms; walk/attack/hurt use actual frames.
	if pose == "dash": lean = 0.14 * strength
	elif pose == "guard": lean = -0.06 * strength
	var dimensions := Vector2.ONE * 153.0 * scale
	canvas.draw_set_transform(point + Vector2(0, bob), lean, Vector2(-1.0 if facing_left else 1.0, 1.0))
	canvas.draw_texture_rect(selected, Rect2(Vector2(-dimensions.x * .5, -dimensions.y * .70), dimensions), false, tint)
	canvas.draw_set_transform(Vector2.ZERO)
