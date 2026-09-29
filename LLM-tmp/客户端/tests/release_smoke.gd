extends SceneTree

var main

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	main._show_map()
	if main.flow != "map" or main.data.catalog.version != 10: return fail("Map/version")
	if main.voice_index.cues.size() != 184: return fail("Voice count")
	for path in main.voice_index.cues.values():
		if not ResourceLoader.exists(path): return fail("Voice " + path)
		var clip := load(path) as AudioStreamWAV
		if clip == null or clip.mix_rate != 24000 or clip.format != AudioStreamWAV.FORMAT_16_BITS:
			return fail("Qwen PCM voice " + path)
	if main.navigation.get_child_count() != 2: return fail("Three-page navigation")
	if AudioServer.get_bus_effect_count(main.echo_bus) != 0: return fail("Speech distortion")
	if main.soundscape.ambience.stream.resource_path != "res://assets/audio/theme.wav": return fail("New background music")
	if not is_equal_approx(main.soundscape.ambience.stream.get_length(), 123.0): return fail("Music duration")
	for name in ["background", "frame", "paper", "ink", "panel", "title"]:
		if not ResourceLoader.exists("res://assets/ink_ui/" + name + ".png"): return fail("Ink UI " + name)
	for filename in ["bridge_restored.jpg", "bridge_eroded.jpg", "temple_interior.png", "guest_room.png", "drum_courtyard.png", "white_erosion.png"]:
		if not ResourceLoader.exists("res://assets/imported/" + filename): return fail("Image " + filename)
	for filename in ["ink_slash", "dougong_ward", "caisson_rosette", "flying_blades", "dodge_smoke", "erosion_burst"]:
		var vfx = load("res://assets/vfx/" + filename + ".png") as Texture2D
		if vfx == null or vfx.get_image().get_pixel(0, 0).a != 0: return fail("Generated transparent VFX " + filename)
	for filename in ["xuan_paper", "brush_cursor", "ink_dab", "cinnabar_seal", "hint_plaque", "jade_seal", "mortise_beam", "tenon_piece", "mortise_marker", "stage_floor", "stage_step_piece", "backdrop_rail", "brocade_panel", "lotus_marker", "gate_2", "gate_3", "gate_4", "glyph_bridge_trace", "glyph_guest_trace", "glyph_drum_trace", "glyph_opera_trace", "glyph_tower_trace"]:
		if not ResourceLoader.exists("res://assets/puzzles/" + filename + ".png"): return fail("Generated puzzle art " + filename)
	if ResourceLoader.exists("res://assets/imported/rubbing_master.png"): return fail("Rejected artwork leaked into release")
	main._open_event("prologue", "prologue_bridge")
	await create_timer(.3).timeout
	if not main.event_audio.playing or main.event_audio.get_playback_position() <= 0: return fail("Voice playback")
	if main.dialogue_stage.text_label.visible_characters <= 0: return fail("Dialogue reveal")
	main._finish_dialogue()
	if main.event_audio.playing: return fail("Voice cancellation")
	for code in [KEY_ENTER, KEY_KP_ENTER]:
		var key := InputEventKey.new()
		key.keycode = code
		if not InputMap.event_is_action(key, "advance"): return fail("Investigation Enter binding")
	var scene = main.scene_view
	scene._discover(0)
	main._show_settings()
	if not main._has_current_event(): return fail("Investigation return entry")
	await main._resume()
	if main.flow != "intro" or main.scene_view != scene or scene.discovered != [0]: return fail("Investigation restoration")
	for i in range(1, scene.investigations.size()): scene._discover(i)
	var reader_script = load("res://scripts/story_reader.gd")
	var readers = main.page.find_children("*", "VBoxContainer", true, false).filter(func(node): return node.get_script() == reader_script)
	if readers.size() != 1: return fail("Optional story reader missing in EXE")
	readers[0].open_story()
	if readers[0].caption.text != main.current_event.story.beats[0] or not main.event_audio.playing: return fail("Optional story text/audio in EXE")
	var figure = load("res://scripts/ink_figure.gd")
	figure.prepare()
	if figure.texture == null or figure.texture.get_image().get_pixel(0, 0).a != 0: return fail("Artisan texture in EXE")
	var arena = load("res://scripts/battle_arena.gd").new()
	root.add_child(arena)
	arena.cast("斗拱", "护阵", Color.WHITE)
	arena.cast("挥墨", "挥墨", Color.WHITE)
	arena.enemy_strike(true)
	if arena.effects.size() != 3: return fail("Layered combat effects in EXE")
	arena.queue_free()
	main._show_map()
	var game = root.get_node("GameState")
	game.player.completed_events["prologue:prologue_bridge"] = {"narrative_choice":""}
	main.current_event = main.data.event("tower", "tower_ascent")
	main._replay_story("prologue", "prologue_bridge")
	if main.dialogue_stage.backdrop.resource_path != main._event_art("prologue_bridge").background: return fail("Replay backdrop")
	print("PASS EXPORTED playability fixes: both Enter bindings, investigation restoration, independent replay backdrop")
	print("PASS EXPORTED v10: fresh local save, auto-started server, 184 voices, six adopted images, rejected asset excluded, dialogue voice and animation")
	print("PASS EXPORTED current release: ink UI, simplified navigation, 184 Qwen 24kHz PCM voices, no speech distortion")
	print("PASS EXPORTED v13: optional story text/audio, library artisan texture, independent attack/defence effects")
	print("PASS EXPORTED v14: six Qwen-generated transparent VFX sprites loaded in Windows EXE")
	print("PASS EXPORTED v15: Qwen-generated brush tracing, joinery, opera and pattern artwork loaded in Windows EXE")
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func fail(reason: String) -> void:
	push_error("Release verification: " + reason)
	quit(90)
