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
var echo_style := false
var material_cursor: Dictionary = {}
var last_cue: Dictionary = {}

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
	if echo_style:
		for name in ["timber_seat","timber_support","ward_knock","pottery_place","paper_rub_1","paper_rub_2","step_wood_1","step_wood_2","step_stone_1","step_stone_2","paper_fold","brush_sweep","erosion_gather","erosion_break","ink_settle"]:
			sounds[name] = load("res://assets/echo_v1/foley/"+name+".wav")
	for i in range(6):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -12
		add_child(voice)
		voices.append(voice)
	ambience = _loop("theme", _music_level("theme"))
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
	if echo_style: base -= 6.0
	return base - (8.0 if speech_active else 0.0)

func cue(name: String) -> void:
	if echo_style:
		var aliases := {"ui":"paper_fold","ui_page":"paper_fold","ui_wood":"ink_settle","brush_touch":"paper_rub","ink":"brush_sweep","repair":"timber_seat","hit":"erosion_break","win":"ink_settle"}
		name = str(aliases.get(name,name))
		var now := Time.get_ticks_msec()
		var interval := 260 if name.begins_with("step_") else (230 if name == "paper_rub" else 65)
		if now-int(last_cue.get(name,-10000)) < interval: return
		last_cue[name] = now
		if name in ["paper_rub","step_wood","step_stone"]:
			var variant := int(material_cursor.get(name,0))%2+1
			material_cursor[name] = variant
			name += "_%d" % variant
	if voices.is_empty() or not sounds.has(name): return
	var player: AudioStreamPlayer = voices[cursor % voices.size()]
	cursor += 1
	player.volume_db = (-22 if speech_active else -12) if echo_style else (-24 if speech_active else -16)
	if echo_style and name.begins_with("step_"): player.volume_db -= 6
	player.stream = sounds[name]
	player.play()

func duck(active: bool) -> void:
	speech_active = active
	for player in voices:
		player.volume_db = (-22 if active else -12) if echo_style else (-24 if active else -16)
		if echo_style and player.stream != null and "/step_" in player.stream.resource_path: player.volume_db -= 6
	for name in {"theme": ambience, "battle": music, "trace": trace_music}:
		var player: AudioStreamPlayer = {"theme": ambience, "battle": music, "trace": trace_music}[name]
		if is_instance_valid(player) and name == scene_music: player.volume_db = _music_level(name)
