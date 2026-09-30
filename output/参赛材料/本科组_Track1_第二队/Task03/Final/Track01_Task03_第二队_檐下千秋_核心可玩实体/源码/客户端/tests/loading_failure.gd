extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(99))
	ProjectSettings.set_setting("yanxia/server_url", "http://127.0.0.1:18099")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.busy or main.front.message.text == "正在准备古建记忆…": await process_frame
	# Loading starts after one frame; allow the HTTP failure to arrive.
	while not main.front.message.text.contains("暂时无法"): await process_frame
	assert(main.flow == "loading" and main.data.catalog.is_empty())
	assert(main.front.overlay.find_children("*", "Button", true, false).size() == 2)
	await main._connect_server()
	assert(main.front.overlay.find_children("*", "Button", true, false).size() == 2, "Retry duplicated actions")
	assert(main.front.message.text.contains("暂时无法"))
	main.queue_free()
	await create_timer(.2).timeout
	print("PASS actual refused connection and clean retry; no fake welcome or offline progress")
	quit(0)
