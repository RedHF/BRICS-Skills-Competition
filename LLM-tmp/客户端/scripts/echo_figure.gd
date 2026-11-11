extends RefCounted
## Eight anatomically distinct walk frames, grounded to one common baseline.

static var textures: Dictionary = {}
static var walk_frames: Array[AtlasTexture] = []
const FEET := {"idle":Vector2(.54,.985),"walk":Vector2(.53,.973),"attack":Vector2(.51,.985)}
# Align the torso as well as the sole across independently painted cells.
const WALK_ANCHORS := [Vector2(220,496),Vector2(216,496),Vector2(222,496),Vector2(222,496),Vector2(224,496),Vector2(226,496),Vector2(227,496),Vector2(228,496)]

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

static func paint(canvas: CanvasItem, point: Vector2, scale: float, time: float, pose: String = "idle", strength: float = 0.0, tint: Color = Color.WHITE, facing_left: bool = false, walk_blend: float = -1.0) -> void:
	prepare()
	var key := pose_name(pose)
	var selected: Texture2D = textures[key]
	var height := 172.0*scale
	var dimensions := Vector2(height*selected.get_width()/selected.get_height(),height)
	var ground: Vector2 = FEET[key]
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
	var blend := (1.0 if key == "walk" else 0.0) if walk_blend < 0 else clampf(walk_blend,0,1)
	if key in ["idle","walk"] and blend > 0:
		if blend < 1:
			var idle: Texture2D = textures.idle
			var idle_size := Vector2(height*idle.get_width()/idle.get_height(),height)
			canvas.draw_texture_rect(idle,Rect2(-FEET.idle*idle_size,idle_size),false,tint)
		var index := walk_frame(time)
		var walk_size := Vector2(height*.75,height)
		canvas.draw_texture_rect(walk_frames[index],Rect2(-WALK_ANCHORS[index]/Vector2(384,512)*walk_size,walk_size),false,Color(tint,tint.a*blend))
	else:
		canvas.draw_texture_rect(selected,Rect2(-ground*dimensions,dimensions),false,tint)
	canvas.draw_set_transform(Vector2.ZERO)
