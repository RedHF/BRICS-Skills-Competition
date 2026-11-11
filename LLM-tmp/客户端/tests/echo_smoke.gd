extends SceneTree

var main: Node
var archive := "she_ning_an"
var capture_view: Viewport
var walk_checked := false

func _check(condition: bool, message: String = "Echo runtime check failed") -> void:
	# Export-release removes GDScript assert calls and their arguments. Keep
	# checks (and any inspected operations) executable in the real EXE.
	if condition: return
	push_error(message)
	quit(98)

func _initialize() -> void:
	_run.call_deferred()

func _check_front_buttons() -> void:
	var bounds := Rect2(Vector2.ZERO,main.front.overlay.size)
	for button in main.front.overlay.find_children("*","Button",true,false):
		if button.is_visible_in_tree():
			_check(bounds.encloses(button.get_global_rect()),"Welcome button is clipped: "+str(button.text))

func _run() -> void:
	if OS.get_environment("YANXIA_EXPECT_CHECK_FAILURE") == "1":
		_check(false,"EXPECTED_RELEASE_CHECK_FAILURE")
		return
	if not OS.get_environment("YANXIA_REVIEW_ARCHIVE").is_empty(): archive = OS.get_environment("YANXIA_REVIEW_ARCHIVE")
	create_timer(150).timeout.connect(func(): push_error("Echo smoke timed out"); quit(99))
	capture_view = root
	var requested := OS.get_environment("YANXIA_CAPTURE_SIZE").split("x")
	if requested.size() == 2 and DisplayServer.get_name() != "headless":
		# Render the real game scene at the requested native pixel size. A
		# hidden Windows window is otherwise clamped to the monitor work area.
		var surface := SubViewport.new()
		surface.size = Vector2i(int(requested[0]),int(requested[1]))
		var factor := minf(float(requested[0])/1280.0,float(requested[1])/720.0)
		surface.size_2d_override = Vector2i(roundi(float(requested[0])/factor),roundi(float(requested[1])/factor))
		surface.size_2d_override_stretch = true
		surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		surface.gui_embed_subwindows = true
		root.add_child(surface)
		capture_view = surface
	main = load("res://scenes/main.tscn").instantiate()
	capture_view.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	await process_frame
	await process_frame
	_check(_button(main.front.overlay,"路演片段 · 独立进度") == null,"Removed independent-progress entry remains visible")
	_check_front_buttons()
	await _capture("echo-welcome")
	_check(main._is_echo(), "Expected echo edition")
	if not OS.has_feature("editor"):
		_check(not ResourceLoader.exists("res://assets/imported/rubbing_master.png"),"Rejected artwork was exported")
		_check(not FileAccess.file_exists("res://tests/echo_smoke.gd"),"Test scripts were exported")
	_check(int(root.get_node("GameState").player.capacity) == 3, "New journey must begin with three slots")
	_check(main._event_background("temple_incense").resource_path == "res://assets/echo_v1/temple_hall_master.png", "Revised temple art not connected")
	for chapter in main.data.catalog.chapters.slice(0,2):
		for event in chapter.events:
			main._open_event(str(chapter.id),str(event.id))
			main._finish_dialogue()
			if event.has("stage"):
				while main.busy or main.flow != "puzzle": await process_frame
				await _stage(str(event.id))
			else:
				_check(main.flow == "intro")
				_check(main.scene_view.echo_style,"Old-proportion character still used in echo exploration")
				await _capture("adult-investigation")
				Input.action_press("move_right")
				await create_timer(.15).timeout
				await _capture("adult-walking")
				Input.action_release("move_right")
				if not walk_checked:
					await _check_walking()
					walk_checked = true
				await main._start_event()
				for step in event.puzzle.steps:
					var payload := {"step_id":str(step.id),"strokes":_strokes(step.trace.strokes)}
					var solved: Dictionary = await main.network.request_json("/api/v1/sessions/%s/puzzle" % main.session_id,HTTPClient.METHOD_POST,payload)
					_check(bool(solved.get("accepted",false)), "Echo puzzle rejected: " + str(solved))
			await main._resume()
			_check(main.flow == "choice")
			if str(event.id) == "temple_drum":
				_snapshot_demo("choice")
				_check(root.get_node("GameState").player.memories.size() == 3)
				_check(int(root.get_node("GameState").player.capacity) == 3)
				if archive != "she_hui_chun": main.echo_journey._select(archive)
				if archive != "she_hui_chun":
					var new_card: Control = main.page.find_child("NewResponse",true,false)
					var old_card: Control = main.page.find_child("HeldResponse",true,false)
					_check(new_card != null and old_card != null,"The paired response comparison is missing")
					await process_frame
					_check(absf(new_card.size.x-old_card.size.x) < 2,"New and old responses have unequal space")
				else:
					_check(_button(main.page,"带走「社·回春」 · 归档所选旧回声…").disabled,"Taking a new response requires selecting an old one")
				if archive == "she_cheng_xiang":
					await _press("看与听 · 社·承香")
					_check(main.echo_journey.preview.living)
					await _capture("beam-before-archive")
					await _press("返回取舍")
				await _capture("first-choice")
				var confirm: Button = _button(main.page,"保留现有回声 · 只归档「社·回春」…" if archive == "she_hui_chun" else "带走「社·回春」 · 归档所选旧回声…")
				_check(confirm != null)
				confirm.pressed.emit()
				await _check_archive_confirmation(confirm)
				while main.busy: await process_frame
				_check(not main.echo_journey.held(archive))
				_check(main.echo_journey.held("she_hui_chun") == (archive != "she_hui_chun"))
				await _capture("choice-retiring")
				await create_timer(1.3).timeout
				_check(main.echo_journey.preview.strength == 0, "Archived visual layer did not retire")
				await _capture("choice-result")
			else:
				if str(event.id) == "temple_guest":
					# The user's screenshot archives a new response with room left.
					var state_before := JSON.stringify(root.get_node("GameState").player)
					var archive_new := _button(main.page,"只留下新回声的记录…")
					archive_new.pressed.emit()
					await _capture("archive-new-with-room")
					await _pointer(main.archive_prompt.cancel_button,main.archive_prompt.cancel_button.size*.5,true)
					await _pointer(main.archive_prompt.cancel_button,main.archive_prompt.cancel_button.size*.5,false)
					_check(not main.archive_prompt.visible and JSON.stringify(root.get_node("GameState").player) == state_before,"Cancelling a new archive changed held memories")
				var keep: Button = _button(main.page,"收入心舍")
				_check(keep != null)
				keep.pressed.emit()
				while main.busy: await process_frame
				if str(event.id) == "temple_incense":
					_check(main.echo_journey.preview.living, "Kept labor memory is not living")
					await process_frame
					_check(main.echo_journey.preview.strength == 1, "Kept labor memory is invisible")
					_check(main.echo_journey.preview.is_visible_in_tree())
					await create_timer(.5).timeout
					_check(not main.echo_journey.preview.retiring, "A kept memory is retiring")
					_check(main.echo_journey.preview.strength == 1, "Living labor faded after layout")
					await _check_labor_pixels()
				await _capture(str(event.id)+"-kept-response")
			_check(_button(main.page,"收起谱页，继续 →") != null)
			await _check_result_layout()
			if event.has("battle"):
				await main._resume()
				_check(main.flow == "battle" and main.arena.echo_style,"Old-proportion character still used in echo guarding")
				await _capture("adult-battle-idle")
				if str(event.id) == "prologue_bridge": await _check_battle_movement_and_audio()
				main.arena.cast("挥墨","挥墨",Color.WHITE)
				await create_timer(.12).timeout
				await _capture("adult-battle-casting")
				var battle: Dictionary = await main.network.request_json("/api/v1/sessions/%s/battle" % main.session_id,HTTPClient.METHOD_POST,_battle(event))
				_check(bool(battle.get("won",false)), "Battle fixture failed: " + str(battle))
			await main._resume()
			if str(event.id) == "temple_drum":
				_check(main.flow == "response", "Post-choice drum interaction missing")
				_check(int(root.get_node("GameState").player.capacity) == 3, "Capacity expanded before the consequence")
				await _press("敲一下鼓")
				_check(main.echo_journey.preview.last_child_echo == (archive != "she_hui_chun"), "Child echo ignores the archive")
				_check(main.echo_journey.preview.physical_audio.playing, "Real drum was silenced")
				if archive == "she_hui_chun": _check(not main.event_audio.playing, "Archived child still speaks")
				await _capture("drum-response")
				await main._resume()
			_check(main.flow == "settlement", "Echo result not shown: " + main.status.text)
			_check(_all_text(main.page).find("★") == -1, "Echo settlement still ranks the journey")
	var player: Dictionary = root.get_node("GameState").player
	_check(int(player.capacity) == 4 and player.memories.size() == 3 and player.recorded_memories.size() == 4)
	_check("藻井" in main._learned_skills(), "Archiving removed a learned craft")
	main._memory_detail(archive)
	_check(_button(main.page,"聆听这段鲜活回声") == null)
	main._play_memory(str(main.data.memory(archive).echo_audio))
	_check(not main.memory_audio.playing, "Archived echo still plays")
	await _capture("archived-record")
	main._show_memories()
	_check(_all_text(main.page).contains("已归档"), "Archive disappeared from records")
	if OS.get_environment("YANXIA_REVIEW_FULL") == "1": await _remaining_journey()
	main._show_welcome()
	await process_frame
	_check(_button(main.front.overlay,"路演片段 · 独立进度") == null,"Independent-progress entry returns after loading a saved journey")
	_check(_button(main.front.overlay,"继续旅程") != null,"Saved journey cannot be continued from the simplified homepage")
	_check_front_buttons()
	await _capture("echo-welcome-returning")
	print("PASS echo client: temple observations, reversible joinery mistake, both-side assembly, sheltered placement saved, gradual rubbing and held assistance, first three-slot choice, confirmed archive and persistent craft")
	# Exercise the same close path as the window's Exit action. It retires
	# looping audio before the engine shuts down, rather than freeing the
	# scene underneath active playbacks as a test-only teardown would do.
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func _remaining_journey() -> void:
	# Answer fixtures remain in the server source, which is excluded from the
	# client export. These checks cover UI transitions, not first-time solving.
	var fixture := OS.get_environment("YANXIA_FIXTURE_PATH")
	if fixture.is_empty(): fixture = ProjectSettings.globalize_path("res://../服务端/content/chapters.json")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	for chapter in source.chapters.slice(2):
		for event in chapter.events:
			main._open_event(str(chapter.id),str(event.id))
			main._finish_dialogue()
			_check(main.flow == "intro")
			await main._start_event()
			for step in event.puzzle.steps:
				await process_frame
				await process_frame
				var answer := str(step.get("answer",""))
				if answer.is_empty() and not step.get("options",[]).is_empty(): answer = str(step.options[0])
				if step.kind == "trace":
					if str(event.id) == "opera_opening":
						await _capture("opera-trace-layout")
						for control in main.page.find_children("*","Button",true,false):
							if control.is_visible_in_tree(): _check(main.page.get_viewport_rect().encloses(control.get_global_rect()),"Trace action clipped: "+control.text)
					await main._submit_puzzle({"step_id":step.id,"strokes":_strokes(step.trace.strokes)})
				elif step.kind == "skill":
					await _press(answer)
					var scene: Control = main.skill_scene
					await _click(scene,scene.size*scene.anchors[str(step.target)])
				elif step.kind == "join":
					var canvas: Control = main.join_canvas
					var slot: int = step.options.find(answer)
					var down := InputEventMouseButton.new()
					down.button_index = MOUSE_BUTTON_LEFT
					down.pressed = true
					down.position = canvas.piece
					canvas._gui_input(down)
					var motion := InputEventMouseMotion.new()
					motion.position = canvas._socket_center(slot)
					canvas._gui_input(motion)
					var up := InputEventMouseButton.new()
					up.button_index = MOUSE_BUTTON_LEFT
					up.position = motion.position
					canvas._gui_input(up)
					await _idle()
				elif str(step.id) in ["opera_role","archway_grade"]:
					if str(step.id) == "opera_role": await _capture("opera-sleeve-puzzle")
					var found := false
					for button in main.page.find_children("*","Button",true,false):
						if not button.disabled and str(button.get("motif")) == answer:
							button.pressed.emit()
							found = true
							break
					_check(found,"Missing pattern choice")
					await _idle()
				else: await _press(answer)
				_check(str(step.id) in root.get_node("GameState").session.accepted_steps,"Later-chapter puzzle did not advance: " + str(step.id))
			_check(main.flow == "choice")
			if str(event.id) == "opera_opening":
				await _capture("opera-memory-choice")
				main._memory_detail(str(event.reward.memory_id))
				await process_frame
				await main._resume()
				_check(main.flow == "choice", "Memory detail did not return to the active choice")
			var player: Dictionary = root.get_node("GameState").player
			if str(event.id) == "tower_ledger": await _press("收下最后一页")
			elif player.memories.size() < int(player.capacity): await _press("收入心舍")
			else:
				main.echo_journey._select(str(player.memories[0].id))
				await main._choose("replace",str(player.memories[0].id))
			await main._resume()
			if event.has("battle"):
				_check(main.flow == "battle")
				var result: Dictionary = await main.network.request_json("/api/v1/sessions/%s/battle" % main.session_id,HTTPClient.METHOD_POST,_battle(event))
				_check(bool(result.get("won",false)),"Later-chapter battle fixture failed: " + str(event.id) + " " + str(result))
				await main._resume()
			_check(main.flow == "settlement","Later-chapter settlement missing")
			_check(not _all_text(main.page).contains("★"))
			if str(event.id) == "tower_ledger":
				await process_frame
				await process_frame
				for grid in main.page.find_children("*","GridContainer",true,false):
					if grid.columns == 2 and grid.get_child_count() == 10:
						for label in grid.get_children():
							_check(label.size.x >= 250,"Epilogue record column collapsed")
			await _capture(str(event.id)+"-result")
	var player: Dictionary = root.get_node("GameState").player
	_check(player.completed_events.size() == 10 and player.recorded_memories.size() == 10)
	_check(int(player.capacity) == 5 and player.memories.size() == 5)
	_check(not main.echo_journey.held("tower_epilogue"))
	await main._load_game()
	_check(root.get_node("GameState").player.completed_events.size() == 10,"Complete journey failed to reload")
	print("PASS full echo journey: ten UI event flows, non-slot final page, no stars, five living echoes and persisted completion; later trace/battle use deterministic fixtures")

func _idle() -> void:
	await process_frame
	while main.busy: await process_frame
	await process_frame

func _press(text: String) -> void:
	var button := _button(main.page,text)
	_check(button != null, "Missing visible control: " + text)
	button.pressed.emit()
	await _idle()

func _click(canvas: Control, point: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	canvas._gui_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	canvas._gui_input(up)
	await _idle()

func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	main.get_viewport().push_input(down,true)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = code
	main.get_viewport().push_input(up,true)
	await _idle()

func _pointer(canvas: Control, point: Vector2, pressed: bool, motion: bool = false) -> void:
	# Dispatch through the viewport's GUI routing, including transforms. Calling
	# place_piece directly cannot detect a pickup that resets the rotation.
	var event: InputEventMouse
	if motion:
		event = InputEventMouseMotion.new()
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = canvas.get_global_transform_with_canvas()*point
	event.global_position = event.position
	main.get_viewport().push_input(event,true)
	await process_frame

func _drag_rotated_piece(canvas: Control) -> void:
	var stage: Control = canvas.stage
	stage.put_back_piece()
	# Switching pieces and cancelling must preserve each piece's orientation.
	stage.choose_piece(2)
	stage.put_back_piece()
	var start: Vector2 = canvas.piece_rects[0].get_center()
	var finish: Vector2 = canvas.slot_rects["SLOT-L"].get_center()
	await _pointer(canvas,start,true)
	_check(stage.selected == "JOIN-L" and stage.piece_turn == 180,"Picking up the rotated left piece reset its orientation")
	await _key(KEY_R)
	_check(stage.piece_turn == 0,"R did not rotate while dragging")
	await _key(KEY_R)
	for i in range(1,9):
		await _pointer(canvas,start.lerp(finish,float(i)/8),true,true)
		_check(stage.piece_turn == 180,"Dragging reset the rotated left piece")
	await _capture("joinery-rotated-drag")
	await _pointer(canvas,finish,false)
	await _idle()

func _check_result_layout() -> void:
	await process_frame
	await process_frame
	var result: Control = main.page.get_node_or_null("ChoiceResult")
	if result == null: return
	_check(result.size.y >= main.page.size.y*.80,"Result did not expand into the available page height")
	var notes: Control = result.get_node("ResultNotes")
	var next: Button = _button(notes,"收起谱页，继续 →")
	_check(next.size.x <= 360,"Result button stretches across the screen")
	var bounds := Rect2(Vector2.ZERO,main.get_viewport().get_visible_rect().size)
	_check(bounds.encloses(next.get_global_rect()),"Result continue button is outside the viewport")
	_check(absf(notes.get_global_rect().get_center().y-result.get_global_rect().get_center().y) < 4,"Result text is not vertically centred")

func _check_archive_confirmation(trigger: Button) -> void:
	var prompt: Control = main.archive_prompt
	_check(prompt.visible and not main.confirmation.visible,"Archive still opens a native system dialog")
	await process_frame
	await process_frame
	var bounds := main.get_viewport().get_visible_rect()
	await _capture("archive-confirmation")
	if not bounds.encloses(prompt.sheet.get_global_rect()): print("Archive bounds=",bounds," prompt=",prompt.size," sheet=",prompt.sheet.get_global_rect()," minimum=",prompt.sheet.get_combined_minimum_size())
	_check(bounds.encloses(prompt.sheet.get_global_rect()),"Archive sheet exceeds the viewport")
	for button in [prompt.cancel_button,prompt.confirm_button]:
		_check(prompt.sheet.get_global_rect().encloses(button.get_global_rect()),"Archive action is clipped")
	_check(main.get_viewport().gui_get_focus_owner() == prompt.cancel_button,"Archive should initially focus the return action")
	var before := JSON.stringify(root.get_node("GameState").player)
	var before_session := JSON.stringify(root.get_node("GameState").session)
	# A click behind the sheet must not reach the candidate selection controls.
	await _pointer(prompt,Vector2(6,6),true)
	await _pointer(prompt,Vector2(6,6),false)
	_check(prompt.visible and JSON.stringify(root.get_node("GameState").player) == before,"Backdrop click changed the pending choice")
	await _pointer(prompt.cancel_button,prompt.cancel_button.size*.5,true)
	await _pointer(prompt.cancel_button,prompt.cancel_button.size*.5,false)
	_check(not prompt.visible and JSON.stringify(root.get_node("GameState").session) == before_session,"Cancelling archive changed the session")
	trigger.pressed.emit()
	await process_frame
	await _key(KEY_TAB)
	_check(main.get_viewport().gui_get_focus_owner() == prompt.confirm_button,"Tab cannot reach the archive action")
	await _key(KEY_TAB)
	_check(main.get_viewport().gui_get_focus_owner() == prompt.cancel_button,"Tab escaped the modal")
	await _key(KEY_ESCAPE)
	_check(not prompt.visible and JSON.stringify(root.get_node("GameState").player) == before,"Escape changed the choice")
	trigger.pressed.emit()
	await process_frame
	await _pointer(prompt.confirm_button,prompt.confirm_button.size*.5,true)
	await _pointer(prompt.confirm_button,prompt.confirm_button.size*.5,false)
	await _idle()
	_check(not prompt.visible,"Archive sheet did not close after confirmation")

func _check_walking() -> void:
	# Targeted layout runs may omit the unchanged walk-cycle capture.
	if OS.get_environment("YANXIA_SKIP_WALK_CHECK") == "1": return
	var scene: Control = main.scene_view
	var figure = preload("res://scripts/echo_figure.gd")
	_check(figure.walk_frames.size() == 8,"Adult walking cycle did not load")
	var phases := {}
	Input.action_press("move_left")
	for i in range(90):
		await process_frame
		_check(scene.character_moving,"Walking input did not move the artisan")
		var frame: int = figure.walk_frame(scene.walk_time)
		if phases.has(frame): continue
		phases[frame] = true
		var directory := OS.get_environment("YANXIA_REVIEW_SHOTS")
		if not directory.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var error := capture_view.get_texture().get_image().save_png(directory.path_join("walk-left-frame-%d.png" % frame))
			_check(error == OK)
		# Reading a native frame can skip animation phases on a slow render.
		# Sample several changing poses before reaching the scene boundary.
		if phases.size() >= 3: break
	Input.action_release("move_left")
	await process_frame
	var stopped: float = scene.walk_time
	await create_timer(.15).timeout
	_check(not scene.character_moving and scene.walk_time == stopped,"Idle character continues walking or making footsteps")
	_check(phases.size() >= 3,"Moving artisan did not advance through distinct walk frames")
	_check(main.soundscape.material_cursor.has("step_wood"),"Movement has no material-specific footsteps")

func _check_battle_movement_and_audio() -> void:
	main._begin_battle()
	var arena: Control = main.arena
	var before: float = arena.walk_time
	Input.action_press("move_right")
	await create_timer(.24).timeout
	Input.action_release("move_right")
	_check(arena.walk_time > before,"Guarding movement did not advance the adult walk cycle")
	_check(not main.battle_buttons.has("斗拱") and not main.battle_buttons.has("藻井"),"Passive skills still occupy action buttons")
	_check(main.battle_buttons.size() >= 2,"Active skill controls are missing")
	_check(arena.shield > 0,"Automatic ward did not trigger")
	await create_timer(3.0).timeout
	_check(main.soundscape.last_cue.has("erosion_gather"),"Enemy wind-up did not play the paper/plaster cue")
	_check(arena.strike_number >= 1 and main.battle_hits == 0,"Real timed enemy strike was not blocked")
	await _capture("white-erosion-after-timed-strike")
	# Stop the local clock before the existing deterministic server fixture.
	# The timed sample above verifies feedback, not a human battle completion.
	main.battle_running = false
	arena.active = false

func _restore_stage() -> void:
	var previous: Control = main.echo_stage
	var accepted: Array = previous.accepted.duplicate()
	main._show_settings()
	await main._resume()
	_check(main.echo_stage == previous and previous.accepted == accepted, "Settings lost the live scene")
	# A second resume fetches the persisted checkpoint and constructs a fresh
	# scene, as a restart does after loading the same active session.
	await main._resume()
	await _idle()
	_check(main.echo_stage.accepted == accepted, "Fresh scene lost its saved actions")

func _stage(id: String) -> void:
	var stage: Control = main.echo_stage
	var canvas: Control = stage.canvas
	await process_frame
	await _capture(id+"-observe")
	if id == "temple_incense":
		main._show_settings()
		var option: CheckButton
		for child in main.page.get_children():
			if child is CheckButton and child.text == "减弱环境动态与转场": option = child
		_check(option != null)
		option.button_pressed = true
		await _press("保存设置")
		await main._resume()
		var before: float = canvas.scene_time
		await create_timer(.15).timeout
		_check(canvas.scene_time == before,"Reduced environment motion was ignored")
		main.reduced_motion = false
	for object in stage.spec.objects:
		if str(object.get("step_id", "")).is_empty(): continue
		await _click(canvas,canvas.scene_point(object.position))
		_check(canvas.inspect_id == str(object.id),"Object close-up did not open")
		await _capture(id+"-close-"+str(object.id))
		if str(object.id) == "marks":
			var previous_steps: Array = stage.accepted.duplicate()
			await _click(canvas,canvas.scene_point([.49,.61]))
			_check(stage.accepted == previous_steps,"Close-up leaked a scene action")
		await _press("返回场景，继续 →")
		_check(canvas.inspect_id.is_empty(),"Could not return from the close-up")
	_check(stage.observed(), "Scene observations did not persist")
	if id == "temple_incense":
		_snapshot_demo("repair")
		await _press("选用斗拱")
		await _click(canvas,canvas.support_rect.get_center())
		_check(stage.done("hall_support"))
		await _capture("joinery-before")
		# Pick and install right first: dependency handling must not force order.
		if archive == "yan_ping_an":
			canvas.keyboard_buttons["piece_1"].grab_focus()
			await _key(KEY_ENTER)
			_check(stage.selected == "JOIN-R", "Keyboard could not select a piece")
			canvas.keyboard_buttons["SLOT-R"].grab_focus()
			await _key(KEY_ENTER)
		else:
			await _click(canvas,canvas.piece_rects[1].get_center())
			await _click(canvas,canvas.slot_rects["SLOT-R"].get_center())
		_check(stage.done("hall_right"))
		if archive == "yan_ping_an":
			await _restore_stage()
			stage = main.echo_stage
			canvas = stage.canvas
		await _click(canvas,canvas.piece_rects[0].get_center())
		await _click(canvas,canvas.slot_rects["SLOT-L"].get_center())
		_check(not stage.done("hall_left"), "Wrong orientation was accepted")
		_check(int(root.get_node("GameState").player.erosion) == 0)
		await _press("将所选木件转半圈 · R")
		await _drag_rotated_piece(canvas)
		_check(stage.done("hall_left"))
		await _click(canvas,canvas.piece_rects[2].get_center())
		await _click(canvas,canvas.slot_rects["SLOT-C"].get_center())
		await _press("撤下临撑")
		_check(stage.complete)
		_check(not canvas.workbench,"Repair outcome did not return to the same hall")
		await create_timer(1.2).timeout
		await _capture("joinery-after")
		await _press("查看接合处 / 回到正殿")
		await _capture("joinery-detail-after")
		await _press("查看接合处 / 回到正殿")
	elif id == "temple_guest":
		await _press("看看檐下边界")
		await _press("拿起空碗")
		await _click(canvas,canvas.scene_point([.25,.83]))
		_check(not stage.complete, "Wet floor accepted")
		if archive == "yan_ping_an":
			canvas.grab_focus()
			for i in range(10): await _key(KEY_RIGHT)
			await _key(KEY_ENTER)
		else: await _click(canvas,canvas.scene_point([.60,.81]))
		_check(stage.complete)
		var saved: Dictionary = await main.network.request_json("/api/v1/sessions/" + main.session_id)
		_check(abs(float(saved.stage_placements.guest_place[0])-.60) < .001, "Actual bowl position not saved")
		await _capture("guest-after")
	else:
		await _press("选用藻井")
		await _click(canvas,canvas.scene_point([.48,.47]))
		_check(stage.done("drum_reveal"))
		await _capture("rubbing-before")
		for region in ["outer","center"]:
			stage.select_region(region)
			for y in range(5,96,6):
				var down := InputEventMouseButton.new()
				down.button_index = MOUSE_BUTTON_LEFT
				down.pressed = true
				down.position = canvas.rubbing_rect.position+Vector2(.04,float(y)/100)*canvas.rubbing_rect.size
				canvas._gui_input(down)
				for x in range(8,97,4):
					var move := InputEventMouseMotion.new()
					move.position = canvas.rubbing_rect.position+Vector2(float(x)/100,float(y)/100)*canvas.rubbing_rect.size
					canvas._gui_input(move)
				var up := InputEventMouseButton.new()
				up.button_index = MOUSE_BUTTON_LEFT
				up.position = down.position
				canvas._gui_input(up)
				if y == 29 and region == "outer": await _capture("rubbing-partial")
			_check(canvas.coverage(region) >= .65)
			await _press("收笔，查看这处纹理")
			_check(stage.done("rub_" + region), "Visible coverage disagrees with saved coverage")
			if region == "outer" and archive == "yan_ping_an":
				await _restore_stage()
				stage = main.echo_stage
				canvas = stage.canvas
				_check(canvas.coverage("outer") == 1, "Accepted rubbing region did not restore")
		stage.select_region("seam")
		var assist := _button(main.page,"按住此处 · 辅助拓显")
		assist.button_down.emit()
		await create_timer(.5).timeout
		_check(not stage.done("rub_seam"), "Assist accepted before the hold finished")
		assist.button_up.emit()
		await create_timer(.1).timeout
		_check(not stage.done("rub_seam"), "Released assist completed")
		_check(stage.held_seconds >= .45, "Released assist lost its progress")
		assist.button_down.emit()
		await create_timer(1.15).timeout
		await _idle()
		_check(stage.complete)
		await _capture("rubbing-after")

func _strokes(source: Array) -> Array:
	var result: Array = []
	for stroke in source:
		var sampled: Array = [stroke[0]]
		for i in range(1,stroke.size()):
			for k in range(1,41):
				var blend := float(k)/40.0
				sampled.append([lerpf(float(stroke[i-1][0]),float(stroke[i][0]),blend),lerpf(float(stroke[i-1][1]),float(stroke[i][1]),blend)])
		result.append(sampled)
	return result

func _snapshot_demo(kind: String) -> void:
	var source := OS.get_environment("YANXIA_DEMO_SAVE")
	var directory := OS.get_environment("YANXIA_DEMO_CAPTURE")
	if source.is_empty() or directory.is_empty(): return
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK)
	_check(DirAccess.copy_absolute(source,directory.path_join(kind+".json")) == OK)

func _battle(event: Dictionary) -> Dictionary:
	var ready: Dictionary = {}
	var actions: Array = []
	var names: Array = event.battle.get("required_skills",[]).duplicate()
	if not names.has("斗拱"): names.append("斗拱")
	names.append("挥墨")
	var wave := 0
	var hp := int(event.battle.enemy_hp)
	var at := 0
	while wave < int(event.battle.waves) and at < int(event.battle.duration_sec)*1000:
		for skill in names:
			if at < int(ready.get(skill,0)): continue
			var spec: Dictionary = main.data.catalog.skills[skill]
			actions.append({"skill":skill,"at_ms":at})
			ready[skill] = at+int(spec.cooldown_ms)
			hp -= int(spec.damage)
			if hp <= 0:
				wave += 1
				hp = int(event.battle.get("boss_hp",event.battle.enemy_hp)) if not str(event.battle.get("boss_name","")).is_empty() and wave == int(event.battle.waves)-1 else int(event.battle.enemy_hp)
			if wave == int(event.battle.waves): break
		if wave == int(event.battle.waves): break
		at += 500
	return {"duration_ms":at+1,"actions":actions}

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _button(child,text)
		if found != null: return found
	return null

func _all_text(node: Node) -> String:
	var text := str(node.text) if node is Label or node is Button else ""
	for child in node.get_children(): text += "\n" + _all_text(child)
	return text

func _capture(name: String) -> void:
	if main.transition_tween != null and main.transition_tween.is_running():
		await main.transition_tween.finished
	await process_frame
	await process_frame
	var directory := OS.get_environment("YANXIA_REVIEW_SHOTS")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var error := capture_view.get_texture().get_image().save_png(directory.path_join(name+".png"))
	_check(error == OK)

func _check_labor_pixels() -> void:
	if OS.get_environment("YANXIA_REVIEW_SHOTS").is_empty() or DisplayServer.get_name() == "headless": return
	var view = main.echo_journey.preview
	await RenderingServer.frame_post_draw
	var living_image := capture_view.get_texture().get_image()
	view.living = false
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var physical_image := capture_view.get_texture().get_image()
	view.living = true
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var changed := 0
	var ratio := Vector2(living_image.get_size())/Vector2(1280,720)
	var area: Rect2 = view.image_rect
	var begin: Vector2 = (view.global_position+area.position+Vector2(.32,.31)*area.size)*ratio
	var end: Vector2 = (view.global_position+area.position+Vector2(.61,.59)*area.size)*ratio
	for y in range(int(begin.y),int(end.y)):
		for x in range(int(begin.x),int(end.x)):
			var a := living_image.get_pixel(x,y)
			var b := physical_image.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > .08: changed += 1
	_check(changed > 300,"Living labor overlay has no visible pixels at actual result-page size")
	print("PASS labor overlay visible pixels: ",changed)
