extends Node

const TRACE = preload("res://scripts/trace_canvas.gd")
const NETWORK = preload("res://scripts/network_client.gd")
const REPOSITORY = preload("res://scripts/data_repository.gd")
const MENU_BACKGROUND = preload("res://assets/ink_ui/background.png")

var front: RefCounted
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
var battle_controls: GridContainer
var battle_dock: VBoxContainer
var erosion_bar: ProgressBar
var skill_scene: Control
var soundscape: Node
var confirmation: ConfirmationDialog
var dialogue_lines: Array = []
var dialogue_index := 0
var dialogue_done: Callable
var dialogue_title := ""
var dialogue_return: Callable
var dialogue_stage: CanvasLayer
var dialogue_background: Texture2D
var dialogue_mode := "story"
var dialogue_key := ""
var failure_key := ""
var story_progress := ConfigFile.new()
var heading: VBoxContainer
var navigation: GridContainer
var paused_page: VBoxContainer
var paused_flow := ""
var paused_scroll := 0
var scene_view: Control
var join_canvas: Control
var echo_bus := 0
var volume := 1.0
var muted := false
var event_audio: AudioStreamPlayer
var closing := false
const BATTLE_KEYS := ["挥墨", "斗拱", "藻井", "飞檐", "闪身"]
var voice_index: Dictionary = {}
var voice_queue: Array[String] = []

func _ready() -> void:
	get_tree().auto_accept_quit = false
	front = preload("res://scripts/front_pages.gd").new(self)
	add_child(network)
	soundscape = preload("res://scripts/soundscape.gd").new()
	add_child(soundscape)
	AudioServer.add_bus()
	echo_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(echo_bus, "Echo")
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
	# All speech stays clean; erosion only gently attenuates collectible echoes.
	voice_index = JSON.parse_string(FileAccess.get_file_as_string("res://assets/voice/index.json"))
	event_audio.finished.connect(_voice_next)
	add_child(event_audio)
	memory_audio = AudioStreamPlayer.new()
	memory_audio.bus = "Echo"
	memory_audio.finished.connect(func(): soundscape.duck(false))
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
	root.resized.connect(func():
		var side := maxi(20, int((root.size.x - 1440) / 2))
		margin.add_theme_constant_override("margin_left", side)
		margin.add_theme_constant_override("margin_right", side))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	heading = VBoxContainer.new()
	column.add_child(heading)
	_label(heading, "檐下千秋  /  檐下谱", 20, Color("#e4c98a"))
	stats = _label(heading, "正在连接本地服务…", 17)
	erosion_bar = ProgressBar.new()
	erosion_bar.custom_minimum_size.y = 12
	erosion_bar.show_percentage = false
	heading.add_child(erosion_bar)
	var nav := GridContainer.new()
	nav.columns = 2
	nav.size_flags_horizontal = Control.SIZE_SHRINK_END
	nav.custom_minimum_size.x = 280
	navigation = nav
	heading.add_child(nav)
	_button(nav, "‹ 返回关卡", _show_map)
	_button(nav, "设置", _show_settings)
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
	battle_dock = VBoxContainer.new()
	column.add_child(battle_dock)
	battle_dock.hide()

	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认抹去记忆"
	confirmation.ok_button_text = "亲手抹去"
	confirmation.cancel_button_text = "留下这段记忆"
	add_child(confirmation)
	await _connect_server()

func _connect_server() -> void:
	_clear()
	front.loading()
	await get_tree().process_frame
	front.stage(15, "正在连接本地存档…")
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
	if health.game_id != "yanxia-qianqiu" or int(health.content_version) != 10:
		_error("端口上的服务与本客户端内容版本不匹配，请关闭旧服务后重试。")
		return
	front.stage(45, "正在读取旅程…")
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
	front.stage(65, "正在展开五章古建…")
	var catalog: Dictionary = await network.request_json("/api/v1/catalog")
	if catalog.is_empty():
		_error(network.last_error)
		return
	data.catalog = catalog
	session_id = ""
	GameState.session = {}
	current_event = {}
	front.stage(85, "正在恢复未完的记忆…")
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
	front.select_current()
	front.stage(100, "檐下谱已就绪")
	await get_tree().process_frame
	_show_welcome()

func _show_welcome() -> void:
	if busy: return
	_pause_event()
	_clear()
	front.welcome()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not closing:
		closing = true
		_stop_voice()
		soundscape.stop_all()
		for player in [memory_audio, event_audio]:
			player.stop()
			player.stream = null
		# Let the audio server retire playback before the engine shuts down.
		await get_tree().create_timer(.3).timeout
		get_tree().quit()

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
	if flow == "loading": front.connection_error(message)
	elif data.catalog.is_empty(): _button(page, "重新连接服务端", _connect_server)

func _refresh_stats(erosion: int = -1) -> void:
	var p: Dictionary = GameState.player
	if erosion < 0:
		erosion = int(p.erosion)
		if flow == "battle" or (is_instance_valid(paused_page) and paused_flow == "battle"):
			erosion = mini(100, erosion + battle_hits * 5)
	var used := 0
	for memory in p.memories: used += int(memory.capacity)
	stats.text = str(p.display_name) + " · 识海 %d/%d   墨痕 %d   侵蚀 %d/100 · %s" % [used, int(p.capacity), int(p.ink_marks), erosion, "浸" if erosion < 40 else ("蚀" if erosion < 70 else "竭")]

	erosion_bar.value = erosion
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#83bfa4") if erosion < 40 else (Color("#d8b67c") if erosion < 70 else Color("#d78275"))
	erosion_bar.add_theme_stylebox_override("fill", fill)
	_apply_erosion(erosion)

func _apply_erosion(value: int) -> void:
	backdrop_art.texture = MENU_BACKGROUND
	backdrop_art.modulate = Color.WHITE
	backdrop.color = Color(0.93, 0.90, 0.82, 0.70 + float(value) / 1000.0)
	AudioServer.set_bus_volume_db(echo_bus, -float(value) * 0.04)
	if is_instance_valid(scene_view):
		scene_view.erosion = value
		scene_view.queue_redraw()

func _add_building(interactive: bool = false) -> void:
	scene_view = preload("res://scripts/building_scene.gd").new()
	scene_view.interactive = interactive
	scene_view.bridge = chapter_id == "prologue"
	scene_view.tint = Color(data.memory(current_event.reward.memory_id).color)
	scene_view.background = _event_background()
	var eroded_path := str(_event_art(str(current_event.id)).get("eroded_background", ""))
	if not eroded_path.is_empty(): scene_view.eroded_background = load(eroded_path)
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

func _event_background(event_id: String = "") -> Texture2D:
	if event_id.is_empty():
		if current_event.is_empty(): return null
		event_id = str(current_event.id)
	var art: Dictionary = _event_art(event_id)
	var path := str(art.get("background", ""))
	if path.is_empty() or not ResourceLoader.exists(path): return MENU_BACKGROUND
	var texture := load(path) as Texture2D
	if texture == null: push_error("无法读取事件背景：" + path)
	return texture

func _event_art(event_id: String) -> Dictionary:
	var landscape := "res://assets/landscape/" + event_id + ".jpeg"
	if ResourceLoader.exists(landscape):
		return {"background": landscape, "backdrop_color": "#263331"}
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
	if flow not in ["intro", "puzzle", "choice", "battle"]: return
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
	_button(page, "切换全屏 / 窗口", func():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN))
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
	if _has_current_event(): _button(page, "返回当前事件", _resume)
	_button(page, "返回关卡选择", _show_map)
	_button(page, "返回欢迎页", _show_welcome)

func _has_current_event() -> bool:
	return not session_id.is_empty() or is_instance_valid(paused_page)

func _clear() -> void:
	_close_dialogue()
	if flow not in ["map", "loading", "welcome", "splash"]: front.enter_game()
	_layout_landscape.call_deferred()
	if is_instance_valid(battle_dock): battle_dock.visible = flow == "battle"
	if is_instance_valid(soundscape): soundscape.set_battle(flow == "battle")
	status.text = ""
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0
	memory_audio.stop()
	memory_audio.stream = null
	_stop_voice()
	if not GameState.player.is_empty(): _refresh_stats()

func _show_map() -> void:
	if busy: return
	_pause_event()
	flow = "map"
	_clear()
	front.map_page()

func _open_event(chapter: String, event: String) -> void:
	if busy: return
	front.enter_game()
	if is_instance_valid(paused_page) and chapter == chapter_id and event == str(current_event.id):
		await _resume()
		return
	if is_instance_valid(paused_page) and session_id.is_empty():
		# An unstarted investigation may be left for another unlocked scene.
		paused_page.free()
		paused_page = null
	if not session_id.is_empty():
		status.text = "请先继续并完成当前事件；失败后可使用回溯。"
		return
	chapter_id = chapter
	current_event = data.event(chapter, event)
	session_id = ""
	var lines: Array = current_event.story.dialogue.duplicate(true)
	for i in range(lines.size()): lines[i]["audio_cue"] = str(current_event.id) + "_dialogue_%02d" % (i+1)
	_begin_dialogue(current_event.title, lines, _show_investigation, _show_map)

func _show_investigation() -> void:
	flow = "intro"
	_clear()
	_label(page, current_event.scene + " · " + current_event.title, 26, Color("#e4c98a"))
	var memory: Dictionary = data.memory(current_event.reward.memory_id)
	_add_building(true)
	_label(page, "点击金色标记调查 · 也可方向键移动、空格调查", 16)
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
		for old in discoveries.get_children():
			discoveries.remove_child(old)
			old.queue_free()
		_label(discoveries, "✓ " + label, 16, Color("#9ad5ad"))
		var clues: Array = current_event.get("story", {}).get("clues", [])
		for i in range(scene_view.investigations.size()):
			if scene_view.investigations[i].label == label:
				if i < clues.size(): _label(discoveries, str(clues[i]), 18)
		for i in range(scene_view.investigations.size()):
			if scene_view.investigations[i].label == label:
				_play_cues([str(current_event.id) + "_clue_%02d" % (i+1)])
		if found < total: return
		var beat_cues: Array = []
		for i in range(current_event.story.beats.size()):
			beat_cues.append(str(current_event.id) + "_beat_%02d" % (i+1))
		_button(story_details, "聆听往事（可选）", func(): _play_cues(beat_cues))
		if completed:
			if scene_view.forgotten: _label(story_details, memory.forgotten_text, 20)
			else: _label(story_details, current_event.story.outro, 20)
			_button(story_details, "查看这道墨灵", _memory_detail.bind(memory.id))
		else: _button(story_details, "开始修复 →", _start_event))

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
	front.enter_game()
	backdrop_art.texture = MENU_BACKGROUND
	if is_instance_valid(paused_page):
		_clear()
		scroll.remove_child(page)
		page.queue_free()
		page = paused_page
		paused_page = null
		scroll.add_child(page)
		flow = paused_flow
		battle_dock.visible = flow == "battle"
		soundscape.set_battle(flow == "battle")
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
		_begin_failure()
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
		_memory_art(page, current_event.reward.memory_id, 130)
	elif step.kind != "skill" and step.id not in ["opera_role", "archway_grade"]:
		_add_building()
	if step.kind == "trace":
		_label(page, "按住拖动：从青印描到朱印。", 17, Color("#d7c69c"))
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
		skill_scene = preload("res://scripts/skill_scene.gd").new()
		skill_scene.accepted = GameState.session.accepted_steps
		page.add_child(skill_scene)
		_label(page, "斗拱承重，飞檐触及远端，藻井净化显影。选好技艺后点击构件。", 17)
		var tools_row := HBoxContainer.new()
		page.add_child(tools_row)
		for skill in _learned_skills():
			_button(tools_row, skill, func():
				skill_scene.selected = skill
				status.text = "已选「%s」，请点击作用构件。" % skill)
		skill_scene.applied.connect(func(skill, target): _submit_puzzle({"step_id":step.id, "answer":skill, "target":target}))
	elif step.id in ["opera_role", "archway_grade"]:
		_label(page, "观察图式，选择相符的一项。", 17)
		var options := HBoxContainer.new()
		page.add_child(options)
		for i in range(step.options.size()):
			var option = preload("res://scripts/pattern_option.gd").new()
			option.motif = str(step.options[i])
			option.choice_index = i
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.pressed.connect(func(): _submit_puzzle({"step_id":step.id, "answer":step.options[i]}))
			options.add_child(option)
	else:
		for option in step.options: _button(page, str(option), _submit_puzzle.bind({"step_id": step.id, "answer": option}))

	var clues: Array = current_event.get("story", {}).get("clues", [])
	if not clues.is_empty():
		var clue_box := VBoxContainer.new()
		var help := _button(page, "查看调查线索", func(): clue_box.visible = not clue_box.visible)
		help.tooltip_text = "需要时再展开本关调查线索"
		page.add_child(clue_box)
		for clue in clues: _label(clue_box, str(clue), 16)
		clue_box.hide()

func _trace_feedback() -> void:
	var count := 0
	for stroke in trace_canvas.strokes:
		if not stroke.is_empty(): count += 1
	trace_progress.text = "落墨 %d/%d · 当前第 %02d 笔%s" % [count, trace_canvas.strokes.size(), trace_canvas.active + 1, " · 朱色笔迹需要重描" if trace_canvas.failed.has(trace_canvas.active) else ""]
	for i in range(stroke_buttons.get_child_count()):
		var button: Button = stroke_buttons.get_child(i)
		button.text = "%02d" % [i + 1] + (" ×" if trace_canvas.failed.has(i) else "")
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
		soundscape.cue("repair")
		skill_scene.accepted = GameState.session.accepted_steps.duplicate()
		skill_scene.accepted.append(payload.step_id)
		skill_scene.locked = true
		skill_scene.queue_redraw()
		await get_tree().create_timer(0.35).timeout
	await _resume()
	if response.accepted: status.text = "墨线相合，记忆显影。"

func _show_choice() -> void:
	flow = "choice"
	_clear()
	var memory: Dictionary = data.memory(current_event.reward.memory_id)
	_label(page, "墨灵显影 · " + memory.title, 26, Color(memory.color))
	_memory_art(page, memory.id, 320)
	_label(page, memory.summary, 21)
	_play_cues([str(current_event.id) + "_keep"])
	_label(page, "技能：%s" % memory.skill)
	if not memory.skill.is_empty(): _label(page, data.catalog.skills[memory.skill].description, 16)
	var used := 0
	for held in GameState.player.memories: used += int(held.capacity)
	var keep := _button(page, "拓印这道墨灵", _choose.bind("keep", ""))
	keep.disabled = used + int(memory.capacity) > int(GameState.player.capacity)
	if used + int(memory.capacity) <= int(GameState.player.capacity): return
	_label(page, "记忆空间已满，请替换一段旧记忆。技艺仍会保留。", 16)
	for held in GameState.player.memories:
		if held.id == memory.id: continue
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
	var boss_name := str(current_event.battle.get("boss_name", ""))
	_label(page, "首领战 · " + boss_name if not boss_name.is_empty() else "白蚀来袭", 26, Color("#e4c98a"))
	if not boss_name.is_empty():
		_label(page, "第三项技艺 · 飞檐已习得。先清除游蚀，再迎战噤声客；首领每 2.4 秒侵袭，记得护盾与闪身。", 17)
	_play_cues([str(current_event.id) + "_before_battle"])
	_label(page, current_event.story.get("before_battle", "守住刚刚显影的记忆。"), 17)
	_label(page, "1 挥墨　2 斗拱　3 藻井　4 飞檐　5 闪身\n数字键或点击施展；未习得的技艺暂不可用。", 16)
	battle_note = _label(page, "", 17)
	arena = preload("res://scripts/battle_arena.gd").new()
	arena.background = _event_background()
	arena.dodge_triggered.connect(_battle_dodge)
	arena.hp = _wave_hp()
	arena.max_hp = arena.hp
	page.add_child(arena)
	for child in battle_dock.get_children():
		battle_dock.remove_child(child)
		child.queue_free()
	battle_start = _button(battle_dock, "开始守护 · 准备好再迎战", _begin_battle)
	battle_controls = GridContainer.new()
	battle_controls.columns = 5
	battle_dock.add_child(battle_controls)
	for skill in BATTLE_KEYS:
		if skill not in ["挥墨", "闪身"] and not battle_skills.has(skill): continue
		battle_ready[skill] = 0
		battle_buttons[skill] = _button(battle_controls, skill, _battle_skill.bind(skill))
		battle_buttons[skill].tooltip_text = data.catalog.skills[skill].description
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
	soundscape.cue("ink" if int(spec.damage) > 0 else "repair")
	if arena.hp <= 0:
		battle_wave += 1
		arena.hp = _wave_hp()
		arena.max_hp = arena.hp
		if _boss_wave():
			next_attack = at + _attack_interval()
			arena.flash("噤声客现身", Color("#e9b991"))
			soundscape.cue("hit")
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
			soundscape.cue("hit")
		next_attack += _attack_interval()
	_battle_update()

func _battle_update() -> void:
	_refresh_stats(mini(100, int(GameState.player.erosion) + battle_hits * 5))
	arena.hits = battle_hits
	arena.phase = 1.0 - float(next_attack - int(battle_elapsed * 1000)) / float(_attack_interval())
	arena.boss_name = str(current_event.battle.get("boss_name", "")) if _boss_wave() else ""
	battle_note.text = "第 %d/%d 波 · 剩余 %d 秒 · 受蚀 %d/%d" % [mini(battle_wave + 1, int(current_event.battle.waves)), int(current_event.battle.waves), ceili(float(current_event.battle.duration_sec) - battle_elapsed), battle_hits, int(current_event.battle.max_hits_taken) + 1]
	if battle_wave == int(current_event.battle.waves) or battle_hits > int(current_event.battle.max_hits_taken) or int(GameState.player.erosion) + battle_hits * 5 >= 100 or battle_elapsed >= float(current_event.battle.duration_sec):
		battle_finished = true
		arena.active = false
		arena.defeated = battle_wave == int(current_event.battle.waves)
		var complete: bool = arena.defeated
		for skill in current_event.battle.required_skills: complete = complete and wave_skills.has(skill)
		status.text = "白蚀已驱散。" if complete else ("白蚀已散，但未施展本关要求的技能。" if arena.defeated else "墨线失守，本次战斗失败。")
		_button(battle_dock, "结算白蚀战斗", _submit_battle)
		soundscape.cue("win" if complete else "hit")
	for skill in battle_buttons:
		var remaining := maxi(0, int(battle_ready[skill]) - int(battle_elapsed * 1000))
		battle_buttons[skill].text = "%d · %s" % [BATTLE_KEYS.find(skill)+1, skill] + (" · %.1f 秒" % (remaining / 1000.0) if remaining > 0 else " · 点击施展")
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
	_settlement(response.result, str(response.get("reason","")) == "settled")

func _settlement(result: Dictionary, first_clear: bool = false) -> void:
	flow = "settlement"
	_clear()
	var stars := _label(page, "古建修复 · " + "★".repeat(int(result.stars)), 30, Color("#e4c98a"))
	stars.visible_characters = 7
	var reveal := create_tween()
	reveal.tween_property(stars, "visible_characters", stars.text.length(), 0.9)
	_memory_art(page, current_event.reward.memory_id, 320)
	_label(page, current_event.story.outro, 23)
	var ending_cues: Array = [str(current_event.id) + "_outro", str(current_event.id) + ("_forget" if GameState.session.get("choice_action", "") == "forget" else "_keep")]
	if current_event.story.has("chapter_outro"): ending_cues.append(str(current_event.id) + "_chapter_outro")
	_play_cues(ending_cues)
	var whisper_key := chapter_id + ":" + str(current_event.id)
	var whisper := str(current_event.story.get("first_clear_whisper",""))
	if first_clear and not whisper.is_empty() and not bool(story_progress.get_value("whisper",whisper_key,false)):
		story_progress.set_value("whisper",whisper_key,true)
		var saved := story_progress.save("user://story-" + str(GameState.player.id) + ".cfg")
		if saved != OK: status.text = "呓语阅读标记保存失败。"
		_play_cues([str(current_event.id) + "_first_clear"], true)
		var aside := _label(page,"戏楼：" + whisper,21,Color("#c5caba"))
		aside.visible_characters = 0
		aside.create_tween().tween_property(aside,"visible_characters",aside.text.length(),aside.text.length()/32.0)
	_label(page, "修复 %d%%   侵蚀 %d%%   墨痕 +%d" % [int(result.repair_percent), int(result.erosion_at_end), int(result.ink_marks_earned)])
	if not str(result.get("narrative_choice", "")).is_empty():
		_label(page, "你交给人间的回答：" + str(result.narrative_choice), 22, Color("#b7d8c8"))
		_label(page, _ending_response(str(result.narrative_choice)), 21)
	_button(page, "回看这道墨灵", _memory_detail.bind(current_event.reward.memory_id))
	_button(page, "下一段旅程 →", _next_event)
	_button(page, "返回关卡", _show_map)
	session_id = ""

func _show_memories() -> void:
	if busy: return
	_pause_event()
	flow = "memories"
	_clear()
	_label(page, "旅途收藏 · 记忆图录", 26, Color("#e4c98a"))
	var tabs := HBoxContainer.new()
	page.add_child(tabs)
	_button(tabs, "往事回放", _show_journal)
	_button(tabs, "取舍记录", _show_ledger)
	_button(tabs, "返回主页", _show_welcome)
	if GameState.player.memories.is_empty(): _label(page, "修复第一座古建后，记忆会收藏在这里。", 20)
	var slots := GridContainer.new()
	slots.columns = 3
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
	if _has_current_event(): _button(page, "返回游戏", _resume)

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
	backdrop.color = Color(0.93, 0.90, 0.82, 0.80)
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
	_button(page, "返回收藏", _show_memories)
	if _has_current_event(): _button(page, "返回当前事件", _resume)

func _play_memory(path: String) -> void:
	_stop_voice()
	if memory_audio.playing:
		memory_audio.stream_paused = not memory_audio.stream_paused
		soundscape.duck(not memory_audio.stream_paused)
		return
	var sound := load(path) as AudioStream
	if sound == null:
		_error("无法读取墨灵回声：" + path)
		return
	memory_audio.stream = sound
	memory_audio.stream_paused = false
	memory_audio.play()
	soundscape.duck(true)

func _show_ledger() -> void:
	if busy: return
	_pause_event()
	flow = "ledger"
	_clear()
	_label(page, "取舍记录", 26)
	_button(page, "返回收藏", _show_memories)
	if GameState.player.memory_ledger.is_empty(): _label(page, "还没有取舍记录。", 20)
	for entry in GameState.player.memory_ledger:
		var memory: Dictionary = data.memory(entry.memory_id)
		var trigger: Dictionary = data.event(entry.chapter_id, entry.event_id)
		_label(page, "%s「%s」 · 在「%s」作出抉择" % ["记住" if entry.action == "kept" else "遗忘", entry.title, trigger.title], 20, Color(memory.color) if entry.action == "kept" else Color("#929996"))
		_button(page, "查看当前回声", _memory_detail.bind(entry.memory_id))
	if _has_current_event(): _button(page, "返回当前事件", _resume)

func _label(parent: Node, text: String, font_size: int = 18, color: Color = Color("#303832")) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#303832") if color != Color("#f4ead3") else color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var style = preload("res://scripts/ink_theme.gd").surface("ink", 12)
	button.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.modulate_color = Color("#d8c393")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", preload("res://scripts/ink_theme.gd").surface("paper", 12))
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_color_override("font_color", Color("#f4ead3"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("#303832"))
	button.add_theme_color_override("font_disabled_color", Color("#999d96"))
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(func():
		if not busy:
			soundscape.cue("ui")
			callback.call())
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
	var art := _art_banner(parent, texture, height)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return art

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
		if _has_current_event(): _button(parent, "继续当前修复", _resume)
		return
	_label(parent, "当前任务 · " + str(task.event.title), 23, Color("#e4c98a"))
	for objective in task.event.objectives: _label(parent, "· " + str(objective), 17)
	if not _has_current_event():
		_button(parent, "前往任务", _open_event.bind(task.chapter, task.event.id))
	else:
		_button(parent, "继续当前修复", _resume)

func _close_dialogue() -> void:
	_stop_voice()
	if is_instance_valid(dialogue_stage):
		dialogue_stage.dismiss()
	dialogue_stage = null

func _begin_dialogue(title: String, lines: Array, done: Callable, back: Callable, mode: String = "story", key: String = "", background: Texture2D = null) -> void:
	_close_dialogue()
	dialogue_background = background
	dialogue_title = title
	dialogue_key = key if not key.is_empty() else title
	dialogue_mode = mode
	dialogue_lines = lines
	dialogue_done = done
	dialogue_return = back
	dialogue_index = clampi(int(story_progress.get_value("dialogue", dialogue_key, 0)), 0, maxi(0, lines.size() - 1))
	_render_dialogue()

func _render_dialogue() -> void:
	flow = "gameover" if dialogue_mode == "failure" else "dialogue"
	if not is_instance_valid(dialogue_stage):
		_clear()
		dialogue_stage = preload("res://scripts/dialogue_stage.gd").new()
		dialogue_stage.failure = dialogue_mode == "failure"
		dialogue_stage.backdrop = load("res://assets/landscape/failure.jpeg") if dialogue_mode == "failure" else _event_background()
		if dialogue_background != null: dialogue_stage.backdrop = dialogue_background
		add_child(dialogue_stage)
		dialogue_stage.advance_requested.connect(_advance_dialogue)
		dialogue_stage.previous_requested.connect(_previous_dialogue)
		dialogue_stage.skip_requested.connect(_finish_dialogue)
		dialogue_stage.back_requested.connect(func(): dialogue_return.call())
	if dialogue_mode == "failure":
		var reason := str(GameState.session.get("failure_reason", ""))
		var cue := "failure_first_" + reason if dialogue_index == 0 and data.catalog.failure_scene.first_lines.has(reason) else "failure_line_%02d" % (dialogue_index+1)
		_play_cues([cue])
	else:
		var line: Dictionary = dialogue_lines[dialogue_index]
		_play_cues([str(line.get("audio_cue", voice_index.get("lines", {}).get(str(line.text), "")))])
	dialogue_stage.show_line(dialogue_title, dialogue_lines[dialogue_index], dialogue_index, dialogue_lines.size(), bool(story_progress.get_value("read",dialogue_key,false)))

func _previous_dialogue() -> void:
	if dialogue_index == 0: return
	dialogue_index -= 1
	_save_dialogue_cursor()
	_render_dialogue()

func _save_dialogue_cursor() -> void:
	story_progress.set_value("dialogue", dialogue_key, dialogue_index)
	var error := story_progress.save("user://story-" + str(GameState.player.id) + ".cfg")
	if error != OK: status.text = "剧情阅读位置未能保存；游戏进度不受影响。"

func _advance_dialogue() -> void:
	if busy or not is_instance_valid(dialogue_stage): return
	if dialogue_index + 1 >= dialogue_lines.size():
		_finish_dialogue()
		return
	dialogue_index += 1
	_save_dialogue_cursor()
	_render_dialogue()

func _finish_dialogue() -> void:
	# Failure recovery is revealed only after the ninth line; there is no skip control.
	if dialogue_mode == "failure" and dialogue_index + 1 < dialogue_lines.size(): return
	story_progress.set_value("read", dialogue_key, true)
	dialogue_index = 0
	_save_dialogue_cursor()
	_close_dialogue()
	dialogue_done.call()

func _begin_failure() -> void:
	failure_key = "failure:" + session_id + ":" + str(GameState.session.retries)
	if bool(story_progress.get_value("read",failure_key,false)):
		_show_failure_actions()
		return
	var scene: Dictionary = data.catalog.failure_scene
	var lines: Array = scene.dialogue.duplicate(true)
	var reason := str(GameState.session.failure_reason)
	if scene.first_lines.has(reason): lines[0] = scene.first_lines[reason].duplicate(true)
	_begin_dialogue(scene.title,lines,_show_failure_actions,Callable(),"failure",failure_key)

func _show_failure_actions() -> void:
	flow = "failed"
	_clear()
	_art_banner(page,load("res://assets/landscape/failure.jpeg"),240)
	_label(page,"飞鸟山 · 墨迹未尽",26,Color("#e4c98a"))
	var reasons := {"erosion_limit":"侵蚀已达 100", "puzzle_attempt_limit":"修复尝试用尽", "session_expired":"旧版本事件已超时", "battle_requirements_not_met":"白蚀未清除或未施展所需技能"}
	var response: Dictionary = GameState.session
	_label(page,"事件失败：%s。已拓印记忆仍保留。" % reasons.get(response.failure_reason,response.failure_reason),19)
	_label(page,"解谜 %d/%d · 已清除白蚀 %d 波" % [int(response.puzzle_score),int(response.puzzle_total),int(response.battle_waves)],18)
	_label(page,"回溯会恢复本次事件开始时的侵蚀与谜题；已拓印记忆、技艺和已确认的取舍保留。墨痕为零时免费回溯。",19)
	_button(page,"消耗 1 墨痕 · 回溯事件起点" if int(GameState.player.ink_marks)>0 else "墨痕不足 · 免费回溯事件起点",_rewind)
	_button(page,"返回古建地图",_show_map)

func _show_journal() -> void:
	if busy: return
	_pause_event()
	flow = "journal"
	_clear()
	_label(page, "往事回放", 26)
	_button(page, "返回收藏", _show_memories)
	_label(page, "旅途回顾", 23, Color("#b7d8c8"))
	var count := 0
	for chapter in data.catalog.chapters:
		for event in chapter.events:
			if not GameState.player.completed_events.has(chapter.id + ":" + event.id): continue
			count += 1
			_button(page, chapter.title + " / " + event.title, _replay_story.bind(chapter.id, event.id))
			var result: Dictionary = GameState.player.completed_events[chapter.id + ":" + event.id]
			_label(page, "★".repeat(int(result.stars)) + " · 当时侵蚀 %d%% · 记忆 %d/%d" % [int(result.erosion_at_end), int(result.get("memories_kept",0)), int(result.get("memories_acquired",0))], 17)
	if count == 0: _label(page, "完成任务后，对话与结语会收进这里。", 18)
	if _has_current_event(): _button(page, "返回当前事件", _resume)

func _replay_story(chapter: String, event_id: String) -> void:
	# Keep active event identity intact while reading completed stories.
	var event: Dictionary = data.event(chapter, event_id)
	var lines: Array = event.story.dialogue.duplicate(true)
	for i in range(lines.size()): lines[i]["audio_cue"] = event_id + "_dialogue_%02d" % (i+1)
	lines.append({"speaker": "檐下谱", "text": event.story.outro, "audio_cue":event_id + "_outro"})
	var result: Dictionary = GameState.player.completed_events[chapter + ":" + event_id]
	if not str(result.get("narrative_choice", "")).is_empty():
		lines.append({"speaker": "你的回答 · " + str(result.narrative_choice), "text": _ending_response(str(result.narrative_choice))})
	for entry in GameState.player.memory_ledger:
		if entry.chapter_id == chapter and entry.event_id == event_id and entry.action == "forgotten":
			lines.append({"speaker": "心舍", "text": event.story.forget_response})
	_begin_dialogue(event.title + " · 回顾", lines, _show_journal, _show_journal, "story", "", _event_background(event_id))

func _ending_response(choice: String) -> String:
	return {"传下修复的方法": "你在塔下开了一间小工坊。第一位学徒没有问什么叫永恒，只问：这块坏木头，还能修吗？", "留下所有取舍的记录": "你把灰页也装订进谱。翻阅的人第一次看见修复者的迟疑，开始在页边写下自己的不同意见。", "留白让后来人续写": "你留下空白与未蘸墨的笔。一个孩子画上了今天新搭的小棚，古建们第一次听见未来的声音。"}.get(choice, "故事由后来的人继续书写。")

func _boss_wave() -> bool:
	return not str(current_event.battle.get("boss_name", "")).is_empty() and battle_wave == int(current_event.battle.waves)-1

func _wave_hp() -> int:
	return int(current_event.battle.boss_hp) if _boss_wave() else int(current_event.battle.enemy_hp)

func _attack_interval() -> int:
	return int(current_event.battle.boss_attack_interval_ms) if _boss_wave() else 3000

func _unhandled_key_input(event: InputEvent) -> void:
	if flow != "battle" or busy or not battle_running or battle_finished: return
	if event is not InputEventKey or not event.pressed or event.echo: return
	var number := -1
	var code: int = event.keycode
	if code == 0: code = event.physical_keycode
	if code >= KEY_1 and code <= KEY_5: number = code - KEY_1
	elif code >= KEY_KP_1 and code <= KEY_KP_5: number = code - KEY_KP_1
	if number < 0: return
	get_viewport().set_input_as_handled()
	var skill: String = BATTLE_KEYS[number]
	if battle_buttons.has(skill): _battle_skill(skill)

func _stop_voice() -> void:
	voice_queue.clear()
	if is_instance_valid(event_audio):
		event_audio.stop()
		event_audio.stream = null
	if is_instance_valid(soundscape): soundscape.duck(false)

func _play_line(text: String) -> void:
	_play_cues([str(voice_index.get("lines", {}).get(text, ""))])

func _play_cues(cues: Array, append: bool = false) -> void:
	if not append: _stop_voice()
	for cue in cues:
		var path := str(voice_index.get("cues", {}).get(str(cue), ""))
		if not path.is_empty(): voice_queue.append(path)
	if not event_audio.playing: _voice_next()

func _voice_next() -> void:
	if voice_queue.is_empty():
		soundscape.duck(false)
		return
	var path: String = voice_queue.pop_front()
	var sound := load(path) as AudioStream
	if sound == null:
		push_warning("无法播放语音：" + path)
		_voice_next()
		return
	memory_audio.stop()
	event_audio.stream = sound
	event_audio.play()
	soundscape.duck(true)

## Reparent the active canvas into a wide stage. The right-hand notes scroll
## independently, so investigation targets and puzzle input stay visible.
func _layout_landscape() -> void:
	if flow not in ["intro", "puzzle", "battle", "choice", "settlement", "memory"] or page.has_node("LandscapeBody"): return
	var visual: Control
	for child in page.get_children():
		if child is Control and child.get_script() in [preload("res://scripts/building_scene.gd"), TRACE, preload("res://scripts/join_canvas.gd"), preload("res://scripts/skill_scene.gd"), preload("res://scripts/battle_arena.gd")]:
			visual = child
	if visual == null and flow in ["choice", "settlement", "memory"]:
		for child in page.get_children():
			if child is TextureRect: visual = child
	if visual == null: return
	var children := page.get_children()
	var body := HBoxContainer.new()
	body.name = "LandscapeBody"
	body.add_theme_constant_override("separation", 24)
	body.custom_minimum_size.y = 330 if flow == "battle" else 460
	page.add_child(body)
	page.remove_child(visual)
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visual.size_flags_vertical = Control.SIZE_EXPAND_FILL
	visual.size_flags_stretch_ratio = 1.8
	body.add_child(visual)
	var notes_scroll := ScrollContainer.new()
	notes_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(notes_scroll)
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_theme_constant_override("separation", 12)
	notes_scroll.add_child(notes)
	for child in children:
		if child == visual: continue
		page.remove_child(child)
		notes.add_child(child)
	backdrop_art.texture = MENU_BACKGROUND

func _next_event() -> void:
	for chapter in data.catalog.chapters:
		if chapter.id not in GameState.player.unlocked_chapters: continue
		for event in chapter.events:
			if not event.draft and not GameState.player.completed_events.has(chapter.id + ":" + event.id):
				_open_event(chapter.id, event.id)
				return
	_show_map()
