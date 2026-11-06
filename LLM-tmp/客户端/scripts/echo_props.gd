extends RefCounted
## Runtime-only physical details. The source scene remains intact outside the
## two small feathered prop regions; a private memory never removes these.

static var beater: Texture2D
static var guest_patch: Texture2D
static var hands: Texture2D
static var bowl_close: Texture2D
const GUEST_PATCHES := [Rect2(.616,.522,.080,.282),Rect2(.731,.857,.102,.104)]
const BEATER_RECT := Rect2(.48,.35,.25,.2963)

static func prepare() -> void:
	if beater != null: return
	beater = load("res://assets/echo_v1/drum_beater_three_knots.png")
	guest_patch = load("res://assets/echo_v1/temple_guest_detail_patch.png")
	hands = load("res://assets/echo_v1/beam_lifting_hands.png")
	bowl_close = load("res://assets/echo_v1/guest_bowl_close.png")

static func release() -> void:
	beater = null
	guest_patch = null
	hands = null
	bowl_close = null

static func mapped(rect: Rect2, unit: Rect2) -> Rect2:
	return Rect2(rect.position+unit.position*rect.size,unit.size*rect.size)

static func _patch(canvas: CanvasItem, rect: Rect2, unit: Rect2, alpha: float) -> void:
	canvas.draw_texture_rect_region(guest_patch,mapped(rect,unit),Rect2(unit.position*guest_patch.get_size(),unit.size*guest_patch.get_size()),Color(1,1,1,alpha))

static func guest(canvas: CanvasItem, rect: Rect2) -> void:
	prepare()
	for patch in GUEST_PATCHES:
		# Eight narrow edge bands blend the edited wall/floor into the master;
		# the prop at the center is opaque. No global replacement/color grade.
		var feather := .005
		for i in range(8):
			var outer: Rect2 = patch.grow(-feather*float(i)/8)
			var inner: Rect2 = patch.grow(-feather*float(i+1)/8)
			var a := float(i+1)/8
			_patch(canvas,rect,Rect2(outer.position,Vector2(outer.size.x,inner.position.y-outer.position.y)),a)
			_patch(canvas,rect,Rect2(Vector2(outer.position.x,inner.end.y),Vector2(outer.size.x,outer.end.y-inner.end.y)),a)
			_patch(canvas,rect,Rect2(Vector2(outer.position.x,inner.position.y),Vector2(inner.position.x-outer.position.x,inner.size.y)),a)
			_patch(canvas,rect,Rect2(Vector2(inner.end.x,inner.position.y),Vector2(outer.end.x-inner.end.x,inner.size.y)),a)
		_patch(canvas,rect,patch.grow(-feather),1.0)

static func paint(canvas: CanvasItem, rect: Rect2, event_id: String) -> void:
	if event_id == "temple_guest": guest(canvas,rect)
	elif event_id == "temple_drum":
		prepare()
		canvas.draw_texture_rect(beater,mapped(rect,BEATER_RECT),false)
	elif event_id == "temple_incense": preload("res://scripts/echo_hall.gd").marks(canvas,rect)

static func remembered_hands(canvas: CanvasItem, rect: Rect2, strength: float) -> void:
	if strength <= 0: return
	prepare()
	# Put the upper fingertips beneath the repaired beam. Repainting a textured
	# beam polygon after this sprite can erase the overlay at small UI sizes.
	# Keep physical drawing first and this private response last.
	var area := mapped(rect,Rect2(.32,.252,.29,.344))
	canvas.draw_texture_rect(hands,area,false,Color(.94,.90,.79,strength*.48))
