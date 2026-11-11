extends SceneTree
## Deterministic movement checks independent of server, save and frame rate.

func _check(ok: bool) -> void:
	if not ok:
		push_error("Movement regression failed")
		quit(98)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var figure = preload("res://scripts/echo_figure.gd")
	figure.prepare()
	for i in range(8):
		_check(figure.walk_frames[i].region == Rect2(Vector2(i%4,floori(i/4.0))*Vector2(384,512),Vector2(384,512)))
	var scene = preload("res://scripts/building_scene.gd").new()
	scene.interactive = true
	scene.echo_style = true
	scene.size = Vector2(800,450)
	root.add_child(scene)
	scene.set_process(false)
	var arena = preload("res://scripts/battle_arena.gd").new()
	arena.echo_style = true
	arena.active = true
	arena.size = Vector2(800,450)
	root.add_child(arena)
	arena.set_process(false)
	# Previously sub-threshold input could repeatedly flip idle/walk and facing.
	for i in range(120):
		scene.joystick = Vector2(.03 if i%2 == 0 else -.03,0)
		arena.joystick = scene.joystick
		scene._process(1.0/240.0)
		arena._process(1.0/240.0)
		_check(not scene.character_moving and not arena.character_moving)
		_check(not scene.character_facing_left and not arena.character_facing_left)
	_check(scene.walk_time == 0 and arena.walk_time == 0)
	scene.joystick = Vector2.ZERO
	arena.joystick = Vector2.ZERO
	Input.action_press("move_right")
	for i in range(120):
		var before: Vector2 = scene.player
		scene._process(1.0/240.0)
		arena._process(1.0/240.0)
		_check(scene.character_moving and arena.character_moving)
		_check(scene.player.x > before.x)
	_check(is_equal_approx(scene.walk_blend,1) and is_equal_approx(arena.walk_blend,1))
	Input.action_release("move_right")
	var stopped: float = scene.walk_time
	for i in range(30):
		scene._process(1.0/240.0)
		arena._process(1.0/240.0)
	_check(not scene.character_moving and scene.walk_time == stopped)
	_check(scene.walk_blend == 0 and arena.walk_blend == 0)
	# Manual input at the edge must not leave a target outside the play area.
	scene.player.x = .95
	scene.target = scene.player
	Input.action_press("move_right")
	scene._process(.1)
	Input.action_release("move_right")
	_check(scene.target == scene.player)
	scene._process(.1)
	_check(not scene.character_moving)
	# Click-to-move arrives once and stays still; reversal follows actual travel.
	scene.target = scene.player-Vector2(.1,0)
	for i in range(180): scene._process(1.0/240.0)
	_check(scene.player == scene.target and scene.character_facing_left)
	scene._process(.1)
	_check(not scene.character_moving and scene.walk_blend == 0)
	await process_frame
	print("PASS movement: 240Hz travel, joystick noise, gradual start/stop, edge target, click arrival, facing and eight atlas regions")
	scene.queue_free()
	arena.queue_free()
	await process_frame
	figure.release()
	quit(0)
