extends SceneTree

var main: Node
var shots := ""
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(shots.path_join(name + ".png"))

func show_step(chapter: String, event_id: String, index: int) -> void:
	main.chapter_id = chapter
	main.current_event = main.data.event(chapter, event_id)
	var accepted: Array = []
	for i in range(index): accepted.append("fixture")
	root.get_node("GameState").session = {"accepted_steps": accepted}
	main._show_puzzle()

func _run() -> void:
	create_timer(80).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	main._show_map()
	main.set_process(false)
	var ui_font = main.stats.get_theme_font("font")
	check(ui_font is SystemFont, "UI did not load the Chinese system font")
	check((ui_font as SystemFont).font_names[0] == "Noto Serif SC", "Unexpected Chinese font family")
	await capture("font-map")
	for name in ["ui_wood", "ui_page", "brush_touch"]:
		check(main.soundscape.sounds.has(name) and main.soundscape.sounds[name] != null, "Missing tactile sound: " + name)
	check(main.soundscape.trace_music.stream.resource_path.ends_with("trace_music.wav"), "Missing tracing score")
	var hover: Button = main.page.find_children("*", "Button", true, false)[0]
	hover.mouse_entered.emit()
	await create_timer(.24).timeout
	check(hover.scale.x > 1.02, "Button hover tween does not grow")
	hover.mouse_exited.emit()
	await create_timer(.24).timeout
	check(is_equal_approx(hover.scale.x, 1.0), "Button hover tween does not reset")
	for item in [["prologue", "prologue_bridge", 0], ["temple", "temple_guest", 1], ["temple", "temple_drum", 1], ["opera", "opera_opening", 1], ["tower", "tower_ascent", 0]]:
		show_step(item[0], item[1], item[2])
		await process_frame
		check(main.soundscape.scene_music == "trace", "Tracing score did not switch on")
		var trace = main.trace_canvas
		check(is_instance_valid(trace) and trace.glyph != null, "Missing authored brush glyph: " + item[1])
		check(trace.canvas_rect.has_area(), "No paper canvas")
		await capture("trace-" + item[1])
	show_step("prologue", "prologue_bridge", 0)
	await process_frame
	var trace = main.trace_canvas
	var first: Array = trace.spec.strokes[0][0]
	var start: Vector2 = trace.canvas_rect.position + Vector2((float(first[0]) - trace.view_x) * trace.characters, float(first[1])) * trace.canvas_rect.size
	var pen := InputEventMouseMotion.new()
	pen.position = start
	trace._gui_input(pen)
	check(trace.brush_visible, "Painted cursor does not follow pointer")
	await capture("brush-hover")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start
	trace._gui_input(down)
	pen.position = start + Vector2(40, 0)
	trace._gui_input(pen)
	check(trace.strokes[0].size() > 1, "Brush drag lost sample path")
	await capture("brush-drawing")
	for item in [["temple", "temple_incense", 0], ["opera", "opera_master", 0], ["opera", "opera_master", 1], ["archway", "archway_form", 1]]:
		show_step(item[0], item[1], item[2])
		await process_frame
		check(main.soundscape.scene_music == "theme", "Tracing score did not switch off")
		check(is_instance_valid(main.join_canvas) and main.join_canvas.options.size() > 0, "Join asset missing")
		await capture("join-" + item[1] + "-" + str(item[2]))
	var join = main.join_canvas
	var chosen := [""]
	join.placed.connect(func(answer: String): chosen[0] = answer)
	main.busy = true
	var grab := InputEventMouseButton.new()
	grab.button_index = MOUSE_BUTTON_LEFT
	grab.pressed = true
	grab.position = join.piece
	join._gui_input(grab)
	check(join.dragging, "Join piece cannot be grabbed")
	var target: Vector2 = join._socket_center(0)
	var drag := InputEventMouseMotion.new()
	drag.position = target
	join._gui_input(drag)
	grab.pressed = false
	grab.position = target
	join._gui_input(grab)
	check(join.snapped and chosen[0] == join.options[0], "Join piece cannot snap to authored choice")
	main.busy = false
	await capture("join-snapped")
	for item in [["archway", "archway_craftsman", 0], ["tower", "tower_ascent", 1]]:
		show_step(item[0], item[1], item[2])
		await process_frame
		check(is_instance_valid(main.skill_scene), "Skill scene missing")
		await capture("skill-" + item[1])
	for item in [["archway", "archway_form", 0], ["opera", "opera_opening", 0]]:
		show_step(item[0], item[1], item[2])
		await capture("pattern-" + item[1])
	await main._fade_to_dark()
	check(main.transition_veil.color.a > .9, "Level transition did not darken")
	await capture("transition-dark")
	main._fade_from_dark()
	await create_timer(.45).timeout
	check(main.transition_veil.color.a < .01, "Level transition did not brighten")
	print("PASS generated puzzle art checks=", checks)
	main.queue_free()
	await create_timer(.3).timeout
	quit(0)
