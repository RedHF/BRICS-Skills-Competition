extends SceneTree

var main: Node
var shots := ""
const FIGURE = preload("res://scripts/ink_figure.gd")

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	main._show_map()
	main.set_process(false)
	main.chapter_id = "prologue"
	main.current_event = main.data.event("prologue", "prologue_bridge")
	main._show_investigation()
	var building = main.scene_view
	building.set_process(false)
	var before: Vector2 = building.player
	Input.action_press("move_right")
	building._process(.1)
	Input.action_release("move_right")
	assert(building.character_moving and building.player.x > before.x, "Exploration movement did not activate walk frames")
	await capture("exploration-walk")
	building._process(.1)
	assert(not building.character_moving, "Exploration did not return to idle")
	main._start_battle()
	main._begin_battle()
	var arena = main.arena
	arena.set_process(false)
	before = arena.player_position
	Input.action_press("move_left")
	arena._process(.1)
	Input.action_release("move_left")
	assert(arena.character_moving and arena.character_facing_left and arena.player_position.x < before.x, "Battle walk or facing did not follow input")
	await capture("battle-walk-left")
	arena._process(.1)
	assert(not arena.character_moving, "Battle did not return to idle")
	arena.character_facing_left = false
	for action in ["walk", "attack", "hurt"]:
		assert(FIGURE.frames[action].size() == 6)
		var hashes := {}
		for i in range(6):
			assert(FIGURE.frame_index(action, float(i) / 10.0, 1.0 - float(i) / 6.0) == i, "Action skipped a frame boundary")
			var image: Image = FIGURE.frames[action][i].get_image()
			if image.is_compressed(): image.decompress()
			assert(image.get_pixel(0, 0).a == 0 and image.get_used_rect().has_area())
			hashes[hash(image.get_data())] = true
			arena.pose = action
			arena.pose_time = .45 * (1.0 - float(i) / 6.0)
			arena.motion_time = float(i) / 10.0
			arena.queue_redraw()
			await capture(action + "-" + str(i))
		assert(hashes.size() == 6, "Repeated or missing action frames: " + action)
	arena.cast("挥墨", "挥墨", Color.WHITE)
	assert(arena.pose == "attack" and arena.pose_time > 0)
	arena.enemy_strike(false)
	assert(arena.pose == "hurt" and arena.pose_time > 0)
	arena._process(.6)
	assert(arena.pose_time == 0, "Completed action did not return to idle")
	print("PASS character animation: exploration/battle input, left facing, 18 distinct transparent frames, attack/hurt dispatch and idle recovery")
	main.queue_free()
	await create_timer(.3).timeout
	quit(0)
