extends "res://tests/review_journey.gd"

var problems: Array[String] = []
var checks := 0
var characters := "檐下千秋★✓→ ×ⅠⅡⅢ·……"

func collect_text(value: Variant) -> void:
	if value is Dictionary:
		for item in value.values(): collect_text(item)
	elif value is Array:
		for item in value: collect_text(item)
	elif value is String:
		for character in value:
			if character.unicode_at(0) >= 0x3000 and not characters.contains(character): characters += character

func check_glyphs() -> void:
	collect_text(main.data.catalog)
	var server := TextServerManager.get_primary_interface()
	var shaped := server.create_shaped_text()
	server.shaped_text_add_string(shaped, characters, main.stats.get_theme_font("font").get_rids(), 20)
	var missing := ""
	for glyph in server.shaped_text_get_glyphs(shaped):
		if (int(glyph.flags) & TextServer.GRAPHEME_IS_VALID) == 0:
			missing += characters.substr(glyph.start, glyph.end - glyph.start)
	server.free_rid(shaped)
	check(missing.is_empty(), "Missing rendered glyphs: " + missing)
	print("FONT unique characters=", characters.length(), " missing=", missing)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		problems.append(message)
		print("FAIL ", message)

func layout(name: String) -> void:
	await process_frame
	await process_frame
	var visible := root.get_visible_rect()
	for control in main.navigation.get_children():
		check(visible.encloses(control.get_global_rect()), name + " navigation outside viewport")
	for control in main.page.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree(): continue
		var rect: Rect2 = control.get_global_rect()
		check(rect.position.x >= main.scroll.global_position.x - 1 and rect.end.x <= main.scroll.get_global_rect().end.x + 1, name + " horizontal overflow: " + str(control.get("text")))
	await capture(name)

func _run() -> void:
	root.gui_embed_subwindows = true
	create_timer(150).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "map" or main.busy: await process_frame
	main.set_process(false)
	game = root.get_node("GameState")
	check_glyphs()
	var player_snapshot: Dictionary = game.player.duplicate(true)
	# All fixtures use this process only, without writing progress to the server.
	main.session_id = ""
	main.story_progress = ConfigFile.new()
	for code in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		var event := InputEventKey.new()
		event.keycode = code
		check(InputMap.event_is_action(event, "advance"), "Investigation key missing: " + OS.get_keycode_string(code))
	main._open_event("prologue", "prologue_bridge")
	await click(main.dialogue_stage.skip)
	var original_scene = main.scene_view
	var point: Dictionary = original_scene.investigations[0]
	await tap(original_scene.global_position + original_scene.size * Vector2(point.position[0], point.position[1]))
	original_scene._process(2)
	check(original_scene.discovered.size() == 1, "Investigation click")
	await click(button("设置", main.navigation))
	var return_button: Button
	for item in main.page.find_children("*", "Button", true, false):
		if item.text == "返回当前事件": return_button = item
	check(is_instance_valid(return_button), "Settings has no return to unfinished investigation")
	if is_instance_valid(return_button):
		await click(return_button)
		check(main.flow == "intro" and main.scene_view == original_scene and original_scene.discovered.size() == 1, "Investigation progress lost after settings")
		# Return through the main task entry as well.
		await click(button("地图", main.navigation))
		await click(button("继续当前修复"))
		check(main.flow == "intro" and main.scene_view == original_scene, "Map failed to resume investigation")
		await capture("investigation-restored")
	if is_instance_valid(main.paused_page):
		main.paused_page.free()
		main.paused_page = null
	main.flow = "map"
	main._show_map()
	# A replay must use its own scene, even when the active task is elsewhere.
	main.chapter_id = "tower"
	main.current_event = main.data.event("tower", "tower_ascent")
	game.player.completed_events["prologue:prologue_bridge"] = {"narrative_choice":""}
	main._replay_story("prologue", "prologue_bridge")
	check(main.dialogue_stage.backdrop.resource_path == main._event_art("prologue_bridge").background, "Story replay shows unrelated active scene")
	await create_timer(1.5).timeout
	await capture("replay-correct-background")
	main._show_map()
	game.player = player_snapshot.duplicate(true)
	for dimensions in [Vector2i(450,800),Vector2i(1280,720),Vector2i(1920,1080)]:
		DisplayServer.window_set_size(dimensions)
		await create_timer(.2).timeout
		var suffix := "-%dx%d" % [dimensions.x,dimensions.y]
		for show_page in [main._show_map,main._show_memories,main._show_ledger,main._show_settings,main._show_journal]:
			show_page.call()
			await layout(main.flow + suffix)
		main.chapter_id = "prologue"
		main.current_event = main.data.event("prologue", "prologue_bridge")
		game.session = {"accepted_steps":[]}
		main._show_puzzle()
		await process_frame
		main.scroll.ensure_control_visible(main.trace_canvas)
		await layout("trace" + suffix)
		var canvas = main.trace_canvas
		var text := "当前第 %02d 笔 · 由青印起笔，向朱印收锋" % [canvas.active + 1]
		var text_end: float = canvas.canvas_rect.position.x + ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		check(text_end <= canvas.size.x, "Trace instruction clipped" + suffix)
		main.flow = "map"
		main._show_map()
		main._open_event("prologue", "prologue_bridge")
		await create_timer(1.8).timeout
		check(root.get_visible_rect().encloses(main.dialogue_stage.card.get_global_rect()), "Dialogue card overflow" + suffix)
		await capture("dialogue" + suffix)
		main._show_map()
	main._show_settings()
	await process_frame
	await process_frame
	var slider: HSlider = main.page.find_children("*", "HSlider", true, false)[0]
	await tap(slider.global_position + slider.size * Vector2(.25,.5))
	check(main.volume >= .2 and main.volume <= .3, "Volume slider did not respond to click")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(0), main.volume), "Volume was not applied to mixer")
	await click(button("静音"))
	check(main.muted and AudioServer.is_bus_mute(0), "Mute button did not silence master bus")
	await click(button("保存设置"))
	var saved_settings := ConfigFile.new()
	check(saved_settings.load("user://settings.cfg") == OK and saved_settings.get_value("audio", "muted") == main.muted and is_equal_approx(saved_settings.get_value("audio", "volume"), main.volume), "Audio settings did not persist")
	await click(button("静音"))
	check(not AudioServer.is_bus_mute(0), "Unmute did not restore master bus")
	# Allow the audio thread to attach the effect before sampling the live mixer.
	var capture_effect := AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, capture_effect)
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_linear(0, 1)
	await create_timer(.6).timeout
	check(capture_effect.get_frames_available() > 0, "Audio mixer produced no frames")
	var frames := capture_effect.get_buffer(capture_effect.get_frames_available())
	var peak := 0.0
	for sample in frames: peak = maxf(peak, sample.length())
	print("MIX exploration frames=", frames.size(), " peak=", peak)
	check(peak > .0001, "Exploration BGM is silent")
	main.soundscape.set_battle(true)
	capture_effect.clear_buffer()
	await create_timer(.6).timeout
	frames = capture_effect.get_buffer(capture_effect.get_frames_available())
	peak = 0
	for sample in frames: peak = maxf(peak, sample.length())
	print("MIX battle frames=", frames.size(), " peak=", peak)
	check(peak > .0001, "Battle BGM is silent")
	main.soundscape.set_battle(false)
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0)-1)
	print("PLAYABILITY checks=", checks, " failures=", problems.size())
	main.queue_free()
	await create_timer(.3).timeout
	quit(0 if problems.is_empty() else 1)
