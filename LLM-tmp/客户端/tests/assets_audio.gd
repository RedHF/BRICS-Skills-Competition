extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(99))
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.busy or main.data.catalog.is_empty(): await process_frame
	assert(main.flow == "map")
	main.current_event = {}
	main._replay_story("prologue", "prologue_bridge")
	assert(main.event_audio.playing and main.event_audio.stream.resource_path.ends_with("prologue_bridge_dialogue_01.wav"))
	assert(main.current_event.is_empty(), "Replay changed active event identity")
	for i in range(6): main._advance_dialogue()
	assert(main.event_audio.stream.resource_path.ends_with("prologue_bridge_outro.wav"))
	main._show_map()
	assert(not main.event_audio.playing and main.voice_queue.is_empty())
	main._play_cues(["prologue_bridge_clue_01", "prologue_bridge_clue_02"])
	assert(main.voice_queue.size() == 1 and main.soundscape.ambience.volume_db == -32)
	main.event_audio.seek(main.event_audio.stream.get_length() - .1)
	await create_timer(.4).timeout
	assert(main.event_audio.playing and main.event_audio.stream.resource_path.ends_with("prologue_bridge_clue_02.wav"), "Finished signal did not advance narration queue")
	main.event_audio.seek(main.event_audio.stream.get_length() - .1)
	await create_timer(.4).timeout
	assert(not main.event_audio.playing and main.soundscape.ambience.volume_db == -24)
	main._play_cues(["failure_line_07"])
	main._play_cues(["failure_line_08"])
	assert(not main.event_audio.playing, "Silent ellipsis reused preceding audio")
	main._play_memory(main.data.memory("yan_ping_an").echo_audio)
	assert(main.memory_audio.stream.resource_path.ends_with("assets/voice/yan_ping_an.wav"))
	await create_timer(.2).timeout
	assert(main.memory_audio.get_playback_position() > 0)
	main._play_memory("")
	assert(main.memory_audio.stream_paused)
	main._show_map()
	assert(not main.memory_audio.playing)
	print("PASS story replay with no active event, actual narration queue completion, music ducking restore, silent pause, supplied memory voice and pause")
	main.queue_free()
	await create_timer(.3).timeout
	quit(0)
