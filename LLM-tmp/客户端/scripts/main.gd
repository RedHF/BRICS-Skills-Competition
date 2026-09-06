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
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_label(column, "檐 下 千 秋", 32, Color("#e4c98a"))
	_label(column, "听古建呓语 · 拓人间记忆", 14, Color("#94b0aa"))
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
	if health.game_id != "yanxia-qianqiu" or int(health.content_version) != 4:
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
	stats.text = "识海 %d/%d   墨痕 %d   侵蚀 %d/100 · %s" % [used, int(p.capacity), int(p.ink_marks), int(p.erosion), "浸" if int(p.erosion) < 40 else ("蚀" if int(p.erosion) < 70 else "竭")]

func _clear() -> void:
	status.text = ""
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0
	memory_audio.stop()
	memory_audio.stream = null
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
		_label(page, "逐字放大描摹：绿点起笔、橙点收笔。金色宽带内均可落墨，短暂手抖可容忍。点击笔画编号可单独重描。", 16)
		trace_canvas = TRACE.new()
		trace_canvas.spec = step.trace
		page.add_child(trace_canvas)
		trace_progress = _label(page, "", 16)
		stroke_buttons = HFlowContainer.new()
		page.add_child(stroke_buttons)
		for i in range(step.trace.strokes.size()):
			var button := _button(stroke_buttons, str(i + 1), trace_canvas.select_stroke.bind(i))
			button.custom_minimum_size = Vector2(48, 42)
		trace_canvas.stroke_finished.connect(_trace_feedback)
		_trace_feedback()
		var buttons := HBoxContainer.new()
		page.add_child(buttons)
		_button(buttons, "清空当前笔", func():
			trace_canvas.strokes[trace_canvas.active] = []
			trace_canvas.queue_redraw()
			_trace_feedback())
		_button(buttons, "提交拓印", func(): _submit_puzzle({"step_id": step.id, "strokes": trace_canvas.strokes}))
	elif step.kind == "skill":
		for skill in _learned_skills(): _button(page, "使用「%s」" % skill, _submit_puzzle.bind({"step_id": step.id, "answer": skill}))
	else:
		for option in step.options: _button(page, str(option), _submit_puzzle.bind({"step_id": step.id, "answer": option}))

func _trace_feedback() -> void:
	var count := 0
	for stroke in trace_canvas.strokes:
		if not stroke.is_empty(): count += 1
	trace_progress.text = "第 %d 笔 · 已描 %d/%d · 红色 × 为未通过" % [trace_canvas.active + 1, count, trace_canvas.strokes.size()]
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
		else: status.text = "修复尚未相合，侵蚀 +10。"
		return
	await _resume()
	if response.accepted: status.text = "墨线相合，记忆显影。"

func _show_choice() -> void:
	flow = "choice"
	_clear()
	var memory: Dictionary = data.memory(current_event.reward.memory_id)
	_label(page, "墨灵显影 · " + memory.title, 26, Color(memory.color))
	_label(page, memory.summary, 21)
	_label(page, "技能：%s" % memory.skill)
	if not memory.skill.is_empty(): _label(page, data.catalog.skills[memory.skill].description, 16)
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
	battle_running = false
	wave_skills = []
	battle_ready = {}
	battle_buttons = {}
	next_attack = 3000
	battle_skills = _learned_skills()
	_label(page, "白蚀来袭", 26, Color("#e4c98a"))
	_label(page, "点击挥墨消灭白蚀；红色蓄力时用斗拱防护。白蚀每 3 秒攻击一次。", 16)
	battle_note = _label(page, "", 17)
	arena = preload("res://scripts/battle_arena.gd").new()
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
	battle_start.hide()
	_battle_update()

func _battle_skill(skill: String) -> void:
	if busy or battle_finished or not battle_running: return
	var at := int(battle_elapsed * 1000)
	if at < int(battle_ready[skill]): return
	var spec: Dictionary = data.catalog.skills[skill]
	battle_actions.append({"skill": skill, "at_ms": at})
	battle_ready[skill] = at + int(spec.cooldown_ms)
	if not wave_skills.has(skill): wave_skills.append(skill)
	arena.hp -= int(spec.damage)
	if int(spec.shield) > 0: arena.shield = int(spec.shield)
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
	while next_attack <= int(battle_elapsed * 1000) and battle_hits <= int(current_event.battle.max_hits_taken):
		if arena.shield > 0:
			arena.shield -= 1
			arena.flash("斗拱挡住侵袭", Color("#9ad5ad"))
		else:
			battle_hits += 1
			arena.flash("受到侵蚀 +1", Color("#ff8078"))
		next_attack += 3000
	_battle_update()

func _battle_update() -> void:
	arena.hits = battle_hits
	arena.phase = 1.0 - float(next_attack - int(battle_elapsed * 1000)) / 3000.0
	battle_note.text = "第 %d/%d 波 · 剩余 %d 秒 · 受蚀 %d/%d" % [mini(battle_wave + 1, int(current_event.battle.waves)), int(current_event.battle.waves), ceili(float(current_event.battle.duration_sec) - battle_elapsed), battle_hits, int(current_event.battle.max_hits_taken) + 1]
	if battle_wave == int(current_event.battle.waves) or battle_hits > int(current_event.battle.max_hits_taken) or battle_elapsed >= float(current_event.battle.duration_sec):
		battle_finished = true
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
	_label(page, "技艺册 · 点击按钮施展", 23, Color("#e4c98a"))
	_label(page, "战斗中点击挥墨攻击，技能冷却结束后可再次施展。遗忘记忆后，习得的技艺仍然保留。", 16)
	for skill in ["挥墨"] + _learned_skills():
		_label(page, skill + " · " + data.catalog.skills[skill].description, 18)
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
