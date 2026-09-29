extends "res://tests/review_journey.gd"

var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(99))
	shots = OS.get_environment("YANXIA_REVIEW_SHOTS")
	DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://scenes/main.tscn").instantiate()
	main.network.base_url = "http://127.0.0.1:18093"
	root.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	main._show_map()
	main.set_process(false)
	game = root.get_node("GameState")
	# Exercise the actual investigation button and all ten stories without changing saves.
	for chapter in main.data.catalog.chapters:
		for event in chapter.events:
			if event.draft: continue
			main.chapter_id = chapter.id
			main.current_event = event
			main._show_investigation()
			var original = main.scene_view
			for i in range(original.investigations.size()): original._discover(i)
			await process_frame
			var readers = main.page.find_children("*", "VBoxContainer", true, false).filter(func(node): return node.get_script() == load("res://scripts/story_reader.gd"))
			check(readers.size() == 1, "Story reader missing/duplicated")
			var reader = readers[0]
			await create_timer(.15).timeout
			await click(button("聆听往事"))
			if not reader.panel.visible: await capture("failed-" + str(event.id))
			check(reader.panel.visible, "Story click did not open text: " + str(event.id))
			for i in range(event.story.beats.size()):
				reader.show_beat(i)
				check(reader.caption.text == event.story.beats[i], "Story text mismatch")
				check(main.event_audio.playing, "Story voice unavailable")
			check(reader.following.disabled, "Last story page can overflow")
			reader.show_beat(0)
			if event.id == "prologue_bridge": await capture("01-story-reader")
			await click(button("收起往事"))
			check(main.scene_view == original and original.discovered.size() == original.investigations.size(), "Story erased investigation")
			check(not reader.panel.visible and not main.event_audio.playing, "Story did not stop")
	main.chapter_id = "opera"
	main.current_event = main.data.event("opera", "opera_opening")
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
		var hp: int = main.arena.hp
		main._battle_skill(skill)
		check(main.arena.effects.size() == 1, "Skill has no effect: " + skill)
		check(main.arena.hp == hp - int(main.data.catalog.skills[skill].damage), "Damage mismatch")
		main.arena._process(.28)
		main.arena.queue_redraw()
		await capture("02-skill-" + str(main.BATTLE_KEYS.find(skill)))
		var actions: int = main.battle_actions.size()
		main._battle_skill(skill)
		check(main.battle_actions.size() == actions, "Cooldown ignored")
	main.arena.effects.clear()
	main.arena.enemy_strike(true)
	main.arena._process(.3)
	await capture("03-block")
	main.arena.effects.clear()
	main.arena.enemy_strike(false)
	main.arena._process(.3)
	await capture("04-hit")
	main.arena.effects.clear()
	main.arena.disperse()
	main.arena.defeated = true
	main.arena._process(.4)
	await capture("05-dispersal")
	main.arena._process(2)
	check(main.arena.effects.is_empty(), "Expired effects leaked")
	var texture = load("res://scripts/ink_figure.gd").texture.get_image()
	check(texture.get_pixel(0, 0).a == 0, "Character backdrop remains")
	check(texture.get_pixel(168, 220).a > .9, "Character interior erased")
	print("PASS story/combat/artisan checks=", checks)
	main.queue_free()
	await create_timer(.3).timeout
	quit(0)
