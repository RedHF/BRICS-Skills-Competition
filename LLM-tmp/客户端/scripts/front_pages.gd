extends RefCounted

const WELCOME = preload("res://assets/landscape/welcome.png")
const MAP = preload("res://assets/landscape/chapters.png")
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.91, 0.89, 0.83, 0.95) if light else Color(0.055, 0.085, 0.09, 0.94)
	style.border_color = Color("#aa9064")
	style.border_width_top = 2
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	frame.add_theme_stylebox_override("panel", style)
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
	region.anchor_top = 0.53
	region.anchor_bottom = 0.93
	overlay.add_child(region)
	var box := panel(region)
	var title: Label = host._label(box, "一笔留住千秋，一念守住人间", 22, Color("#e4c98a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var saved: bool = host._has_current_event() or not GameState.player.completed_events.is_empty()
	host._button(box, "继续旅程" if saved else "启程 · 展开檐下谱", _continue)
	host._button(box, "选择关卡", host._show_map)
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
	host.status.hide()
	host.backdrop_art.texture = MAP
	host.backdrop_art.modulate = Color.WHITE
	host.backdrop.color = Color(0.04, 0.07, 0.07, 0.48)
	var top := HBoxContainer.new()
	host.page.add_child(top)
	var title: Label = host._label(top, "古建行旅", 30, Color("#f1dfb9"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count_label: Label = host._label(top, "已修复 %02d / 10 段记忆" % GameState.player.completed_events.size(), 18)
	count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	count_label.custom_minimum_size.x = 240
	var home: Button = host._button(top, "返回欢迎页", host._show_welcome)
	home.size_flags_horizontal = Control.SIZE_SHRINK_END
	home.custom_minimum_size.x = 160
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
		var state := "%d/%d" % [count, chapter.events.size()] if available else "未解锁"
		var button: Button = host._button(route, "%02d  %s\n%s" % [i+1, chapter.title, state], choose_chapter.bind(i))
		button.custom_minimum_size.y = 66
		if i == selected:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("#75613f")
			style.border_color = Color("#e4c98a")
			style.set_border_width_all(2)
			button.add_theme_stylebox_override("normal", style)
	var chapter: Dictionary = chapters[selected]
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	host.page.add_child(body)
	var art := TextureRect.new()
	art.texture = host._event_background(str(chapter.events[0].id))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.custom_minimum_size = Vector2(0, 312)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.size_flags_stretch_ratio = 1.35
	body.add_child(art)
	var details := panel(body)
	details.add_theme_constant_override("separation", 8)
	host._label(details, chapter.title, 27, Color("#e4c98a"))
	host._label(details, chapter.summary, 17)
	for event in chapter.events:
		var done: bool = GameState.player.completed_events.has(chapter.id + ":" + event.id)
		var reason := ""
		if not chapter.id in GameState.player.unlocked_chapters: reason = "完成上一章节后开放"
		else:
			for previous in chapter.events:
				if int(previous.order) < int(event.order) and not GameState.player.completed_events.has(chapter.id + ":" + previous.id):
					reason = "先完成「%s」" % previous.title
		if event.draft: reason = "尚未开放"
		var button: Button = host._button(details, ("✓  " if done else "○  ") + event.title + (" · 重访" if done else ""), host._open_event.bind(chapter.id, event.id))
		button.disabled = not reason.is_empty()
		if not reason.is_empty(): host._label(details, reason, 14, Color("#b8b8a9"))
	if host._has_current_event():
		host._button(host.page, "继续当前事件 · " + str(host.current_event.get("title", "未完的记忆")), host._resume)
