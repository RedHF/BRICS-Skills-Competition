extends Control
## Runtime overlays share normalized coordinates with the authoritative rules.
## Source artwork is preserved; the ink reveal is a runtime mask, not new art.

const PAPER := Color("#eee5d4")
const INK := Color("#38312a")
const GOLD := Color("#b99a5c")
const RED := Color("#a34838")
const MASK_SHADER := "shader_type canvas_item; uniform sampler2D reveal_mask: filter_linear; void fragment(){ vec4 source=texture(TEXTURE,UV); float a=texture(reveal_mask,UV).r; vec3 faint=mix(vec3(.93,.89,.81),source.rgb,.13); COLOR=vec4(mix(faint,source.rgb,smoothstep(.02,.8,a)),source.a); }"

var stage: Control
var background: Texture2D
var bowl: Texture2D
var paper: Texture2D
var font: Font
var textures: Dictionary = {}
var image_rect := Rect2()
var work_rect := Rect2()
var rubbing_rect := Rect2()
var piece_rects: Array[Rect2] = []
var slot_rects: Dictionary = {}
var support_rect := Rect2()
var bowl_pickup := Rect2()
var show_shelter := false
var dragging := false
var cursor := Vector2.ZERO
var strokes: Dictionary = {}
var grids: Dictionary = {}
var current_stroke: Array = []
var drawing := false
var drum: TextureRect
var mask_image: Image
var mask_texture: ImageTexture
var mask_material: ShaderMaterial
var guides: Control
var keyboard_buttons: Dictionary = {}
var bowl_cursor := Vector2(.40,.82)
var workbench := false
var repair_time := -1.0
var scene_time := 0.0
var inspect_id := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	background = load(str(stage.spec.background))
	font = preload("res://scripts/ink_theme.gd").font()
	paper = load("res://assets/ink_ui/paper.png")
	bowl = load("res://assets/echo_v1/empty_bowl.png")
	for piece in stage.spec.get("pieces", []): textures[str(piece.id)] = load(str(piece.texture))
	workbench = stage.done("hall_support") and not stage.complete
	if stage.spec.kind == "joinery":
		for i in range(stage.spec.pieces.size()):
			_keyboard_button("piece_%d" % i,str(stage.spec.pieces[i].label),stage.choose_piece.bind(i))
		for slot in ["SLOT-L","SLOT-C","SLOT-R"]:
			_keyboard_button(slot,{"SLOT-L":"双短痕榫口","SLOT-C":"中部榫口","SLOT-R":"斜痕榫口"}[slot],stage.place_piece.bind(slot))
		_keyboard_button("support","临时承架",stage.observe.bind("beam"))
	if stage.spec.kind == "drum":
		var n: int = stage.spec.rubbing.resolution
		mask_image = Image.create(n, n, false, Image.FORMAT_L8)
		mask_image.fill(Color.BLACK)
		mask_texture = ImageTexture.create_from_image(mask_image)
		mask_material = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = MASK_SHADER
		mask_material.shader = shader
		mask_material.set_shader_parameter("reveal_mask", mask_texture)
		drum = TextureRect.new()
		drum.texture = load(str(stage.spec.rubbing.texture))
		drum.material = mask_material
		drum.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drum.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(drum)
		guides = Control.new()
		guides.mouse_filter = Control.MOUSE_FILTER_IGNORE
		guides.draw.connect(_draw_rubbing_guides)
		add_child(guides)
		for region in stage.spec.rubbing.regions:
			strokes[str(region.id)] = []
			grids[str(region.id)] = {}
			if stage.done("rub_" + str(region.id)): finish_region(str(region.id))
	resized.connect(queue_redraw)
	set_process(true)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if not stage.host.reduced_motion: scene_time += delta
	if repair_time >= 0: repair_time += delta
	if stage.spec.kind in ["joinery","guest"]: queue_redraw()

func repair_finished() -> void:
	workbench = false
	repair_time = 0.0
	queue_redraw()

func _fit(texture: Texture2D, rect: Rect2) -> Rect2:
	var extent := texture.get_size()
	var scale_factor := minf(rect.size.x/extent.x, rect.size.y/extent.y)
	return Rect2(rect.get_center()-extent*scale_factor*.5, extent*scale_factor)

func _label_at(rect: Rect2, text: String, color: Color = INK, font_size: int = 18) -> void:
	draw_string(font, Vector2(rect.position.x, rect.get_center().y+font_size*.34), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)

func _draw() -> void:
	if background == null: return
	_sync_keyboard.call_deferred()
	if not inspect_id.is_empty():
		if is_instance_valid(drum): drum.hide()
		if is_instance_valid(guides): guides.hide()
		_draw_inspection()
		return
	if is_instance_valid(guides): guides.show()
	image_rect = _fit(background, Rect2(Vector2.ZERO, size))
	if stage.spec.kind == "joinery": _draw_hall()
	else:
		draw_texture_rect(background, image_rect, false)
		preload("res://scripts/echo_props.gd").paint(self,image_rect,str(stage.host.current_event.id))
	piece_rects.clear()
	slot_rects.clear()
	if stage.spec.kind == "drum" and is_instance_valid(drum): drum.visible = stage.done("drum_reveal")
	if stage.complete:
		if stage.spec.kind == "guest": _draw_bowl()
		elif stage.spec.kind == "joinery" and workbench: _draw_joinery()
		elif stage.spec.kind == "drum": _draw_drum()
		return
	if not stage.observed():
		for object in stage.spec.objects:
			if str(object.get("step_id", "")).is_empty(): continue
			var p := scene_point(object.position)
			draw_circle(p, 15, INK)
			draw_arc(p, 15, 0, TAU, 32, GOLD, 2, true)
			_label_at(Rect2(p-Vector2(14,14), Vector2(28,28)), "✓" if stage.done(str(object.step_id)) else "·", PAPER, 22)
			var label_rect := Rect2(p+Vector2(-66,23), Vector2(132,32))
			draw_rect(label_rect, Color(.94,.9,.81,.94))
			_label_at(label_rect, str(object.label), INK, 17)
		return
	if stage.spec.kind == "joinery": _draw_joinery()
	elif stage.spec.kind == "guest": _draw_bowl()
	elif stage.done("drum_reveal"): _draw_drum()
	else:
		var p := scene_point([.48,.47])
		draw_arc(p, 30, 0, TAU, 48, GOLD, 3, true)
		_label_at(Rect2(p+Vector2(-100,34), Vector2(200,32)), "点鼓面施用藻井", PAPER)

func _draw_hall() -> void:
	var repaired := .24 if stage.done("hall_support") else 0.0
	if stage.done("hall_left"): repaired += .18
	if stage.done("hall_right"): repaired += .18
	if stage.done("hall_center"): repaired = .84
	var support := 1.0 if stage.done("hall_support") and not stage.done("hall_release") else 0.0
	var flash := 0.0
	if stage.complete:
		var t := 1.0 if repair_time < 0 else clampf(repair_time/.8,0,1)
		if stage.host.reduced_motion: t = 1.0
		repaired = lerpf(.84,1.0,smoothstep(0.0,1.0,t))
		support = maxf(0,1-repair_time/.45) if repair_time >= 0 and not stage.host.reduced_motion else 0.0
		flash = maxf(0,1-absf(repair_time-1.0)) if repair_time >= 0 and not stage.host.reduced_motion else 0.0
	preload("res://scripts/echo_hall.gd").paint(self,image_rect,repaired,support,flash)
	var outside := PackedVector2Array([Vector2(.81,.63),Vector2(.98,.53),Vector2(.98,.98),Vector2(.65,.98)])
	preload("res://scripts/echo_hall.gd").rain(self,image_rect,outside,scene_time,.17)
	if not stage.complete:
		var leak := PackedVector2Array([Vector2(.37,.38),Vector2(.60,.34),Vector2(.63,.79),Vector2(.34,.81)])
		preload("res://scripts/echo_hall.gd").rain(self,image_rect,leak,scene_time,.28)

func scene_point(point: Array) -> Vector2:
	return image_rect.position+Vector2(float(point[0]),float(point[1]))*image_rect.size

func _draw_inspection() -> void:
	var paper_rect := Rect2(Vector2(14,20),size-Vector2(28,40))
	_draw_paper(paper_rect)
	var frame := paper_rect.grow(-22)
	frame.size.y -= 46
	if inspect_id in ["rope","bowl"]:
		preload("res://scripts/echo_props.gd").prepare()
		var texture: Texture2D = preload("res://scripts/echo_props.gd").beater if inspect_id == "rope" else preload("res://scripts/echo_props.gd").bowl_close
		draw_texture_rect(texture,_fit(texture,frame),false)
	else:
		var crop := Rect2(.20,.14,.56,.25)
		if inspect_id == "join": crop = Rect2(.06,.20,.32,.25)
		elif inspect_id == "cape": crop = Rect2(.61,.51,.10,.30)
		elif inspect_id == "bowl": crop = Rect2(.725,.845,.118,.124)
		elif inspect_id == "drum": crop = Rect2(.32,.32,.33,.35)
		var extent := crop.size*background.get_size()
		var factor := minf(frame.size.x/extent.x,frame.size.y/extent.y)
		var dest := Rect2(frame.get_center()-extent*factor*.5,extent*factor)
		var texture: Texture2D = background
		if inspect_id in ["bowl","cape"]:
			preload("res://scripts/echo_props.gd").prepare()
			texture = preload("res://scripts/echo_props.gd").guest_patch
		draw_texture_rect_region(texture,dest,Rect2(crop.position*texture.get_size(),crop.size*texture.get_size()))
		if inspect_id in ["marks","join"]:
			var whole := Rect2(dest.position-crop.position*dest.size/crop.size,dest.size/crop.size)
			preload("res://scripts/echo_hall.gd").marks(self,whole,1,crop)
			preload("res://scripts/echo_hall.gd").seams(self,whole,1 if stage.complete else 0,0,crop)
	_label_at(Rect2(Vector2(paper_rect.position.x+8,paper_rect.end.y-42),Vector2(paper_rect.size.x-16,32)),"物件近看 · 返回场景后继续",INK,18)

func normalized(point: Vector2) -> Vector2:
	return (point-image_rect.position)/image_rect.size

func _draw_joinery() -> void:
	if not stage.done("hall_support"):
		var p := scene_point([.49,.61])
		support_rect = Rect2(p-Vector2(55,35), Vector2(110,70))
		draw_rect(support_rect, Color(.92,.87,.73,.18))
		draw_rect(support_rect, GOLD, false, 2)
		_label_at(Rect2(p+Vector2(-90,40),Vector2(180,32)), "临时承架", PAPER)
		return
	if not workbench: return
	work_rect = Rect2(Vector2(14,20), size-Vector2(28,40))
	_draw_paper(work_rect)
	_label_at(Rect2(work_rect.position+Vector2(8,8),Vector2(work_rect.size.x-16,32)), "比对旧痕，让凸榫与凹口接住", INK, 21)
	var width := work_rect.size.x
	var y := work_rect.position.y+work_rect.size.y*.35
	var span := width*.24
	var positions := {"SLOT-L":Vector2(work_rect.position.x+width*.22,y), "SLOT-C":Vector2(work_rect.position.x+width*.50,y), "SLOT-R":Vector2(work_rect.position.x+width*.78,y)}
	var ids := {"SLOT-L":"hall_left", "SLOT-C":"hall_center", "SLOT-R":"hall_right"}
	for slot in positions:
		var p: Vector2 = positions[slot]
		var rect := Rect2(p-Vector2(span*.5,44), Vector2(span,88))
		slot_rects[slot] = rect
		var filled: bool = stage.done(ids[slot])
		var sign := "||" if slot == "SLOT-L" else ("/" if slot == "SLOT-R" else "=")
		var piece := "JOIN-L" if slot == "SLOT-L" else ("JOIN-R" if slot == "SLOT-R" else "JOIN-C")
		var profile := _profile(piece,rect.grow(-5),180 if slot == "SLOT-L" else 0)
		if filled:
			_draw_piece(piece, rect.grow(-5), 180 if slot == "SLOT-L" else 0)
		else:
			draw_colored_polygon(profile,Color("#b1a38d"))
			profile.append(profile[0])
			draw_polyline(profile,INK,2,true)
		_label_at(Rect2(rect.position+Vector2(0,-29),Vector2(rect.size.x,26)), sign, RED, 23)
		_label_at(Rect2(rect.position+Vector2(0,92),Vector2(rect.size.x,26)), "已合拢" if filled else ("中部" if slot == "SLOT-C" else "榫口"), INK, 16)
	var support_y := y+128
	if not stage.done("hall_release"):
		var left := work_rect.position.x+width*.4
		var right := work_rect.position.x+width*.6
		draw_line(Vector2(left,y+44),Vector2(left,support_y),GOLD,8)
		draw_line(Vector2(right,y+44),Vector2(right,support_y),GOLD,8)
		draw_line(Vector2(left-20,support_y),Vector2(right+20,support_y),INK,6)
	if stage.complete:
		_label_at(Rect2(Vector2(work_rect.position.x+8,support_y+30),Vector2(width-16,40)), "临撑撤下，梁已稳住 · 拼缝与旧痕留下", INK, 20)
		return
	var tile_width := (width-40)/4.0
	var tray_y := work_rect.end.y-108
	for i in range(stage.spec.pieces.size()):
		var piece: Dictionary = stage.spec.pieces[i]
		var rect := Rect2(Vector2(work_rect.position.x+12+i*(tile_width+5),tray_y),Vector2(tile_width,80))
		piece_rects.append(rect)
		var placed: bool = stage.done("hall_left" if i == 0 else ("hall_right" if i == 1 else ("hall_center" if i == 2 else "")))
		if placed: continue
		var active: bool = stage.selected == str(piece.id)
		if active: draw_rect(rect.grow(3), GOLD, false, 2)
		_draw_piece(str(piece.id), rect, stage.piece_turn if active else int(stage.piece_turns.get(str(piece.id),piece.initial_rotation)))
		_label_at(Rect2(rect.position+Vector2(0,80),Vector2(tile_width,24)), str(piece.label), INK, 15)
	if dragging and stage.selected.begins_with("JOIN-"):
		_draw_piece(stage.selected, Rect2(cursor-Vector2(60,35),Vector2(120,70)),stage.piece_turn)

func _draw_piece(id: String, rect: Rect2, turn: int) -> void:
	var texture: Texture2D = textures.get("JOIN-L")
	if texture == null: return
	var polygon := _profile(id,rect,turn)
	var uvs := PackedVector2Array()
	for point in polygon:
		var local := (point-rect.position)/rect.size
		# Sample the intact wood face of the existing asset. Geometry stays
		# deterministic so the socket and the piece are exact counterparts.
		uvs.append(Vector2(.57+local.x*.22,.34+local.y*.30))
	draw_polygon(polygon,PackedColorArray([Color.WHITE]),uvs,texture)
	polygon.append(polygon[0])
	draw_polyline(polygon,Color("#59412b"),1.5,true)
	var mark := "||" if id == "JOIN-L" else ("/" if id == "JOIN-R" else ("=" if id == "JOIN-C" else "×"))
	_label_at(rect, mark, PAPER, 24)
	if stage.selected == id:
		_label_at(Rect2(rect.position-Vector2(0,24),Vector2(rect.size.x,24)), "← 凸榫" if turn == 180 else "凸榫 →", INK, 15)

func _profile(id: String, rect: Rect2, turn: int) -> PackedVector2Array:
	var source: Array
	if id == "JOIN-C": source = [[.02,.35],[.20,.35],[.20,.08],[.80,.08],[.80,.35],[.98,.35],[.98,.65],[.80,.65],[.80,.92],[.20,.92],[.20,.65],[.02,.65]]
	elif id == "JOIN-R": source = [[.05,.08],[.65,.08],[.78,.30],[.97,.30],[.97,.67],[.78,.67],[.65,.92],[.05,.92]]
	elif id == "JOIN-X": source = [[.05,.08],[.75,.08],[.75,.35],[.88,.35],[.81,.50],[.97,.65],[.75,.65],[.75,.92],[.05,.92]]
	else: source = [[.05,.08],[.75,.08],[.75,.35],[.97,.35],[.97,.65],[.75,.65],[.75,.92],[.05,.92]]
	var result := PackedVector2Array()
	for p in source:
		var point := Vector2(p[0],p[1])
		if turn == 180: point = Vector2.ONE-point
		result.append(rect.position+point*rect.size)
	return result

func _draw_bowl() -> void:
	var wet := PackedVector2Array([Vector2(.02,.25),Vector2(.39,.23),Vector2(.45,.97),Vector2(.02,.97)])
	preload("res://scripts/echo_hall.gd").rain(self,image_rect,wet,scene_time,.32)
	var shelter := PackedVector2Array()
	for point in stage.spec.dry_area: shelter.append(scene_point(point))
	draw_colored_polygon(shelter,Color(.88,.75,.52,.06))
	if show_shelter and not stage.complete:
		var points := PackedVector2Array()
		for point in stage.spec.dry_area: points.append(scene_point(point))
		draw_colored_polygon(points,Color(.91,.81,.58,.18))
		points.append(points[0])
		draw_polyline(points,GOLD,2,true)
	var placements: Dictionary = {}
	if GameState.session.get("stage_placements") is Dictionary:
		placements = GameState.session.stage_placements
	if placements.has("guest_place"):
		var p := scene_point(placements.guest_place)
		var width := image_rect.size.x*.105
		draw_texture_rect(bowl, Rect2(p-Vector2(width*.5,width*.522),Vector2(width,width*.674)),false)
		return
	bowl_pickup = Rect2(Vector2(16,size.y-100),Vector2(140,90))
	_draw_paper(bowl_pickup)
	draw_texture_rect(bowl,Rect2(bowl_pickup.position+Vector2(12,0),Vector2(116,77)),false)
	_label_at(Rect2(bowl_pickup.position+Vector2(0,64),Vector2(140,25)), "空碗 · 拿起",INK,16)
	if stage.selected == "bowl":
		draw_rect(bowl_pickup,GOLD,false,2)
		if dragging: draw_texture_rect(bowl,Rect2(cursor-Vector2(46,48),Vector2(92,62)),false)
		elif has_focus():
			var p := scene_point([bowl_cursor.x,bowl_cursor.y])
			draw_texture_rect(bowl,Rect2(p-Vector2(46,48),Vector2(92,62)),false,Color(1,1,1,.8))
			draw_arc(p,16,0,TAU,40,GOLD,2,true)

func _draw_drum() -> void:
	var side := minf(size.y-12,size.x-40)
	rubbing_rect = Rect2((size-Vector2(side,side))*.5,Vector2(side,side))
	drum.position = rubbing_rect.position
	drum.size = rubbing_rect.size
	_draw_paper(Rect2(Vector2.ZERO,size))
	guides.queue_redraw()

func _draw_paper(rect: Rect2) -> void:
	draw_rect(rect,Color("#eee5d4"))
	draw_texture_rect_region(paper,rect,Rect2(100,55,470,250),Color(1,1,1,.13))
	draw_rect(rect,Color("#b5a68d"),false,1)

func _draw_rubbing_guides() -> void:
	if not stage.done("drum_reveal") or stage.complete: return
	var side := rubbing_rect.size.x
	if not stage.complete:
		var region: Dictionary = _region(stage.region)
		if region.shape == "rect":
			var rect := Rect2(Vector2(float(region.rect[0]),float(region.rect[1])),Vector2(float(region.rect[2]),float(region.rect[3])))
			guides.draw_rect(Rect2(rubbing_rect.position+rect.position*side,rect.size*side),RED,false,1)
		else:
			var center := rubbing_rect.position+Vector2(.5,.5)*side
			guides.draw_arc(center,float(region.outer)*side,0,TAU,100,GOLD,1,true)
			if region.shape == "ring": guides.draw_arc(center,float(region.inner)*side,0,TAU,100,GOLD,1,true)

func _region(id: String) -> Dictionary:
	for region in stage.spec.rubbing.regions:
		if str(region.id) == id: return region
	return {}

func _in_region(region: Dictionary, p: Vector2) -> bool:
	if region.shape == "rect": return Rect2(Vector2(region.rect[0],region.rect[1]),Vector2(region.rect[2],region.rect[3])).has_point(p)
	var distance := p.distance_to(Vector2(region.center[0],region.center[1]))
	return distance <= float(region.outer) and (region.shape != "ring" or distance >= float(region.inner))

func _paint(point: Vector2, previous: Vector2) -> void:
	stage.host.soundscape.cue("paper_rub")
	var n: int = stage.spec.rubbing.resolution
	var radius: float = stage.spec.rubbing.brush_radius
	var shape := _region(stage.region)
	for y in range(n):
		for x in range(n):
			var p := Vector2((x+.5)/n,(y+.5)/n)
			if not _in_region(shape,p): continue
			var hit := p.distance_to(point) <= radius
			if not hit and point.distance_to(previous) <= .12:
				hit = p.distance_to(Geometry2D.get_closest_point_to_segment(p,previous,point)) <= radius
			if hit:
				grids[stage.region][y*n+x] = true
				mask_image.set_pixel(x,y,Color.WHITE)
	mask_texture.update(mask_image)
	stage._update()

func coverage(id: String) -> float:
	if stage.done("rub_" + id): return 1.0
	var total := 0
	var n: int = stage.spec.rubbing.resolution
	var region := _region(id)
	for y in range(n):
		for x in range(n):
			if _in_region(region,Vector2((x+.5)/n,(y+.5)/n)): total += 1
	return float(grids.get(id,{}).size())/maxi(1,total)

func finish_region(id: String) -> void:
	if mask_image == null: return
	var n: int = stage.spec.rubbing.resolution
	var region := _region(id)
	for y in range(n):
		for x in range(n):
			if _in_region(region,Vector2((x+.5)/n,(y+.5)/n)): mask_image.set_pixel(x,y,Color.WHITE)
	if stage.complete: mask_image.fill(Color.WHITE)
	mask_texture.update(mask_image)

func _gui_input(event: InputEvent) -> void:
	if not inspect_id.is_empty(): return
	if stage.locked or stage.complete: return
	if event is InputEventKey and event.pressed and not event.echo:
		if stage.spec.kind == "guest" and stage.selected == "bowl":
			var arrows := {KEY_LEFT:Vector2(-.02,0),KEY_RIGHT:Vector2(.02,0),KEY_UP:Vector2(0,-.02),KEY_DOWN:Vector2(0,.02)}
			if arrows.has(event.keycode):
				bowl_cursor = (bowl_cursor+arrows[event.keycode]).clamp(Vector2(.04,.08),Vector2(.96,.96))
				queue_redraw()
				accept_event()
			elif event.keycode == KEY_ENTER:
				stage.place_bowl(bowl_cursor)
				accept_event()
		elif stage.spec.kind == "drum" and not stage.done("drum_reveal") and event.keycode == KEY_ENTER:
			stage.use_drum()
			accept_event()
		elif stage.spec.kind == "joinery" and not stage.done("hall_support") and event.keycode == KEY_ENTER:
			stage.observe("beam")
			accept_event()
		return
	if event is InputEventMouseMotion:
		cursor = event.position
		if drawing:
			if rubbing_rect.has_point(cursor):
				var point := (cursor-rubbing_rect.position)/rubbing_rect.size
				var previous := Vector2(current_stroke[-1][0],current_stroke[-1][1])
				if point.distance_to(previous) >= .003:
					current_stroke.append([point.x,point.y])
					_paint(point,previous)
			else:
				drawing = false
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		cursor = event.position
		if event.pressed:
			if not stage.observed():
				for object in stage.spec.objects:
					if str(object.get("step_id", "")).is_empty(): continue
					if cursor.distance_to(scene_point(object.position)) < 32:
						stage.observe(str(object.id))
						break
			elif stage.spec.kind == "joinery":
				if not stage.done("hall_support"):
					if support_rect.has_point(cursor): stage.observe("beam")
				else:
					for i in range(piece_rects.size()):
						if piece_rects[i].has_point(cursor):
							stage.choose_piece(i)
							dragging = stage.selected == str(stage.spec.pieces[i].id)
							return
					for slot in slot_rects:
						if slot_rects[slot].has_point(cursor): stage.place_piece(slot); break
			elif stage.spec.kind == "guest":
				if bowl_pickup.has_point(cursor):
					stage.selected = "bowl"
					dragging = true
				elif stage.selected == "bowl" and image_rect.has_point(cursor): stage.place_bowl(normalized(cursor))
			elif not stage.done("drum_reveal"): stage.use_drum()
			elif rubbing_rect.has_point(cursor):
				drawing = true
				var point := (cursor-rubbing_rect.position)/rubbing_rect.size
				current_stroke = [[point.x,point.y]]
				strokes[stage.region].append(current_stroke)
				_paint(point,point)
		else:
			drawing = false
			if dragging:
				dragging = false
				if stage.spec.kind == "joinery":
					for slot in slot_rects:
						if slot_rects[slot].has_point(cursor): stage.place_piece(slot); break
				elif stage.spec.kind == "guest" and image_rect.has_point(cursor) and not bowl_pickup.has_point(cursor): stage.place_bowl(normalized(cursor))
		queue_redraw()

func _keyboard_button(id: String, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.tooltip_text = label
	for state in ["normal","hover","pressed","disabled"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0,0,0,0)
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus",focus)
	button.pressed.connect(callback)
	button.focus_entered.connect(func():
		if is_instance_valid(stage.hint): stage.hint.text = label + " · 回车选取或安放，R 键转向。")
	add_child(button)
	keyboard_buttons[id] = button

func _sync_keyboard() -> void:
	if not is_inside_tree(): return
	for id in keyboard_buttons:
		var button: Button = keyboard_buttons[id]
		var rect := Rect2()
		if inspect_id.is_empty() and not stage.complete and stage.observed():
			if id == "support" and not stage.done("hall_support"): rect = support_rect
			elif stage.done("hall_support"):
				if id.begins_with("piece_"):
					var index := int(id.trim_prefix("piece_"))
					if index < piece_rects.size(): rect = piece_rects[index]
				else: rect = slot_rects.get(id,Rect2())
		button.visible = rect.size.x > 0
		if not button.visible: continue
		button.position = rect.position
		button.size = rect.size
		button.disabled = stage.locked
