extends RefCounted

const CHINESE_FONT = preload("res://assets/fonts/chinese_system_font.tres")

static func font() -> Font:
	return CHINESE_FONT

static func surface(kind: String = "ink", margin: float = 18.0) -> StyleBox:
	if kind == "paper":
		var paper := StyleBoxFlat.new()
		paper.bg_color = Color("#efe5cd")
		paper.border_color = Color("#9a855c")
		paper.set_border_width_all(1)
		paper.set_corner_radius_all(6)
		paper.shadow_color = Color(0.13, 0.12, 0.09, 0.18)
		paper.shadow_size = 4
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			paper.set_content_margin(side, margin)
		return paper
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/ink_ui/" + kind + ".png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 0)
		style.set_content_margin(side, margin)
	return style
