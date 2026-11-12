extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../服务端/content/chapters.json")))
	var trace: Dictionary = {}
	for chapter in catalog.chapters:
		for event in chapter.events:
			for step in event.puzzle.get("steps", []):
				if step.id == "opera_trace": trace = step.trace
	assert(trace.glyph == "台")
	assert(trace.strokes.size() == 5)
	assert(trace.strokes[0][3][0] > trace.strokes[0][2][0])
	assert(trace.strokes[1][1][0] > trace.strokes[1][0][0])
	assert(trace.strokes[1][-1] == trace.strokes[0][-1])
	var canvas := Control.new()
	canvas.set_script(load("res://scripts/trace_canvas.gd"))
	canvas.spec = trace
	canvas.step_id = "opera_trace"
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	await process_frame
	await process_frame
	for i in range(trace.strokes.size()):
		canvas.strokes[i] = canvas._guide_samples(i)
		assert(canvas._stroke_reached_end(i), "Complete guide must be accepted locally")
		canvas.strokes[i] = []
	var shots := OS.get_environment("YANXIA_REVIEW_SHOTS")
	if not shots.is_empty():
		DirAccess.make_dir_recursive_absolute(shots)
		get_root().get_texture().get_image().save_png(shots.path_join("opera-trace-before.png"))
	canvas.drawing = true
	canvas.strokes[0] = [trace.strokes[0][0], trace.strokes[0][1]]
	canvas.queue_redraw()
	await process_frame
	if not shots.is_empty():
		get_root().get_texture().get_image().save_png(shots.path_join("opera-trace-partial.png"))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	var end: Array = trace.strokes[0][1]
	release.position = canvas.canvas_rect.position + Vector2((float(end[0]) - canvas.view_x) * canvas.characters, float(end[1])) * canvas.canvas_rect.size
	canvas._gui_input(release)
	assert(canvas.strokes[0].is_empty() and canvas.active == 0 and canvas.interrupted, "Interrupted stroke must restore its guide")
	await process_frame
	if not shots.is_empty():
		get_root().get_texture().get_image().save_png(shots.path_join("opera-trace-interrupted.png"))
	canvas.select_stroke(3)
	canvas.strokes[3] = [[.69, .65], [.69, .79]]
	assert(not canvas._stroke_reached_end(3), "A missing top edge must not count as a complete stroke")
	var skipped_corner: Array = []
	var beginning := Vector2(float(trace.strokes[3][0][0]), float(trace.strokes[3][0][1]))
	var ending := Vector2(float(trace.strokes[3][-1][0]), float(trace.strokes[3][-1][1]))
	for i in range(21):
		var point := beginning.lerp(ending, float(i) / 20.0)
		skipped_corner.append([point.x, point.y])
	canvas.strokes[3] = skipped_corner
	assert(not canvas._stroke_reached_end(3), "A shortcut across a bend must not count as a complete stroke")
	canvas.strokes[3] = []
	canvas.drawing = true
	canvas.strokes[3] = [trace.strokes[3][0], trace.strokes[3][1]]
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.position = canvas.size + Vector2(30, 30)
	canvas._input(outside)
	assert(canvas.strokes[3].is_empty() and canvas.interrupted and canvas.active == 3, "Releasing outside the canvas must restore the guide")
	canvas.auto_complete()
	await process_frame
	if not shots.is_empty():
		get_root().get_texture().get_image().save_png(shots.path_join("opera-trace-after.png"))
	print("PASS 台字五笔方向与拓印渲染")
	quit()
