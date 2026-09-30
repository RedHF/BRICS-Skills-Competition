extends "res://tests/review_journey.gd"

func hold(seconds: float) -> void:
	await create_timer(seconds).timeout

func drag_path(points: Array) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = points[0]
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	for i in range(1, points.size()):
		for t in range(1, 5):
			var motion := InputEventMouseMotion.new()
			motion.position = points[i-1].lerp(points[i], t / 4.0)
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			root.push_input(motion, true)
			await process_frame
	var up = down.duplicate()
	up.pressed = false
	up.position = points[-1]
	root.push_input(up, true)
	await process_frame
	while main.busy: await process_frame

func _run() -> void:
	create_timer(205).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	game = root.get_node("GameState")
	while main.flow != "welcome" or main.busy: await process_frame
	print("CAPTURE viewport=",root.size)
	await hold(5)
	await click(button("开始旅程",main.front.overlay))
	await hold(4)
	await click(button("进入关卡", main.page))
	while main.busy: await process_frame
	while main.flow != "dialogue": await process_frame
	assert(main.flow == "dialogue")
	await hold(4)
	await key(KEY_SPACE)
	await hold(3)
	await click(main.dialogue_stage.skip)
	assert(main.flow == "intro")
	Input.action_press("move_right")
	await hold(1.2)
	Input.action_release("move_right")
	for point in main.scene_view.investigations:
		await tap(main.scene_view.global_position + main.scene_view.size * Vector2(point.position[0],point.position[1]))
		await hold(2.0)
	await click(button("聆听往事"))
	await hold(4)
	await click(button("收起往事"))
	await click(button("开始修复"))
	var step = main.current_event.puzzle.steps[0]
	await hold(2)
	for index in range(step.trace.strokes.size()):
		await click(button("%02d" % [index+1],main.stroke_buttons))
		main.scroll.ensure_control_visible(main.trace_canvas)
		await process_frame
		await process_frame
		var canvas = main.trace_canvas
		var samples: Array = []
		for point in step.trace.strokes[index]:
			samples.append(canvas.global_position + canvas.canvas_rect.position + Vector2((point[0]-canvas.view_x)*canvas.characters,point[1])*canvas.canvas_rect.size)
		await drag_path(samples)
		await hold(.2)
	await hold(2)
	await click(button("核对拓印"))
	assert(main.flow == "choice",main.status.text)
	await hold(3)
	await click(button("拓印这道墨灵"))
	await hold(3)
	await click(main.battle_start)
	while not main.battle_finished:
		if not main.battle_buttons["斗拱"].disabled: await key(KEY_2)
		if not main.battle_buttons["闪身"].disabled: await key(KEY_5)
		if not main.battle_buttons["挥墨"].disabled: await key(KEY_1)
		Input.action_press("move_left" if fmod(main.battle_elapsed,4)<2 else "move_right")
		await hold(.52)
		Input.action_release("move_left")
		Input.action_release("move_right")
	assert(main.arena.defeated,"Battle did not finish successfully")
	await hold(2)
	await click(button("结算白蚀战斗",main.battle_dock))
	while main.flow != "settlement": await process_frame
	assert(main.flow == "settlement",main.status.text)
	assert(game.player.completed_events.has("prologue:prologue_bridge"))
	await capture("settlement")
	await hold(7)
	await click(button("下一段旅程"))
	while main.flow != "dialogue": await process_frame
	await hold(5)
	if main.flow == "map":
		await click(button("02",main.page))
		await hold(3)
		await click(button("进入关卡"))
	await hold(5)
	await click(main.dialogue_stage.skip)
	for point in main.scene_view.investigations:
		await tap(main.scene_view.global_position + main.scene_view.size * Vector2(point.position[0],point.position[1]))
		await hold(1.5)
	await click(button("开始修复"))
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("YANXIA_CONTENT_FILE")))
	for join_step in fixture.chapters[1].events[0].puzzle.steps:
		main.scroll.ensure_control_visible(main.join_canvas)
		await process_frame
		await process_frame
		var canvas = main.join_canvas
		var slot: int = join_step.options.find(join_step.answer)
		await hold(1.5)
		await drag_path([canvas.global_position+canvas.piece,canvas.global_position+canvas._socket_center(slot)])
		await hold(2)
	assert(main.flow == "choice",main.status.text)
	await click(button("拓印这道墨灵"))
	await hold(3)
	await click(main.battle_start)
	while not main.battle_finished:
		for skill in ["斗拱","藻井","闪身","挥墨"]:
			if main.battle_buttons.has(skill) and not main.battle_buttons[skill].disabled:
				await key(KEY_1+main.BATTLE_KEYS.find(skill))
		await hold(.52)
	assert(main.arena.defeated)
	await hold(2)
	await click(button("结算白蚀战斗",main.battle_dock))
	while main.flow != "settlement": await process_frame
	assert(main.flow == "settlement")
	assert(game.player.completed_events.has("temple:temple_incense"))
	await capture("temple-settlement")
	await hold(6)
	await click(button("回看这道墨灵"))
	await hold(5)
	var seconds := float(Engine.get_process_frames())/30.0
	if seconds < 180: await hold(180-seconds)
	print("PASS video: actual input, one complete bridge event, server settlement; frames=",Engine.get_process_frames())
	quit(0)
