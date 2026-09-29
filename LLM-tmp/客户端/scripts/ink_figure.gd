extends RefCounted

const SOURCE = preload("res://assets/imported/artisan_source.png")
static var texture: ImageTexture

static func prepare() -> void:
	if texture != null: return
	# Remove only the border-connected backdrop, retaining white sleeves and face.
	var picture := SOURCE.get_image()
	if picture.is_compressed(): picture.decompress()
	picture.convert(Image.FORMAT_RGBA8)
	var width := picture.get_width()
	var height := picture.get_height()
	var seen := PackedByteArray()
	seen.resize(width * height)
	var pending := PackedInt32Array()
	for x in range(width):
		pending.append(x)
		pending.append((height - 1) * width + x)
	for y in range(height):
		pending.append(y * width)
		pending.append(y * width + width - 1)
	var at := 0
	while at < pending.size():
		var index := pending[at]
		at += 1
		if seen[index]: continue
		seen[index] = 1
		var x := index % width
		var y := int(index / width)
		var color := picture.get_pixel(x, y)
		if minf(color.r, minf(color.g, color.b)) < 0.88: continue
		picture.set_pixel(x, y, Color(0, 0, 0, 0))
		if x > 0: pending.append(index - 1)
		if x < width - 1: pending.append(index + 1)
		if y > 0: pending.append(index - width)
		if y < height - 1: pending.append(index + width)
	texture = ImageTexture.create_from_image(picture)

static func paint(canvas: CanvasItem, point: Vector2, scale: float, time: float, pose: String = "idle", strength: float = 0.0, tint: Color = Color.WHITE) -> void:
	prepare()
	var bob := sin(time * 3.0) * 1.5
	var lean := 0.0
	var stretch := Vector2.ONE
	match pose:
		"attack":
			lean = -0.16 * strength
			stretch = Vector2(1.0 + 0.08 * strength, 1.0 - 0.05 * strength)
		"guard":
			stretch = Vector2(1.0 + 0.08 * strength, 1.0 - 0.10 * strength)
		"dash": lean = 0.22 * strength
		"hurt": lean = 0.15 * strength
	var dimensions := Vector2(86, 115) * scale
	canvas.draw_set_transform(point + Vector2(0, bob), lean, stretch)
	canvas.draw_texture_rect(texture, Rect2(Vector2(-dimensions.x * .5, -dimensions.y * .78), dimensions), false, tint)
	canvas.draw_set_transform(Vector2.ZERO)
