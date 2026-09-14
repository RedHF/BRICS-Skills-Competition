extends Button

var motif := ""
var choice_index := 0

func _ready() -> void:
	custom_minimum_size = Vector2(0, 165)
	text = ""
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_constant_override("outline_size", 1)

func _draw() -> void:
	var ink := Color("#e4c98a")
	draw_string(ThemeDB.fallback_font,Vector2(20,145),"图式 %s" % ["甲", "乙", "丙"][choice_index],HORIZONTAL_ALIGNMENT_LEFT,-1,20,ink)
	var center := Vector2(size.x/2, 59)
	if motif in ["四柱三间", "两柱一间", "三柱两间"]:
		var count: int = {"四柱三间":4,"两柱一间":2,"三柱两间":3}[motif]
		for i in range(count):
			var x := 18 + (size.x-36)*i/(count-1)
			draw_line(Vector2(x,27),Vector2(x,91),ink,4)
		draw_line(Vector2(12,29),Vector2(size.x-12,29),ink,5)
		draw_polyline(PackedVector2Array([Vector2(12,25),Vector2(size.x*.5,10),Vector2(size.x-12,25)]),ink,3,true)
	else:
		draw_arc(center,18,0,TAU,36,ink,2,true)
		if motif == "旦":
			for side in [-1,1]:
				draw_circle(center+Vector2(side*19,-14),6,ink)
				draw_polyline(PackedVector2Array([center+Vector2(side*13,22),center+Vector2(side*34,30),center+Vector2(side*40,55)]),ink,6,true)
		elif motif == "净":
			draw_line(center+Vector2(-12,-5),center+Vector2(12,12),ink,4)
			draw_line(center+Vector2(12,-5),center+Vector2(-12,12),ink,4)
			draw_rect(Rect2(center+Vector2(-26,-29),Vector2(52,9)),ink)
		elif motif == "生":
			draw_line(center+Vector2(-17,-20),center+Vector2(17,-20),ink,5)
			draw_colored_polygon(PackedVector2Array([center+Vector2(-9,12),center+Vector2(9,12),center+Vector2(0,38)]),ink)
