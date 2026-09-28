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
		assert(find_button(main.page, "○").disabled)
		main._show_welcome()
		await capture("welcome-%dx%d" % [dimensions.x, dimensions.y])
		visible_buttons(main.front.overlay)
	main._show_map()
	main._show_settings()
	await capture("settings-final")
	main.queue_free()
	await create_timer(.2).timeout
	print("PASS welcome and three-event chapter controls fully visible at 960x540, 1280x720 and 1600x720; chapter locks preserved")
	quit(0)
