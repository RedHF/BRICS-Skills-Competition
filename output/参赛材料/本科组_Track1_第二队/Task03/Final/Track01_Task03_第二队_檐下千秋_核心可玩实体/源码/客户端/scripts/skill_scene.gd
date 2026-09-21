extends Control

signal applied(skill: String, target: String)
var selected := ""
var accepted: Array = []
var locked := false
var anchors := {"beam": Vector2(.24, .57), "bell": Vector2(.79, .31), "inscription": Vector2(.66, .75)}

func _ready() -> void:
	custom_minimum_size.y = 280
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if locked or selected.is_empty(): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for target in anchors:
			if event.position.distance_to(anchors[target] * size) < 49:
				applied.emit(selected, target)
				accept_event()
				return

func _draw() -> void:
	draw_style_box(_panel(), Rect2(Vector2.ZERO, size))
	var supported := accepted.has("craftsman_anchor") or accepted.has("tower_anchor")
	var triggered := accepted.has("craftsman_trigger")
	var purged := accepted.has("tower_purify") or accepted.has("drum_purify")
	var wood := Color("#c0a274")
	var beam: Vector2 = anchors.beam * size
	var bell: Vector2 = anchors.bell * size
	var tablet: Vector2 = anchors.inscription * size
	draw_line(beam + Vector2(-60, -57 if supported else -30), beam + Vector2(120, -57), wood, 12, true)
	for i in range(3):
		draw_rect(Rect2(beam + Vector2(-35+i*8, -22+i*15), Vector2(70-i*16, 10)), wood)
	draw_line(beam + Vector2(0, 12), beam + Vector2(0, 43), wood, 13)
	draw_line(bell + Vector2(0,-50), bell, wood, 3)
	draw_arc(bell, 24, PI, TAU, 24, wood, 5, true)
	draw_line(bell + Vector2(-24, 0), bell + Vector2(24, 0), wood, 4)
	draw_circle(bell + Vector2(0, 6), 5, wood)
	draw_line(beam + Vector2(100,-57), bell+Vector2(0,-50), Color("#87bfb1") if supported else Color("#586564"), 2)
	draw_rect(Rect2(tablet-Vector2(48,34),Vector2(96,57)), Color("#57796f") if purged else Color("#8b8e82"))
	if purged:
		for i in range(3): draw_line(tablet+Vector2(-30,-20+i*14),tablet+Vector2(30,-20+i*14),wood,2)
	for target in anchors:
		var point: Vector2 = anchors[target] * size
		draw_arc(point, 47, 0, TAU, 48, Color("#dbc48c"), 1, true)
		var caption: String = {"beam":"承重斗拱", "bell":"远端风铃", "inscription":"白蚀碑面"}[target]
		draw_string(ThemeDB.fallback_font,point+Vector2(-48,65),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#efe4c4"))
	var state := "梁架已稳，连杆接通" if supported else "梁架倾斜，连杆尚未受力"
	if triggered: state = "风铃已响，匠人的刻痕重现"
	if purged: state = "白斑消退，刻痕显影"
	draw_string(ThemeDB.fallback_font,Vector2(14,25),state,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#a9d5c3"))

func _panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#182e30")
	style.border_color = Color("#9a8960")
	style.set_border_width_all(1)
	return style
