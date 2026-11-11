extends SceneTree
var main: Node
var surface: Viewport

func _check(condition: bool, message: String = "Demo runtime check failed") -> void:
	if condition: return
	push_error(message)
	quit(98)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("YANXIA_EXPECT_CHECK_FAILURE") == "1":
		_check(false,"EXPECTED_RELEASE_CHECK_FAILURE")
		return
	create_timer(70).timeout.connect(func(): push_error("Demo check timed out"); quit(99))
	surface = root
	if DisplayServer.get_name() != "headless":
		var render := SubViewport.new()
		render.size = Vector2i(1920,1080)
		render.size_2d_override = Vector2i(1280,720)
		render.size_2d_override_stretch = true
		render.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		render.gui_embed_subwindows = true
		root.add_child(render)
		surface = render
	main = load("res://scenes/main.tscn").instantiate()
	surface.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	_check(not OS.has_feature("editor") and main._is_echo())
	_check(main.server_pid > 0 and main.network.base_url == "http://127.0.0.1:8092")
	_check(main.profile_root.begins_with("user://demo/"+main.demo_mode+"/"))
	_check(int(root.get_node("GameState").player.capacity) == 3)
	var mode := str(main.demo_mode)
	await _capture(mode+"-welcome")
	_check_buttons_fit(main.front.overlay)
	if surface is SubViewport:
		surface.size = Vector2i(960,540)
		surface.size_2d_override = Vector2i(960,540)
		for i in range(5): await process_frame
		_check_buttons_fit(main.front.overlay)
		await _capture(mode+"-welcome-small")
		surface.size = Vector2i(1920,1080)
		surface.size_2d_override = Vector2i(1280,720)
		for i in range(5): await process_frame
	await _press("开始接梁片段" if mode == "repair" else "开始取舍片段",main.front.overlay)
	if mode == "repair":
		_check(main.flow == "puzzle" and main.current_event.id == "temple_incense")
		var stage: Control = main.echo_stage
		var canvas: Control = stage.canvas
		_check(stage.observed() and not stage.done("hall_support"))
		_check(root.get_node("GameState").player.completed_events.size() == 1)
		await _capture("repair-start")
		await _press("选用斗拱")
		await _click(canvas,canvas.support_rect.get_center())
		await _click(canvas,canvas.piece_rects[1].get_center())
		await _click(canvas,canvas.slot_rects["SLOT-R"].get_center())
		await _click(canvas,canvas.piece_rects[0].get_center())
		await _press("将所选木件转半圈 · R")
		await _click(canvas,canvas.slot_rects["SLOT-L"].get_center())
		await _click(canvas,canvas.piece_rects[2].get_center())
		await _click(canvas,canvas.slot_rects["SLOT-C"].get_center())
		await _press("撤下临撑")
		_check(stage.complete)
		await _capture("repair-complete")
		await main._resume()
		await _press("收入心舍")
		_check(main.echo_journey.held("she_cheng_xiang"))
		await _capture("repair-living-response")
		await main._resume()
		_check(main.flow == "settlement")
	else:
		_check(mode == "choice" and main.flow == "choice" and main.current_event.id == "temple_drum")
		_check(root.get_node("GameState").player.memories.size() == 3)
		_check(root.get_node("GameState").player.completed_events.size() == 3)
		_check(not root.get_node("GameState").session.choice_done)
		await _capture("choice-start")
		await _press("看与听 · 社·回春")
		_check(main.echo_journey.preview.living)
		await _press("返回取舍")
		_check(not root.get_node("GameState").session.choice_done,"Viewing changed the choice")
		await _press("保留现有回声 · 只归档「社·回春」…")
		_check(main.archive_prompt.visible)
		main.archive_prompt.accept()
		await _idle()
		_check(not main.echo_journey.held("she_hui_chun"))
		await main._resume()
		_check(main.flow == "response")
		await _press("敲一下鼓")
		_check(main.echo_journey.preview.physical_audio.playing)
		_check(not main.echo_journey.preview.last_child_echo and not main.event_audio.playing)
		await _capture("choice-physical-drum")
		await main._resume()
		_check(main.flow == "settlement" and int(root.get_node("GameState").player.capacity) == 4)
	print("PASS exported demo: "+mode+" starts from the embedded checkpoint and remains playable in its own profile")
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func _idle() -> void:
	await process_frame
	while main.busy: await process_frame
	await process_frame

func _press(title: String, node: Node = null) -> void:
	var parent: Node = main.page if node == null else node
	var button := _button(parent,title)
	_check(button != null,"Missing demo button: "+title)
	button.pressed.emit()
	await _idle()

func _check_buttons_fit(node: Control) -> void:
	var bounds := Rect2(Vector2.ZERO,node.size)
	for button in node.find_children("*","Button",true,false):
		if button.is_visible_in_tree():
			if not bounds.encloses(button.get_global_rect()):
				print("Clipped layout bounds=",bounds," button=",button.get_global_rect()," overlay=",node.get_global_transform_with_canvas()," viewport=",surface.size)
			_check(bounds.encloses(button.get_global_rect()),"Welcome button is clipped: "+str(button.text))

func _button(node: Node, title: String) -> Button:
	if node is Button and node.text == title: return node
	for child in node.get_children():
		var found := _button(child,title)
		if found != null: return found
	return null

func _click(canvas: Control, point: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	canvas._gui_input(down)
	await _idle()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	canvas._gui_input(up)
	await _idle()

func _capture(name: String) -> void:
	var directory := OS.get_environment("YANXIA_REVIEW_SHOTS")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	if main.transition_tween != null and main.transition_tween.is_running(): await main.transition_tween.finished
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(directory)
	RenderingServer.force_draw()
	_check(surface.get_texture().get_image().save_png(directory.path_join(name+".png")) == OK)
