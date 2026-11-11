extends Button

var skill := "挥墨"
var remaining := 0.0
var cooldown := 1.0
const ICONS = {
	"挥墨": preload("res://assets/vfx/ink_slash.png"),
	"飞檐": preload("res://assets/vfx/flying_blades.png"),
	"闪身": preload("res://assets/vfx/dodge_smoke.png")
}

func _ready() -> void:
	custom_minimum_size = Vector2(110, 100)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

func _draw() -> void:
	var center := Vector2(size.x*.5, 41)
	draw_circle(center, 38, Color("#302c28"))
	draw_arc(center, 38, 0, TAU, 64, Color("#b99a5c"), 2, true)
	if ICONS.has(skill): draw_texture_rect(ICONS[skill], Rect2(center-Vector2.ONE*31, Vector2.ONE*62), false)
	if remaining > 0:
		var points := PackedVector2Array([center])
		for i in range(65):
			var angle := -PI/2 + TAU*clampf(remaining/cooldown,0,1)*i/64.0
			points.append(center+Vector2(cos(angle),sin(angle))*37)
		draw_colored_polygon(points, Color(0,0,0,.7))
		draw_arc(center, 35, -PI/2, -PI/2+TAU*clampf(remaining/cooldown,0,1), 64, Color("#e4c98a"), 3, true)
		draw_string(preload("res://scripts/ink_theme.gd").font(),center+Vector2(-16,7),"%.1f" % remaining,HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color.WHITE)
	elif not disabled:
		draw_arc(center, 41, 0, TAU, 64, Color("#e4c98a"), 2, true)
	if has_focus(): draw_arc(center,44,0,TAU,64,Color.WHITE,2,true)
	var key: String = {"挥墨":"1", "飞檐":"2", "闪身":"3"}.get(skill,"")
	draw_string(preload("res://scripts/ink_theme.gd").font(),Vector2(size.x*.5-44,96),key+" · "+skill,HORIZONTAL_ALIGNMENT_CENTER,88,18,Color("#302c28"))
