extends RefCounted

const WELCOME = preload("res://assets/landscape/welcome.png")
const MAP = preload("res://assets/ink_ui/background.png")
const LOGO = preload("res://assets/landscape/logo.png")
const INK = preload("res://scripts/logo_ink.gdshader")
var host: Node
var overlay: Control
var progress: ProgressBar
var message: Label
var selected := 0

func _init(main: Node) -> void:
	host = main

func logo(parent: Node, dimensions: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = LOGO
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = dimensions
	var ink := ShaderMaterial.new()
	ink.shader = INK
	art.material = ink
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	return art

func _surface(texture: Texture2D) -> void:
	if is_instance_valid(overlay):
		host.remove_child(overlay)
		overlay.queue_free()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(overlay)
	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(art)
	host.heading.hide()
	host.navigation.hide()
	host.status.hide()

func panel(parent: Node, light: bool = false) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", preload("res://scripts/ink_theme.gd").surface("paper" if light else "panel", 24))
	parent.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	frame.add_child(box)
	return box

func loading() -> void:
	_surface(MAP)
	host.flow = "loading"
	var region := CenterContainer.new()
	region.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(region)
	var box := panel(region, true)
	box.custom_minimum_size.x = 460
	logo(box, Vector2(460, 230))
	var title: Label = host._label(box, "展 卷 · 入 檐", 24, Color("#303c39"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 6
	progress.show_percentage = false
	box.add_child(progress)
	message = host._label(box, "正在准备古建记忆…", 17, Color("#4d5b55"))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func stage(value: float, text: String) -> void:
	if is_instance_valid(progress): progress.value = value
	if is_instance_valid(message): message.text = text

func connection_error(text: String) -> void:
	stage(0, "暂时无法读取旅程\n" + text)
	var box := message.get_parent()
	host._button(box, "重新加载", host._connect_server)
	host._button(box, "退出游戏", host._notification.bind(Node.NOTIFICATION_WM_CLOSE_REQUEST))

func welcome() -> void:
	_surface(WELCOME)
	host.flow = "welcome"
	var region := MarginContainer.new()
	region.anchor_left = 0.57
	region.anchor_right = 0.91
	region.anchor_top = 0.42
	region.anchor_bottom = 0.93
	overlay.add_child(region)
	var box := panel(region, true)
	var title: Label = host._label(box, "一笔留住千秋，一念守住人间", 22, Color("#e4c98a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var saved: bool = host._has_current_event() or not GameState.player.completed_events.is_empty()
	host._button(box, "继续旅程" if saved else "开始旅程", _continue)
	if saved: host._button(box, "选择关卡", host._show_map)
	host._button(box, "旅途收藏", func(): enter_game(); host._show_memories())
	var row := HBoxContainer.new()
	box.add_child(row)
	host._button(row, "声音设置", func(): enter_game(); host._show_settings())
	host._button(row, "退出", host._notification.bind(Node.NOTIFICATION_WM_CLOSE_REQUEST))

func _continue() -> void:
	enter_game()
	if host._has_current_event(): host._resume()
	else: host._show_map()

func enter_game() -> void:
	if is_instance_valid(overlay): overlay.hide()
	host.heading.show()
	host.navigation.show()
	host.status.show()

func choose_chapter(index: int) -> void:
	selected = index
	host._show_map()

func select_current() -> void:
	var chapters: Array = host.data.catalog.chapters
	for i in range(chapters.size()):
		if chapters[i].id == host.chapter_id:
			selected = i
			return
		if chapters[i].id in GameState.player.unlocked_chapters: selected = i

func map_page() -> void:
	enter_game()
	host.heading.hide()
	host.navigation.hide()
	host.status.hide()
	host.backdrop_art.texture = MAP
	host.backdrop_art.modulate = Color.WHITE
	host.backdrop.color = Color(0.94, 0.90, 0.81, 0.16)
	var top := HBoxContainer.new()
	host.page.add_child(top)
	var title_art := TextureRect.new()
	title_art.texture = preload("res://assets/ink_ui/title.png")
	title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_art.custom_minimum_size = Vector2(300, 76)
	title_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_art)
	var home: Button = host._button(top, "‹ 主页", host._show_welcome)
	home.size_flags_horizontal = Control.SIZE_SHRINK_END
	home.custom_minimum_size.x = 120
	var settings: Button = host._button(top, "设置", host._show_settings)
	settings.size_flags_horizontal = Control.SIZE_SHRINK_END
	settings.custom_minimum_size.x = 120
	var route := HBoxContainer.new()
	route.add_theme_constant_override("separation", 10)
	host.page.add_child(route)
	var chapters: Array = host.data.catalog.chapters
	selected = clampi(selected, 0, chapters.size() - 1)
	for i in range(chapters.size()):
		var chapter: Dictionary = chapters[i]
		var count := 0
		for event in chapter.events:
			if GameState.player.completed_events.has(chapter.id + ":" + event.id): count += 1
		var available: bool = chapter.id in GameState.player.unlocked_chapters
		var state := "%d / %d" % [count, chapter.events.size()] if available else "未解锁"
		var button: Button = host._button(route, "%02d\n%s\n%s" % [i+1, chapter.title, state], choose_chapter.bind(i))
		button.custom_minimum_size.y = 110
		if i == selected:
			button.add_theme_stylebox_override("normal", preload("res://scripts/ink_theme.gd").surface("paper", 12))
			button.add_theme_color_override("font_color", Color("#303832"))
	var chapter: Dictionary = chapters[selected]
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	host.page.add_child(body)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.5
	frame.add_theme_stylebox_override("panel", preload("res://scripts/ink_theme.gd").surface("frame", 8))
	body.add_child(frame)
	var art := TextureRect.new()
	art.texture = host._event_background(str(chapter.events[0].id))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.custom_minimum_size.y = 340
	frame.add_child(art)
	var details := panel(body)
	host._label(details, chapter.title, 28, Color("#f4ead3"))
	var teasers := ["风雨初歇，找回廊桥的第一段记忆。", "循香入庙，让沉寂的钟鼓再次回响。", "登上旧戏台，寻回失落的唱腔。", "走近石刻，读懂匠人留下的名字。", "登塔寻源，写下你对传承的回答。"]
	host._label(details, teasers[selected], 19, Color("#f4ead3"))
	var target: Dictionary = chapter.events[0]
	var available: bool = chapter.id in GameState.player.unlocked_chapters
	for event in chapter.events:
		if not GameState.player.completed_events.has(chapter.id + ":" + event.id):
			target = event
			break
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(spacer)
	if not available: host._label(details, "完成上一章后解锁", 18, Color("#f4ead3"))
	elif host._has_current_event(): host._label(details, "你有一段尚未完成的旅程", 18, Color("#f4ead3"))
	else: host._label(details, target.title, 18, Color("#f4ead3"))
	var continuing: bool = host._has_current_event()
	var enter: Button = host._button(details, "继续当前旅程 →" if continuing else "进入关卡 →", host._resume if continuing else host._open_event.bind(chapter.id, target.id))
	enter.disabled = not available or target.draft
	enter.add_theme_stylebox_override("normal", preload("res://scripts/ink_theme.gd").surface("paper", 16))
	enter.add_theme_color_override("font_color", Color("#303832"))
	var completed: Array = []
	for event in chapter.events:
		if GameState.player.completed_events.has(chapter.id + ":" + event.id): completed.append(event)
	if not completed.is_empty() and not continuing:
		var revisit := OptionButton.new()
		revisit.add_item("重访已完成的记忆…")
		for event in completed: revisit.add_item(event.title)
		revisit.custom_minimum_size.y = 44
		details.add_child(revisit)
		revisit.item_selected.connect(func(index):
			if index > 0: host._open_event(chapter.id, completed[index - 1].id))
