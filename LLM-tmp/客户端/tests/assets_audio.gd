extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(99))
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	assert(AudioServer.get_bus_effect_count(main.echo_bus) == 0, "Speech distortion must stay disabled")
	for path in main.voice_index.cues.values():
		var clip := load(path) as AudioStreamWAV
		assert(clip != null and clip.mix_rate == 24000 and not clip.stereo)
		assert(clip.format == AudioStreamWAV.FORMAT_16_BITS and clip.get_length() > .3)
	main._show_map()
	assert(main.flow == "map")
	var game = root.get_node("GameState")
	game.player.completed_events["prologue:prologue_bridge"] = {"stars": 3, "erosion_at_end": 0}
	main.story_progress = ConfigFile.new()
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
	main.soundscape.cue("ui")
	assert(main.soundscape.speech_active and main.soundscape.voices[0].volume_db == -24)
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
	assert(main.soundscape.speech_active)
	main._apply_erosion(80)
	assert(is_equal_approx(AudioServer.get_bus_volume_db(main.echo_bus), -3.2))
	assert(AudioServer.get_bus_effect_count(main.echo_bus) == 0)
	main._play_memory("")
	assert(main.memory_audio.stream_paused)
	assert(not main.soundscape.speech_active)
	main._show_map()
	assert(not main.memory_audio.playing)
	game.player.completed_events.erase("prologue:prologue_bridge")
	main._open_event("prologue", "prologue_bridge")
	main._finish_dialogue()
	for index in range(3):
		main.scene_view._discover(index)
		assert(main.voice_queue.is_empty(), "Investigation accumulated stale or repeated speech")
	assert(main.event_audio.stream.resource_path.ends_with("prologue_bridge_clue_03.wav"))
	print("PASS story replay with no active event, actual narration queue completion, music ducking restore, silent pause, supplied memory voice and pause")
	main.queue_free()
	await create_timer(.3).timeout
	quit(0)
