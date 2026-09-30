extends "res://tests/landscape.gd"

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "welcome": await process_frame
	await capture("welcome-final")
	visible_buttons(main.front.overlay)
	# Visual fixtures only. Preserve the completed service save unchanged.
	var game = root.get_node("GameState")
	game.player.completed_events = {}
	game.player.unlocked_chapters = ["prologue"]
	main.current_event = {}
	main.session_id = ""
	main.front.choose_chapter(0)
	await capture("chapters-final")
	visible_buttons(main.page)
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,720)]:
		DisplayServer.window_set_size(dimensions)
		await create_timer(.2).timeout
		main.front.choose_chapter(1)
		await capture("locked-%dx%d" % [dimensions.x, dimensions.y])
		visible_buttons(main.page)
		assert(find_button(main.page, "进入关卡").disabled)
		main._show_welcome()
		await capture("welcome-%dx%d" % [dimensions.x, dimensions.y])
		visible_buttons(main.front.overlay)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(.2).timeout
	main.front.choose_chapter(0)
	find_button(main.page, "进入关卡").pressed.emit()
	await process_frame
	main._finish_dialogue()
	await capture("investigation-final")
	main.scene_view._discover(0)
	main._show_map()
	main._show_welcome()
	find_button(main.front.overlay, "继续旅程").pressed.emit()
	await process_frame
	assert(main.flow == "intro" and main.scene_view.discovered.size() == 1)
	main._show_welcome()
	find_button(main.front.overlay, "旅途收藏").pressed.emit()
	await capture("collection-final")
	assert(main.flow == "memories")
	main._show_settings()
	await capture("settings-final")
	game.session = {"accepted_steps": []}
	main._show_puzzle()
	await capture("puzzle-final")
	assert(main.trace_canvas.size.x > 700)
	main._settlement({"stars": 3, "repair_percent": 100, "erosion_at_end": 0, "ink_marks_earned": 3})
	await capture("settlement-final")
	visible_buttons(main.page)
	if is_instance_valid(main.paused_page):
		main.paused_page.free()
		main.paused_page = null
	main._next_event()
	assert(main.flow == "dialogue" and main.current_event.id == "prologue_bridge")
	main._show_map()
	for chapter in main.data.catalog.chapters:
		for event in chapter.events: game.player.completed_events[chapter.id + ":" + event.id] = {}
	main._next_event()
	assert(main.flow == "map")
	main.queue_free()
	await create_timer(.2).timeout
	print("PASS welcome and three-event chapter controls fully visible at 960x540, 1280x720 and 1600x720; chapter locks preserved")
	quit(0)
