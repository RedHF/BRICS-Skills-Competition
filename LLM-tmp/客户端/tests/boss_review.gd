extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(15).timeout.connect(func(): quit(99))
	var target := OS.get_environment("YANXIA_BOSS_SHOT")
	assert(not target.is_empty())
	var boss := load("res://assets/echo_v1/white_erosion_opera_boss.png") as Texture2D
	assert(boss != null and boss.get_width() == 1400 and boss.get_height() == 1700)
	var sound := load("res://assets/audio/boss_arrival.wav") as AudioStreamWAV
	assert(sound != null and sound.get_length() > 1.5)
	var arena = load("res://scripts/battle_arena.gd").new()
	arena.echo_style = true
	arena.boss_name = "白蚀·噤声客"
	arena.background = load("res://assets/landscape/opera_opening.jpeg")
	arena.hp = 620
	arena.max_hp = 620
	root.add_child(arena)
	arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.set_process(false)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	assert(root.get_texture().get_image().save_png(target) == OK)
	print("PASS boss sprite and audio loaded; image=", target)
	arena.queue_free()
	await create_timer(.2).timeout
	quit(0)
