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

func _draw() -> void:
	if MOTIFS.has(motif):
		draw_texture_rect(MOTIFS[motif], Rect2(Vector2(size.x * .5 - 80, 5), Vector2(160, 115)), false)
	draw_string(ThemeDB.fallback_font, Vector2(20, 145), "图式 %s · %s" % [["甲", "乙", "丙"][choice_index], motif], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#e4c98a"))
