extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	if main.flow != "splash":
		push_error("Opening logo screen missing")
		quit(20)
		return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://auth-splash.png")
	var deadline := Time.get_ticks_msec() + 12000
	while main.flow != "auth" and Time.get_ticks_msec() < deadline: await process_frame
	if main.flow != "auth":
		push_error("Login screen unavailable: " + main.status.text)
		quit(21)
		return
	if main.navigation.visible or not main.network.access_token.is_empty():
		quit(22)
		return
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://auth-login.png")
	var username := "player_" + str(Time.get_ticks_usec())
	main.registering = true
	main._show_auth()
	main.auth_username.text = username
	main.auth_password.text = "test-password-123"
	main.auth_confirm.text = "different-password"
	await main._authenticate()
	if not main.network.access_token.is_empty():
		quit(23)
		return
	main.auth_confirm.text = "test-password-123"
	await main._authenticate()
	if main.flow != "map":
		push_error("Registration failed: " + main.status.text)
		quit(24)
		return
	var player_id: String = root.get_node("GameState").player.id
	var old_token: String = main.network.access_token
	await main._logout()
	main.auth_username.text = username
	main.auth_password.text = "incorrect-password"
	await main._authenticate()
	if main.flow != "auth" or not main.network.access_token.is_empty() or main.auth_password.text != "":
		quit(25)
		return
	main.auth_password.text = "test-password-123"
	await main._authenticate()
	if main.flow != "map" or root.get_node("GameState").player.id != player_id or main.network.access_token == old_token:
		quit(26)
		return
	print("PASS splash, registration confirmation, password login, invalid password, logout and stable identity")
	main.set_process(false)
	var game = root.get_node("GameState")
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://portrait-map.png")
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
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("user://portrait-trace.png")
				canvas.strokes[-1] = saved_last
				print("PASS failed stroke marked; other strokes preserved; single-stroke repair")
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
			main._process(10.0)
			if main.battle_elapsed != 0:
				push_error("Battle started before player was ready")
				quit(16)
				return
			main._begin_battle()
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
				await RenderingServer.frame_post_draw
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
	await create_timer(0.3).timeout
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
		await RenderingServer.frame_post_draw
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
	await main._logout()
	main.registering = true
	main._show_auth()
	main.auth_username.text = username + "_b"
	main.auth_password.text = "test-password-123"
	main.auth_confirm.text = "test-password-123"
	await main._authenticate()
	if game.player.id == player_id or game.player.completed_events.size() != 0 or not main.session_id.is_empty():
		push_error("Second account inherited first player progress")
		quit(27)
		return
	var response: Dictionary = await main.network.request_json("/api/v1/players/" + player_id)
	if not response.is_empty() or main.network.last_status != 403:
		quit(28)
		return
	await main._logout()
	main.network.access_token = old_token
	response = await main.network.request_json("/api/v1/auth/me")
	main._error(main.network.last_error)
	if not response.is_empty() or main.flow != "auth" or not main.network.access_token.is_empty():
		quit(29)
		return
	print("PASS account switch isolates progress, foreign save denied, revoked token returns to login")
	main.memory_audio.stop()
	main.memory_audio.stream = null
	await create_timer(0.1).timeout
	main.queue_free()
	await create_timer(0.2).timeout
	quit(0)
