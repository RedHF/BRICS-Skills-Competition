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
	canvas.drawing = false
	canvas.auto_complete()
	await process_frame
	if not shots.is_empty():
		get_root().get_texture().get_image().save_png(shots.path_join("opera-trace-after.png"))
	print("PASS 台字五笔方向与拓印渲染")
	quit()
