extends Node

const TRACE = preload("res://scripts/trace_canvas.gd")
const NETWORK = preload("res://scripts/network_client.gd")
const REPOSITORY = preload("res://scripts/data_repository.gd")
const MENU_BACKGROUND = preload("res://assets/generated/ui_01_open_scroll_main_menu_base.png")
const SKILL_EMBLEM_SHEET = preload("res://assets/generated/ui_03_skill_emblems_sheet.png")
var network = NETWORK.new()
var data = REPOSITORY.new()
var page: VBoxContainer
var status: Label
var stats: Label
var backdrop: ColorRect
var backdrop_art: TextureRect
var scroll: ScrollContainer
var current_event: Dictionary
var chapter_id := ""
var session_id := ""
var busy := false
var flow := "map"
var trace_canvas: Control
var server_pid := -1
var memory_audio: AudioStreamPlayer
var battle_elapsed := 0.0
var battle_actions: Array = []
var battle_wave := 0
var battle_hits := 0
var battle_note: Label
var battle_skills: Array[String] = []
var wave_skills: Array[String] = []
var arena: Control
var battle_ready: Dictionary = {}
var battle_buttons: Dictionary = {}
var next_attack := 3000
var echo_note: Label
var echo_button: Button
var stroke_buttons: HFlowContainer
var trace_progress: Label
var battle_finished := false
var battle_running := false
var battle_start: Button
var battle_controls: VBoxContainer
var confirmation: ConfirmationDialog
var dialogue_lines: Array = []
var dialogue_index := 0
var dialogue_done: Callable
var dialogue_title := ""
var dialogue_return: Callable
var story_progress := ConfigFile.new()
var heading: VBoxContainer
var navigation: HFlowContainer
var paused_page: VBoxContainer
var paused_flow := ""
var paused_scroll := 0
var scene_view: Control
var join_canvas: Control
var echo_bus := 0
var volume := 1.0
var muted := false
var event_audio: AudioStreamPlayer

func _ready() -> void:
	add_child(network)
	AudioServer.add_bus()
	echo_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(echo_bus, "Echo")
	var distortion := AudioEffectDistortion.new()
	distortion.mode = AudioEffectDistortion.MODE_LOFI
	distortion.drive = 0.2
	AudioServer.add_bus_effect(echo_bus, distortion)
	AudioServer.set_bus_effect_enabled(echo_bus, 0, false)
	var settings := ConfigFile.new()
	if FileAccess.file_exists("user://settings.cfg"):
		var error := settings.load("user://settings.cfg")
		if error != OK:
			push_error("设置文件读取失败：%s" % error)
			get_tree().quit(1)
			return
		else:
			volume = clampf(float(settings.get_value("audio", "volume", 1.0)), 0, 1)
			muted = bool(settings.get_value("audio", "muted", false))
	AudioServer.set_bus_volume_linear(0, volume)
	AudioServer.set_bus_mute(0, muted)
	event_audio = AudioStreamPlayer.new()
	event_audio.bus = "Echo"
	add_child(event_audio)
	memory_audio = AudioStreamPlayer.new()
	memory_audio.bus = "Echo"
	add_child(memory_audio)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	backdrop_art = TextureRect.new()
	backdrop_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop_art.texture = MENU_BACKGROUND
	backdrop_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_art.modulate = Color(1, 1, 1, 0.82)
	root.add_child(backdrop_art)
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.078, 0.149, 0.169, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	heading = VBoxContainer.new()
	column.add_child(heading)
	_label(heading, "檐 下 千 秋", 32, Color("#e4c98a"))
	_label(heading, "听古建呓语 · 拓人间记忆", 14, Color("#94b0aa"))
	stats = _label(heading, "正在连接本地服务…", 17)
	var nav := HFlowContainer.new()
	navigation = nav
	column.add_child(nav)
	_button(nav, "古建地图", _show_map)
	_button(nav, "心舍 · 墨灵", _show_memories)
	_button(nav, "记忆账册", _show_ledger)
	_button(nav, "设置", _show_settings)
	_button(nav, "剧情 · 任务", _show_journal)
	navigation.hide()
	for button in nav.get_children(): button.disabled = true
	status = _label(column, "", 16, Color("#e9bb86"))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	scroll.add_child(page)
	column.move_child(nav, column.get_child_count() - 1)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认抹去记忆"
	confirmation.ok_button_text = "亲手抹去"
	confirmation.cancel_button_text = "留下这段记忆"
	add_child(confirmation)
	heading.hide()
	flow = "splash"
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 170
	page.add_child(spacer)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/logo.svg")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 220)
	page.add_child(logo)
	var title := _label(page, "檐 下 千 秋", 36, Color("#e4c98a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := _label(page, "一笔留住千秋，一念守住人间", 18)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	await get_tree().create_timer(1.2).timeout
	heading.show()
	await _connect_server()

func _connect_server() -> void:
	_clear()
	busy = true
	network.base_url = str(ProjectSettings.get_setting("yanxia/server_url", "http://127.0.0.1:8090"))
	var config := ConfigFile.new()
	var config_path := OS.get_executable_path().get_base_dir().path_join("client.cfg")
	if FileAccess.file_exists(config_path):
		var error := config.load(config_path)
		if error != OK:
			_error("无法读取 client.cfg：%s" % error)
			return
		network.base_url = str(config.get_value("server", "url", "http://127.0.0.1:8090"))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-url="): network.base_url = argument.trim_prefix("--server-url=")
	var local_address := RegEx.create_from_string("^http://(127\\.0\\.0\\.1|localhost)(:[0-9]+)?(/|$)")
	if local_address.search(network.base_url) == null:
		_error("游戏使用本地存档，请连接本机配套服务。")
		return
	var health: Dictionary = await network.request_json("/healthz")
	if health.is_empty() and network.base_url == "http://127.0.0.1:8090" and not OS.has_feature("editor"):
		var server := OS.get_executable_path().get_base_dir().path_join("server/yanxia-server.exe")
		var content := server.get_base_dir().path_join("content/chapters.json")
		server_pid = OS.create_process(server, PackedStringArray(["-addr", "127.0.0.1:8090", "-content", content, "-data", ProjectSettings.globalize_path("user://save.json"), "-log", ProjectSettings.globalize_path("user://server.log")]), false)
		if server_pid <= 0:
			_error("无法启动配套服务端，请确认 server/yanxia-server.exe 完整。")
			return
		for attempt in range(20):
			await get_tree().create_timer(0.2).timeout
			if not OS.is_process_running(server_pid):
				_error("服务端启动失败，详情见 %s" % ProjectSettings.globalize_path("user://server.log"))
				return
			health = await network.request_json("/healthz")
			if not health.is_empty(): break
	if health.is_empty():
		_error(network.last_error)
		return
	if health.game_id != "yanxia-qianqiu" or int(health.content_version) != 7:
		_error("端口上的服务与本客户端内容版本不匹配，请关闭旧服务后重试。")
		return
	await _load_game()

func _load_game() -> void:
	var response: Dictionary = await network.request_json("/api/v1/players", HTTPClient.METHOD_POST, {})
	if response.is_empty():
		_error(network.last_error)
		return
	GameState.player = response.player
	story_progress = ConfigFile.new()
	var progress_path := "user://story-" + str(GameState.player.id) + ".cfg"
	if FileAccess.file_exists(progress_path):
		var progress_error := story_progress.load(progress_path)
		if progress_error != OK:
			_error("剧情阅读进度读取失败：%s" % progress_error)
			return
	var catalog: Dictionary = await network.request_json("/api/v1/catalog")
	if catalog.is_empty():
		_error(network.last_error)
		return
	data.catalog = catalog
	session_id = ""
	GameState.session = {}
	current_event = {}
	var pending: Dictionary = await network.request_json("/api/v1/sessions")
	if pending.is_empty():
		_error(network.last_error)
		return
	if pending.session != null:
		GameState.session = pending.session
		session_id = pending.session.id
		chapter_id = pending.session.chapter_id
		current_event = data.event(chapter_id, pending.session.event_id)
	busy = false
	navigation.show()
	for button in navigation.get_children(): button.disabled = false
	flow = "map"
	_refresh_stats()
	_show_map()

func _exit_tree() -> void:
	memory_audio.stop()
	memory_audio.stream = null
	if is_instance_valid(paused_page): paused_page.free()
	if server_pid > 0 and OS.is_process_running(server_pid):
		var error := OS.kill(server_pid)
		if error != OK: push_error("关闭本地服务失败：%s" % error)

func _error(message: String) -> void:
	busy = false
	status.text = message
	push_error(message)
	if data.catalog.is_empty(): _button(page, "重新连接服务端", _connect_server)

func _refresh_stats(erosion: int = -1) -> void:
	var p: Dictionary = GameState.player
	if erosion < 0:
		erosion = int(p.erosion)
		if flow == "battle" or (is_instance_valid(paused_page) and paused_flow == "battle"):
			erosion = mini(100, erosion + battle_hits * 5)
	var used := 0
	for memory in p.memories: used += int(memory.capacity)
	stats.text = str(p.display_name) + " · 识海 %d/%d   墨痕 %d   侵蚀 %d/100 · %s" % [used, int(p.capacity), int(p.ink_marks), erosion, "浸" if erosion < 40 else ("蚀" if erosion < 70 else "竭")]

	_apply_erosion(erosion)

func _apply_erosion(value: int) -> void:
	var base := Color("#14262b")
	if not current_event.is_empty():
		var event_art := _event_art(str(current_event.get("id", "")))
		var backdrop_color := str(event_art.get("backdrop_color", "#14262b"))
		if not backdrop_color.is_empty(): base = Color(backdrop_color)
	var mixed := base.lerp(Color("#535953"), float(value) / 100.0)
	mixed.a = 0.78
	backdrop.color = mixed
	backdrop_art.modulate = Color(1, 1, 1, 0.82 - float(value) / 500.0)
	AudioServer.set_bus_volume_db(echo_bus, -float(value) * 0.12)
	AudioServer.set_bus_effect_enabled(echo_bus, 0, value >= 40)
	if is_instance_valid(scene_view):
		scene_view.erosion = value
		scene_view.queue_redraw()

func _add_building(interactive: bool = false) -> void:
	scene_view = preload("res://scripts/building_scene.gd").new()
	scene_view.interactive = interactive
	scene_view.bridge = chapter_id == "prologue"
	scene_view.tint = Color(data.memory(current_event.reward.memory_id).color)
	scene_view.background = _event_background()
	scene_view.investigations = current_event.get("investigations", [])
	scene_view.erosion = int(GameState.player.erosion)
	var held := false
	var acquired := false
	for memory in GameState.player.memories:
		if memory.id == current_event.reward.memory_id: held = true
	for entry in GameState.player.memory_ledger:
		if entry.memory_id == current_event.reward.memory_id and entry.action == "kept": acquired = true
	scene_view.forgotten = acquired and not held
	page.add_child(scene_view)

func _event_background() -> Texture2D:
	if current_event.is_empty(): return null
	var art: Dictionary = _event_art(str(current_event.get("id", "")))
	var path := str(art.get("background", ""))
	if path.is_empty() or not ResourceLoader.exists(path): return MENU_BACKGROUND
	var texture := load(path) as Texture2D
	if texture == null: push_error("无法读取事件背景：" + path)
	return texture

func _event_art(event_id: String) -> Dictionary:
	# Catalogs from older servers may omit art for newly added events. Keep the
	# client playable with the neutral fallback instead of indexing a missing key.
	if data.catalog.is_empty(): return {}
	var art_catalog: Variant = data.catalog.get("art", {})
	if not art_catalog is Dictionary: return {}
	var value: Variant = art_catalog.get(event_id, {})
	return value if value is Dictionary else {}

func _art_banner(parent: Node, texture: Texture2D, height: float) -> TextureRect:
	var banner := TextureRect.new()
	banner.texture = texture
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.custom_minimum_size = Vector2(0, height)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(banner)
	return banner

func _pause_event() -> void:
	if flow not in ["puzzle", "choice", "battle"]: return
	paused_flow = flow
	paused_scroll = scroll.scroll_vertical
	paused_page = page
	scroll.remove_child(page)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	scroll.add_child(page)

func _show_settings() -> void:
	if busy: return
	_pause_event()
	flow = "settings"
	_clear()
	_label(page, "声音设置", 26, Color("#e4c98a"))
	_label(page, "总音量（侵蚀还会降低回声强度）", 18)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = volume
	slider.custom_minimum_size.y = 48
	page.add_child(slider)
	slider.value_changed.connect(func(value):
		volume = value
		AudioServer.set_bus_volume_linear(0, volume))
	var mute := CheckButton.new()
	mute.text = "静音"
	mute.button_pressed = muted
	page.add_child(mute)
	mute.toggled.connect(func(value):
		muted = value
		AudioServer.set_bus_mute(0, muted))
	_button(page, "保存设置", func():
		var config := ConfigFile.new()
		config.set_value("audio", "volume", volume)
		config.set_value("audio", "muted", muted)
		var error := config.save("user://settings.cfg")
		if error != OK: _error("设置保存失败：%s" % error)
		else: status.text = "声音设置已保存。")
	if not session_id.is_empty(): _button(page, "返回当前事件", _resume)

func _clear() -> void:
	status.text = ""
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0
	memory_audio.stop()
	memory_audio.stream = null
	event_audio.stop()
	if not GameState.player.is_empty(): _refresh_stats()

func _show_map() -> void:
	if busy: return
	_pause_event()
	flow = "map"
	_clear()
	status.text = "从廊桥走到墨塔，替古建找回仍有人回应的记忆。"
	_add_current_task(page)
	for chapter in data.catalog.chapters:
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#1c3235")
		style.border_color = Color("#9a8960")
		style.border_width_left = 3
		style.set_corner_radius_all(8)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 14
		style.content_margin_bottom = 14
		card.add_theme_stylebox_override("panel", style)
		page.add_child(card)
		var entries := VBoxContainer.new()
		entries.add_theme_constant_override("separation", 12)
		card.add_child(entries)
		_label(entries, chapter.title, 24, Color("#e4c98a"))
		_label(entries, chapter.summary, 17)
		for event in chapter.events:
			var done: bool = GameState.player.completed_events.has(chapter.id + ":" + event.id)
			var button := _button(entries, event.title + (" · 已修复" if done else "") + (" · 剧情草稿" if event.draft else ""), _open_event.bind(chapter.id, event.id))
			button.disabled = event.draft or not chapter.id in GameState.player.unlocked_chapters
			for previous in chapter.events:
				if int(previous.order) < int(event.order) and not GameState.player.completed_events.has(chapter.id + ":" + previous.id): button.disabled = true
	if not session_id.is_empty(): _button(page, "继续当前事件", _resume)

func _open_event(chapter: String, event: String) -> void:
	if busy: return
	if not session_id.is_empty():
		status.text = "请先继续并完成当前事件；失败后可使用回溯。"
		return
	chapter_id = chapter
	current_event = data.event(chapter, event)
	session_id = ""
	_begin_dialogue(current_event.title, current_event.story.dialogue, _show_investigation, _show_map)

func _show_investigation() -> void:
	flow = "intro"
	_clear()
	_label(page, current_event.scene + " · " + current_event.title, 26, Color("#e4c98a"))
	var memory: Dictionary = data.memory(current_event.reward.memory_id)
	_add_building(true)
	_label(page, "WASD / 方向键或左下摇杆自由移动；靠近金色目标按空格/回车调查，也可点击目标自动走近。", 16)
	var details := VBoxContainer.new()
	page.add_child(details)
	var investigation_progress := _label(details, "调查进度 0/%d" % scene_view.investigations.size(), 17, Color("#b7d8c8"))
	var discoveries := VBoxContainer.new()
	details.add_child(discoveries)
	var story_details := VBoxContainer.new()
	details.add_child(story_details)
	var completed: bool = GameState.player.completed_events.has(chapter_id + ":" + str(current_event.id))
	scene_view.investigated.connect(func(label: String, found: int, total: int):
		investigation_progress.text = "调查进度 %d/%d" % [found, total]
		_label(discoveries, "✓ " + label, 16, Color("#9ad5ad"))
		var clues: Array = current_event.get("story", {}).get("clues", [])
		for i in range(scene_view.investigations.size()):
			if scene_view.investigations[i].label == label:
				if i < clues.size(): _label(discoveries, str(clues[i]), 18)
		if found == 1 and not scene_view.forgotten:
			var event_art := _event_art(str(current_event.get("id", "")))
			var whisper_path := str(event_art.get("whisper_audio", ""))
			var sound: AudioStream = null
			if not whisper_path.is_empty(): sound = load(whisper_path) as AudioStream
			if sound == null:
				_error("无法读取调查呓语：" + whisper_path)
				return
			event_audio.stream = sound
			event_audio.play()
		if found < total: return
		for beat in current_event.story.beats: _label(story_details, beat, 20)
		if completed:
			if scene_view.forgotten: _label(story_details, memory.forgotten_text, 20)
			else: _label(story_details, current_event.story.outro, 20)
			_button(story_details, "查看这道墨灵", _memory_detail.bind(memory.id))
		else: _button(story_details, "三处调查完成 · 开始修复", _start_event))

func _start_event() -> void:
	busy = true
	var response: Dictionary = await network.request_json("/api/v1/events/%s/%s/start" % [chapter_id, current_event.id], HTTPClient.METHOD_POST, {"player_id": GameState.player.id})
	if response.is_empty():
		_error(network.last_error)
		return
	session_id = response.session_id
	chapter_id = response.chapter_id
	current_event = data.event(chapter_id, response.event_id)
	busy = false
	await _resume()

func _resume() -> void:
	if is_instance_valid(paused_page):
		_clear()
		scroll.remove_child(page)
		page.queue_free()
		page = paused_page
		paused_page = null
		scroll.add_child(page)
		flow = paused_flow
		scroll.set_deferred("scroll_vertical", paused_scroll)
		_refresh_stats()
		return
	busy = true
	var response: Dictionary = await network.request_json("/api/v1/sessions/" + session_id)
	if response.is_empty():
		_error(network.last_error)
		return
	GameState.session = response
	var player: Dictionary = await network.request_json("/api/v1/players/" + GameState.player.id)
	if player.is_empty():
		_error(network.last_error)
		return
	GameState.player = player
	_refresh_stats()
	busy = false
	if response.status == "failed":
		flow = "failed"
		_clear()
		_add_building()
		var reasons := {"erosion_limit":"侵蚀已达 100", "puzzle_attempt_limit":"修复尝试用尽", "session_expired":"旧版本事件已超时", "battle_requirements_not_met":"白蚀未清除或未施展所需技能"}
		status.text = "事件失败：%s。已拓印记忆仍保留。" % reasons.get(response.failure_reason, response.failure_reason)
		_label(page, "解谜 %d/%d · 已清除白蚀 %d 波" % [int(response.puzzle_score), int(response.puzzle_total), int(response.battle_waves)], 18)
		var retry := _button(page, "消耗 1 墨痕 · 回溯事件起点" if int(GameState.player.ink_marks) > 0 else ("序章免费重试" if chapter_id == "prologue" else "回溯需要 1 墨痕，当前不足"), _rewind)
		retry.disabled = int(GameState.player.ink_marks) == 0 and chapter_id != "prologue"
		_button(page, "返回古建地图", _show_map)
	elif response.status == "completed":
		_settlement(response.pending_result)
	elif response.accepted_steps.size() < current_event.puzzle.steps.size(): _show_puzzle()
	elif not response.choice_done: _show_choice()
	elif current_event.has("battle") and not response.battle_checked: _start_battle()
	else: await _finish()

func _rewind() -> void:
	if busy: return
	busy = true
	var response: Dictionary = await network.request_json("/api/v1/sessions/%s/rewind" % session_id, HTTPClient.METHOD_POST, {"retries": int(GameState.session.retries)})
	if response.is_empty():
		_error(network.last_error)
		return
	await _resume()

func _show_puzzle() -> void:
	flow = "puzzle"
	_clear()
	var index: int = GameState.session.accepted_steps.size()
	var step: Dictionary = current_event.puzzle.steps[index]
	_label(page, "修复 %d / %d · %s" % [index + 1, current_event.puzzle.steps.size(), current_event.title], 24, Color("#e4c98a"))
	_label(page, step.prompt, 20)
	if step.kind == "trace":
		_memory_art(page, current_event.reward.memory_id, 200)
	else:
		_add_building()
	if step.kind == "trace":
		_label(page, "拓印纸已铺开。青印为起笔，朱印为收锋；沿浅金笔势落墨即可，不必压在线心。", 17, Color("#d7c69c"))
		trace_canvas = TRACE.new()
		trace_canvas.spec = step.trace
		page.add_child(trace_canvas)
		trace_progress = _label(page, "", 16)
		stroke_buttons = HFlowContainer.new()
		page.add_child(stroke_buttons)
		for i in range(step.trace.strokes.size()):
			var button := _button(stroke_buttons, "%02d" % [i + 1], trace_canvas.select_stroke.bind(i))
			button.custom_minimum_size = Vector2(48, 42)
		trace_canvas.stroke_finished.connect(_trace_feedback)
		_trace_feedback()
		var buttons := HBoxContainer.new()
		page.add_child(buttons)
		_button(buttons, "重描本笔", func():
			trace_canvas.strokes[trace_canvas.active] = []
			trace_canvas.queue_redraw()
			_trace_feedback())
		_button(buttons, "核对拓印", func(): _submit_puzzle({"step_id": step.id, "strokes": trace_canvas.strokes}))
	elif step.kind == "join":
		join_canvas = preload("res://scripts/join_canvas.gd").new()
		join_canvas.options = step.options
		page.add_child(join_canvas)
		join_canvas.placed.connect(func(answer): _submit_puzzle({"step_id": step.id, "answer": answer}))
	elif step.kind == "skill":
		scene_view.purification = 1.0
		for skill in _learned_skills(): _button(page, "使用「%s」" % skill, _submit_puzzle.bind({"step_id": step.id, "answer": skill}))
	else:
		for option in step.options: _button(page, str(option), _submit_puzzle.bind({"step_id": step.id, "answer": option}))

func _trace_feedback() -> void:
	var count := 0
	for stroke in trace_canvas.strokes:
		if not stroke.is_empty(): count += 1
	trace_progress.text = "落墨 %d/%d · 当前第 %02d 笔%s" % [count, trace_canvas.strokes.size(), trace_canvas.active + 1, " · 朱色笔迹需要重描" if trace_canvas.failed.has(trace_canvas.active) else ""]
	for i in range(stroke_buttons.get_child_count()):
		var button: Button = stroke_buttons.get_child(i)
		button.text = str(i + 1) + (" ×" if trace_canvas.failed.has(i) else "")
		button.modulate = Color("#ff8078") if trace_canvas.failed.has(i) else (Color("#e4c98a") if i == trace_canvas.active else Color.WHITE)

func _submit_puzzle(payload: Dictionary) -> void:
	if busy: return
	busy = true
	if current_event.puzzle.steps[GameState.session.accepted_steps.size()].kind == "trace": trace_canvas.locked = true
	var response: Dictionary = await network.request_json("/api/v1/sessions/%s/puzzle" % session_id, HTTPClient.METHOD_POST, payload)
	if response.is_empty():
		_error(network.last_error)
		_button(page, "读取服务器进度后继续", _resume)
		return
	if not response.accepted and response.status != "failed":
		GameState.player.erosion = response.erosion
		_refresh_stats()
		busy = false
		if current_event.puzzle.steps[GameState.session.accepted_steps.size()].kind == "trace":
			trace_canvas.locked = false
			trace_canvas.failed = []
			for index in response.failed_strokes: trace_canvas.failed.append(int(index))
			trace_canvas.select_stroke(int(response.failed_strokes[0]))
			_trace_feedback()
			status.text = "未通过的笔画已标红，点击编号重描即可。描摹练习不扣侵蚀。"
		else:
			if current_event.puzzle.steps[GameState.session.accepted_steps.size()].kind == "join":
				join_canvas.locked = false
				join_canvas.snapped = false
				join_canvas.queue_redraw()
			status.text = "修复尚未相合，侵蚀 +10。"
		return
	if response.accepted and current_event.puzzle.steps[GameState.session.accepted_steps.size()].kind == "skill":
		var tween := create_tween()
		tween.tween_property(scene_view, "purification", 0.0, 0.7)
		await tween.finished
	await _resume()
	if response.accepted: status.text = "墨线相合，记忆显影。"

func _show_choice() -> void:
	flow = "choice"
	_clear()
	var memory: Dictionary = data.memory(current_event.reward.memory_id)
	_label(page, "墨灵显影 · " + memory.title, 26, Color(memory.color))
	_memory_art(page, memory.id, 320)
	_label(page, memory.summary, 21)
	_label(page, current_event.story.keep_response, 18)
	_label(page, "技能：%s" % memory.skill)
	if not memory.skill.is_empty(): _label(page, data.catalog.skills[memory.skill].description, 16)
	var used := 0
	for held in GameState.player.memories: used += int(held.capacity)
	var keep := _button(page, "拓印这道墨灵", _choose.bind("keep", ""))
	keep.disabled = used + int(memory.capacity) > int(GameState.player.capacity)
	_label(page, "识海满时须择一旧记忆抹去；也可主动取舍。抹除会留下账册与场景回声。", 16)
	for held in GameState.player.memories:
		if held.id == memory.id: continue
		_button(page, "并排对比「%s」与新墨灵" % held.title, _compare_memories.bind(held.id, memory.id))
		var old: Dictionary = data.memory(held.id)
		var button := _button(page, "抹去「%s」 → 拓印「%s」" % [old.title, memory.title], _confirm_forget.bind(old.id))
		button.disabled = used - int(held.capacity) + int(memory.capacity) > int(GameState.player.capacity)

func _confirm_forget(id: String) -> void:
	var memory: Dictionary = data.memory(id)
	confirmation.dialog_text = "%s\n\n%s\n\n抹除后对应色调与心舍音色消失，技能保留为残余技艺。" % [memory.title, memory.forgotten_text]
	for connection in confirmation.confirmed.get_connections(): confirmation.confirmed.disconnect(connection.callable)
	confirmation.confirmed.connect(_choose.bind("forget", id), CONNECT_ONE_SHOT)
	confirmation.popup_centered(Vector2i(460, 300))

func _choose(action: String, forget_id: String) -> void:
	if busy: return
	busy = true
	var response: Dictionary = await network.request_json("/api/v1/sessions/%s/choice" % session_id, HTTPClient.METHOD_POST, {"action": action, "forget_memory_id": forget_id})
	if response.is_empty():
		_error(network.last_error)
		_button(page, "读取服务器进度后继续", _resume)
		return
	if action == "forget":
		memory_audio.stop()
		backdrop.color = Color(0.341, 0.357, 0.349, 0.88)
		await get_tree().create_timer(0.6).timeout
	await _resume()

func _learned_skills() -> Array[String]:
	var skills: Array[String] = []
	for entry in GameState.player.memory_ledger:
		var skill: String = data.memory(entry.memory_id).skill
		if entry.action == "kept" and not skill.is_empty() and not skills.has(skill): skills.append(skill)
	return skills

func _start_battle() -> void:
	flow = "battle"
	_clear()
	battle_elapsed = 0
	battle_actions = []
	battle_wave = 0
	battle_hits = 0
	battle_finished = false
	battle_running = false
	wave_skills = []
	battle_ready = {}
	battle_buttons = {}
	next_attack = 3000
	battle_skills = _learned_skills()
	battle_ready["闪身"] = 0
	_art_banner(page, SKILL_EMBLEM_SHEET, 118)
	_label(page, "白蚀来袭", 26, Color("#e4c98a"))
	_label(page, current_event.story.get("before_battle", "守住刚刚显影的记忆。"), 20)
	_label(page, "WASD / 方向键或摇杆移动。白蚀变红锁定时保持移动会自动闪身；也可用斗拱正面防护。", 16)
	battle_note = _label(page, "", 17)
	arena = preload("res://scripts/battle_arena.gd").new()
	arena.background = _event_background()
	arena.dodge_triggered.connect(_battle_dodge)
	arena.hp = int(current_event.battle.enemy_hp)
	arena.max_hp = arena.hp
	page.add_child(arena)
	battle_start = _button(page, "开始守护 · 准备好再迎战", _begin_battle)
	battle_controls = VBoxContainer.new()
	page.add_child(battle_controls)
	for skill in ["挥墨"] + battle_skills:
		battle_ready[skill] = 0
		battle_buttons[skill] = _button(battle_controls, skill, _battle_skill.bind(skill))
		_label(battle_controls, data.catalog.skills[skill].description, 15, Color("#aac4bd"))
	status.text = "此战需至少施展一次：" + "、".join(current_event.battle.required_skills)
	_battle_update()

func _begin_battle() -> void:
	battle_running = true
	arena.active = true
	battle_start.hide()
	_battle_update()

func _battle_dodge() -> void:
	if not battle_running or battle_finished: return
	_battle_skill("闪身")

func _battle_skill(skill: String) -> void:
	if busy or battle_finished or not battle_running: return
	var at := int(battle_elapsed * 1000)
	if at < int(battle_ready[skill]): return
	var spec: Dictionary = data.catalog.skills[skill]
	battle_actions.append({"skill": skill, "at_ms": at})
	battle_ready[skill] = at + int(spec.cooldown_ms)
	if not wave_skills.has(skill): wave_skills.append(skill)
	arena.hp -= int(spec.damage)
	if int(spec.shield) > 0: arena.shield = maxi(arena.shield, int(spec.shield))
	battle_hits = maxi(0, battle_hits - int(spec.heal))
	var effect := skill
	if int(spec.damage) > 0: effect += " -%d" % int(spec.damage)
	if int(spec.shield) > 0: effect += " 护盾 +%d" % int(spec.shield)
	if int(spec.heal) > 0: effect += " 净化"
	arena.flash(effect, Color(spec.color))
	if arena.hp <= 0:
		battle_wave += 1
		arena.hp = int(current_event.battle.enemy_hp)
	_battle_update()

func _process(delta: float) -> void:
	if flow == "memory" and memory_audio.stream != null:
		var position := memory_audio.get_playback_position()
		echo_note.text = "%s  %.1f / %.1f 秒" % ["已暂停" if memory_audio.stream_paused else ("正在聆听" if memory_audio.playing else "回声播放完毕"), position, memory_audio.stream.get_length()]
		echo_button.text = "暂停回声" if memory_audio.playing and not memory_audio.stream_paused else "继续 / 重听回声"
	if flow != "battle" or battle_finished or not battle_running: return
	battle_elapsed = minf(battle_elapsed + delta, float(current_event.battle.duration_sec))
	while next_attack <= int(battle_elapsed * 1000) and battle_hits <= int(current_event.battle.max_hits_taken) and int(GameState.player.erosion) + battle_hits * 5 < 100:
		if arena.shield > 0:
			arena.shield -= 1
			arena.flash("斗拱挡住侵袭", Color("#9ad5ad"))
		else:
			battle_hits += 1
			arena.flash("侵蚀 +5", Color("#ff8078"))
		next_attack += 3000
	_battle_update()

func _battle_update() -> void:
	_refresh_stats(mini(100, int(GameState.player.erosion) + battle_hits * 5))
	arena.hits = battle_hits
	arena.phase = 1.0 - float(next_attack - int(battle_elapsed * 1000)) / 3000.0
	battle_note.text = "第 %d/%d 波 · 剩余 %d 秒 · 受蚀 %d/%d" % [mini(battle_wave + 1, int(current_event.battle.waves)), int(current_event.battle.waves), ceili(float(current_event.battle.duration_sec) - battle_elapsed), battle_hits, int(current_event.battle.max_hits_taken) + 1]
	if battle_wave == int(current_event.battle.waves) or battle_hits > int(current_event.battle.max_hits_taken) or int(GameState.player.erosion) + battle_hits * 5 >= 100 or battle_elapsed >= float(current_event.battle.duration_sec):
		battle_finished = true
		arena.active = false
		arena.defeated = battle_wave == int(current_event.battle.waves)
		var complete: bool = arena.defeated
		for skill in current_event.battle.required_skills: complete = complete and wave_skills.has(skill)
		status.text = "白蚀已驱散。" if complete else ("白蚀已散，但未施展本关要求的技能。" if arena.defeated else "墨线失守，本次战斗失败。")
		_button(page, "结算白蚀战斗", _submit_battle)
	for skill in battle_buttons:
		var remaining := maxi(0, int(battle_ready[skill]) - int(battle_elapsed * 1000))
		battle_buttons[skill].text = skill + (" · %.1f 秒" % (remaining / 1000.0) if remaining > 0 else " · 点击施展")
		battle_buttons[skill].disabled = not battle_running or battle_finished or remaining > 0

func _submit_battle() -> void:
	if busy: return
	busy = true
	var response: Dictionary = await network.request_json("/api/v1/sessions/%s/battle" % session_id, HTTPClient.METHOD_POST, {"actions": battle_actions, "duration_ms": maxi(1, int(battle_elapsed * 1000)), "waves_cleared": battle_wave, "hits_taken": battle_hits})
	if response.is_empty():
		_error(network.last_error)
		_button(page, "读取服务器进度后继续", _resume)
		return
	await _resume()

func _finish() -> void:
	busy = true
	var response: Dictionary = await network.request_json("/api/v1/sessions/%s/finish" % session_id, HTTPClient.METHOD_POST, {})
	if response.is_empty():
		_error(network.last_error)
		_button(page, "重新请求结算", _finish)
		return
	GameState.player = response.player
	_refresh_stats()
	busy = false
	_settlement(response.result)

func _settlement(result: Dictionary) -> void:
	flow = "settlement"
	_clear()
	_label(page, "古建修复 · " + "★".repeat(int(result.stars)), 30, Color("#e4c98a"))
	_memory_art(page, current_event.reward.memory_id, 320)
	_label(page, current_event.story.outro, 23)
	if GameState.session.get("choice_action", "") == "forget":
		_label(page, current_event.story.forget_response, 20)
	else:
		_label(page, current_event.story.keep_response, 20)
	_label(page, "修复度 %d%%　侵蚀 %d%%　获得墨痕 %d" % [int(result.repair_percent), int(result.erosion_at_end), int(result.ink_marks_earned)])
	if result.has("memories_acquired"):
		_label(page, "解谜 %d/%d　白蚀清除 %s　记忆保留 %d/%d" % [int(result.puzzle_score), int(result.puzzle_total), ("%d%%" % int(result.battle_clear_percent)) if current_event.has("battle") else "本事件无战斗", int(result.memories_kept), int(result.memories_acquired)], 18)
	if current_event.story.has("chapter_outro"): _label(page, current_event.story.chapter_outro, 20)
	if not str(result.get("narrative_choice", "")).is_empty():
		_label(page, "你交给人间的回答：" + str(result.narrative_choice), 22, Color("#b7d8c8"))
		_label(page, _ending_response(str(result.narrative_choice)), 21)
	_button(page, "回看这道墨灵", _memory_detail.bind(current_event.reward.memory_id))
	_button(page, "继续古建旅程", _show_map)
	session_id = ""

func _show_memories() -> void:
	if busy: return
	_pause_event()
	flow = "memories"
	_clear()
	_label(page, "心舍 · 记住的墨灵", 26, Color("#e4c98a"))
	_label(page, "拓印图录 · 每一张图，都对应一段亲手找回的往事。", 17)
	var slots := GridContainer.new()
	slots.columns = 2
	page.add_child(slots)
	var used := 0
	for held in GameState.player.memories:
		var memory: Dictionary = data.memory(held.id)
		var tile := VBoxContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots.add_child(tile)
		_memory_art(tile, memory.id, 180)
		var card := _button(tile, "%s\n%s · %d 格" % [memory.title, memory.skill, int(memory.capacity)], _memory_detail.bind(held.id))
		card.custom_minimum_size.y = 90
		used += int(memory.capacity)
	for i in range(int(GameState.player.capacity) - used):
		var empty := _button(slots, "空符诏格", func(): pass)
		empty.disabled = true
		empty.custom_minimum_size.y = 90
	_label(page, "技艺册 · 点击按钮施展", 23, Color("#e4c98a"))
	_label(page, "战斗中点击挥墨攻击，技能冷却结束后可再次施展。遗忘记忆后，习得的技艺仍然保留。", 16)
	for skill in ["挥墨"] + _learned_skills():
		_label(page, skill + " · " + data.catalog.skills[skill].description, 18)
	if not session_id.is_empty(): _button(page, "返回当前事件", _resume)

func _compare_memories(old_id: String, new_id: String) -> void:
	_pause_event()
	flow = "compare"
	_clear()
	_label(page, "墨灵对照", 26, Color("#e4c98a"))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	page.add_child(columns)
	for id in [old_id, new_id]:
		var memory: Dictionary = data.memory(id)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		_label(column, ("旧记忆 · " if id == old_id else "新墨灵 · ") + memory.title, 21, Color(memory.color))
		_memory_art(column, memory.id, 200)
		_label(column, memory.summary, 18)
		_label(column, "技能：%s\n占用：%d 格" % [memory.skill, int(memory.capacity)], 17)
		_label(column, "遗忘后：" + memory.forgotten_text, 17)
	_button(page, "返回抉择", _resume)

func _memory_detail(id: String) -> void:
	_pause_event()
	flow = "memory"
	_clear()
	var memory: Dictionary = data.memory(id)
	var remembered := false
	for held in GameState.player.memories:
		if held.id == id: remembered = true
	var memory_backdrop := Color(memory.color).darkened(0.8) if remembered else Color("#282c2b")
	memory_backdrop.a = 0.86
	backdrop.color = memory_backdrop
	_label(page, memory.title + (" · 记住" if remembered else " · 遗忘"), 28, Color(memory.color) if remembered else Color("#929996"))
	var artwork := _memory_art(page, id, 390)
	if not remembered and artwork != null: artwork.modulate = Color(0.45, 0.45, 0.45, 0.7)
	_label(page, memory.remembered_text if remembered else memory.forgotten_text, 22)
	var source: PackedStringArray = str(memory.source).split("/")
	var event: Dictionary = data.event(source[0], source[1])
	_label(page, "来历：%s / %s\n技能：%s　识海：%d 道" % [event.scene, event.title, memory.skill, int(memory.capacity)], 18)
	if not memory.skill.is_empty(): _label(page, data.catalog.skills[memory.skill].description, 17)
	if remembered:
		echo_button = _button(page, "聆听墨灵回声", _play_memory.bind(memory.echo_audio))
		echo_note = _label(page, "点击聆听这段记忆的中文回声。", 16)
	else: _label(page, "色调与音色已随记忆褪去；习得的技艺仍可用于修复。", 16)
	_button(page, "返回心舍", _show_memories)
	if not session_id.is_empty(): _button(page, "返回当前事件", _resume)

func _play_memory(path: String) -> void:
	if memory_audio.playing:
		memory_audio.stream_paused = not memory_audio.stream_paused
		return
	var sound := load(path) as AudioStream
	if sound == null:
		_error("无法读取墨灵回声：" + path)
		return
	memory_audio.stream = sound
	memory_audio.stream_paused = false
	memory_audio.play()

func _show_ledger() -> void:
	if busy: return
	_pause_event()
	flow = "ledger"
	_clear()
	_label(page, "记忆账册 · 每次抉择的来处", 26, Color("#e4c98a"))
	for entry in GameState.player.memory_ledger:
		var memory: Dictionary = data.memory(entry.memory_id)
		var trigger: Dictionary = data.event(entry.chapter_id, entry.event_id)
		_label(page, "%s「%s」 · 在「%s」作出抉择" % ["记住" if entry.action == "kept" else "遗忘", entry.title, trigger.title], 20, Color(memory.color) if entry.action == "kept" else Color("#929996"))
		_label(page, "原生记忆：%s\n%s" % [memory.source, memory.remembered_text if entry.action == "kept" else memory.forgotten_text], 16)
		_button(page, "查看当前回声", _memory_detail.bind(entry.memory_id))
	if not session_id.is_empty(): _button(page, "返回当前事件", _resume)

func _label(parent: Node, text: String, font_size: int = 18, color: Color = Color("#d9e5df")) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#29423f")
	style.border_color = Color("#688477")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color("#3d5b51")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = Color("#596447")
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := style.duplicate()
	disabled.bg_color = Color("#223236")
	disabled.border_color = Color("#344c46")
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", Color("#acb8b3"))
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(func():
		if not busy: callback.call())
	parent.add_child(button)
	return button

# Finished rubbing art is a packaged bitmap, never generated at runtime.
func _memory_art(parent: Node, id: String, height: float) -> TextureRect:
	var memory := data.memory(id)
	var title := str(memory.get("title", id))
	var path := data.memory_image_path(id)
	if path.is_empty():
		_label(parent, title + " · 拓印图待装裱", 18, Color("#b7c0b8"))
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		_label(parent, title + " · 拓印图待装裱", 18, Color("#b7c0b8"))
		return null
	return _art_banner(parent, texture, height)

func _task_event() -> Dictionary:
	for chapter in data.catalog.chapters:
		for event in chapter.events:
			if not event.draft and not GameState.player.completed_events.has(chapter.id + ":" + event.id):
				return {"chapter": chapter.id, "event": event}
	return {}

func _add_current_task(parent: Node) -> void:
	var task := _task_event()
	if task.is_empty():
		_label(parent, "全篇已完成 · 檐下的故事仍在继续", 23, Color("#e4c98a"))
		_label(parent, "你留下了 %d 段记忆、%d 条抉择。可以在剧情册回看旅程。" % [GameState.player.memories.size(), GameState.player.memory_ledger.size()], 18)
		return
	_label(parent, "当前任务 · " + str(task.event.title), 23, Color("#e4c98a"))
	for objective in task.event.objectives: _label(parent, "· " + str(objective), 17)
	if session_id.is_empty():
		_button(parent, "前往任务", _open_event.bind(task.chapter, task.event.id))
	else:
		_button(parent, "继续当前修复", _resume)

func _begin_dialogue(title: String, lines: Array, done: Callable, back: Callable) -> void:
	dialogue_title = title
	dialogue_lines = lines
	dialogue_done = done
	dialogue_return = back
	dialogue_index = clampi(int(story_progress.get_value("dialogue", title, 0)), 0, maxi(0, lines.size() - 1))
	_render_dialogue()

func _render_dialogue() -> void:
	flow = "dialogue"
	_clear()
	_label(page, dialogue_title + " · 对话 %d/%d" % [dialogue_index + 1, dialogue_lines.size()], 24, Color("#e4c98a"))
	_art_banner(page, _event_background(), 210)
	var line: Dictionary = dialogue_lines[dialogue_index]
	_label(page, str(line.speaker), 24, Color("#b7d8c8"))
	_label(page, str(line.text), 23)
	var controls := HBoxContainer.new()
	page.add_child(controls)
	var previous := _button(controls, "上一句", func():
		dialogue_index -= 1
		_save_dialogue_cursor()
		_render_dialogue())
	previous.disabled = dialogue_index == 0
	_button(controls, "下一句" if dialogue_index + 1 < dialogue_lines.size() else "对话结束 · 继续", _advance_dialogue)
	_button(page, "跳过对话 · 继续", _finish_dialogue)
	_button(page, "返回", dialogue_return)

func _save_dialogue_cursor() -> void:
	story_progress.set_value("dialogue", dialogue_title, dialogue_index)
	var error := story_progress.save("user://story-" + str(GameState.player.id) + ".cfg")
	if error != OK: status.text = "剧情阅读位置未能保存；游戏进度不受影响。"

func _advance_dialogue() -> void:
	if dialogue_index + 1 >= dialogue_lines.size():
		_finish_dialogue()
		return
	dialogue_index += 1
	_save_dialogue_cursor()
	_render_dialogue()

func _finish_dialogue() -> void:
	dialogue_index = 0
	_save_dialogue_cursor()
	dialogue_done.call()

func _show_journal() -> void:
	if busy: return
	_pause_event()
	flow = "journal"
	_clear()
	_label(page, "檐下谱 · 剧情与任务", 26, Color("#e4c98a"))
	_add_current_task(page)
	_label(page, "旅途回顾", 23, Color("#b7d8c8"))
	var count := 0
	for chapter in data.catalog.chapters:
		for event in chapter.events:
			if not GameState.player.completed_events.has(chapter.id + ":" + event.id): continue
			count += 1
			_button(page, chapter.title + " / " + event.title, _replay_story.bind(chapter.id, event.id))
	if count == 0: _label(page, "完成任务后，对话与结语会收进这里。", 18)
	if not session_id.is_empty(): _button(page, "返回当前事件", _resume)

func _replay_story(chapter: String, event_id: String) -> void:
	# Keep active event identity intact while reading completed stories.
	var event: Dictionary = data.event(chapter, event_id)
	var lines: Array = event.story.dialogue.duplicate(true)
	lines.append({"speaker": "檐下谱", "text": event.story.outro})
	var result: Dictionary = GameState.player.completed_events[chapter + ":" + event_id]
	if not str(result.get("narrative_choice", "")).is_empty():
		lines.append({"speaker": "你的回答 · " + str(result.narrative_choice), "text": _ending_response(str(result.narrative_choice))})
	for entry in GameState.player.memory_ledger:
		if entry.chapter_id == chapter and entry.event_id == event_id and entry.action == "forgotten":
			lines.append({"speaker": "心舍", "text": event.story.forget_response})
	_begin_dialogue(event.title + " · 回顾", lines, _show_journal, _show_journal)

func _ending_response(choice: String) -> String:
	return {"传下修复的方法": "你在塔下开了一间小工坊。第一位学徒没有问什么叫永恒，只问：这块坏木头，还能修吗？", "留下所有取舍的记录": "你把灰页也装订进谱。翻阅的人第一次看见修复者的迟疑，开始在页边写下自己的不同意见。", "留白让后来人续写": "你留下空白与未蘸墨的笔。一个孩子画上了今天新搭的小棚，古建们第一次听见未来的声音。"}.get(choice, "故事由后来的人继续书写。")
