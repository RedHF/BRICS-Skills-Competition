extends SceneTree

var main
var shots := ""

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(shots.path_join(name + ".png"))

func find_button(parent: Node, text: String) -> Button:
	for child in parent.find_children("*", "Button", true, false):
		if child.text.contains(text): return child
	assert(false, "Missing button: " + text)
	return null

func visible_buttons(parent: Node) -> void:
	for button in parent.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			assert(root.get_visible_rect().encloses(button.get_global_rect()), "Clipped action: " + button.text)

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	assert(main.flow == "loading")
	await capture("01-loading")
	while main.flow != "welcome": await process_frame
	await capture("02-welcome")
	visible_buttons(main.front.overlay)
	find_button(main.front.overlay, "选择关卡").pressed.emit()
	await capture("03-chapters")
	assert(main.flow == "map")
	visible_buttons(main.page)
	main.front.choose_chapter(1)
	await capture("04-locked-chapter")
	assert(find_button(main.page, "○").disabled, "Locked chapter became playable")
	main.front.choose_chapter(0)
	find_button(main.page, "○").pressed.emit()
	await capture("05-dialogue")
	main._finish_dialogue()
	await capture("06-investigation")
	assert(main.scene_view.size.x > 700)
	assert(root.get_visible_rect().encloses(main.scene_view.get_global_rect()))
	main.scene_view._discover(0)
	main._show_map()
	assert(is_instance_valid(main.paused_page))
	main._show_welcome()
	find_button(main.front.overlay, "继续旅程").pressed.emit()
	await capture("07-resumed-investigation")
	assert(main.flow == "intro" and main.scene_view.discovered.size() == 1, "Resume lost investigation")
	for index in [1, 2]: main.scene_view._discover(index)
	await main._start_event()
	await capture("08-puzzle")
	assert(main.flow == "puzzle")
	var saved_id: String = main.session_id
	main._show_map()
	main._show_welcome()
	find_button(main.front.overlay, "继续旅程").pressed.emit()
	await process_frame
	assert(main.flow == "puzzle" and main.session_id == saved_id)
	# Battle fixture changes only in-memory UI. It sends no battle requests.
	main._start_battle()
	await capture("09-battle")
	visible_buttons(main.battle_dock)
	assert(root.get_visible_rect().encloses(main.arena.get_global_rect()))
	for dimensions in [Vector2i(960,540), Vector2i(1600,900), Vector2i(1600,720)]:
		DisplayServer.window_set_size(dimensions)
		await create_timer(.2).timeout
		visible_buttons(main.battle_dock)
		assert(root.get_visible_rect().encloses(main.arena.get_global_rect()))
		await capture("battle-%dx%d" % [dimensions.x, dimensions.y])
	main._show_map()
	await capture("10-map-resized")
	visible_buttons(main.page)
	main._show_settings()
	await capture("11-settings")
	main.queue_free()
	await create_timer(.3).timeout
	print("PASS loading/welcome/chapter locks, real session start, paused resume and landscape bounds at 4 sizes")
	quit(0)
