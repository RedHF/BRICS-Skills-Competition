extends Node

var ambience: AudioStreamPlayer
var music: AudioStreamPlayer
var trace_music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var cursor := 0
var sounds := {}
var speech_active := false
var scene_music := "theme"
var music_tween: Tween

func _exit_tree() -> void:
	stop_all()

func stop_all() -> void:
	if music_tween and music_tween.is_valid(): music_tween.kill()
	for player in voices + [ambience, music, trace_music]:
		if is_instance_valid(player):
			player.stream_paused = false
			if player.stream is AudioStreamWAV:
				player.stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
			player.stop()
			player.stream = null
	sounds.clear()

func _ready() -> void:
	for name in ["ui", "ink", "repair", "hit", "win", "ui_wood", "ui_page", "brush_touch"]:
		sounds[name] = load("res://assets/audio/" + name + ".wav")
	for i in range(6):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -12
		add_child(voice)
		voices.append(voice)
	ambience = _loop("theme", -24)
	music = _loop("battle", -19)
	music.stream_paused = true
	music.volume_db = -55
	trace_music = _loop("trace_music", -23)
	trace_music.stream_paused = true
	trace_music.volume_db = -55

func _loop(name: String, level: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream := load("res://assets/audio/" + name + ".wav") as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	player.stream = stream
	player.volume_db = level
	add_child(player)
	player.play()
	return player

func set_battle(active: bool) -> void:
	set_scene("battle" if active else "theme")

func set_scene(mode: String) -> void:
	if not is_instance_valid(trace_music) or mode == scene_music: return
	scene_music = mode
	if music_tween and music_tween.is_valid(): music_tween.kill()
	music_tween = create_tween().set_parallel()
	var players := {"theme": ambience, "battle": music, "trace": trace_music}
	for name in players:
		var player: AudioStreamPlayer = players[name]
		if name == mode:
			player.stream_paused = false
			music_tween.tween_property(player, "volume_db", _music_level(name), .45)
		else:
			music_tween.tween_property(player, "volume_db", -55.0, .45)
	music_tween.finished.connect(func():
		for name in players:
			if name != scene_music: (players[name] as AudioStreamPlayer).stream_paused = true)

func _music_level(name: String) -> float:
	var base := -19.0 if name == "battle" else (-23.0 if name == "trace" else -24.0)
	return base - (8.0 if speech_active else 0.0)

func cue(name: String) -> void:
	if voices.is_empty() or not sounds.has(name): return
	var player: AudioStreamPlayer = voices[cursor % voices.size()]
	cursor += 1
	player.volume_db = -24 if speech_active else -16
	player.stream = sounds[name]
	player.play()

func duck(active: bool) -> void:
	speech_active = active
	for player in voices: player.volume_db = -24 if active else -16
	for name in {"theme": ambience, "battle": music, "trace": trace_music}:
		var player: AudioStreamPlayer = {"theme": ambience, "battle": music, "trace": trace_music}[name]
		if is_instance_valid(player) and name == scene_music: player.volume_db = _music_level(name)
