extends RefCounted

const INK := Color("#302c28")
const NOTE := Color("#746b60")
const OBJECTS := {
	"yan_ping_an": "廊桥与桥灯",
	"she_cheng_xiang": "拼合的旧梁",
	"she_ning_an": "檐下的空碗",
	"she_hui_chun": "仍能敲响的鼓"
}
const EFFECTS := {
	"yan_ping_an": "桥和斗拱手艺仍在；那一次归人的脚步声不再被你唤回。",
	"she_cheng_xiang": "屋梁仍然稳固；众人抬梁的手影与号子不再随身显现。",
	"she_ning_an": "你留下的碗与待客记录仍在；那一夜的客声不再随身回应。",
	"she_hui_chun": "鼓仍可以敲响；孩子独有的记忆跟拍不再随身响起。",
	"xi_xing_qiang": "戏台和引响技艺仍在；那一段初唱不再被你完整唤回。",
	"xi_jue_chang": "传授与练习的记录仍在；那一次师徒对答不再随身重现。",
	"fang_wu_ming": "柱脚手印与营造记录仍在；那一段敲凿的回声不再随身响起。",
	"fang_jiang_hun": "做法与技艺仍在；那双手独有的授艺回应不再重现。",
	"tower_origin": "抹忆的因果记录仍在；初代那一次完整自述不再被你唤回。"
}

var host: Node
var candidate := ""
var choice_event := ""
var preview: Control
var response_note: Label
var response_continue: Button

func _init(main: Node) -> void:
	host = main

func held(id: String) -> bool:
	for memory in GameState.player.get("memories", []):
		if str(memory.id) == id: return true
	return false

func can_listen(path: String) -> bool:
	for memory in GameState.player.get("memories", []):
		if str(host.data.memory(memory.id).get("echo_audio", "")) == path: return true
	if not host.current_event.is_empty() and not bool(GameState.session.get("choice_done", true)):
		var pending: Dictionary = host.data.memory(host.current_event.reward.memory_id)
		return str(pending.get("echo_audio", "")) == path
	return false

func consequence(id: String) -> String:
	return str(EFFECTS.get(id, "已证实的记录与手艺保留，这一次独有的回应不再随身响起。"))

func choice() -> void:
	host.flow = "choice"
	host._clear()
	var memory: Dictionary = host.data.memory(host.current_event.reward.memory_id)
	if choice_event != str(host.current_event.id):
		choice_event = str(host.current_event.id)
		candidate = ""
	if bool(memory.get("epilogue", false)):
		host._label(host.page, "最后一页记录你的旅途，不占用心舍。", 20)
		_record_list(host.page)
		host._button(host.page, "收下最后一页", host._choose.bind("keep", ""))
		return
	var used := 0
	for item in GameState.player.memories: used += int(item.capacity)
	var full: bool = used + int(memory.capacity) > int(GameState.player.capacity)
	host._label(host.page, "回声取舍  /  心舍 %d/%d" % [used, int(GameState.player.capacity)], 26)
	host._label(host.page, "心舍已满。先选一段旧回声比较，再决定带走新回应或保留现有回应。" if full else "还有空位。新回声可以收入心舍，也可以只留下记录。", 19)
	if full:
		var choices := HBoxContainer.new()
		choices.add_theme_constant_override("separation", 10)
		host.page.add_child(choices)
		for old in GameState.player.memories:
			var select: Button = host._button(choices, ("已选 · " if candidate == str(old.id) else "比较 · ") + str(old.title), _select.bind(str(old.id)))
			select.custom_minimum_size.y = 50
			if candidate == str(old.id):
				select.add_theme_stylebox_override("normal",preload("res://scripts/ink_theme.gd").surface("paper",10))
				select.add_theme_color_override("font_color",INK)
	var comparison := HBoxContainer.new()
	comparison.add_theme_constant_override("separation",16)
	comparison.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.page.add_child(comparison)
	_comparison_card(comparison,memory,"新听见")
	if full and not candidate.is_empty():
		_comparison_card(comparison,host.data.memory(candidate),"现有回应")
	else:
		var placeholder := PanelContainer.new()
		placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		placeholder.size_flags_stretch_ratio = 1
		placeholder.add_theme_stylebox_override("panel",preload("res://scripts/ink_theme.gd").surface("paper",18))
		comparison.add_child(placeholder)
		var note := VBoxContainer.new()
		note.alignment = BoxContainer.ALIGNMENT_CENTER
		placeholder.add_child(note)
		host._label(note,"现有回声" if full else "留在檐下的记录",22)
		host._label(note,"从上方选一段，再看见完整的比较。" if full else "修复、手艺与摘要会保存；不带走这次独有的回应。",19)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",16)
	host.page.add_child(actions)
	var take_label := "带走「%s」 · 归档所选旧回声…" % memory.title if full else "收入心舍"
	var take_action: Callable = confirm.bind("replace",candidate) if full else host._choose.bind("keep","")
	var take: Button = host._button(actions,take_label,take_action)
	take.disabled = full and candidate.is_empty()
	var archive_label := "保留现有回声 · 只归档「%s」…" % memory.title if full else "只留下新回声的记录…"
	host._button(actions,archive_label,confirm.bind("archive",str(memory.id)))
	host._label(host.page,"记录、修复与技艺始终保留；归档后，这次独有的完整回应不再随身响起。",16)

func _comparison_card(parent: HBoxContainer, memory: Dictionary, heading: String) -> void:
	var frame := PanelContainer.new()
	frame.name = "NewResponse" if heading == "新听见" else "HeldResponse"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1
	frame.add_theme_stylebox_override("panel",preload("res://scripts/ink_theme.gd").surface("paper",14))
	parent.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	frame.add_child(column)
	host._label(column,heading+"  /  「%s」" % memory.title,22)
	var art: TextureRect = host._memory_art(column,str(memory.id),190)
	if art != null: art.custom_minimum_size.y = 190
	host._label(column,"旧物 · "+str(OBJECTS.get(str(memory.id),"留下的旧迹")),17)
	host._label(column,str(memory.summary),18)
	if str(memory.id) in ["yan_ping_an","she_cheng_xiang","she_ning_an","she_hui_chun"]:
		host._button(column,"看与听 · %s" % memory.title,inspect_choice.bind(str(memory.id)))
	else:
		host._button(column,"聆听 · %s" % memory.title,host._play_memory.bind(str(memory.echo_audio)))

func _select(id: String) -> void:
	candidate = id
	choice()

func inspect_choice(id: String) -> void:
	host._clear()
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",24)
	host.page.add_child(body)
	preview = _scene(body,id)
	preview.living = held(id) or str(host.current_event.reward.memory_id) == id
	var notes := VBoxContainer.new()
	notes.custom_minimum_size.x = 300
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_theme_constant_override("separation",16)
	body.add_child(notes)
	var memory: Dictionary = host.data.memory(id)
	host._label(notes,str(memory.title)+" · 这次鲜活的回应",26)
	host._label(notes,str(memory.summary),22)
	host._label(notes,"若归档这段回应："+consequence(id),20)
	host._button(notes,"重听这段回声",host._play_memory.bind(str(memory.echo_audio)))
	host._button(notes,"返回取舍",choice)

func confirm(action: String, id: String) -> void:
	var memory: Dictionary = host.data.memory(id)
	for connection in host.archive_prompt.confirmed.get_connections():
		host.archive_prompt.confirmed.disconnect(connection.callable)
	host.archive_prompt.confirmed.connect(host._choose.bind(action, id if action == "replace" else ""), Object.CONNECT_ONE_SHOT)
	var incoming := str(host.data.memory(host.current_event.reward.memory_id).title) if action == "replace" else ""
	host.archive_prompt.open(memory,consequence(id),incoming)

func choice_result(response: Dictionary) -> void:
	GameState.player = response.player
	host.busy = false
	host.flow = "choice"
	host._clear()
	var archived := str(response.get("forgotten_memory_id", ""))
	var memory: Dictionary = host.data.memory(host.current_event.reward.memory_id)
	var body := HBoxContainer.new()
	body.name = "ChoiceResult"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	host.page.add_child(body)
	var scene_id := archived if not archived.is_empty() else str(memory.id)
	if scene_id in ["yan_ping_an","she_cheng_xiang","she_ning_an","she_hui_chun"]:
		preview = _scene(body,scene_id,not archived.is_empty())
		preview.size_flags_stretch_ratio = 1.65
	else:
		var art: TextureRect = host._memory_art(body, str(memory.id), 330)
		if art != null:
			art.custom_minimum_size.x = 260
			art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var notes := VBoxContainer.new()
	notes.name = "ResultNotes"
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	notes.add_theme_constant_override("separation", 16)
	body.add_child(notes)
	host._label(notes, "已收入心舍" if archived.is_empty() else "已记入檐下谱", 26)
	if archived.is_empty():
		host._label(notes, "你带走了「%s」。" % memory.title, 23)
	else:
		var old: Dictionary = host.data.memory(archived)
		host._label(notes, "已归档「%s」" % old.title, 23)
		host._label(notes, consequence(archived), 22)
		if archived != str(memory.id): host._label(notes, "「%s」留在心舍，成为新的回应。" % memory.title, 22)
	host._label(notes, "手艺与修复成果已保存。", 18)
	var next: Button = host._button(notes, "收起谱页，继续 →", host._resume)
	next.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	next.custom_minimum_size.x = 260

func _scene(parent: Node, id: String, retiring: bool = false, interactive: bool = false) -> Control:
	var view = preload("res://scripts/echo_resonance.gd").new()
	view.host = host
	view.memory_id = id
	view.living = held(id)
	view.retiring = retiring
	view.interactive = interactive
	parent.add_child(view)
	return view

func drum_response() -> void:
	host.flow = "response"
	host._clear()
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",24)
	host.page.add_child(body)
	preview = _scene(body,"she_hui_chun",false,true)
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.custom_minimum_size.x = 300
	notes.add_theme_constant_override("separation",16)
	body.add_child(notes)
	host._label(notes,"鼓还在这里",28)
	var archived := str(GameState.session.get("forgotten_memory",""))
	if not archived.is_empty(): host._label(notes,consequence(archived),21)
	host._label(notes,"敲一下鼓，听听现在会得到怎样的回应。",22)
	response_note = host._label(notes,"不必对准节拍，也不需要连续点击。",19)
	host._button(notes,"敲一下鼓",_sound_drum)
	response_continue = host._button(notes,"合上这一页 →",host._resume)
	response_continue.hide()
	preview.drum_pressed.connect(_sound_drum)

func _sound_drum() -> void:
	if host.busy: return
	host.busy = true
	var response: Dictionary = await host.network.request_json("/api/v1/sessions/%s/respond" % host.session_id,HTTPClient.METHOD_POST,{})
	host.busy = false
	if not bool(response.get("accepted",false)):
		response_note.text = "鼓声还没有确认保存，请再试一次。"
		return
	GameState.session.world_response = true
	var child: bool = bool(response.get("child_echo",false)) and held("she_hui_chun")
	preview.sound_drum(child)
	response_note.text = "鼓声响起。孩子接上：一、二、三！" if child else "鼓声响起，院子里留下一段余响。那次独有的数拍不再跟来。"
	response_continue.show()
	if child: host._play_cues(["temple_drum_dialogue_02"])
	else: host._stop_voice()

func revisit() -> void:
	host.flow = "echo_memory"
	host._clear()
	var id := str(host.current_event.reward.memory_id)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",24)
	host.page.add_child(body)
	preview = _scene(body,id,false,id == "she_hui_chun")
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.custom_minimum_size.x = 300
	notes.add_theme_constant_override("separation",16)
	body.add_child(notes)
	host._label(notes,"重访 · " + str(host.current_event.title),28)
	host._label(notes,str(host.current_event.story.outro),22)
	if held(id): host._button(notes,"唤回这段回应",host._play_memory.bind(str(host.data.memory(id).echo_audio)))
	else: host._label(notes,consequence(id),21)
	if id == "she_hui_chun":
		var tap := func():
			preview.sound_drum(held("she_hui_chun"))
			if held("she_hui_chun"): host._play_cues(["temple_drum_dialogue_02"])
		preview.drum_pressed.connect(tap)
		host._button(notes,"敲一下鼓",tap)
	host._button(notes,"查看已存记录",host._memory_detail.bind(id))
	host._button(notes,"返回关卡",host._show_map)

func settlement(result: Dictionary, first_clear: bool = false) -> void:
	host.flow = "settlement"
	host._clear()
	if first_clear and str(host.current_event.id) == "temple_drum":
		var gong := AudioStreamPlayer.new()
		gong.stream = load("res://assets/echo_v1/distant_gong.wav")
		gong.volume_db = -19
		host.page.add_child(gong)
		gong.play()
	host._label(host.page, "古建又得到了一次回应", 28)
	host._memory_art(host.page, str(host.current_event.reward.memory_id), 200)
	host._label(host.page, str(host.current_event.story.outro), 23)
	var action := str(result.get("memory_action", "keep"))
	var name := str(host.data.memory(host.current_event.reward.memory_id).title)
	var prefix := "收下终章页：" if bool(host.data.memory(host.current_event.reward.memory_id).get("epilogue",false)) else ("本次只留记录：" if action == "archive" else "本次带走：")
	host._label(host.page, prefix + name, 22)
	var archived := str(result.get("archived_memory_id", ""))
	if not archived.is_empty(): host._label(host.page, consequence(archived), 20)
	var answer := str(result.get("narrative_choice", ""))
	if not answer.is_empty():
		host._label(host.page, "你把最后一页用于：" + answer, 23)
		_record_list(host.page)
		host._label(host.page, host._ending_response(answer), 21)
	host._button(host.page, "查看这段记录", host._memory_detail.bind(str(host.current_event.reward.memory_id)))
	var next_label := {"temple_incense":"前往侧厢 →", "temple_guest":"走向前坪 →", "temple_drum":"去听远处的锣 →"}
	host._button(host.page, str(next_label.get(str(host.current_event.id), "下一段旅程 →")), host._next_event)
	host._button(host.page, "返回关卡", host._show_map)
	host.session_id = ""

func memories() -> void:
	host._pause_event()
	host.flow = "memories"
	host._clear()
	host._label(host.page, "旅途收藏 · 回声与记录", 28)
	var tabs := HBoxContainer.new()
	host.page.add_child(tabs)
	host._button(tabs, "取舍记录", host._show_ledger)
	host._button(tabs, "返回主页", host._show_welcome)
	_record_list(host.page, true)
	if host._has_current_event(): host._button(host.page, "返回游戏", host._resume)

func _record_list(parent: Node, interactive: bool = false) -> void:
	var records: Array = GameState.player.get("recorded_memories", [])
	if records.is_empty(): host._label(parent, "修复与取舍之后，已证实的记录会收在这里。", 20)
	var target := parent
	if not interactive and records.size() > 4:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation",36)
		grid.add_theme_constant_override("v_separation",6)
		parent.add_child(grid)
		target = grid
	for record in records:
		var memory: Dictionary = host.data.memory(str(record.id))
		var state := "终章页" if bool(memory.get("epilogue", false)) else ("鲜活" if held(str(record.id)) else "已归档")
		var text := "%s · %s" % [memory.title, state]
		if interactive: host._button(target, text, host._memory_detail.bind(str(record.id)))
		else:
			var label: Label = host._label(target,text,19)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func detail(id: String) -> void:
	host._pause_event()
	host.flow = "echo_memory"
	host._clear()
	var memory: Dictionary = host.data.memory(id)
	var living := held(id)
	var epilogue := bool(memory.get("epilogue", false))
	host._label(host.page, str(memory.title) + (" · 终章页" if epilogue else (" · 鲜活共鸣" if living else " · 已归档")), 28)
	host._memory_art(host.page, id, 240)
	host._label(host.page, str(memory.summary), 22)
	if living:
		host._button(host.page, "聆听这段鲜活回声", host._play_memory.bind(str(memory.echo_audio)))
	elif not epilogue:
		host._label(host.page, consequence(id), 21)
		host._label(host.page, "记录仍可查，这次回声不再随身响起。", 19)
	if not str(memory.skill).is_empty(): host._label(host.page, "已经学会的技艺：" + str(memory.skill), 20)
	host._button(host.page, "返回收藏", host._show_memories)
	if host._has_current_event(): host._button(host.page, "继续当前旅程", host._resume)

func ledger() -> void:
	host._pause_event()
	host.flow = "ledger"
	host._clear()
	host._label(host.page, "取舍记录", 28)
	for entry in GameState.player.memory_ledger:
		var action := str({"kept":"带走", "archived":"归档", "epilogue":"收下最后一页"}.get(str(entry.action), str(entry.action)))
		var trigger: Dictionary = host.data.event(str(entry.chapter_id), str(entry.event_id))
		host._label(host.page, "%s「%s」 · 在「%s」" % [action, entry.title, trigger.title], 21)
	if GameState.player.memory_ledger.is_empty(): host._label(host.page, "还没有取舍记录。", 20)
	host._button(host.page, "返回收藏", host._show_memories)
	if host._has_current_event(): host._button(host.page, "继续当前旅程", host._resume)

func failure() -> void:
	host.flow = "failed"
	host._clear()
	host._art_banner(host.page, host._event_background(), 230)
	host._label(host.page, "守护暂歇 · 可以再试", 28)
	host._label(host.page, "本次守护未完成，旅程仍可继续。", 23)
	host._label(host.page, "修复、已经学会的技艺和确认的取舍都保留。重试从本次守护开始。", 21)
	host._button(host.page, "免费重试守护", host._rewind)
	host._button(host.page, "返回关卡", host._show_map)

func journal() -> void:
	host._pause_event()
	host.flow = "journal"
	host._clear()
	host._label(host.page, "旅途回顾 · 已发生的事", 28)
	for chapter in host.data.catalog.chapters:
		for event in chapter.events:
			if GameState.player.completed_events.has(str(chapter.id) + ":" + str(event.id)):
				host._label(host.page, str(chapter.title) + " / " + str(event.title), 23)
				host._label(host.page, str(event.story.outro), 20)
				host._button(host.page, "查看记录", host._memory_detail.bind(str(event.reward.memory_id)))
	host._button(host.page, "返回收藏", host._show_memories)
	if host._has_current_event(): host._button(host.page, "继续当前旅程", host._resume)
