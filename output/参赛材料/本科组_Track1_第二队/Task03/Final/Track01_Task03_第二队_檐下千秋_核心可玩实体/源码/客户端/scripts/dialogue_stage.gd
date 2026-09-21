extends CanvasLayer

signal advance_requested
signal previous_requested
signal skip_requested
signal back_requested

var failure := false
var backdrop: Texture2D
var stage: Control
var picture: TextureRect
var card: PanelContainer
var title_label: Label
var speaker_label: Label
var text_label: Label
var hint: Label
var previous: Button
var skip: Button
var back: Button
var reveal: Tween
var entrance: Tween
var atmosphere: Tween
var pulse: Tween

func _ready() -> void:
	layer = 20
	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	var base := ColorRect.new()
	base.color = Color("#111d21")
	_fill(base)
	picture = TextureRect.new()
	picture.texture = backdrop
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.modulate = Color(.48,.49,.47) if failure else Color(.7,.77,.73)
	_fill(picture)
	var shade := ColorRect.new()
	shade.color = Color(0.025,0.055,0.065,.36)
	_fill(shade)
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: frame.add_theme_constant_override("margin_"+side,32)
	stage.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",18)
	frame.add_child(column)
	title_label = _label(column,"",18,Color("#d6c8a7"))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	card = PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(.055,.09,.095,.94)
	paper.border_color = Color("#b2a383")
	paper.border_width_top = 2
	paper.content_margin_left = 24
	paper.content_margin_right = 24
	paper.content_margin_top = 26
	paper.content_margin_bottom = 26
	card.add_theme_stylebox_override("panel",paper)
	column.add_child(card)
	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation",22)
	card.add_child(text_column)
	speaker_label = _label(text_column,"",24,Color("#d7bd85"))
	text_label = _label(text_column,"",26,Color("#eee8d8"))
	text_label.custom_minimum_size.y = 168
	text_label.add_theme_constant_override("line_spacing",9)
	hint = _label(text_column,"点击任意位置 · 下一句",15,Color("#9caaa3"))
	var utilities := HBoxContainer.new()
	utilities.add_theme_constant_override("separation",14)
	column.add_child(utilities)
	previous = _utility(utilities,"上一句",func(): previous_requested.emit())
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utilities.add_child(gap)
	skip = _utility(utilities,"跳过",func(): skip_requested.emit())
	back = _utility(utilities,"返回",func(): back_requested.emit())
	skip.visible = not failure
	back.visible = not failure
	# Input is intercepted before GUI dispatch; decorative Controls cannot swallow clicks.
	stage.modulate.a = 0
	entrance = create_tween()
	entrance.tween_property(stage,"modulate:a",1.0,.4)
	atmosphere = create_tween().set_loops()
	atmosphere.tween_property(picture,"self_modulate",Color(.82,.85,.86),5.0)
	atmosphere.tween_property(picture,"self_modulate",Color.WHITE,5.0)
	pulse = create_tween().set_loops()
	pulse.tween_property(hint,"modulate:a",.45,1.1)
	pulse.tween_property(hint,"modulate:a",1.0,1.1)

func _fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(control)

func _label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _utility(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.flat = true
	button.custom_minimum_size = Vector2(68,44)
	button.add_theme_font_size_override("font_size",16)
	button.add_theme_color_override("font_color",Color("#b7bcae"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func show_line(title: String, line: Dictionary, index: int, total: int, read: bool) -> void:
	if reveal and reveal.is_valid(): reveal.kill()
	title_label.text = ("残迹 · " if failure else "檐下谱 · ") + title + "    %02d / %02d" % [index+1,total]
	speaker_label.text = str(line.speaker)
	text_label.text = str(line.text)
	text_label.visible_characters = 0
	card.modulate.a = .25
	previous.disabled = index == 0
	skip.text = "已读 · 跳过" if read else "跳过"
	hint.text = "点击任意位置 · 继续" if index+1 == total else "点击任意位置 · 下一句"
	reveal = create_tween().set_parallel()
	reveal.tween_property(card,"modulate:a",1.0,.25)
	reveal.tween_property(text_label,"visible_characters",text_label.text.length(),maxf(.3,text_label.text.length()/32.0))

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			for utility in [previous,skip,back]:
				if utility.is_visible_in_tree() and utility.get_global_rect().has_point(event.position): return
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			advance_requested.emit()
	elif event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.keycode in [KEY_SPACE,KEY_ENTER,KEY_KP_ENTER]: advance_requested.emit()
		elif event.keycode == KEY_LEFT and not previous.disabled: previous_requested.emit()
		elif event.keycode == KEY_ESCAPE and not failure: back_requested.emit()
	elif event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.pressed: advance_requested.emit()

func dismiss() -> void:
	set_process_input(false)
	hide()
	queue_free()
