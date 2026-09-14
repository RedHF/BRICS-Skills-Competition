extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OS.get_environment("YANXIA_REVIEW_SHOTS").path_join(name+".png"))

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(99))
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "map" or main.busy: await process_frame
	var game = root.get_node("GameState")
	# Read an existing QA save; these display fixtures never send state mutations to the service.
	main.chapter_id = "archway"
	main.current_event = main.data.event("archway","archway_form")
	game.session = {"accepted_steps":[]}
	main._show_puzzle()
	await capture("archway_grade")
	main.current_event = main.data.event("archway","archway_craftsman")
	game.session = {"accepted_steps":["craftsman_anchor"]}
	main._show_puzzle()
	await capture("craftsman_trigger")
	main.chapter_id = "tower"
	main.current_event = main.data.event("tower","tower_ascent")
	main._start_battle()
	await capture("tower_ascent-battle-ready")
	DisplayServer.window_set_size(Vector2i(1280,720))
	await create_timer(.3).timeout
	for skill in main.battle_buttons:
		assert(root.get_visible_rect().encloses(main.battle_buttons[skill].get_global_rect()),"Skill outside resized viewport")
	await capture("battle-wide")
	print("PASS current pattern and linked scene fixtures; battle controls visible at 1280x720")
	main.queue_free()
	await create_timer(.3).timeout
	quit(0)
