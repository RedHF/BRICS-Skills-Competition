extends Button

var motif := ""
var choice_index := 0

const MOTIFS = {
	"两柱一间": preload("res://assets/puzzles/gate_2.png"),
	"三柱两间": preload("res://assets/puzzles/gate_3.png"),
	"四柱三间": preload("res://assets/puzzles/gate_4.png"),
	"旦": preload("res://assets/puzzles/opera_dan.png"),
	"净": preload("res://assets/puzzles/opera_jing.png"),
	"生": preload("res://assets/puzzles/opera_sheng.png"),
}

func _ready() -> void:
	custom_minimum_size = Vector2(0, 165)
	text = ""
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_constant_override("outline_size", 1)
	for state in ["normal", "disabled", "hover", "pressed", "focus"]:
		var paper := StyleBoxFlat.new()
		paper.bg_color = Color("#f3e7cd") if state in ["normal", "disabled"] else Color("#e5d1a4")
		paper.border_color = Color("#a58b5d")
		paper.set_border_width_all(2 if state in ["hover", "focus"] else 1)
		paper.set_corner_radius_all(8)
		add_theme_stylebox_override(state,paper)

func _draw() -> void:
	if motif in ["旦", "净", "生"]:
		var center := size.x*.5
		var long_sleeve := motif == "旦"
		var sleeve_end := 112.0 if long_sleeve else (65.0 if motif == "净" else 80.0)
		var width := 66.0 if motif != "生" else 40.0
		var robe := PackedVector2Array([Vector2(center-18,30),Vector2(center-width,48),Vector2(center-width,sleeve_end),Vector2(center-33,sleeve_end),Vector2(center-25,65),Vector2(center-26,118),Vector2(center+26,118),Vector2(center+25,65),Vector2(center+33,sleeve_end),Vector2(center+width,sleeve_end),Vector2(center+width,48),Vector2(center+18,30)])
		draw_colored_polygon(robe,Color("#799c9b") if long_sleeve else Color("#ad8669"))
		var outline := robe.duplicate()
		outline.append(robe[0])
		draw_polyline(outline,Color("#302c28"),2,true)
		draw_line(Vector2(center,35),Vector2(center,116),Color("#eee2ca"),3,true)
		var caption := "长水袖" if long_sleeve else ("宽短袖" if motif == "净" else "窄直袖")
		draw_string(preload("res://scripts/ink_theme.gd").font(),Vector2(16,148),caption,HORIZONTAL_ALIGNMENT_CENTER,int(size.x)-32,20,Color("#302c28"))
	else:
		if MOTIFS.has(motif): draw_texture_rect(MOTIFS[motif],Rect2(Vector2(size.x*.5-80,5),Vector2(160,115)),false)
		draw_string(preload("res://scripts/ink_theme.gd").font(),Vector2(20,145),"图式 %s" % [["甲","乙","丙"][choice_index]],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#302c28"))
