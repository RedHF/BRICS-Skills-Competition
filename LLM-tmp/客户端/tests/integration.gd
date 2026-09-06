extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.busy or main.data.catalog == null: await process_frame
	var game = root.get_node("GameState")
	var ids := [["prologue", "prologue_bridge"], ["temple", "temple_incense"], ["temple", "temple_guest"], ["temple", "temple_drum"]]
	for ids_pair in ids:
		main._open_event(ids_pair[0], ids_pair[1])
		await main._start_event()
		for step in main.current_event.puzzle.steps:
			await process_frame
			var payload := {"step_id": step.id}
			if step.kind == "trace":
				var canvas = main.trace_canvas
				await process_frame
				var hand_offset := Vector2(0, canvas.canvas_rect.size.y * 0.055)
				for stroke in step.trace.strokes:
					var press := InputEventMouseButton.new()
					press.button_index = MOUSE_BUTTON_LEFT
					press.pressed = true
					press.position = canvas.canvas_rect.position + Vector2(stroke[0][0], stroke[0][1]) * canvas.canvas_rect.size + hand_offset
					canvas._gui_input(press)
					for p in stroke.slice(1):
						var motion := InputEventMouseMotion.new()
						motion.position = canvas.canvas_rect.position + Vector2(p[0], p[1]) * canvas.canvas_rect.size + hand_offset
						canvas._gui_input(motion)
					var release := InputEventMouseButton.new()
					release.button_index = MOUSE_BUTTON_LEFT
					release.pressed = false
					release.position = canvas.canvas_rect.position + Vector2(stroke[-1][0], stroke[-1][1]) * canvas.canvas_rect.size + hand_offset
					canvas._gui_input(release)
				payload.strokes = canvas.strokes
			else:
				# Test answers are fixture data, not bundled in the release client.
				payload.answer = {"beam_left":"left","beam_center":"center","beam_right":"right","guest_word":"宁","drum_purify":"藻井"}[step.id]
			if step.id == "bridge_trace":
				var canvas = main.trace_canvas
				var saved_last: Array = canvas.strokes[-1].duplicate(true)
				canvas.strokes[-1][-1][0] = -1.0
				await main._submit_puzzle(payload)
				if main.trace_canvas != canvas or canvas.strokes.size() != step.trace.strokes.size():
					push_error("Rejected tracing was erased")
					quit(7)
					return
				for row in main.page.get_children():
					if row is HBoxContainer:
						for button in row.get_children():
							if button.text == "撤回上一笔": button.pressed.emit()
				if canvas.strokes.size() != step.trace.strokes.size() - 1:
					quit(8)
					return
				canvas.strokes.append(saved_last)
				print("PASS rejection preserves canvas and undo removes one stroke")
			await main._submit_puzzle(payload)
		if main.flow != "choice":
			push_error("Puzzle flow failed: " + main.status.text)
			quit(1)
			return
		if ids_pair[1] == "temple_drum":
			main._confirm_forget("yan_ping_an")
			if not main.confirmation.visible:
				quit(2)
				return
			main.confirmation.hide()
			await main._choose("forget", "yan_ping_an")
		else: await main._choose("keep", "")
		if main.current_event.has("battle"):
			for skill in main.current_event.battle.required_skills: main._battle_skill(skill)
			# Advance only the battle clock to keep integration verification fast.
			main._process(float(main.current_event.battle.duration_sec))
			await main._submit_battle()
		if main.flow != "settlement":
			push_error("Settlement flow failed: " + main.status.text)
			quit(3)
			return
		print("PASS event: ", ids_pair[1])
	if game.player.completed_events.size() != 4 or int(game.player.capacity) != 6 or game.player.memories.size() != 3:
		push_error("Incorrect progression: " + JSON.stringify(game.player))
		quit(4)
		return
	main._show_ledger()
	main._memory_detail("yan_ping_an")
	if main.memory_audio.playing:
		quit(5)
		return
	main._memory_detail("she_hui_chun")
	main._play_memory(329.63)
	if not main.memory_audio.playing:
		quit(6)
		return
	print("PASS memory choice, confirmation, source story, audio, capacity and ledger")
	print("TEST_PLAYER=", game.player.id)
	main.memory_audio.stop()
	main.memory_audio.stream = null
	await create_timer(0.1).timeout
	main.queue_free()
	await create_timer(0.2).timeout
	quit(0)
