extends Control
## In-scene paper confirmation, above the game and below no native window.
signal confirmed

const INK := Color("#302c28")
const MUTED := Color("#796d5c")
var host: Node
var sheet: PanelContainer
var content: HBoxContainer
var illustration: VBoxContainer
var cancel_button: Button
var confirm_button: Button
var previous_focus: Control
var submitting := false
var layout_pending := false
var paper: Texture2D = preload("res://assets/ink_ui/paper.png")

func _text(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var label: Label = host._label(parent,value,font_size)
	label.add_theme_color_override("font_color",color)
	return label

func _ready() -> void:
	name = "ArchivePrompt"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.color = Color(.12,.10,.08,.56)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	sheet = PanelContainer.new()
	sheet.name = "ArchiveSheet"
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.add_theme_stylebox_override("panel",preload("res://scripts/ink_theme.gd").surface("paper",32))
	add_child(sheet)
	sheet.resized.connect(_center_sheet)
	sheet.minimum_size_changed.connect(_request_layout)
	sheet.draw.connect(func():
		sheet.draw_texture_rect_region(paper,Rect2(Vector2.ZERO,sheet.size),Rect2(120,60,430,230),Color(1,1,1,.14)))
	resized.connect(_fit)
	hide()

func open(memory: Dictionary, consequence: String, incoming_title: String = "") -> void:
	if host.busy or visible: return
	previous_focus = get_viewport().gui_get_focus_owner()
	submitting = false
	for child in sheet.get_children():
		sheet.remove_child(child)
		child.queue_free()
	content = HBoxContainer.new()
	content.add_theme_constant_override("separation",30)
	sheet.add_child(content)
	illustration = VBoxContainer.new()
	illustration.add_theme_constant_override("separation",12)
	content.add_child(illustration)
	var art := TextureRect.new()
	art.name = "MemoryPrint"
	art.texture = load(host.data.memory_image_path(str(memory.id)))
	art.custom_minimum_size = Vector2(202,278)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	illustration.add_child(art)
	var caption: Label = _text(illustration,"一页旧迹，留在檐下",16,MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	notes.add_theme_constant_override("separation",14)
	content.add_child(notes)
	_text(notes,"檐 下 谱  /  回 声 取 舍",16,MUTED)
	_text(notes,"将这段回声归档？",28,INK)
	_text(notes,"「%s」" % memory.title,23,Color("#9a593e"))
	var clauses := consequence.split("；",false,1)
	_text(notes,str(clauses[-1]),21,INK)
	var line := HSeparator.new()
	var rule := StyleBoxLine.new()
	rule.color = Color("#c4b38d")
	rule.thickness = 1
	line.add_theme_stylebox_override("separator",rule)
	notes.add_child(line)
	_text(notes,"记录、修复与技艺保留，可在檐下谱回看。",17,MUTED)
	if not incoming_title.is_empty(): _text(notes,"「%s」将留在心舍。" % incoming_title,18,INK)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",14)
	notes.add_child(actions)
	cancel_button = host._button(actions,"再想想",cancel)
	cancel_button.name = "CancelArchive"
	var quiet := preload("res://scripts/ink_theme.gd").surface("paper",12)
	cancel_button.add_theme_stylebox_override("normal",quiet)
	cancel_button.add_theme_color_override("font_color",INK)
	cancel_button.add_theme_color_override("font_focus_color",INK)
	cancel_button.add_theme_color_override("font_hover_color",INK)
	var quiet_hover: StyleBoxFlat = quiet.duplicate()
	quiet_hover.bg_color = Color("#f1e3bf")
	quiet_hover.border_color = Color("#b99a5c")
	cancel_button.add_theme_stylebox_override("hover",quiet_hover)
	confirm_button = host._button(actions,"确认归档",accept)
	confirm_button.name = "ConfirmArchive"
	cancel_button.custom_minimum_size = Vector2(140,50)
	confirm_button.custom_minimum_size = Vector2(170,50)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0,0,0,0)
	focus.border_color = Color("#b99a5c")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(4)
	for button in [cancel_button,confirm_button]: button.add_theme_stylebox_override("focus",focus)
	_fit()
	sheet.reset_size()
	show()
	_request_layout()
	cancel_button.grab_focus.call_deferred()

func _request_layout() -> void:
	if layout_pending: return
	layout_pending = true
	_settle_layout.call_deferred()

func _settle_layout() -> void:
	# Wrapped labels must first receive the current column width; otherwise
	# the previously hidden sheet can retain a tall minimum from a narrow pass.
	await get_tree().process_frame
	layout_pending = false
	if not visible: return
	sheet.reset_size()
	_center_sheet()

func _center_sheet() -> void:
	if is_instance_valid(sheet): sheet.position = (size-sheet.size)*.5

func _fit() -> void:
	if not is_instance_valid(sheet): return
	sheet.custom_minimum_size.x = minf(860,size.x-48)
	if is_instance_valid(illustration): illustration.visible = size.x >= 760
	sheet.reset_size()
	_center_sheet()
	sheet.queue_redraw()

func cancel() -> void:
	if not visible or submitting: return
	hide()
	if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree(): previous_focus.grab_focus()

func accept() -> void:
	if not visible or submitting or host.busy: return
	submitting = true
	hide()
	confirmed.emit()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB:
			if get_viewport().gui_get_focus_owner() == cancel_button: confirm_button.grab_focus()
			else: cancel_button.grab_focus()
			get_viewport().set_input_as_handled()
