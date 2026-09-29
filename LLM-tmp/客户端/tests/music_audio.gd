extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(15).timeout.connect(func(): quit(99))
	var sound = load("res://scripts/soundscape.gd").new()
	root.add_child(sound)
	var stream := sound.ambience.stream as AudioStreamWAV
	assert(stream.resource_path == "res://assets/audio/theme.wav")
	assert(stream.stereo and stream.mix_rate == 44100)
	assert(is_equal_approx(stream.get_length(), 123.0))
	assert(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	assert(stream.loop_end == 5424300)
	await create_timer(.2).timeout
	assert(sound.ambience.playing and sound.ambience.get_playback_position() > 0)
	sound.duck(true)
	assert(sound.ambience.volume_db == -32)
	sound.duck(false)
	assert(sound.ambience.volume_db == -24)
	sound.set_battle(true)
	assert(sound.ambience.stream_paused and not sound.music.stream_paused)
	sound.set_battle(false)
	assert(not sound.ambience.stream_paused and sound.music.stream_paused)
	sound.ambience.seek(122.9)
	await create_timer(.4).timeout
	assert(sound.ambience.playing and sound.ambience.get_playback_position() < 1.0)
	sound.stop_all()
	assert(not sound.ambience.playing and not sound.music.playing)
	sound.queue_free()
	stream = null
	sound = null
	await create_timer(.3).timeout
	print("PASS theme: 123s stereo, looping, speech ducking, battle switch, cleanup")
	quit.call_deferred()
