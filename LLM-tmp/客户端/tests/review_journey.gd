extends SceneTree

var main
var game
var shots := ""

func _initialize() -> void:
	_run.call_deferred()

func click(button: Button) -> void:
	assert(is_instance_valid(button) and not button.disabled)
	await process_frame
	await process_frame
	if main.scroll.is_ancestor_of(button): main.scroll.ensure_control_visible(button)
	await process_frame
	await process_frame
	var point := button.get_global_rect().get_center()
	assert(button.get_viewport().get_visible_rect().has_point(point), "Button outside viewport: " + button.text)
	if button.get_viewport() != root:
		point += Vector2(button.get_viewport().position)
	await tap(point)

func tap(point: Vector2, viewport: Viewport = root) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	viewport.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)
	await process_frame
	while main.busy: await process_frame

func button(prefix: String, parent: Node = null) -> Button:
	if parent == null: parent = main.page
	for child in parent.find_children("*", "Button", true, false):
		if child.text.begins_with(prefix): return child
	assert(false, "Missing button " + prefix)
	return null

func capture(name: String) -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(shots.path_join(name + ".png"))

func key(code: int, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func drag_path(points: Array) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = points[0]
	root.push_input(event, true)
	await process_frame
	for point in points.slice(1):
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
	event = event.duplicate()
	event.pressed = false
	event.position = points[-1]
	root.push_input(event, true)
	await process_frame
	while main.busy: await process_frame

func _run() -> void:
	root.gui_embed_subwindows = true
	# Assertions stop a coroutine; a deadline also makes failures exit nonzero in CI.
	create_timer(300).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	if shots.is_empty(): shots = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	game = root.get_node("GameState")
	while main.flow != "map" or main.busy: await process_frame
	main.set_process(false)
	main.story_progress = ConfigFile.new()
	assert(main.voice_index.cues.size() == 184)
	for path in main.voice_index.cues.values():
		assert(ResourceLoader.exists(path), "Missing packaged voice: " + path)
		assert(load(path).get_length() > 0)
	assert(main.voice_index.missing.size() == 1 and main.voice_index.missing[0].text == "……")
	var fixture_path := ProjectSettings.globalize_path("res://../服务端/content/chapters.json")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	await capture("map")
	for chapter in fixture.chapters:
		for event in chapter.events:
			if game.player.completed_events.has(chapter.id + ":" + event.id): continue
			if not main.session_id.is_empty():
				await main._resume()
			else:
				main._open_event(chapter.id, event.id)
				await create_timer(.2).timeout
				assert(main.event_audio.playing and main.event_audio.get_playback_position() > 0, "Dialogue has no voice")
				main._advance_dialogue()
				assert(main.event_audio.stream.resource_path.ends_with(event.id + "_dialogue_02.wav"))
				await click(main.dialogue_stage.skip)
				assert(not main.event_audio.playing and main.voice_queue.is_empty(), "Skipped dialogue kept playing")
				for point in main.scene_view.investigations:
					await tap(main.scene_view.global_position + main.scene_view.size * Vector2(point.position[0], point.position[1]))
					main.scene_view._process(2.0)
				assert(main.scene_view.discovered.size() == 3)
				if event.id in ["prologue_bridge","temple_incense","temple_guest","temple_drum"]: await capture(event.id + "-investigation")
				await click(button("三处调查完成"))
			for step in event.puzzle.steps:
				if game.session.accepted_steps.has(step.id): continue
				await process_frame
				if step.kind == "skill":
					await click(button(step.answer))
					main.scroll.ensure_control_visible(main.skill_scene)
					await process_frame
					await capture(step.id)
					await tap(main.skill_scene.global_position + main.skill_scene.size * main.skill_scene.anchors[step.target])
				elif step.id in ["opera_role", "archway_grade"]:
					await capture(step.id)
					var option: Button
					for child in main.page.find_children("*", "Button",true,false):
						if child.get("motif") == step.answer: option = child
					await click(option)
				elif step.kind == "trace":
					# Drive the real drawing canvas through viewport mouse events.
					for index in range(step.trace.strokes.size()):
						await click(button("%02d" % [index+1],main.stroke_buttons))
						assert(main.trace_canvas.active == index)
						main.scroll.ensure_control_visible(main.trace_canvas)
						await process_frame
						await process_frame
						var canvas = main.trace_canvas
						var samples: Array = []
						for point in step.trace.strokes[index]:
							samples.append(canvas.global_position + canvas.canvas_rect.position + Vector2((point[0] - canvas.view_x) * canvas.characters, point[1]) * canvas.canvas_rect.size)
						for point in samples:
							assert(main.scroll.get_global_rect().has_point(point), "Trace path outside visible scroll area")
						await drag_path(samples)
						assert(not canvas.strokes[index].is_empty(), "Viewport drawing did not reach canvas")
					await click(button("核对拓印"))
					if not game.session.accepted_steps.has(step.id):
						print("TRACE_REJECTED ", step.id, " failed=", main.trace_canvas.failed)
						var diagnostic := FileAccess.open(shots.path_join("rejected-" + step.id + ".json"), FileAccess.WRITE)
						diagnostic.store_string(JSON.stringify(main.trace_canvas.strokes))
						await capture("rejected-" + step.id)
				elif step.kind == "join":
					main.scroll.ensure_control_visible(main.join_canvas)
					await process_frame
					await process_frame
					var canvas = main.join_canvas
					var slot: int = step.options.find(step.answer)
					await drag_path([canvas.global_position + canvas.piece, canvas.global_position + Vector2(canvas.size.x * (slot+.5) / step.options.size(),65)])
				elif step.kind == "narrative":
					await click(button(step.options[0]))
				else:
					await click(button(step.answer))
			assert(main.flow == "choice",main.status.text)
			if game.player.memories.size() >= int(game.player.capacity):
				await click(button("抹去"))
				assert(main.confirmation.visible)
				await capture("confirmation-before")
				await click(main.confirmation.get_cancel_button())
				await capture("confirmation-after")
				assert(not main.confirmation.visible and main.flow == "choice")
				await click(button("抹去"))
				await click(main.confirmation.get_ok_button())
			else: await click(button("拓印这道墨灵"))
			if event.has("battle"):
				await capture(event.id + "-battle-ready")
				await key(KEY_1)
				assert(main.battle_actions.is_empty(), "Keyboard bypassed ready screen")
				await click(main.battle_start)
				await key(KEY_4, true)
				assert(main.battle_actions.is_empty(), "Key repeat fired a skill")
				if event.id == "opera_opening": assert(main._learned_skills().size() == 3)
				await key(KEY_KP_5)
				assert(main.battle_actions.size() == 1 and main.battle_actions[0].skill == "闪身")
				await key(KEY_5)
				assert(main.battle_actions.size() == 1, "Cooldown bypassed with another key")
				if not main.battle_skills.has("飞檐"):
					await key(KEY_4)
					assert(main.battle_actions.size() == 1, "Unlearned skill fired")
				# Every skill must be visible simultaneously without scrolling.
				for skill in main.battle_buttons:
					assert(root.get_visible_rect().encloses(main.battle_buttons[skill].get_global_rect()),"Hidden battle skill")
				var boss_captured := false
				while not main.battle_finished:
					for skill in ["斗拱","藻井","飞檐","挥墨"]:
						if main.battle_buttons.has(skill) and not main.battle_buttons[skill].disabled:
							await key(KEY_1 + main.BATTLE_KEYS.find(skill))
					if main._boss_wave() and not boss_captured:
						boss_captured = true
						assert(main.arena.max_hp == 620 and main._attack_interval() == 2400)
						await capture("miniboss-active")
					if not main.battle_finished: main._process(.75)
				assert(main.arena.defeated,"Battle failed: " + event.id)
				if event.id == "opera_opening": assert(boss_captured)
				print("PACE ",event.id," ",main.battle_elapsed)
				await click(button("结算白蚀战斗",main.battle_dock))
				assert(int(game.session.battle_hits) == main.battle_hits and int(game.session.battle_waves) == main.battle_wave, "Client/server battle values differ: " + event.id)
			assert(main.flow == "settlement",main.status.text)
			var whisper: String = event.story.get("first_clear_whisper","")
			if not whisper.is_empty():
				var found := false
				for label in main.page.find_children("*","Label",true,false):
					if label.text == "戏楼："+whisper: found = true
				assert(found,"First-clear whisper is missing")
				main._settlement(game.player.completed_events[chapter.id+":"+event.id])
				for label in main.page.find_children("*","Label",true,false):
					assert(label.text != "戏楼："+whisper,"Whisper repeated on settlement revisit")
			await capture(event.id+"-settlement")
			await click(button("继续古建旅程"))
			print("PASS UI journey ",event.id)
	assert(game.player.completed_events.size() == 10)
	main._show_journal()
	await capture("journal")
	main._show_memories()
	await capture("heart-room")
	print("PASS all ten UI tasks, 184 voices, dialogue cancellation, 1-5/numpad shortcuts, cooldown, third-skill boss and server settlement")
	main.queue_free()
	await create_timer(0.3).timeout
	quit(0)
