extends SceneTree

var main: Node
var checks := 0
var shots := ""

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _run() -> void:
	create_timer(45).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	DirAccess.make_dir_recursive_absolute(shots)
	for asset_name in ["ink_slash", "dougong_ward", "caisson_rosette", "flying_blades", "dodge_smoke", "erosion_burst"]:
		var visual = load("res://assets/vfx/" + asset_name + ".png") as Texture2D
		check(visual != null, "Missing generated VFX: " + asset_name)
		var image = visual.get_image()
		check(image.get_pixel(0, 0).a == 0 and image.get_used_rect().has_area(), "VFX transparency: " + asset_name)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	main._show_map()
	main.set_process(false)
	main.chapter_id = "opera"
	main.current_event = main.data.event("opera", "opera_opening")
	var game = root.get_node("GameState")
	game.player.memory_ledger = []
	for memory_id in main.data.catalog.memories:
		game.player.memory_ledger.append({"memory_id": memory_id, "action": "kept"})
	game.session = {}
	main._start_battle()
	main._begin_battle()
	await process_frame
	main.arena.set_process(false)
	for skill in main.BATTLE_KEYS:
		main.arena.effects.clear()
		main.battle_ready[skill] = 0
		main.battle_elapsed += 1
		var before_hp: int = main.arena.hp
		main._battle_skill(skill)
		check(main.arena.effects.size() == 1, "No VFX for " + skill)
		check(main.arena.hp == before_hp - int(main.data.catalog.skills[skill].damage), "Damage changed for " + skill)
		main.arena._process(.24)
		await capture("skill-" + str(main.BATTLE_KEYS.find(skill)))
	main.arena.effects.clear()
	main.arena.enemy_strike(true)
	main.arena._process(.24)
	await capture("block")
	main.arena.effects.clear()
	main.arena.enemy_strike(false)
	main.arena._process(.24)
	await capture("hit")
	main.arena.effects.clear()
	main.arena.disperse()
	main.arena.defeated = true
	main.arena._process(.24)
	await capture("disperse")
	print("PASS generated VFX checks=", checks)
	main.queue_free()
	await create_timer(.2).timeout
	quit(0)
