extends Node

const TRACE = preload("res://scripts/trace_canvas.gd")
const NETWORK = preload("res://scripts/network_client.gd")
const REPOSITORY = preload("res://scripts/data_repository.gd")
var network = NETWORK.new()
var data = REPOSITORY.new()
var page: VBoxContainer
var status: Label
var stats: Label
var backdrop: ColorRect
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
var battle_finished := false
var battle_controls: HBoxContainer
var confirmation: ConfirmationDialog
var navigation: HBoxContainer

func _ready() -> void:
	add_child(network)
	memory_audio = AudioStreamPlayer.new()
	add_child(memory_audio)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("#14262b")
	root.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_label(column, "檐下千秋  /  檐下谱", 30, Color("#e4c98a"))
	stats = _label(column, "正在连接本地服务…", 17)
	var nav := HBoxContainer.new()
	navigation = nav
	column.add_child(nav)
	_button(nav, "古建地图", _show_map)
	_button(nav, "心舍 · 墨灵", _show_memories)
	_button(nav, "记忆账册", _show_ledger)
	for button in nav.get_children(): button.disabled = true
	status = _label(column, "", 16, Color("#e9bb86"))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	scroll.add_child(page)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认抹去记忆"
	confirmation.ok_button_text = "亲手抹去"
	confirmation.cancel_button_text = "留下这段记忆"
	add_child(confirmation)
	await _connect_server()

func _connect_server() -> void:
	_clear()
	busy = true
	var config := ConfigFile.new()
	var config_path := OS.get_executable_path().get_base_dir().path_join("client.cfg")
	if FileAccess.file_exists(config_path):
		var error := config.load(config_path)
		if error != OK:
			_error("无法读取 client.cfg：%s" % error)
			return
		network.base_url = str(config.get_value("server", "url", "http://127.0.0.1:8090"))
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
	if health.game_id != "yanxia-qianqiu" or int(health.content_version) != 3:
		_error("端口上的服务与本客户端内容版本不匹配，请关闭旧服务后重试。")
		return
	var catalog: Dictionary = await network.request_json("/api/v1/catalog")
	if catalog.is_empty():
		_error(network.last_error)
		return
	data.catalog = catalog
	var identity := ConfigFile.new()
	var payload := {"display_name": "无名拓印师"}
	if FileAccess.file_exists("user://yanxia_identity.cfg"):
		var error := identity.load("user://yanxia_identity.cfg")
		if error != OK:
			_error("玩家身份文件无法读取：%s" % error)
			return
		payload.player_id = identity.get_value("identity", "player_id")
	var response: Dictionary = await network.request_json("/api/v1/players", HTTPClient.METHOD_POST, payload)
	if response.is_empty():
		_error(network.last_error)
		return
	GameState.player = response.player
	identity.set_value("identity", "player_id", GameState.player.id)
	var save_error := identity.save("user://yanxia_identity.cfg")
	if save_error != OK:
		_error("无法保存玩家身份：%s" % save_error)
		return
	busy = false
	for button in navigation.get_children(): button.disabled = false
	_refresh_stats()
	_show_map()

func _exit_tree() -> void:
	memory_audio.stop()
	memory_audio.stream = null
	if server_pid > 0 and OS.is_process_running(server_pid):
		var error := OS.kill(server_pid)
		if error != OK: push_error("关闭本地服务失败：%s" % error)

func _error(message: String) -> void:
	busy = false
	status.text = message
	push_error(message)
	if data.catalog.is_empty(): _button(page, "重新连接服务端", _connect_server)

func _refresh_stats() -> void:
	var p: Dictionary = GameState.player
	var used := 0
	for memory in p.memories: used += int(memory.capacity)
	stats.text = "识海 %d / %d 道    墨痕 %d    侵蚀 %d / 100    %s" % [used, int(p.capacity), int(p.ink_marks), int(p.erosion), "浸" if int(p.erosion) < 40 else ("蚀" if int(p.erosion) < 70 else "竭")]

func _clear() -> void:
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0
	memory_audio.stop()
	backdrop.color = Color("#14262b")

func _show_map() -> void:
	if busy: return
	if flow == "battle" and not battle_finished:
		status.text = "请先完成当前白蚀战斗。"
		return
	flow = "map"
	_clear()
	status.text = "沿古建呓语前行。序章与社庙为本次可玩篇章。"
	for chapter in data.catalog.chapters:
		_label(page, chapter.title, 24, Color("#e4c98a"))
		_label(page, chapter.summary)
		for event in chapter.events:
			var done: bool = GameState.player.completed_events.has(chapter.id + ":" + event.id)
			var button := _button(page, event.title + (" · 已修复" if done else "") + (" · 剧情草稿" if event.draft else ""), _open_event.bind(chapter.id, event.id))
			button.disabled = event.draft or not chapter.id in GameState.player.unlocked_chapters
			for previous in chapter.events:
				if int(previous.order) < int(event.order) and not GameState.player.completed_events.has(chapter.id + ":" + previous.id): button.disabled = true
	if not session_id.is_empty(): _button(page, "继续当前事件", _resume)

func _open_event(chapter: String, event: String) -> void:
	if busy: return
	chapter_id = chapter
	current_event = data.event(chapter, event)
	session_id = ""
	flow = "intro"
	_clear()
	_label(page, current_event.scene + " · " + current_event.title, 26, Color("#e4c98a"))
	for beat in current_event.story.beats: _label(page, beat, 19)
	for objective in current_event.objectives: _label(page, "· " + objective, 16)
	var memory: Dictionary = data.memory(current_event.reward.memory_id)
	for entry in GameState.player.memory_ledger:
		if entry.memory_id == memory.id and entry.action == "forgotten":
			_label(page, memory.forgotten_text, 18, Color("#929996"))
	if GameState.player.completed_events.has(chapter + ":" + event):
		_label(page, current_event.story.outro, 20)
		_button(page, "查看这道墨灵", _memory_detail.bind(memory.id))
	else:
		_button(page, "聆听呓语 · 开始修复", _start_event)

func _start_event() -> void:
	busy = true
	var response: Dictionary = await network.request_json("/api/v1/events/%s/%s/start" % [chapter_id, current_event.id], HTTPClient.METHOD_POST, {"player_id": GameState.player.id})
	if response.is_empty():
		_error(network.last_error)
		return
	session_id = response.session_id
	busy = false
	await _resume()

func _resume() -> void:
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
		status.text = "事件失败：%s。已拓印记忆仍保留。" % response.failure_reason
		_button(page, "返回古建地图", _show_map)
	elif response.status == "completed":
		_settlement(response.pending_result)
	elif response.accepted_steps.size() < current_event.puzzle.steps.size(): _show_puzzle()
	elif not response.choice_done: _show_choice()
	elif current_event.has("battle") and not response.battle_checked: _start_battle()
	else: await _finish()

func _show_puzzle() -> void:
	flow = "puzzle"
	_clear()
	var index: int = GameState.session.accepted_steps.size()
	var step: Dictionary = current_event.puzzle.steps[index]
	_label(page, "修复 %d / %d · %s" % [index + 1, current_event.puzzle.steps.size(), current_event.title], 24, Color("#e4c98a"))
	_label(page, step.prompt, 20)
	if step.kind == "trace":
		_label(page, "从绿点沿宽金色墨带描到橙点，松开完成一笔。允许偏离细线，不必精确重合。", 16)
		trace_canvas = TRACE.new()
		trace_canvas.spec = step.trace
		page.add_child(trace_canvas)
		var progress := _label(page, "已描 0 / %d 笔" % step.trace.strokes.size(), 16)
		trace_canvas.stroke_finished.connect(func(): progress.text = "已描 %d / %d 笔" % [trace_canvas.strokes.size(), step.trace.strokes.size()])
		var buttons := HBoxContainer.new()
		page.add_child(buttons)
		_button(buttons, "撤回上一笔", func():
			if not trace_canvas.strokes.is_empty():
				trace_canvas.strokes.pop_back()
				trace_canvas.drawing = false
				trace_canvas.queue_redraw()
				trace_canvas.stroke_finished.emit())
		_button(buttons, "重描本步", _show_puzzle)
		_button(buttons, "提交拓印", func(): _submit_puzzle({"step_id": step.id, "strokes": trace_canvas.strokes}))
	elif step.kind == "skill":
		for skill in _learned_skills(): _button(page, "使用「%s」" % skill, _submit_puzzle.bind({"step_id": step.id, "answer": skill}))
	else:
		for option in step.options: _button(page, str(option), _submit_puzzle.bind({"step_id": step.id, "answer": option}))

func _submit_puzzle(payload: Dictionary) -> void:
	if busy: return
	busy = true
	var response: Dictionary = await network.request_json("/api/v1/sessions/%s/puzzle" % session_id, HTTPClient.METHOD_POST, payload)
	if response.is_empty():
		_error(network.last_error)
		_button(page, "读取服务器进度后继续", _resume)
		return
	if not response.accepted and response.status != "failed":
		GameState.player.erosion = response.erosion
		_refresh_stats()
		busy = false
		status.text = "修复尚未相合，侵蚀 +10。描摹会保留，可撤回上一笔修正；不必重新画整幅。"
		return
	await _resume()
	if response.accepted: status.text = "墨线相合，记忆显影。"

func _show_choice() -> void:
	flow = "choice"
	_clear()
	var memory: Dictionary = data.memory(current_event.reward.memory_id)
	_label(page, "墨灵显影 · " + memory.title, 26, Color(memory.color))
	_label(page, memory.summary, 21)
	_label(page, "技能：%s　来历：%s" % [memory.skill, memory.source])
	var used := 0
	for held in GameState.player.memories: used += int(held.capacity)
	var keep := _button(page, "拓印这道墨灵", _choose.bind("keep", ""))
	keep.disabled = used + int(memory.capacity) > int(GameState.player.capacity)
	_label(page, "识海满时须择一旧记忆抹去；也可主动取舍。抹除会留下账册与场景回声。", 16)
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
	confirmation.popup_centered(Vector2i(620, 260))

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
		backdrop.color = Color("#575b59")
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
	wave_skills = []
	battle_skills = _learned_skills()
	_label(page, "白蚀来袭 · " + current_event.title, 26)
	_label(page, "守住墨线直到白蚀散去。每波使用指定技能，战斗结束后结算。", 18)
	battle_note = _label(page, "", 20, Color("#e4c98a"))
	battle_controls = HBoxContainer.new()
	page.add_child(battle_controls)
	for skill in battle_skills: _button(battle_controls, skill, _battle_skill.bind(skill))
	status.text = "需要技能：" + ", ".join(current_event.battle.required_skills)

func _battle_skill(skill: String) -> void:
	if busy or battle_finished: return
	battle_actions.append({"skill": skill, "at_ms": int(battle_elapsed * 1000)})
	if not wave_skills.has(skill): wave_skills.append(skill)
	status.text = "「%s」护住墨线。" % skill

func _process(delta: float) -> void:
	if flow != "battle" or battle_finished: return
	battle_elapsed += delta
	var duration := float(current_event.battle.duration_sec)
	var waves := int(current_event.battle.waves)
	battle_note.text = "白蚀 %d / %d 波　剩余 %d 秒　受蚀 %d 次" % [mini(battle_wave + 1, waves), waves, maxi(0, ceili(duration - battle_elapsed)), battle_hits]
	if battle_elapsed >= duration * (battle_wave + 1) / waves:
		for required in current_event.battle.required_skills:
			if not wave_skills.has(required): battle_hits += 1
		battle_wave += 1
		wave_skills.clear()
	if battle_elapsed >= duration:
		battle_finished = true
		for child in battle_controls.get_children(): child.disabled = true
		_button(page, "结算白蚀战斗", _submit_battle)

func _submit_battle() -> void:
	if busy: return
	busy = true
	var response: Dictionary = await network.request_json("/api/v1/sessions/%s/battle" % session_id, HTTPClient.METHOD_POST, {"actions": battle_actions, "duration_ms": int(current_event.battle.duration_sec) * 1000, "waves_cleared": battle_wave, "hits_taken": battle_hits})
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
	_label(page, current_event.story.outro, 23)
	_label(page, "修复度 %d%%　侵蚀 %d%%　获得墨痕 %d" % [int(result.repair_percent), int(result.erosion_at_end), int(result.ink_marks_earned)])
	if current_event.story.has("chapter_outro"): _label(page, current_event.story.chapter_outro, 20)
	_button(page, "回看这道墨灵", _memory_detail.bind(current_event.reward.memory_id))
	_button(page, "继续古建旅程", _show_map)
	session_id = ""

func _show_memories() -> void:
	if busy or (flow == "battle" and not battle_finished): return
	flow = "memories"
	_clear()
	_label(page, "心舍 · 记住的墨灵", 26, Color("#e4c98a"))
	for held in GameState.player.memories:
		var memory: Dictionary = data.memory(held.id)
		_button(page, "%s  /  %s" % [memory.title, memory.skill], _memory_detail.bind(held.id))
	if not session_id.is_empty(): _button(page, "返回当前事件", _resume)

func _memory_detail(id: String) -> void:
	flow = "memory"
	_clear()
	var memory: Dictionary = data.memory(id)
	var remembered := false
	for held in GameState.player.memories:
		if held.id == id: remembered = true
	backdrop.color = Color(memory.color).darkened(0.8) if remembered else Color("#282c2b")
	_label(page, memory.title + (" · 记住" if remembered else " · 遗忘"), 28, Color(memory.color) if remembered else Color("#929996"))
	_label(page, memory.remembered_text if remembered else memory.forgotten_text, 22)
	var source: PackedStringArray = str(memory.source).split("/")
	var event: Dictionary = data.event(source[0], source[1])
	_label(page, "来历：%s / %s\n技能：%s　识海：%d 道" % [event.scene, event.title, memory.skill, int(memory.capacity)], 18)
	if remembered:
		_button(page, "聆听墨灵回声", _play_memory.bind(float(memory.tone_hz)))
	else: _label(page, "色调与音色已随记忆褪去；习得的技艺仍可用于修复。", 16)
	_button(page, "返回心舍", _show_memories)
	if not session_id.is_empty(): _button(page, "返回当前事件", _resume)

func _play_memory(hz: float) -> void:
	var samples := PackedByteArray()
	for i in range(22050):
		var value := int(sin(TAU * hz * i / 22050.0) * 14000 * pow(1.0 - i / 22050.0, 2))
		samples.append(value & 255)
		samples.append((value >> 8) & 255)
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	sound.data = samples
	memory_audio.stream = sound
	memory_audio.play()

func _show_ledger() -> void:
	if busy or (flow == "battle" and not battle_finished): return
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
	button.custom_minimum_size = Vector2(160, 42)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(func():
		if not busy: callback.call())
	parent.add_child(button)
	return button
