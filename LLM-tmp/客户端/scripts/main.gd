extends Node

## Presentation and flow coordinator for the demo.
##
## The scene contains no hard-coded child hierarchy. Controls are generated
## from the content catalog, so a new chapter/event/puzzle step gets the same
## presentation automatically. Server responses are authoritative whenever
## available; local evaluation is deliberately marked as demo fallback.

const CONTENT_PATH := "res://content/chapters.json"
const STORY_PATH := "res://content/story_text.json"
const IDENTITY_PATH := "user://yanxia_identity.cfg"
const DATA_REPOSITORY_SCRIPT = preload("res://scripts/data_repository.gd")
const NETWORK_CLIENT_SCRIPT = preload("res://scripts/network_client.gd")

var data = DATA_REPOSITORY_SCRIPT.new()
var network = NETWORK_CLIENT_SCRIPT.new()
var story: Dictionary = {}

var root_ui: Control
var scene_backdrop: ColorRect
var scene_image: TextureRect
var title_label: Label
var connection_label: Label
var chapter_label: Label
var event_label: Label
var narrative_label: RichTextLabel
var objective_box: VBoxContainer
var action_panel: PanelContainer
var action_box: VBoxContainer
var status_label: Label
var stats_label: Label
var ledger_label: RichTextLabel
var progress_bar: ProgressBar
var reset_button: Button

var chapter_id := "prologue"
var event_id := "prologue_bridge"
var current_chapter: Dictionary = {}
var current_event: Dictionary = {}
var flow_state := "intro"
var puzzle_index := 0
var puzzle_score := 0
var puzzle_total := 0
var puzzle_attempts := 0
var puzzle_failed := false
var puzzle_input: LineEdit
var puzzle_buttons: Array[Button] = []

var session_id := ""
var battle_elapsed := 0.0
var battle_wave := 0
var battle_hits := 0
var battle_skill_used: Dictionary = {}
var battle_actions: Array = []
var battle_note_label: Label
var battle_timer_bar: ProgressBar
var battle_clear_button: Button

var pending_operation := ""
var pending_token := 0
var pending_answer := ""
var pending_choice := ""
var pending_result: Dictionary = {}
var offline_reason := ""
var server_probe_pending := false
var recovery_target := ""

func _ready() -> void:
	set_process(true)
	data.load_catalog(CONTENT_PATH)
	var story_file := FileAccess.open(STORY_PATH, FileAccess.READ)
	if story_file != null:
		var parsed = JSON.parse_string(story_file.get_as_text())
		if parsed is Dictionary:
			story = parsed
	add_child(network)
	network.request_finished.connect(_on_network_result)
	GameState.player_changed.connect(_on_player_changed)
	GameState.connection_changed.connect(_on_connection_changed)
	_build_ui()
	GameState.set_connection(false, "正在连接服务器…")
	_begin_network_probe()
	_show_event("prologue", "prologue_bridge")

func _process(delta: float) -> void:
	if flow_state != "battle":
		return
	battle_elapsed += delta
	if is_instance_valid(battle_timer_bar):
		var duration := float(current_event.get("battle", {}).get("duration_sec", 30))
		battle_timer_bar.value = min(battle_elapsed, duration)
	if is_instance_valid(battle_note_label):
		var duration_text := int(current_event.get("battle", {}).get("duration_sec", 30))
		battle_note_label.text = "战斗记录：第 %d/%d 波　用时 %02d 秒（关卡上限 %02d 秒）" % [battle_wave, int(current_event.get("battle", {}).get("waves", 1)), int(battle_elapsed), duration_text]
	if battle_wave < int(current_event.get("battle", {}).get("waves", 1)) and battle_elapsed >= float(battle_wave + 1):
		if is_instance_valid(battle_clear_button):
			battle_clear_button.disabled = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("advance"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and not focused.disabled:
			focused.pressed.emit()
			get_viewport().set_input_as_handled()

func _build_ui() -> void:
	root_ui = Control.new()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_ui)

	scene_backdrop = ColorRect.new()
	scene_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene_backdrop.color = Color("#0d1820")
	scene_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(scene_backdrop)
	scene_image = TextureRect.new()
	scene_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_image.modulate = Color(1, 1, 1, 0.34)
	scene_image.visible = false
	root_ui.add_child(scene_image)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	root_ui.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	margin.add_child(columns)

	var sidebar := _panel(Color("#15242b"))
	sidebar.custom_minimum_size = Vector2(250, 0)
	columns.add_child(sidebar)
	var side_box := VBoxContainer.new()
	sidebar.add_child(side_box)
	var brand := _label("檐下\n千秋", 30, Color("#e4c98a"))
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side_box.add_child(brand)
	var tagline := _label("檐下藏千秋，墨中定存亡", 12, Color("#91a8a5"))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side_box.add_child(tagline)
	connection_label = _label("", 13, Color("#a9c7b8"))
	connection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	connection_label.custom_minimum_size = Vector2(0, 40)
	side_box.add_child(connection_label)
	side_box.add_child(_separator())
	stats_label = _label("", 14, Color("#d9e5df"))
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_box.add_child(stats_label)
	side_box.add_child(_separator())
	side_box.add_child(_label("记忆账册", 16, Color("#e4c98a")))
	ledger_label = RichTextLabel.new()
	ledger_label.bbcode_enabled = true
	ledger_label.fit_content = true
	ledger_label.scroll_active = true
	ledger_label.custom_minimum_size = Vector2(0, 210)
	ledger_label.add_theme_font_size_override("normal_font_size", 13)
	side_box.add_child(ledger_label)
	reset_button = _button("重新开始本地演示", _on_reset_pressed, false)
	reset_button.tooltip_text = "清除当前内存态演示进度并回到序章"
	side_box.add_spacer(false)
	side_box.add_child(reset_button)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 12)
	columns.add_child(center)

	var header := HBoxContainer.new()
	center.add_child(header)
	chapter_label = _label("", 18, Color("#e4c98a"))
	chapter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(chapter_label)
	event_label = _label("", 18, Color("#d9e5df"))
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(event_label)

	var title_panel := _panel(Color("#1b3037"))
	center.add_child(title_panel)
	var title_box := VBoxContainer.new()
	title_panel.add_child(title_box)
	title_label = _label("", 27, Color("#f2dfb0"))
	title_box.add_child(title_label)
	narrative_label = RichTextLabel.new()
	narrative_label.bbcode_enabled = true
	narrative_label.fit_content = true
	narrative_label.scroll_active = true
	narrative_label.custom_minimum_size = Vector2(0, 155)
	narrative_label.add_theme_font_size_override("normal_font_size", 17)
	narrative_label.add_theme_color_override("default_color", Color("#d6e1dc"))
	title_box.add_child(narrative_label)

	var objective_panel := _panel(Color("#15242b"))
	objective_panel.custom_minimum_size = Vector2(0, 100)
	center.add_child(objective_panel)
	objective_box = VBoxContainer.new()
	objective_panel.add_child(objective_box)
	objective_box.add_child(_label("事件目标", 15, Color("#e4c98a")))

	action_panel = _panel(Color("#1b3037"))
	action_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(action_panel)
	action_box = VBoxContainer.new()
	action_box.add_theme_constant_override("separation", 10)
	action_panel.add_child(action_box)
	status_label = _label("", 14, Color("#a9c7b8"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_box.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 12)
	progress_bar.show_percentage = false
	progress_bar.visible = false
	action_box.add_child(progress_bar)

	_refresh_sidebar()

func _show_event(next_chapter_id: String, next_event_id: String) -> void:
	# Rebuilding an event invalidates any in-flight request from the previous
	# screen (for example, the sidebar reset button during a network call). The
	# initial player probe is different: _ready starts it before rendering the
	# first event, so preserve that request while allowing the button to remain
	# disabled until the probe resolves.
	var preserve_player_probe := pending_operation == "create_player" and server_probe_pending
	if not pending_operation.is_empty() and not preserve_player_probe:
		pending_operation = ""
		pending_token += 1
	recovery_target = ""
	chapter_id = next_chapter_id
	event_id = next_event_id
	current_chapter = data.chapter(chapter_id)
	current_event = data.event(chapter_id, event_id)
	if current_event.is_empty():
		_show_finish("内容目录中没有找到该事件：%s/%s" % [chapter_id, event_id])
		return
	GameState.current_chapter_id = chapter_id
	GameState.current_event_id = event_id
	flow_state = "intro"
	puzzle_index = 0
	puzzle_score = 0
	puzzle_attempts = 0
	puzzle_failed = false
	puzzle_total = _puzzle_total(current_event)
	session_id = ""
	pending_result = {}
	chapter_label.text = str(current_chapter.get("title", chapter_id))
	event_label.text = "事件 %s" % str(current_event.get("title", event_id))
	title_label.text = str(current_event.get("title", "未命名事件"))
	narrative_label.text = _compose_story(event_id, str(current_event.get("intro", "")))
	_clear_objectives()
	for objective in current_event.get("objectives", []):
		var item := _label("· %s" % str(objective), 14, Color("#c4d3cc"))
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		objective_box.add_child(item)
	_set_backdrop_for_event()
	_clear_actions()
	status_label.text = "探索状态：尚未开始。读取古建呓语后，开始调查。"
	var start := _button("开始调查", _on_begin_event_pressed, true)
	start.disabled = server_probe_pending
	if server_probe_pending:
		start.text = "检测服务器…"
	start.custom_minimum_size = Vector2(0, 48)
	action_box.add_child(start)
	_refresh_sidebar()

func _on_begin_event_pressed() -> void:
	flow_state = "puzzle"
	_clear_actions()
	status_label.text = "调查进行中。每一步答案会按顺序提交并校验。"
	if GameState.online and not str(GameState.player.get("id", "")).is_empty():
		flow_state = "starting"
		status_label.text = "正在向服务器登记事件会话…"
		pending_operation = "start_event"
		pending_token += 1
		var token := pending_token
		network.start_event(str(GameState.player.get("id", "")), chapter_id, event_id)
		get_tree().create_timer(4.0).timeout.connect(_on_network_timeout.bind("start_event", token))
		return
	_show_puzzle_step()

func _show_puzzle_step() -> void:
	if puzzle_index >= current_event.get("puzzle", {}).get("steps", []).size():
		_on_puzzle_complete()
		return
	_clear_actions()
	var steps: Array = current_event.get("puzzle", {}).get("steps", [])
	var step: Dictionary = steps[puzzle_index]
	status_label.text = "谜题 %d/%d　%s" % [puzzle_index + 1, steps.size(), str(current_event.get("puzzle", {}).get("type", "puzzle"))]
	var prompt := _label(str(step.get("prompt", "")), 18, Color("#f0e4c1"))
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_box.add_child(prompt)
	var kind := str(step.get("kind", "choice"))
	var options: Array = step.get("options", [])
	puzzle_buttons.clear()
	if kind == "choice" or not options.is_empty():
		for option in options:
			var option_button := _button(str(option), _on_puzzle_option_pressed.bind(str(option)), true)
			option_button.custom_minimum_size = Vector2(0, 42)
			puzzle_buttons.append(option_button)
			action_box.add_child(option_button)
	else:
		puzzle_input = LineEdit.new()
		puzzle_input.placeholder_text = "输入拓印结果或技能名称"
		puzzle_input.custom_minimum_size = Vector2(0, 44)
		puzzle_input.add_theme_font_size_override("font_size", 18)
		action_box.add_child(puzzle_input)
		var submit := _button("提交答案", _on_puzzle_submit_pressed, true)
		submit.custom_minimum_size = Vector2(0, 44)
		action_box.add_child(submit)
		puzzle_input.text_submitted.connect(func(value): _submit_puzzle_answer(value))
	var hint := _label("提示：答案仅用于当前步骤，顺序由服务器目录决定。", 13, Color("#91a8a5"))
	action_box.add_child(hint)

func _on_puzzle_option_pressed(option: String) -> void:
	_submit_puzzle_answer(option)

func _on_puzzle_submit_pressed() -> void:
	if is_instance_valid(puzzle_input):
		_submit_puzzle_answer(puzzle_input.text)

func _submit_puzzle_answer(answer: String) -> void:
	if pending_operation == "submit_puzzle":
		return
	if GameState.online and pending_operation == "start_event":
		status_label.text = "正在建立服务器事件会话，请稍候。"
		return
	var steps: Array = current_event.get("puzzle", {}).get("steps", [])
	if puzzle_index >= steps.size():
		return
	pending_answer = answer.strip_edges()
	if pending_answer.is_empty():
		status_label.text = "请先输入或选择一个答案。"
		return
	puzzle_attempts += 1
	_disable_puzzle_controls()
	if GameState.online and not session_id.is_empty():
		pending_operation = "submit_puzzle"
		pending_token += 1
		var token := pending_token
		network.submit_puzzle(session_id, str(steps[puzzle_index].get("id", "")), pending_answer)
		get_tree().create_timer(4.0).timeout.connect(_on_network_timeout.bind("submit_puzzle", token))
		status_label.text = "已提交服务器，正在校验步骤与侵蚀度…"
	else:
		_resolve_local_puzzle(pending_answer)

func _resolve_local_puzzle(answer: String) -> void:
	pending_operation = ""
	var steps: Array = current_event.get("puzzle", {}).get("steps", [])
	var step: Dictionary = steps[puzzle_index]
	var expected := str(step.get("answer", "")).strip_edges().to_lower()
	var actual := answer.strip_edges().to_lower()
	if actual == expected:
		puzzle_score += int(step.get("points", 0))
		status_label.text = "本地演示校验通过：墨线与构件产生共鸣。"
		puzzle_index += 1
		await get_tree().create_timer(0.35).timeout
		_show_puzzle_step()
	else:
		var erosion := int(GameState.player.get("erosion", 0)) + 10
		GameState.player["erosion"] = min(erosion, 100)
		GameState.player_changed.emit(GameState.player)
		status_label.text = "答案不符，侵蚀度 +10。可以修正后重试。"
		if puzzle_attempts >= int(current_event.get("puzzle", {}).get("max_attempts", 3)):
			puzzle_failed = true
			status_label.text = "本事件的尝试次数已用尽，记忆进入残迹。可从侧栏重新开始本地演示。"
			_clear_actions()
			var retry := _button("重新尝试事件", _on_retry_event_pressed, true)
			action_box.add_child(retry)
		else:
			_show_puzzle_step()

func _on_retry_event_pressed() -> void:
	_show_event(chapter_id, event_id)

func _show_event_retry(message: String) -> void:
	# A server-failed session cannot be resumed or submitted again. Clear its
	# id and invalidate any late HTTP response before offering a fresh session.
	pending_operation = ""
	pending_token += 1
	recovery_target = ""
	session_id = ""
	flow_state = "intro"
	puzzle_failed = true
	_clear_actions()
	status_label.text = message
	action_box.add_child(_button("重新开始事件", _on_retry_event_pressed, true))
	_refresh_sidebar()

func _show_battle_retry(reason: String) -> void:
	if GameState.online:
		_show_event_retry("服务器判定战斗未通过：%s。当前会话已结束，请重新开始事件。" % reason)
		return
	pending_operation = ""
	status_label.text = "战斗未通过：%s。可以在本地演示中重整后再试。" % reason
	_clear_actions()
	action_box.add_child(_button("重整后重试", _start_battle, true))

func _on_puzzle_complete() -> void:
	flow_state = "battle" if current_event.get("battle", null) != null else "choice"
	if flow_state == "battle":
		_start_battle()
	else:
		_show_choice()

func _start_battle() -> void:
	battle_elapsed = 0.0
	battle_wave = 0
	battle_hits = 0
	battle_skill_used.clear()
	battle_actions.clear()
	_clear_actions()
	var battle: Dictionary = current_event.get("battle", {})
	status_label.text = "白蚀来袭。按要求使用技能并逐波清除。"
	battle_note_label = _label("", 15, Color("#d6e1dc"))
	action_box.add_child(battle_note_label)
	battle_timer_bar = ProgressBar.new()
	battle_timer_bar.max_value = float(battle.get("duration_sec", 30))
	battle_timer_bar.value = 0
	battle_timer_bar.show_percentage = false
	battle_timer_bar.custom_minimum_size = Vector2(0, 16)
	action_box.add_child(battle_timer_bar)
	var skill_title := _label("拓印技能", 15, Color("#e4c98a"))
	action_box.add_child(skill_title)
	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 8)
	action_box.add_child(skill_row)
	for skill in _battle_skill_options():
		var skill_button := _button(skill, _on_battle_skill_pressed.bind(skill), true)
		skill_button.custom_minimum_size = Vector2(0, 44)
		skill_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_row.add_child(skill_button)
	battle_clear_button = _button("清除当前波次", _on_battle_wave_pressed, true)
	battle_clear_button.disabled = false
	battle_clear_button.custom_minimum_size = Vector2(0, 46)
	action_box.add_child(battle_clear_button)
	var hit_button := _button("承受一次冲击（演示）", _on_battle_hit_pressed, false)
	hit_button.custom_minimum_size = Vector2(0, 38)
	action_box.add_child(hit_button)

func _on_battle_skill_pressed(skill: String) -> void:
	if flow_state != "battle":
		return
	battle_skill_used[skill] = true
	# Record every activation. Multi-wave events require a chronological action
	# for each wave; the server still checks that the skill belongs to the player.
	battle_actions.append({"skill": skill, "at_ms": int(battle_elapsed * 1000)})
	status_label.text = "%s已就位。继续观察白蚀的波次变化。" % skill

func _on_battle_hit_pressed() -> void:
	battle_hits += 1
	status_label.text = "白蚀擦过衣袖，侵蚀度将在结算时计入。"

func _on_battle_wave_pressed() -> void:
	var battle: Dictionary = current_event.get("battle", {})
	var required: Array = battle.get("required_skills", [])
	if battle_wave >= int(battle.get("waves", 1)):
		return
	if battle_elapsed < float(battle_wave + 1):
		status_label.text = "先稳住阵脚，再清除这一波。"
		return
	var missing := ""
	for skill in required:
		if not battle_skill_used.has(str(skill)):
			missing = str(skill)
			break
	if not missing.is_empty():
		status_label.text = "这一波需要先使用「%s」。" % missing
		return
	battle_wave += 1
	# Skills are consumed by the cleared wave. Requiring them again makes the
	# client interaction match the server's multi-wave verification contract.
	battle_skill_used.clear()
	battle_clear_button.disabled = battle_wave < int(battle.get("waves", 1))
	status_label.text = "第 %d 波白蚀已清除。" % battle_wave
	if battle_wave >= int(battle.get("waves", 1)):
		battle_clear_button.text = "提交战斗记录"
		battle_clear_button.disabled = false
		battle_clear_button.pressed.disconnect(_on_battle_wave_pressed)
		battle_clear_button.pressed.connect(_submit_battle)
	else:
		battle_clear_button.disabled = false

func _submit_battle() -> void:
	if pending_operation == "submit_battle":
		return
	var payload := {
		"duration_ms": max(1000, int(battle_elapsed * 1000)),
		"waves_cleared": battle_wave,
		"hits_taken": battle_hits,
		"actions": battle_actions
	}
	_disable_action_buttons()
	if GameState.online and not session_id.is_empty():
		pending_operation = "submit_battle"
		pending_token += 1
		var token := pending_token
		network.submit_battle(session_id, payload)
		get_tree().create_timer(4.0).timeout.connect(_on_network_timeout.bind("submit_battle", token))
		status_label.text = "战斗遥测已提交，等待服务器结算…"
	else:
		_resolve_local_battle(payload)

func _resolve_local_battle(payload: Dictionary) -> void:
	pending_operation = ""
	var battle: Dictionary = current_event.get("battle", {})
	var won := battle_wave >= int(battle.get("waves", 1)) and battle_hits <= int(battle.get("max_hits_taken", 0))
	if won:
		status_label.text = "本地演示战斗通过：白蚀退散。"
		flow_state = "choice"
		_show_choice()
	else:
		GameState.player["erosion"] = min(100, int(GameState.player.get("erosion", 0)) + 15 + battle_hits * 5)
		GameState.player_changed.emit(GameState.player)
		status_label.text = "战斗未通过，侵蚀度已增加。"
		_clear_actions()
		action_box.add_child(_button("重整后重试", _start_battle, true))

func _show_choice() -> void:
	flow_state = "choice"
	_clear_actions()
	var memory: Dictionary = current_event.get("reward", {}).get("memory", {})
	var choices: Array = memory.get("choices", [])
	var cost := int(memory.get("capacity", 1))
	var used := _memory_capacity_used()
	status_label.text = "心舍抉择：新记忆「%s」需要 %d 格，当前占用 %d/%d。" % [str(memory.get("title", "新记忆")), cost, used, int(GameState.player.get("capacity", 5))]
	var explanation := _label("保留会把新记忆写入账册；遗忘会留下灰痕，并影响后续回放。", 14, Color("#c4d3cc"))
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_box.add_child(explanation)
	var keep := _button("保留「%s」" % str(memory.get("title", "新记忆")), _on_choice_pressed.bind("keep"), true)
	keep.custom_minimum_size = Vector2(0, 44)
	action_box.add_child(keep)
	var rendered_forget := false
	if choices.size() > 0:
		var candidate_title := _label("可抹去的旧记忆（教学性软抉择）", 14, Color("#e4c98a"))
		action_box.add_child(candidate_title)
		for choice in choices:
			var choice_id := str(choice)
			if choice_id == "keep":
				continue
			if choice_id == "forget":
				for held in GameState.memories():
					rendered_forget = true
					var held_id := str(held.get("id", ""))
					var held_title := str(held.get("title", held_id))
					var forget_held := _button("抹去「%s」" % held_title, _on_choice_pressed.bind("forget:%s" % held_id), false)
					forget_held.custom_minimum_size = Vector2(0, 40)
					action_box.add_child(forget_held)
			elif GameState.has_memory(choice_id):
				rendered_forget = true
				var forget_title := _memory_title(choice_id)
				var forget := _button("抹去「%s」" % forget_title, _on_choice_pressed.bind("forget:%s" % choice_id), false)
				forget.custom_minimum_size = Vector2(0, 40)
				action_box.add_child(forget)
			else:
				var story_choice := _button("选择「%s」" % choice_id, _on_choice_pressed.bind(choice_id), false)
				story_choice.custom_minimum_size = Vector2(0, 40)
				action_box.add_child(story_choice)
	if used + cost > int(GameState.player.get("capacity", 5)) and not rendered_forget:
		for held in GameState.memories():
			var held_id := str(held.get("id", ""))
			var held_title := str(held.get("title", held_id))
			var required_forget := _button("抹去「%s」以腾出空间" % held_title, _on_choice_pressed.bind("forget:%s" % held_id), false)
			required_forget.custom_minimum_size = Vector2(0, 40)
			action_box.add_child(required_forget)
	var note := _label("提示：正式模式下选择会发送到服务器，服务器决定容量、账册与奖励。", 12, Color("#91a8a5"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_box.add_child(note)

func _on_choice_pressed(choice: String) -> void:
	if pending_operation == "submit_choice":
		return
	pending_choice = choice
	_disable_action_buttons()
	if GameState.online and not session_id.is_empty():
		pending_operation = "submit_choice"
		pending_token += 1
		var token := pending_token
		network.submit_choice(session_id, choice)
		get_tree().create_timer(4.0).timeout.connect(_on_network_timeout.bind("submit_choice", token))
		status_label.text = "选择已发送服务器，正在检查心舍容量…"
	else:
		_resolve_local_choice(choice)

func _resolve_local_choice(choice: String) -> void:
	pending_operation = ""
	var memory: Dictionary = current_event.get("reward", {}).get("memory", {})
	var cost := int(memory.get("capacity", 1))
	var used := _memory_capacity_used()
	var forget_id := ""
	if choice.begins_with("forget:"):
		forget_id = choice.trim_prefix("forget:")
		if not GameState.has_memory(forget_id):
			status_label.text = "这道记忆已不在账册中，请重新选择。"
			_show_choice()
			return
	elif GameState.has_memory(choice):
		# Content may use an existing memory ID as a compact forget option.
		forget_id = choice
	var available := int(GameState.player.get("capacity", 5)) - used
	if not forget_id.is_empty():
		for held in GameState.memories():
			if str(held.get("id", "")) == forget_id:
				available += int(held.get("capacity", 1))
				break
	if cost > available:
		status_label.text = "识海空间不足，请从候选记忆中选择一项抹去。"
		_show_choice()
		return
	if not forget_id.is_empty():
		GameState.forget_memory(forget_id, chapter_id, event_id)
	# Narrative choices (for example restore_all/kept) do not fabricate a
	# forgotten ledger entry; they keep the pending memory when capacity allows.
	GameState.keep_memory(memory, chapter_id, event_id)
	var reward: Dictionary = current_event.get("reward", {})
	GameState.player["ink_marks"] = int(GameState.player.get("ink_marks", 0)) + int(reward.get("base_ink_marks", 0))
	GameState.player["capacity"] = int(GameState.player.get("capacity", 5)) + int(reward.get("capacity_increase", 0))
	GameState.player_changed.emit(GameState.player)
	_show_settlement({"stars": _calculate_stars(), "puzzle_score": puzzle_score, "puzzle_total": puzzle_total, "battle_won": true, "offline": true})

func _show_settlement(result: Dictionary) -> void:
	flow_state = "settlement"
	pending_result = result
	_clear_actions()
	var stars := int(result.get("stars", _calculate_stars()))
	var star_text := "★".repeat(clampi(stars, 1, 3)) + "☆".repeat(3 - clampi(stars, 1, 3))
	var heading := _label("事件结算　%s" % star_text, 24, Color("#f2dfb0"))
	action_box.add_child(heading)
	var details := _label("修复度：%d%%\n谜题得分：%d/%d\n白蚀清除：%s\n%s" % [int(result.get("repair_percent", 70 + stars * 10)), int(result.get("puzzle_score", puzzle_score)), int(result.get("puzzle_total", puzzle_total)), "完成" if result.get("battle_won", true) else "未完成", "本地演示结算（未写入服务器）" if result.get("offline", false) else "服务器已确认结算"], 16, Color("#d6e1dc"))
	action_box.add_child(details)
	var outro := str(story.get(event_id, {}).get("outro", "记忆在檐下安静落定。"))
	narrative_label.text = narrative_label.text + "\n\n[font_size=18][color=#e4c98a]" + outro + "[/color][/font_size]"
	if event_id == "temple_drum":
		narrative_label.text += "\n\n[color=#9fb9b0]" + str(story.get(event_id, {}).get("chapter_outro", "")) + "[/color]"
	var next := _button("继续前行", _on_continue_pressed, true)
	next.custom_minimum_size = Vector2(0, 48)
	action_box.add_child(next)
	_refresh_sidebar()

func _on_continue_pressed() -> void:
	var next_event := data.next_event(chapter_id, event_id)
	if not next_event.is_empty():
		_show_event(chapter_id, str(next_event.get("id", "")))
		return
	var next_chapter := data.next_chapter(chapter_id)
	if not next_chapter.is_empty():
		var next_id := str(next_chapter.get("id", ""))
		if not _chapter_unlocked(next_id):
			_show_finish("下一章「%s」需要更多墨痕。当前演示已完成可体验内容。" % str(next_chapter.get("title", next_id)))
		else:
			var first := data.first_event(next_id)
			_show_event(next_id, str(first.get("id", "")))
	else:
		_show_finish("通天塔的门仍在远方。当前章节内容已全部完成。")

func _show_finish(message: String) -> void:
	flow_state = "complete"
	_clear_actions()
	narrative_label.text = "[font_size=20][color=#e4c98a]" + message + "[/color][/font_size]\n\n记忆账册已经记录这一路的保留与遗忘。"
	status_label.text = "演示流程结束。新增章节可直接写入 content/chapters.json。"
	action_box.add_child(_button("回到序章", _on_reset_pressed, true))
	action_box.add_child(_button("查看记忆账册", _on_ledger_pressed, false))

func _on_ledger_pressed() -> void:
	var lines := ["[font_size=18][color=#e4c98a]记忆账册回放[/color][/font_size]"]
	for entry in GameState.memory_ledger:
		var action := "记住" if str(entry.get("action", "")) == "kept" else "遗忘"
		lines.append("[%s] %s　%s" % [action, str(entry.get("title", entry.get("memory_id", ""))), str(entry.get("chapter_id", ""))])
	narrative_label.text = "\n".join(lines)

func _on_reset_pressed() -> void:
	# Online progress belongs to the server. Returning to the prologue must not
	# replace the authoritative snapshot with a fresh local demo player.
	if GameState.online:
		_show_event("prologue", "prologue_bridge")
		return
	GameState.reset_local()
	GameState.set_connection(false, "本地演示模式")
	offline_reason = "用户重新开始本地演示"
	_show_event("prologue", "prologue_bridge")

func _begin_network_probe() -> void:
	server_probe_pending = true
	pending_operation = "create_player"
	pending_token += 1
	var token := pending_token
	network.create_player(_load_identity())
	get_tree().create_timer(4.0).timeout.connect(_on_network_timeout.bind("create_player", token))

func _on_network_result(operation: String, ok: bool, payload: Dictionary, message: String) -> void:
	# A late response must not mutate a newer local/offline event after timeout.
	if pending_operation != operation:
		return
	var response := _payload_data(payload)
	if operation == "create_player":
		pending_operation = ""
		server_probe_pending = false
		if ok:
			var snapshot: Dictionary = response.get("player", response)
			if snapshot.has("id"):
				_save_identity(str(snapshot.get("id", "")))
				GameState.apply_player(snapshot)
			GameState.set_connection(true, "已连接服务器：进度由服务器保存")
		else:
			if _transport_succeeded(payload):
				_set_offline("服务器拒绝了玩家身份请求：%s" % str(response.get("message", response.get("error", "请检查服务端"))))
			else:
				_set_offline("服务器不可用，已切换本地演示模式")
		# The first event was rendered while the probe was pending. Rebuild it so
		# the start button reflects the resolved online/offline state.
		_show_event(chapter_id, event_id)
		return
	if operation == "start_event":
		var remote_session := str(response.get("session_id", response.get("id", response.get("session", {}).get("id", ""))))
		if ok and not remote_session.is_empty():
			pending_operation = ""
			session_id = remote_session
			flow_state = "puzzle"
			status_label.text = "调查进行中。每一步答案会按顺序提交并校验。"
			_show_puzzle_step()
			_enable_puzzle_controls()
		else:
			pending_operation = ""
			if _transport_succeeded(payload):
				flow_state = "intro"
				status_label.text = "服务器拒绝开始此事件：%s" % _server_error_text(response)
				_clear_actions()
				action_box.add_child(_button("重新请求事件", _on_begin_event_pressed, true))
			else:
				_set_offline("事件会话创建失败，当前事件改用本地演示")
				flow_state = "puzzle"
				_show_puzzle_step()
				_enable_puzzle_controls()
		return
	if operation == "get_session":
		pending_operation = ""
		if not ok:
			if _transport_succeeded(payload):
				# A reachable server rejecting the old session must not silently
				# switch the player to local mode. Offer a fresh authoritative run.
				_show_event_retry("服务器会话无法恢复：%s。请重新开始事件。" % _server_error_text(response))
			else:
				_set_offline("无法读取服务器会话：%s" % _server_error_text(response))
				_fallback_after_timeout(recovery_target)
			return
		var remote_status := str(response.get("status", ""))
		if remote_status == "failed":
			# The server is reachable and remains authoritative. A failed session
			# is immutable, so retrying means creating a new session for this event.
			_show_event_retry("服务器已记录本次失败，未同步的本地操作不会覆盖服务器存档。请重新开始事件。")
			return
		if recovery_target == "submit_puzzle":
			var accepted_steps: Array = response.get("accepted_steps", [])
			puzzle_index = clampi(accepted_steps.size(), 0, current_event.get("puzzle", {}).get("steps", []).size())
			puzzle_score = int(response.get("puzzle_score", puzzle_score))
			_show_puzzle_step()
			status_label.text = "服务器会话已同步，继续当前谜题。"
		elif recovery_target == "submit_battle":
			if bool(response.get("battle_won", false)):
				_show_choice()
			else:
				_clear_actions()
				status_label.text = "服务器尚未确认胜利，请重新开始事件。"
				action_box.add_child(_button("重新开始事件", _on_retry_event_pressed, true))
		elif recovery_target == "submit_choice":
			if bool(response.get("choice_done", false)):
				_request_settlement()
			else:
				_show_choice()
		elif recovery_target == "settle":
			var remote_result = response.get("pending_result", null)
			if remote_result is Dictionary and not remote_result.is_empty():
				_show_settlement(remote_result)
			else:
				_request_settlement()
		return
	if operation == "submit_puzzle":
		pending_operation = ""
		if ok:
			var puzzle_player: Dictionary = response.get("player", {})
			if not puzzle_player.is_empty():
				GameState.apply_player(puzzle_player)
			elif response.has("erosion"):
				GameState.player["erosion"] = int(response.get("erosion", GameState.player.get("erosion", 0)))
				GameState.player_changed.emit(GameState.player)
			if str(response.get("status", "")) == "failed":
				_show_event_retry("服务器已记录本事件失败，当前会话已结束。请重新开始事件。")
				return
			var accepted := bool(response.get("accepted", response.get("correct", false)))
			if accepted:
				puzzle_score = int(response.get("puzzle_score", puzzle_score))
				puzzle_index += 1
				status_label.text = "服务器校验通过。"
				_show_puzzle_step()
			else:
				status_label.text = "服务器判定答案不正确，侵蚀度 +10。"
				_show_puzzle_step()
		else:
			if _transport_succeeded(payload):
				if _is_terminal_session_error(response):
					_show_event_retry("服务器会话已结束：%s。请重新开始事件。" % _server_error_text(response))
				else:
					status_label.text = "服务器拒绝了该谜题请求：%s" % _server_error_text(response)
					_show_puzzle_step()
				return
			_set_offline("谜题校验请求超时，已切换本地演示模式")
			_resolve_local_puzzle(pending_answer)
		return
	if operation == "submit_battle":
		pending_operation = ""
		if ok:
			if str(response.get("status", "")) == "failed":
				if response.has("erosion"):
					GameState.player["erosion"] = int(response.get("erosion", GameState.player.get("erosion", 0)))
					GameState.player_changed.emit(GameState.player)
				_show_event_retry("服务器已记录本事件失败，当前会话已结束。请重新开始事件。")
				return
			var won := bool(response.get("won", response.get("battle_won", false)))
			if won:
				_show_choice()
			else:
				if response.has("erosion"):
					GameState.player["erosion"] = int(response.get("erosion", GameState.player.get("erosion", 0)))
					GameState.player_changed.emit(GameState.player)
				_show_battle_retry(str(response.get("reason", "请重整后再试")))
		else:
			if _transport_succeeded(payload):
				if _is_terminal_session_error(response):
					_show_event_retry("服务器会话已结束：%s。请重新开始事件。" % _server_error_text(response))
				else:
					status_label.text = "服务器拒绝了战斗记录：%s" % _server_error_text(response)
					_clear_actions()
					action_box.add_child(_button("重整后重试", _start_battle, true))
				return
			_set_offline("战斗校验请求超时，已切换本地演示模式")
			_resolve_local_battle({})
		return
	if operation == "submit_choice":
		pending_operation = ""
		if ok:
			var snapshot: Dictionary = response.get("player", {})
			if not snapshot.is_empty():
				GameState.apply_player(snapshot)
			if not session_id.is_empty():
				pending_operation = "settle"
				pending_token += 1
				var token := pending_token
				network.settle(session_id)
				get_tree().create_timer(4.0).timeout.connect(_on_network_timeout.bind("settle", token))
				status_label.text = "选择已确认，等待最终结算签名…"
			else:
				_show_settlement(response.get("result", response))
		else:
			if _transport_succeeded(payload):
				if _is_terminal_session_error(response):
					_show_event_retry("服务器会话已结束：%s。请重新开始事件。" % _server_error_text(response))
				else:
					status_label.text = "服务器拒绝了这项心舍选择：%s" % _server_error_text(response)
					_show_choice()
				return
			_set_offline("选择校验请求超时，已切换本地演示模式")
			_resolve_local_choice(pending_choice)
		return
	if operation == "settle":
		pending_operation = ""
		if ok:
			var snapshot: Dictionary = response.get("player", {})
			if not snapshot.is_empty():
				GameState.apply_player(snapshot)
			_show_settlement(response.get("result", response))
		else:
			if _transport_succeeded(payload):
				if _is_terminal_session_error(response):
					_show_event_retry("服务器会话已结束：%s。请重新开始事件。" % _server_error_text(response))
				else:
					status_label.text = "服务器暂未接受结算：%s" % _server_error_text(response)
					_clear_actions()
					action_box.add_child(_button("再次请求结算", _request_settlement, true))
			else:
				_set_offline("结算服务器响应超时")
				_show_settlement({"stars": _calculate_stars(), "puzzle_score": puzzle_score, "puzzle_total": puzzle_total, "battle_won": true, "offline": true})

func _on_network_timeout(operation: String, token: int) -> void:
	if token != pending_token or pending_operation != operation:
		return
	if operation == "create_player":
		pending_operation = ""
		server_probe_pending = false
		_set_offline("连接超时，已切换本地演示模式")
		_show_event(chapter_id, event_id)
	elif operation == "start_event":
		pending_operation = ""
		_set_offline("事件会话响应超时，已切换本地演示模式")
		flow_state = "puzzle"
		_show_puzzle_step()
		_enable_puzzle_controls()
	elif operation == "submit_puzzle":
		_begin_session_recovery("submit_puzzle")
	elif operation == "submit_battle":
		_begin_session_recovery("submit_battle")
	elif operation == "submit_choice":
		_begin_session_recovery("submit_choice")
	elif operation == "settle":
		_begin_session_recovery("settle")
	elif operation == "get_session":
		pending_operation = ""
		_set_offline("无法读取服务器会话，未同步的操作已进入本地演示模式")
		_fallback_after_timeout(recovery_target)

func _begin_session_recovery(target: String) -> void:
	if session_id.is_empty():
		_set_offline("事件会话不存在，已进入本地演示模式")
		_fallback_after_timeout(target)
		return
	recovery_target = target
	pending_operation = "get_session"
	pending_token += 1
	var token := pending_token
	network.get_session(session_id)
	get_tree().create_timer(4.0).timeout.connect(_on_network_timeout.bind("get_session", token))
	status_label.text = "操作响应超时，正在读取服务器会话确认是否已生效…"

func _fallback_after_timeout(target: String) -> void:
	if target == "submit_puzzle":
		_resolve_local_puzzle(pending_answer)
	elif target == "submit_battle":
		_resolve_local_battle({})
	elif target == "submit_choice":
		_resolve_local_choice(pending_choice)
	elif target == "settle":
		_show_settlement({"stars": _calculate_stars(), "puzzle_score": puzzle_score, "puzzle_total": puzzle_total, "battle_won": true, "offline": true})

func _request_settlement() -> void:
	if session_id.is_empty():
		_show_settlement({"stars": _calculate_stars(), "puzzle_score": puzzle_score, "puzzle_total": puzzle_total, "battle_won": true, "offline": true})
		return
	pending_operation = "settle"
	pending_token += 1
	var token := pending_token
	network.settle(session_id)
	get_tree().create_timer(4.0).timeout.connect(_on_network_timeout.bind("settle", token))
	status_label.text = "正在请求服务器最终结算…"

func _set_offline(reason: String) -> void:
	offline_reason = reason
	GameState.set_connection(false, reason)

func _load_identity() -> String:
	var config := ConfigFile.new()
	if config.load(IDENTITY_PATH) != OK:
		return ""
	return str(config.get_value("identity", "player_id", ""))

func _save_identity(player_id: String) -> void:
	if player_id.is_empty():
		return
	var config := ConfigFile.new()
	config.set_value("identity", "player_id", player_id)
	config.save(IDENTITY_PATH)

func _on_connection_changed(is_online: bool, message: String) -> void:
	connection_label.text = ("● 在线　" if is_online else "○ 离线　") + message
	connection_label.add_theme_color_override("font_color", Color("#9ad5ad") if is_online else Color("#d8aa7b"))
	if is_instance_valid(reset_button):
		reset_button.text = "回到序章（保留服务器存档）" if is_online else "重新开始本地演示"
		reset_button.tooltip_text = "重新打开序章，不会清除服务器进度" if is_online else "清除当前内存态演示进度并回到序章"

func _on_player_changed(_player: Dictionary) -> void:
	_refresh_sidebar()

func _refresh_sidebar() -> void:
	if not is_instance_valid(stats_label):
		return
	var player := GameState.player
	stats_label.text = "墨痕　%d\n侵蚀度　%d/100\n识海　%d/%d\n已解锁　%s" % [int(player.get("ink_marks", 0)), int(player.get("erosion", 0)), _memory_capacity_used(), int(player.get("capacity", 5)), _join_strings(player.get("unlocked_chapters", []))]
	var lines := ["[color=#9fb9b0]彩色=记住　灰色=遗忘[/color]"]
	for item in GameState.memory_ledger:
		var remembered := str(item.get("action", "")) == "kept"
		var color := "#d9c38c" if remembered else "#71807d"
		var verb := "记住" if remembered else "遗忘"
		lines.append("[color=%s]%s　%s[/color]" % [color, verb, str(item.get("title", item.get("memory_id", "")))])
	ledger_label.text = "\n".join(lines)

func _compose_story(id: String, intro: String) -> String:
	var lines: Array = ["[font_size=19][color=#e4c98a]%s[/color][/font_size]" % intro]
	var beats: Array = story.get(id, {}).get("beats", [])
	for beat in beats:
		lines.append("\n" + str(beat))
	return "".join(lines)

func _set_backdrop_for_event() -> void:
	var art := data.art(event_id)
	var configured_color := str(art.get("backdrop_color", "")).strip_edges()
	scene_backdrop.color = Color(configured_color) if not configured_color.is_empty() else Color("#18262d")
	if not is_instance_valid(scene_image):
		return
	var background_path := str(art.get("background", "")).strip_edges()
	if not background_path.is_empty() and ResourceLoader.exists(background_path):
		var resource = load(background_path)
		if resource is Texture2D:
			scene_image.texture = resource
			scene_image.visible = true
			return
	scene_image.texture = null
	scene_image.visible = false

func _clear_actions() -> void:
	if not is_instance_valid(action_box):
		return
	for child in action_box.get_children():
		if child == status_label or child == progress_bar:
			continue
		child.queue_free()
	if is_instance_valid(progress_bar):
		progress_bar.visible = false

func _clear_objectives() -> void:
	if not is_instance_valid(objective_box):
		return
	while objective_box.get_child_count() > 1:
		objective_box.get_child(1).queue_free()

func _disable_puzzle_controls() -> void:
	for button in puzzle_buttons:
		if is_instance_valid(button):
			button.disabled = true
	if is_instance_valid(puzzle_input):
		puzzle_input.editable = false

func _enable_puzzle_controls() -> void:
	for button in puzzle_buttons:
		if is_instance_valid(button):
			button.disabled = false
	if is_instance_valid(puzzle_input):
		puzzle_input.editable = true

func _disable_action_buttons() -> void:
	for child in action_box.get_children():
		if child is Button:
			child.disabled = true

func _memory_capacity_used() -> int:
	var total := 0
	for item in GameState.memories():
		total += int(item.get("capacity", 1))
	return total

func _memory_title(memory_id: String) -> String:
	for item in GameState.memories():
		if str(item.get("id", "")) == memory_id:
			return str(item.get("title", memory_id))
	for chapter in data.chapters():
		for item in chapter.get("events", []):
			var memory: Dictionary = item.get("reward", {}).get("memory", {})
			if str(memory.get("id", "")) == memory_id:
				return str(memory.get("title", memory_id))
	return memory_id

func _battle_skill_options() -> Array[String]:
	# Battle controls are assembled from the event contract and the player's
	# current memory skills. A future chapter can introduce a new skill in JSON
	# without requiring a code change or a hard-coded button list.
	var options: Array[String] = []
	var battle: Dictionary = current_event.get("battle", {})
	for value in battle.get("required_skills", []):
		var skill := str(value).strip_edges()
		if not skill.is_empty() and not options.has(skill):
			options.append(skill)
	for memory in GameState.memories():
		var skill := str(memory.get("skill", "")).strip_edges()
		if not skill.is_empty() and not options.has(skill):
			options.append(skill)
	if options.is_empty():
		options.append_array(["斗拱", "飞檐", "藻井"])
	return options

func _chapter_unlocked(id: String) -> bool:
	return id in GameState.player.get("unlocked_chapters", [])

func _puzzle_total(item: Dictionary) -> int:
	var total := 0
	for step in item.get("puzzle", {}).get("steps", []):
		total += int(step.get("points", 0))
	return total

func _calculate_stars() -> int:
	var ratio: float = float(puzzle_score) / maxf(1.0, float(puzzle_total))
	var stars := 1
	if ratio >= 0.6:
		stars = 2
	if ratio >= 0.9 and int(GameState.player.get("erosion", 0)) < 70:
		stars = 3
	return stars

func _payload_data(payload: Dictionary) -> Dictionary:
	var value = payload.get("data", payload)
	return value if value is Dictionary else payload

func _server_error_code(payload: Dictionary) -> String:
	var error_value = payload.get("error", "")
	if error_value is Dictionary:
		return str(error_value.get("code", "")).strip_edges().to_lower()
	return ""

func _server_error_text(payload: Dictionary) -> String:
	var error_value = payload.get("error", "")
	if error_value is Dictionary:
		var detail := str(error_value.get("message", error_value.get("code", ""))).strip_edges()
		if not detail.is_empty():
			return detail
	elif not str(error_value).strip_edges().is_empty():
		return str(error_value).strip_edges()
	var message := str(payload.get("message", "")).strip_edges()
	return message if not message.is_empty() else "服务器拒绝了请求"

func _is_terminal_session_error(payload: Dictionary) -> bool:
	match _server_error_code(payload):
		"session_failed", "session_expired", "session_not_found", "puzzle_attempt_limit", "erosion_limit", "battle_failed":
			return true
	return false

func _transport_succeeded(payload: Dictionary) -> bool:
	return bool(payload.get("_transport_ok", false))

func _join_strings(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return ", ".join(parts)

func _panel(color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("#30484d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable, accent: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#8b6d42") if accent else Color("#263d43")
	normal.set_corner_radius_all(4)
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = Color("#ad8750") if accent else Color("#36565c")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button

func _separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	return separator
