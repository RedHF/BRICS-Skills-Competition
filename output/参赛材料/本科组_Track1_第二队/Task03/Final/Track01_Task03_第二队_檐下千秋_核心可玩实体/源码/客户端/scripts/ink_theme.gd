extends RefCounted

const CHINESE_FONT = preload("res://assets/fonts/chinese_system_font.tres")

static func font() -> Font:
	return CHINESE_FONT

static func surface(kind: String = "ink", margin: float = 18.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/ink_ui/" + kind + ".png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 0)
		style.set_content_margin(side, margin)
	return style
