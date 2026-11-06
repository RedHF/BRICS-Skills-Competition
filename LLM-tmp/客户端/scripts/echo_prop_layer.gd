extends Control
## Cover-fit backdrop used inside the existing dialogue picture, so physical
## clue details match investigation, repair and consequence views.
var backdrop: Texture2D
var event_id := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)

func _draw() -> void:
	if backdrop == null: return
	var factor := maxf(size.x/backdrop.get_width(),size.y/backdrop.get_height())
	var rect := Rect2((size-backdrop.get_size()*factor)*.5,backdrop.get_size()*factor)
	draw_texture_rect(backdrop,rect,false)
	preload("res://scripts/echo_props.gd").paint(self,rect,event_id)
