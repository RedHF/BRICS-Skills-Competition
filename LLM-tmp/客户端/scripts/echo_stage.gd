extends HBoxContainer
## The temple chapter shares one saved scene: observations are actions, rather
## than a separate checklist that disappears when the actual puzzle begins.

var host: Node
var spec: Dictionary
var accepted: Array = []
var canvas: Control
var notes: VBoxContainer
var hint: Label
var progress: Label
var action: Button
var complete := false
var locked := false
var selected := ""
var piece_turn := 0
var piece_turns: Dictionary = {}
var clues_open := false
var region := "outer"
var holding := false
var held_seconds := 0.0
var assist_progress: Dictionary = {}
var region_buttons: Dictionary = {}

func _ready() -> void:
	name = "EchoStage"
	add_theme_constant_override("separation", 24)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 450
	spec = host.current_event.stage
	accepted = GameState.session.get("accepted_steps", []).duplicate()
	complete = accepted.size() == host.current_event.puzzle.steps.size()
	canvas = preload("res://scripts/echo_stage_canvas.gd").new()
	canvas.stage = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_stretch_ratio = 2.6
	canvas.custom_minimum_size = Vector2(580, 440)
	add_child(canvas)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 310
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", preload("res://scripts/ink_theme.gd").surface("paper", 20))
	add_child(card)
	var paper_scroll := ScrollContainer.new()
	paper_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(paper_scroll)
	notes = VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_theme_constant_override("separation", 12)
	paper_scroll.add_child(notes)
	_build_notes()
	set_process(true)

func done(id: String) -> bool:
	return id in accepted

func observed() -> bool:
	for object in spec.objects:
		if not str(object.get("step_id", "")).is_empty() and not done(str(object.step_id)): return false
	return true

func _text(value: String, font_size: int = 20) -> Label:
	var label: Label = host._label(notes, value, font_size, Color("#302c28"))
	return label

func _button(value: String, callback: Callable) -> Button:
	var button: Button = host._button(notes, value, callback)
	button.add_theme_font_size_override("font_size", 19)
	return button

func _build_notes() -> void:
	for child in notes.get_children():
		notes.remove_child(child)
		child.queue_free()
	region_buttons.clear()
	hint = null
	progress = null
	_text(str(host.current_event.title), 26)
	if not canvas.inspect_id.is_empty():
		for object in spec.objects:
			if str(object.id) == canvas.inspect_id:
				_text(str(object.label),23)
				_text(str(object.get("text","")),20)
		var back := _button("返回场景，继续 →",close_inspection)
		back.grab_focus.call_deferred()
		canvas.queue_redraw()
		return
	progress = _text("", 17)
	hint = _text("", 19)
	if complete:
		var outcome := {
			"joinery":"你撤下临撑。梁没有再下沉，旧木的拼缝仍然看得见。",
			"guest":"空碗留在你选的位置。檐外有雨，檐下还能再坐一个人。",
			"drum":"鼓面旧纹重新连起来。那条修补线也留下了，没有被抹平。"
		}
		hint.text = outcome[str(spec.kind)]
		var learned := str(host.data.memory(host.current_event.reward.memory_id).get("skill",""))
		if not learned.is_empty(): _text("已学会「%s」。这门手艺不随回声取舍而丢失。" % learned,18)
		if spec.kind == "joinery": _button("查看接合处 / 回到正殿", func(): canvas.workbench = not canvas.workbench; canvas.queue_redraw())
		_button("收下这次回应 →", host._resume)
		_clue_links()
		_update()
		return
	if not observed():
		hint.text = "先看看场景里的两处旧痕。点标记，也可以按 Tab 选择后按回车。"
		for object in spec.objects:
			if not str(object.get("step_id", "")).is_empty():
				_button(("✓ " if done(str(object.step_id)) else "查看 · ") + str(object.label), observe.bind(str(object.id)))
	elif spec.kind == "joinery":
		if not done("hall_support"):
			hint.text = "梁还在悬着。先选斗拱，再点梁下的承架，让它稳住。"
			_button("选用斗拱", func(): selected = "斗拱"; canvas.grab_focus(); canvas.queue_redraw(); hint.text = "已选斗拱。点击承架，或按回车。")
		elif not done("hall_center"):
			hint.text = "对上记号，旋转后拖入榫口。"
			_button("将所选木件转半圈 · R", rotate_piece)
			_button("放回木件 · Esc", put_back_piece)
			_button("看看屋梁 / 返回工作面", func(): canvas.workbench = not canvas.workbench; canvas.queue_redraw())
		else:
			hint.text = "两端和中部都已接住。现在可以撤下临撑，看看梁能否站稳。"
			_button("撤下临撑", release_support)
	elif spec.kind == "guest":
		hint.text = "把空碗拖到檐下，避开旧碗。"
		_button("拿起空碗", func(): selected = "bowl"; canvas.grab_focus(); canvas.queue_redraw(); hint.text = "点击或拖动放碗，也可用方向键移动、回车放下。")
		_button("看看檐下边界", func(): canvas.show_shelter = not canvas.show_shelter; canvas.queue_redraw())
	elif spec.kind == "drum":
		if not done("drum_reveal"):
			hint.text = "旧纹被白斑遮住。选用藻井，再点鼓面，让纹理显出来。"
			_button("选用藻井", func(): selected = "藻井"; canvas.grab_focus(); canvas.queue_redraw(); hint.text = "已选藻井。点击鼓面，或按回车。")
		else:
			hint.text = "按住拖动拓显，显出大半后收笔。"
			var regions := HBoxContainer.new()
			regions.add_theme_constant_override("separation",6)
			notes.add_child(regions)
			for part in spec.rubbing.regions:
				var id := str(part.id)
				var button: Button = host._button(regions,str(part.label),select_region.bind(id))
				button.add_theme_font_size_override("font_size",17)
				region_buttons[id] = button
			action = _button("收笔，查看这处纹理", submit_rubbing)
			var assist := _button("按住此处 · 辅助拓显", func(): pass)
			assist.button_down.connect(start_assist)
			assist.button_up.connect(stop_assist)
			assist.tooltip_text = "也可按住回车 1.5 秒；松开保留辅助进度。"
			for part in spec.rubbing.regions:
				if not done("rub_" + str(part.id)):
					region = str(part.id)
					break
	if observed():
		_button("收起旧痕说明" if clues_open else "旧痕与操作说明…",toggle_clues)
		if clues_open:
			_text(str(spec.goal),17)
			if spec.kind == "joinery": _text("同样的记号相对，凸榫朝凹口。可点击选取再点击安放，也可拖动。R 转向，Esc 放回。简化接合练习。",16)
			_clue_links()
	_update()

func toggle_clues() -> void:
	clues_open = not clues_open
	_build_notes()

func _clue_links() -> void:
	for object in spec.objects:
		if not str(object.get("step_id", "")).is_empty():
			_button("再看 · "+str(object.label),observe.bind(str(object.id)))

func close_inspection() -> void:
	canvas.inspect_id = ""
	_build_notes()
	canvas.queue_redraw()

func _update() -> void:
	if not is_instance_valid(progress): return
	if complete: progress.text = "修复完成 · 旧痕保留"
	elif not observed():
		var count := 0
		for object in spec.objects:
			if done(str(object.get("step_id", ""))): count += 1
		progress.text = "已看见 %d / 2 处旧痕" % count
	elif spec.kind == "joinery":
		progress.text = "① 稳梁" if not done("hall_support") else ("② 接合两端 · %d/2" % [int(done("hall_left"))+int(done("hall_right"))] if not done("hall_left") or not done("hall_right") else ("③ 合拢中部" if not done("hall_center") else "④ 撤下临撑"))
	elif spec.kind == "guest": progress.text = "给后来的人留个位置"
	elif done("drum_reveal"):
		var coverage: float = canvas.coverage(region)
		progress.text = "当前纹理显出 %d%% · %s" % [roundi(coverage*100), "可以收笔" if coverage >= float(spec.rubbing.threshold) else "继续慢慢拓显"]
		if holding: progress.text = "辅助拓显 %d%% · 松开可停下" % mini(100, int(held_seconds / 1.5 * 100))
		for id in region_buttons:
			var label := ""
			for part in spec.rubbing.regions:
				if str(part.id) == id: label = str(part.label)
			region_buttons[id].text = ("✓ " if done("rub_" + id) else ("● " if region == id else "")) + label
			region_buttons[id].disabled = locked or done("rub_" + id)
	canvas.queue_redraw()

func observe(id: String) -> void:
	if locked: return
	for object in spec.objects:
		if str(object.id) != id: continue
		var text := str(object.get("text", ""))
		if done(str(object.get("step_id", ""))):
			stop_assist()
			canvas.inspect_id = id
			_build_notes()
			return
		if str(object.get("step_id", "")).is_empty():
			if spec.kind == "joinery" and selected == "斗拱":
				await submit({"step_id":"hall_support", "answer":selected, "target":"beam"})
			return
		await submit({"step_id":object.step_id, "answer":id})
		if done(str(object.step_id)):
			canvas.inspect_id = id
			_build_notes()
		return

func use_drum() -> void:
	if selected == "藻井":
		await submit({"step_id":"drum_reveal", "answer":"藻井", "target":"inscription"})
	else: hint.text = "先选一种技艺，再点鼓面。"

func choose_piece(index: int) -> void:
	if locked or not done("hall_support") or complete: return
	var piece: Dictionary = spec.pieces[index]
	var placed := {"JOIN-L":"hall_left", "JOIN-R":"hall_right", "JOIN-C":"hall_center"}
	if done(str(placed.get(str(piece.id), ""))): return
	selected = str(piece.id)
	piece_turn = int(piece_turns.get(selected,piece.initial_rotation))
	hint.text = "%s · R 转向，拖入同记号榫口" % piece.label
	canvas.queue_redraw()

func put_back_piece() -> void:
	selected = ""
	canvas.dragging = false
	canvas.queue_redraw()

func rotate_piece() -> void:
	if selected.is_empty() or not selected.begins_with("JOIN-") or locked: return
	piece_turn = (piece_turn+180)%360
	piece_turns[selected] = piece_turn
	canvas.queue_redraw()

func place_piece(slot: String) -> void:
	if selected.is_empty() or locked: return
	var steps := {"SLOT-L":"hall_left", "SLOT-R":"hall_right", "SLOT-C":"hall_center"}
	await submit({"step_id":steps[slot], "answer":selected, "target":slot, "rotation":piece_turn})

func release_support() -> void:
	await submit({"step_id":"hall_release", "answer":"release", "target":"support"})

func place_bowl(point: Vector2) -> void:
	if locked or selected != "bowl" or complete: return
	await submit({"step_id":"guest_place", "answer":"bowl", "target":"dry_floor", "position":[point.x, point.y]})

func select_region(id: String) -> void:
	if locked: return
	stop_assist()
	region = id
	held_seconds = float(assist_progress.get(id,0.0))
	_update()

func start_assist() -> void:
	if locked or complete or done("rub_" + region): return
	holding = true
	held_seconds = float(assist_progress.get(region,0.0))

func stop_assist() -> void:
	if holding: assist_progress[region] = held_seconds
	holding = false
	_update()

func submit_rubbing() -> void:
	if locked or done("rub_" + region): return
	await submit({"step_id":"rub_" + region, "strokes":canvas.strokes.get(region, [])})

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		stop_assist()
		return
	if not holding or locked or complete or spec.kind != "drum" or not done("drum_reveal"): return
	held_seconds += delta
	assist_progress[region] = held_seconds
	_update()
	if held_seconds >= 1.5:
		holding = false
		await submit({"step_id":"rub_" + region, "assist_ms":1500})

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not canvas.inspect_id.is_empty() or locked or complete or spec.kind != "drum" or not done("drum_reveal"): return
	if event is InputEventKey and event.keycode == KEY_ENTER and not event.echo:
		if event.pressed: start_assist()
		else: stop_assist()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not canvas.inspect_id.is_empty(): return
	if not event is InputEventKey or event.echo or locked or not is_visible_in_tree(): return
	if event.keycode == KEY_R and event.pressed: rotate_piece()
	elif event.keycode == KEY_ESCAPE and event.pressed:
		put_back_piece()

func submit(payload: Dictionary) -> void:
	if locked or host.busy: return
	locked = true
	host.busy = true
	var response: Dictionary = await host.network.request_json("/api/v1/sessions/%s/puzzle" % host.session_id, HTTPClient.METHOD_POST, payload)
	host.busy = false
	locked = false
	if response.is_empty():
		hint.text = "这一步还没有确认保存。请稍后再试。"
		return
	if not bool(response.get("accepted", false)):
		var messages := {
			"prerequisite_incomplete":"先让前面的构件接住：稳住梁，再接两端，最后合中部。",
			"rotation_incorrect":"方向反了。按 R 转半圈后再放。",
			"piece_incorrect":"记号与榫口还没有相合。看看双短痕、斜痕和缺角。",
			"placement_outside_shelter":"这里会淋雨，或与旧碗挤在一起。檐下还能找到别的空处。",
			"rubbing_incomplete":"还可以再显出一些。笔迹会留着，慢慢补拓就好。"
		}
		hint.text = str(messages.get(str(response.get("reason", "")), "还没有相合，可以继续尝试。"))
		_update()
		return
	accepted = response.get("accepted_steps", accepted).duplicate()
	GameState.session.accepted_steps = accepted.duplicate()
	GameState.session.stage_placements = response.stage_placements if response.get("stage_placements") is Dictionary else {}
	selected = ""
	complete = accepted.size() == host.current_event.puzzle.steps.size()
	if str(spec.kind) == "joinery":
		if complete: canvas.repair_finished()
		elif str(payload.step_id) == "hall_support": canvas.workbench = true
	if str(payload.step_id).begins_with("rub_"): canvas.finish_region(str(payload.step_id).trim_prefix("rub_"))
	var step := str(payload.step_id)
	host.soundscape.cue("timber_support" if step in ["hall_support","hall_release"] else ("timber_seat" if step.begins_with("hall_") else ("pottery_place" if step == "guest_place" else "paper_fold")))
	_build_notes()
	canvas.queue_redraw()
