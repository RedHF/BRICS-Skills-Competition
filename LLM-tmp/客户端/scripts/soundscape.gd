extends Node

var ambience: AudioStreamPlayer
var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var cursor := 0
var sounds := {}

func _exit_tree() -> void:
	stop_all()

func stop_all() -> void:
	for player in voices + [ambience, music]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	sounds.clear()

func _ready() -> void:
	for name in ["ui", "ink", "repair", "hit", "win"]:
		sounds[name] = load("res://assets/audio/" + name + ".wav")
	for i in range(6):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -12
		add_child(voice)
		voices.append(voice)
	ambience = _loop("ambience", -24)
	music = _loop("battle", -19)
	music.stream_paused = true

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
	if not is_instance_valid(music): return
	music.stream_paused = not active
	ambience.stream_paused = active

func cue(name: String) -> void:
	if voices.is_empty() or not sounds.has(name): return
	var player: AudioStreamPlayer = voices[cursor % voices.size()]
	cursor += 1
	player.stream = sounds[name]
	player.play()
