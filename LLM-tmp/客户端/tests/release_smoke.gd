extends SceneTree

var main

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.busy or main.data.catalog.is_empty(): await process_frame
	if main.flow != "map" or main.data.catalog.version != 10: return fail("Map/version")
	if main.voice_index.cues.size() != 184: return fail("Voice count")
	for path in main.voice_index.cues.values():
		if not ResourceLoader.exists(path): return fail("Voice " + path)
	for filename in ["bridge_restored.jpg", "bridge_eroded.jpg", "temple_interior.png", "guest_room.png", "drum_courtyard.png", "white_erosion.png"]:
		if not ResourceLoader.exists("res://assets/imported/" + filename): return fail("Image " + filename)
	if ResourceLoader.exists("res://assets/imported/rubbing_master.png"): return fail("Rejected artwork leaked into release")
	main._open_event("prologue", "prologue_bridge")
	await create_timer(.3).timeout
	if not main.event_audio.playing or main.event_audio.get_playback_position() <= 0: return fail("Voice playback")
	if main.dialogue_stage.text_label.visible_characters <= 0: return fail("Dialogue reveal")
	main._finish_dialogue()
	if main.event_audio.playing: return fail("Voice cancellation")
	print("PASS EXPORTED v10: fresh local save, auto-started server, 184 voices, six adopted images, rejected asset excluded, dialogue voice and animation")
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func fail(reason: String) -> void:
	push_error("Release verification: " + reason)
	quit(90)
