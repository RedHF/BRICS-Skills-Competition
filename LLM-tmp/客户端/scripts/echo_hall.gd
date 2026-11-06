extends RefCounted
## Only the original beam footprint is composited. All other pixels retain
## the master image, including columns, doorway, vessels and fixed furniture.

static var master: Texture2D
static var clean_plate: Texture2D
const OUTLINE := [Vector2(.050,.281),Vector2(.777,.104),Vector2(.804,.110),Vector2(.817,.128),Vector2(.809,.180),Vector2(.785,.201),Vector2(.061,.407),Vector2(.045,.377)]
const PIVOT := Vector2(.80,.15)

static func prepare() -> void:
	if master != null: return
	master = load("res://assets/echo_v1/temple_hall_master.png")
	clean_plate = load("res://assets/echo_v1/temple_hall_cleanplate.png")

static func beam_angle(repaired: float) -> float:
	return -.035*(1-clampf(repaired,0,1))

static func release() -> void:
	master = null
	clean_plate = null

static func marks(canvas: CanvasItem, rect: Rect2, repaired: float = 1, visible_area: Rect2 = Rect2(0,0,1,1)) -> void:
	for x in [.30,.50,.69]:
		var unit := Vector2(x,.36-(x-.10)*.28)
		if not visible_area.has_point(unit): continue
		var p := PIVOT+(unit-PIVOT).rotated(beam_angle(repaired))
		var center := rect.position+p*rect.size
		var signs := [Vector2(-.004,-.009),Vector2(-.004,.009),Vector2(.004,-.009),Vector2(.004,.009)]
		if x > .6: signs = [Vector2(-.004,.009),Vector2(.004,-.009)]
		elif x > .4: signs = [Vector2(-.006,-.003),Vector2(.006,-.003),Vector2(-.006,.004),Vector2(.006,.004)]
		for i in range(0,signs.size(),2):
			var a: Vector2 = center+signs[i].rotated(beam_angle(repaired))*rect.size
			var b: Vector2 = center+signs[i+1].rotated(beam_angle(repaired))*rect.size
			canvas.draw_line(a+Vector2(.8,.8),b+Vector2(.8,.8),Color(.09,.06,.04,.85),2,true)
			canvas.draw_line(a,b,Color(.73,.59,.40,.8),1.3,true)

static func beam_over(canvas: CanvasItem, rect: Rect2) -> void:
	prepare()
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for unit in OUTLINE:
		points.append(rect.position+unit*rect.size)
		uvs.append(unit)
	canvas.draw_polygon(points,PackedColorArray([Color.WHITE]),uvs,master)
	marks(canvas,rect)
	seams(canvas,rect)

static func seams(canvas: CanvasItem, rect: Rect2, repaired: float = 1, flash: float = 0, visible_area: Rect2 = Rect2(0,0,1,1)) -> void:
	for x in [.30,.50,.69]:
		var unit := Vector2(x,.36-(x-.10)*.28)
		if not visible_area.has_point(unit): continue
		var line := PackedVector2Array()
		for offset in [Vector2(-.004,-.023),Vector2(.002,-.010),Vector2(-.002,.008),Vector2(.004,.022)]:
			line.append(rect.position+(PIVOT+(unit+offset-PIVOT).rotated(beam_angle(repaired)))*rect.size)
		canvas.draw_polyline(line,Color(.12,.08,.05,.78),1.4 if repaired > .6 else 2.4,true)
		if flash > 0: canvas.draw_polyline(line,Color(.84,.66,.36,flash*.8),3,true)

static func paint(canvas: CanvasItem, rect: Rect2, repaired: float = 1, support: float = 0, flash: float = 0) -> void:
	prepare()
	canvas.draw_texture_rect(master,rect,false)
	var points := PackedVector2Array()
	var moved := PackedVector2Array()
	var uvs := PackedVector2Array()
	for unit in OUTLINE:
		points.append(rect.position+unit*rect.size)
		var turn: Vector2 = PIVOT+(unit-PIVOT).rotated(beam_angle(repaired))
		moved.append(rect.position+turn*rect.size)
		uvs.append(unit)
	canvas.draw_polygon(points,PackedColorArray([Color.WHITE]),uvs,clean_plate)
	canvas.draw_polygon(moved,PackedColorArray([Color.WHITE]),uvs,master)
	marks(canvas,rect,repaired)
	if support > 0:
		for x in [.43,.57]:
			var top := rect.position+Vector2(x,.36-(x-.10)*.28)*rect.size
			var foot := rect.position+Vector2(x-.025,.78)*rect.size
			canvas.draw_line(top+Vector2(3,0),foot+Vector2(3,1),Color(.12,.10,.08,support*.45),10,true)
			canvas.draw_line(top,foot,Color(.34,.25,.17,support),7,true)
			canvas.draw_line(top-Vector2(2,0),foot-Vector2(2,1),Color(.62,.49,.34,support*.7),1.3,true)
			canvas.draw_line(foot+Vector2(-10,0),foot+Vector2(12,0),Color(.25,.19,.13,support),5,true)
	seams(canvas,rect,repaired,flash)

static func rain(canvas: CanvasItem, rect: Rect2, polygon: PackedVector2Array, time: float, alpha: float = .2) -> void:
	for i in range(42):
		var x := fmod(float(i)*.6180339,.98)
		var y := fmod(float(i)*.381966+time*.38,1.0)
		var from := Vector2(x,y)
		var to := from+Vector2(-.004,.026)
		if Geometry2D.is_point_in_polygon(from,polygon) and Geometry2D.is_point_in_polygon(to,polygon):
			canvas.draw_line(rect.position+from*rect.size,rect.position+to*rect.size,Color(.83,.84,.82,alpha),1,true)
