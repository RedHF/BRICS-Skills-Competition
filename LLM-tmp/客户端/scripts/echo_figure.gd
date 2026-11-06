extends RefCounted
## Eight anatomically distinct walk frames, grounded to one common baseline.

static var textures: Dictionary = {}
static var walk_frames: Array[AtlasTexture] = []
const FEET := {"idle":Vector2(.50,.985),"walk":Vector2(.53,.973),"attack":Vector2(.51,.985)}

static func prepare() -> void:
	if not textures.is_empty(): return
	for pair in [["idle","artisan_standing"],["walk","artisan_walking"],["attack","artisan_casting"]]:
		textures[pair[0]] = load("res://assets/echo_v1/" + pair[1] + ".png") as Texture2D
	var sheet: Texture2D = load("res://assets/echo_v1/artisan_walk_cycle.png")
	var cell := sheet.get_size()/Vector2(4,2)
	for i in range(8):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(Vector2(i%4,i/4)*cell,cell)
		frame.filter_clip = true
		walk_frames.append(frame)

static func release() -> void:
	textures.clear()
	walk_frames.clear()

static func walk_frame(time: float) -> int:
	return posmod(int(floor(time*10.0)),8)

static func pose_name(pose: String) -> String:
	if pose in ["attack","guard","skill"]: return "attack"
	if pose in ["walk","dash"]: return "walk"
	return "idle"

static func paint(canvas: CanvasItem, point: Vector2, scale: float, time: float, pose: String = "idle", strength: float = 0.0, tint: Color = Color.WHITE, facing_left: bool = false) -> void:
	prepare()
	var key := pose_name(pose)
	var selected: Texture2D = textures[key]
	if key == "walk": selected = walk_frames[walk_frame(time)]
	var height := 172.0*scale
	var dimensions := Vector2(height*selected.get_width()/selected.get_height(),height)
	var ground: Vector2 = FEET[key]
	if key == "walk": ground = Vector2(.58,.969)
	var lean := 0.0
	var lift := 0.0
	if pose == "dash": lean = .08*strength
	elif pose == "attack": lean = -.025*strength
	elif pose == "hurt":
		lean = -.04*strength
		tint = tint.lerp(Color("#e6b5a6"),.3*strength)
	canvas.draw_set_transform(point+Vector2(0,2),0,Vector2(1,.25))
	canvas.draw_circle(Vector2.ZERO,dimensions.x*.22,Color(0.08,.07,.06,.16*tint.a))
	canvas.draw_set_transform(point-Vector2(0,lift),lean,Vector2(-1 if facing_left else 1,1))
	canvas.draw_texture_rect(selected,Rect2(-ground*dimensions,dimensions),false,tint)
	canvas.draw_set_transform(Vector2.ZERO)
