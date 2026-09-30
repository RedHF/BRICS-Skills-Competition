extends "res://tests/landscape.gd"

func _run() -> void:
	create_timer(45).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	assert(root.size == Vector2i(1920, 1080), "Capture must render at native 1920x1080")
	await capture("welcome-final")
	visible_buttons(main.front.overlay)
	var game = root.get_node("GameState")
	game.player.completed_events = {}
	game.player.unlocked_chapters = ["prologue"]
	main.front.choose_chapter(0)
	await capture("chapters-final")
	visible_buttons(main.page)
	main.front.choose_chapter(1)
	await capture("locked-chapter")
	assert(find_button(main.page, "进入关卡").disabled)
	visible_buttons(main.page)
	main.queue_free()
	await create_timer(.2).timeout
	print("PASS native 1920x1080 welcome, chapters and locked chapter")
	quit(0)
