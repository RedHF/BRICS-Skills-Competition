extends SceneTree

class Observer extends Node:
	var main
	func _input(event: InputEvent) -> void:
		if event is InputEventKey:
			print("KEY code=",event.keycode," physical=",event.physical_keycode," pressed=",event.pressed," advance=",event.is_action("advance")," pos=",main.scene_view.player," points=",main.scene_view.investigations)
	func _process(_delta: float) -> void:
		if Input.is_action_just_pressed("advance"):
			print("PROCESS advance; discovered=",main.scene_view.discovered)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while main.flow != "map" or main.busy: await process_frame
	main._open_event("prologue","prologue_bridge")
	main._finish_dialogue()
	main.scene_view.player = Vector2(.28,.44)
	main.scene_view.target = main.scene_view.player
	var observer := Observer.new()
	observer.main = main
	root.add_child(observer)
	print("READY manual keyboard probe, player beside first clue")
