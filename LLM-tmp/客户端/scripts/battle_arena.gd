extends Control

var hp := 30
var max_hp := 30
var shield := 0
var hits := 0
var phase := 0.0
var effect := 0.0
var effect_color := Color.WHITE
var effect_text := ""
var defeated := false

func _ready() -> void:
	custom_minimum_size = Vector2(0, 230)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func flash(text: String, color: Color) -> void:
	effect_text = text
	effect_color = color
	effect = 0.7

func _process(delta: float) -> void:
	effect = maxf(0, effect - delta)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#101f28"))
	var enemy := Vector2(size.x * 0.5, 76)
	var player := Vector2(size.x * 0.5, 186)
	var font := ThemeDB.fallback_font
	if not defeated:
		var body := PackedVector2Array()
		for i in range(12):
			var angle := TAU * i / 12
			body.append(enemy + Vector2(cos(angle), sin(angle)) * (38 if i % 2 == 0 else 28))
		draw_colored_polygon(body, Color("#f0eae0") if phase < 0.7 else Color("#ff8078"))
		draw_circle(enemy + Vector2(-12, -3), 4, Color("#243840"))
		draw_circle(enemy + Vector2(12, -3), 4, Color("#243840"))
		draw_line(enemy + Vector2(-8, 14), enemy + Vector2(8, 14), Color("#243840"), 3)
		draw_rect(Rect2(Vector2(size.x * 0.2, 16), Vector2(size.x * 0.6, 7)), Color("#394448"))
		draw_rect(Rect2(Vector2(size.x * 0.2, 16), Vector2(size.x * 0.6 * float(hp) / max_hp, 7)), Color("#e6a275"))
		draw_string(font, Vector2(12, 48), "白蚀 %d/%d" % [hp, max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#e4c98a"))
		if phase > 0.7: draw_string(font, Vector2(12, 122), "白蚀蓄力 · 即将侵袭", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#ff8078"))
	draw_circle(player, 20, Color("#e4c98a"))
	draw_line(player + Vector2(-10, 10), player + Vector2(10, -12), Color("#243840"), 5)
	if shield > 0: draw_arc(player, 30, 0, TAU, 48, Color("#9ad5ad"), 4, true)
	draw_string(font, Vector2(12, 215), "拓印师 · 护盾 %d · 受蚀 %d" % [shield, hits], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#d9e5df"))
	if effect > 0:
		draw_line(player, enemy, Color(effect_color, effect / 0.7), 6, true)
		draw_string(font, Vector2(size.x * 0.5 - 70, 152), effect_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, effect_color)
