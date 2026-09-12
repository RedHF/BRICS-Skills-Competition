extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ProjectSettings.set_setting("yanxia/server_url", "http://127.0.0.1:8097")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	if main.flow != "splash":
		push_error("Opening logo screen missing")
		quit(20)
		return
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("user://auth-splash.png")
	var deadline := Time.get_ticks_msec() + 12000
	while (main.busy or root.get_node("GameState").player.is_empty()) and Time.get_ticks_msec() < deadline: await process_frame
	assert(main.flow == "map" and main.navigation.visible, "Direct play unavailable: " + main.status.text)
	var player_id: String = root.get_node("GameState").player.id
	await main._load_game()
	assert(root.get_node("GameState").player.id == player_id, "Local save identity changed")
	print("PASS direct play and stable local save")
	main.set_process(false)
	var game = root.get_node("GameState")
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("user://portrait-map.png")
	var ids := [["prologue", "prologue_bridge"], ["temple", "temple_incense"], ["temple", "temple_guest"], ["temple", "temple_drum"]]
	for ids_pair in ids:
		main._open_event(ids_pair[0], ids_pair[1])
		assert(main.flow == "dialogue" and main.dialogue_lines.size() == 6)
		main._advance_dialogue()
		assert(main.dialogue_index == 1)
		main._show_map()
		main._open_event(ids_pair[0], ids_pair[1])
		assert(main.dialogue_index == 1, "Dialogue cursor lost")
		main._finish_dialogue()
		assert(main.flow == "intro")
		await process_frame
		var scene = main.scene_view
		var initial_position: Vector2 = scene.player
		Input.action_press("move_right")
		scene._process(0.2)
		Input.action_release("move_right")
		assert(scene.player.x > initial_position.x, "Directional movement failed")
		scene.player = Vector2(0.5, 0.5)
		Input.action_press("move_up")
		scene._process(0.4)
		Input.action_release("move_up")
		assert(scene.player.y < 0.5 and scene.player.y >= 0.16, "Exploration bounds still block the upper scene")
		var investigate := InputEventMouseButton.new()
		investigate.button_index = MOUSE_BUTTON_LEFT
		investigate.pressed = true
		for investigation in scene.investigations:
			investigate.position = scene.size * Vector2(float(investigation.position[0]), float(investigation.position[1]))
			scene._gui_input(investigate)
			scene._process(1.0)
			await process_frame
		assert(scene.discovered.size() == scene.investigations.size(), "Not all investigation points were discoverable")
		assert(main.event_audio.playing, "Investigation did not play event whisper")
		for erosion in [0,39,40,69,70,99,100]:
			main._refresh_stats(erosion)
			assert(scene.erosion == erosion)
			assert(is_equal_approx(AudioServer.get_bus_volume_db(main.echo_bus), -float(erosion)*.12))
			assert(AudioServer.is_bus_effect_enabled(main.echo_bus,0) == (erosion >= 40))
			if DisplayServer.get_name() != "headless" and ids_pair[1] == "prologue_bridge" and erosion in [0,40,70]:
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png("user://erosion-%d.png" % erosion)
		main._refresh_stats()
		await main._start_event()
		if ids_pair[1] == "prologue_bridge":
			var current_id: String = main.session_id
			await main._load_game()
			assert(main.session_id == current_id, "Reopen lost current event")
			await main._resume()
			for attempt in range(3):
				await main.network.request_json("/api/v1/sessions/%s/puzzle" % current_id, HTTPClient.METHOD_POST, {"step_id":"out_of_order","answer":"wrong"})
			await main._resume()
			assert(main.flow == "failed" and int(game.player.erosion) == 30)
			await main._rewind()
			assert(main.flow == "puzzle" and int(game.player.erosion) == 0 and int(game.player.ink_marks) == 0)
			print("PASS reconnect and tutorial free rewind restore checkpoint")
		for step in main.current_event.puzzle.steps:
			await process_frame
			var payload := {"step_id": step.id}
			if step.kind == "trace":
				var canvas = main.trace_canvas
				await process_frame
				var hand_offset := Vector2(0, canvas.canvas_rect.size.y * 0.055)
				for stroke_index in range(step.trace.strokes.size()):
					canvas.select_stroke(stroke_index)
					await process_frame
					var stroke: Array = step.trace.strokes[stroke_index]
					var press := InputEventMouseButton.new()
					press.button_index = MOUSE_BUTTON_LEFT
					press.pressed = true
					press.position = canvas.canvas_rect.position + Vector2((stroke[0][0] - canvas.view_x) * canvas.characters, stroke[0][1]) * canvas.canvas_rect.size + hand_offset
					canvas._gui_input(press)
					for p in stroke.slice(1):
						var motion := InputEventMouseMotion.new()
						motion.position = canvas.canvas_rect.position + Vector2((p[0] - canvas.view_x) * canvas.characters, p[1]) * canvas.canvas_rect.size + hand_offset
						canvas._gui_input(motion)
					var release := InputEventMouseButton.new()
					release.button_index = MOUSE_BUTTON_LEFT
					release.pressed = false
					release.position = canvas.canvas_rect.position + Vector2((stroke[-1][0] - canvas.view_x) * canvas.characters, stroke[-1][1]) * canvas.canvas_rect.size + hand_offset
					canvas._gui_input(release)
				payload.strokes = canvas.strokes
			else:
				# Test answers are fixture data, not bundled in the release client.
				payload.answer = {"beam_left":"left","beam_center":"center","beam_right":"right","guest_word":"宁","drum_purify":"藻井"}[step.id]
			if step.id == "bridge_trace":
				var canvas = main.trace_canvas
				var draft: Array = canvas.strokes.duplicate(true)
				main._show_memories()
				main._show_settings()
				await main._resume()
				assert(main.trace_canvas == canvas and canvas.strokes == draft, "Heart room lost tracing draft")
				var saved_last: Array = canvas.strokes[-1].duplicate(true)
				canvas.strokes[-1][-1][0] = -1.0
				await main._submit_puzzle(payload)
				if main.trace_canvas != canvas or canvas.strokes.size() != step.trace.strokes.size():
					push_error("Rejected tracing was erased")
					quit(7)
					return
				if canvas.failed != [step.trace.strokes.size() - 1]:
					push_error("Wrong failed stroke indexes: " + str(canvas.failed))
					quit(8)
					return
				await process_frame
				if DisplayServer.get_name() != "headless":
					RenderingServer.force_draw()
					root.get_texture().get_image().save_png("user://portrait-trace.png")
				canvas.strokes[-1] = saved_last
				print("PASS failed stroke marked; other strokes preserved; single-stroke repair")
			if step.kind == "join":
				var canvas = main.join_canvas
				var slot: int = step.options.find(payload.answer)
				var press := InputEventMouseButton.new()
				press.button_index = MOUSE_BUTTON_LEFT
				press.pressed = true
				press.position = canvas.piece
				canvas._gui_input(press)
				var drag := InputEventMouseMotion.new()
				drag.position = Vector2(canvas.size.x * (slot+.5) / step.options.size(),65)
				canvas._gui_input(drag)
				press.pressed = false
				press.position = drag.position
				canvas._gui_input(press)
				assert(canvas.snapped, "Join did not snap")
				while main.busy: await process_frame
			else: await main._submit_puzzle(payload)
		if main.flow != "choice":
			push_error("Puzzle flow failed: " + main.status.text)
			quit(1)
			return
		if ids_pair[1] == "temple_drum":
			var choice_page = main.page
			main._compare_memories("yan_ping_an", "she_hui_chun")
			assert(main.flow == "compare" and is_instance_valid(main.paused_page))
			await main._resume()
			assert(main.flow == "choice" and main.page == choice_page)
			main._confirm_forget("yan_ping_an")
			if not main.confirmation.visible:
				quit(2)
				return
			main.confirmation.hide()
			await main._choose("forget", "yan_ping_an")
		else: await main._choose("keep", "")
		if main.current_event.has("battle"):
			main._process(10.0)
			if main.battle_elapsed != 0:
				push_error("Battle started before player was ready")
				quit(16)
				return
			main._begin_battle()
			var active_arena = main.arena
			main._show_memories()
			main._process(100.0)
			assert(main.battle_elapsed == 0, "Paused battle consumed time")
			await main._resume()
			assert(main.arena == active_arena and main.battle_running, "Battle scene reset on resume")
			if ids_pair[1] == "temple_incense":
				main._process(2.2)
				Input.action_press("move_right")
				main.arena._process(0.1)
				Input.action_release("move_right")
				assert(main.battle_actions[-1].skill == "闪身" and main.arena.shield == 1, "Movement did not trigger dodge")
				main._process(0.8)
				assert(main.battle_hits == 0 and main.arena.shield == 0, "Dodge did not avoid the telegraphed attack")
				print("PASS moving battle dodge")
			if ids_pair[1] == "temple_drum":
				main._process(3.0)
				if main.battle_hits != 1:
					push_error("Enemy failed to attack")
					quit(9)
					return
			for skill in main.current_event.battle.required_skills: main._battle_skill(skill)
			if main.battle_hits != 0:
				push_error("Purification did not heal")
				quit(10)
				return
			if ids_pair[1] == "prologue_bridge":
				main._process(3.0)
				if main.arena.shield != 1 or main.battle_hits != 0:
					push_error("Shield did not block enemy attack")
					quit(11)
					return
			main._battle_skill("挥墨")
			var hp: int = main.arena.hp
			main._battle_skill("挥墨")
			if main.arena.hp != hp:
				push_error("Cooldown did not stop repeated attack")
				quit(12)
				return
			await process_frame
			await process_frame
			if DisplayServer.get_name() != "headless":
				print("CAPTURE battle: ", ids_pair[1])
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png("user://portrait-battle-" + ids_pair[1] + ".png")
			while not main.battle_finished:
				main._process(0.501)
				main._battle_skill("挥墨")
			print("PASS actual enemy damage, shield, healing, cooldown and victory")
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
	main._open_event("prologue", "prologue_bridge")
	main._finish_dialogue()
	assert(main.scene_view.forgotten, "Forgotten building regained its color")
	main._show_ledger()
	main._memory_detail("yan_ping_an")
	if main.memory_audio.playing:
		quit(5)
		return
	main._memory_detail("she_hui_chun")
	main._play_memory(main.data.memory("she_hui_chun").echo_audio)
	if not main.memory_audio.playing:
		quit(6)
		return
	var audio_deadline := Time.get_ticks_msec() + 1500
	while main.memory_audio.get_playback_position() < 0.1 and Time.get_ticks_msec() < audio_deadline:
		await process_frame
	if main.memory_audio.get_playback_position() < 0.1 or main.memory_audio.stream.get_length() < 2:
		push_error("Narration did not progress")
		quit(13)
		return
	main._play_memory(main.data.memory("she_hui_chun").echo_audio)
	if not main.memory_audio.stream_paused:
		quit(14)
		return
	main._process(0.0)
	await process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("user://portrait-echo.png")
	main._play_memory(main.data.memory("she_hui_chun").echo_audio)
	if main.memory_audio.stream_paused:
		quit(15)
		return
	print("PASS narration duration, playback progress, pause/resume, memory source, capacity and ledger")
	print("TEST_PLAYER=", game.player.id)
	main._start_battle()
	main._begin_battle()
	main._process(float(main.current_event.battle.duration_sec))
	if not main.battle_finished or main.battle_wave != 0 or main.battle_hits != int(main.current_event.battle.max_hits_taken) + 1:
		push_error("Idle player did not lose to actual enemy attacks")
		quit(17)
		return
	print("PASS idle defeat")
	main._show_journal()
	assert(main.flow == "journal")
	main._replay_story("prologue", "prologue_bridge")
	assert(main.flow == "dialogue" and main.dialogue_lines.size() >= 7)
	main._finish_dialogue()
	assert(main.flow == "journal")
	await main._load_game()
	assert(game.player.id == player_id and game.player.completed_events.size() == 4)
	print("PASS journal, dialogue replay and persistent local progress")
	main.memory_audio.stop()
	main.memory_audio.stream = null
	await create_timer(0.1).timeout
	main.queue_free()
	await create_timer(0.2).timeout
	quit(0)
