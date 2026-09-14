extends SceneTree

var main
var game
var shots := ""

func _initialize() -> void:
	_run.call_deferred()

func tap(point: Vector2) -> void:
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await process_frame
	while main.busy: await process_frame

func capture(name: String) -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(shots.path_join(name+".png"))

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.busy or main.data.catalog.is_empty(): await process_frame
	game = root.get_node("GameState")
	assert(main.session_id.is_empty(),"Use a fresh isolated save")
	main._open_event("prologue","prologue_bridge")
	await process_frame
	var stage = main.dialogue_stage
	assert(stage.text_label.visible_characters < stage.text_label.text.length())
	await create_timer(.2).timeout
	assert(stage.text_label.visible_characters > 0,"Typewriter animation is not running")
	await capture("dialogue-reveal")
	await tap(Vector2(8,8))
	assert(main.dialogue_index == 1,"Clicking the window corner did not advance")
	await tap(stage.text_label.get_global_rect().get_center())
	assert(main.dialogue_index == 2,"Clicking text did not advance directly")
	await tap(Vector2(270,240))
	assert(main.dialogue_index == 3,"Background did not advance")
	await tap(stage.previous.get_global_rect().get_center())
	assert(main.dialogue_index == 2,"Previous also advanced the line")
	await tap(stage.back.get_global_rect().get_center())
	assert(main.flow == "map")
	main._open_event("prologue","prologue_bridge")
	assert(main.dialogue_index == 2,"Cursor did not survive return")
	await create_timer(1.8).timeout
	await capture("dialogue-full")
	await tap(main.dialogue_stage.skip.get_global_rect().get_center())
	assert(main.flow == "intro","Skip must enter investigation")
	await main._start_event()
	for i in range(3):
		await main.network.request_json("/api/v1/sessions/%s/puzzle" % main.session_id,HTTPClient.METHOD_POST,{"step_id":"out_of_order","answer":"wrong"})
	await main._resume()
	assert(main.flow == "gameover" and main.dialogue_lines.size() == 9)
	assert(main.dialogue_lines[0].text.ends_with("你的手抖得太厉害了。"))
	assert(main.page.find_children("*","Button",true,false).is_empty(),"Recovery exposed before scene ends")
	var actual_session: Dictionary = game.session.duplicate(true)
	var actual_id: String = main.session_id
	var player_snapshot := JSON.stringify(game.player)
	main._finish_dialogue()
	assert(main.flow == "gameover","Failure scene was skippable")
	for i in range(4): await tap(Vector2(10,10))
	await main._load_game()
	await main._resume()
	assert(main.flow == "gameover" and main.dialogue_index == 4,"Failure cursor lost on reload")
	for i in range(4): await tap(Vector2(270,240))
	assert(main.dialogue_lines[8].text == "你这个人，满脑子只想着自己呢。")
	await create_timer(1.8).timeout
	await capture("gameover-last-line")
	await tap(main.dialogue_stage.text_label.get_global_rect().get_center())
	assert(main.flow == "failed" and main.session_id == actual_id)
	await capture("gameover-recovery")
	await main._resume()
	assert(main.flow == "failed","Completed failure scene replayed for same attempt")
	assert(JSON.stringify(game.player) == player_snapshot,"Scene changed player state")
	print("PASS dialogue input, animation, navigation, failure gating, reload and unchanged player")
	# Display-only fixtures cover every server reason plus unknown fallback.
	for reason in ["erosion_limit","puzzle_attempt_limit","battle_requirements_not_met","session_expired","unknown"]:
		main.session_id = "fixture-"+reason
		game.session = actual_session.duplicate(true)
		game.session.failure_reason = reason
		main._begin_failure()
		var expected: String = main.data.catalog.failure_scene.first_lines.get(reason,main.data.catalog.failure_scene.dialogue[0]).text
		assert(main.dialogue_lines[0].text == expected)
		for i in range(9): await tap(Vector2(10,10))
		assert(main.flow == "failed")
	main.session_id = actual_id
	game.session = actual_session
	await main._resume()
	var retry: Button
	for child in main.page.find_children("*","Button",true,false):
		if child.text.begins_with("墨痕不足"): retry = child
	assert(is_instance_valid(retry) and not retry.disabled)
	await process_frame
	main.scroll.ensure_control_visible(retry)
	await process_frame
	await tap(retry.get_global_rect().get_center())
	assert(main.flow == "puzzle" and int(game.player.ink_marks)==0 and int(game.player.erosion)==0)
	for i in range(3):
		await main.network.request_json("/api/v1/sessions/%s/puzzle" % main.session_id,HTTPClient.METHOD_POST,{"step_id":"out_of_order","answer":"wrong"})
	await main._resume()
	assert(main.flow == "gameover" and main.dialogue_index==0,"A new failure reused the completed scene marker")
	print("PASS all failure first-line variants, real free rewind, fresh playback after another failure")
	main.queue_free()
	await create_timer(.3).timeout
	quit(0)
