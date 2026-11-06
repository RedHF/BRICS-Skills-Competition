extends SceneTree
## Short, labelled automated input against the exported game. Never shipped.
var main: Node
var game: SubViewport
var caption: Label
var origin := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if ok: return
	push_error(message)
	quit(98)

func _until(seconds: float) -> void:
	while Engine.get_process_frames() < origin+roundi(seconds*30): await process_frame

func _run() -> void:
	_check(OS.has_feature("movie"),"Use native Movie Writer")
	game = SubViewport.new()
	game.size = Vector2i(1920,990)
	game.size_2d_override = Vector2i(1280,660)
	game.size_2d_override_stretch = true
	game.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(game)
	var screen := TextureRect.new()
	screen.position = Vector2(0,90)
	screen.size = Vector2(1920,990)
	screen.texture = game.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(screen)
	var bar := ColorRect.new()
	bar.size = Vector2(1920,90)
	bar.color = Color("#eee5d4")
	root.add_child(bar)
	caption = Label.new()
	caption.position = Vector2(36,15)
	caption.size = Vector2(1848,60)
	caption.add_theme_font_override("font",load("res://assets/fonts/NotoSerifSC-Regular.ttf"))
	caption.add_theme_font_size_override("font_size",30)
	caption.add_theme_color_override("font_color",Color("#302c28"))
	root.add_child(caption)
	main = load("res://scenes/main.tscn").instantiate()
	game.add_child(main)
	while main.flow != "welcome" or main.busy: await process_frame
	_check(main._is_echo() and main.server_pid > 0,"Expected isolated exported game")
	main._open_event("prologue","prologue_bridge")
	main._finish_dialogue()
	_check(main.flow == "intro","Expected the actual investigation scene")
	origin = Engine.get_process_frames()
	caption.text = "A12 行走检查｜站立 → 迈步 → 停步 → 转向 · 实际程序／自动输入"
	await _until(1.0)
	Input.action_press("move_right")
	await _until(2.6)
	Input.action_release("move_right")
	await _until(3.3)
	Input.action_press("move_left")
	await _until(5.7)
	Input.action_release("move_left")
	await _until(6.5)
	Input.action_press("move_right")
	await _until(7.3)
	Input.action_release("move_right")
	await _until(8.0)
	_check(not main.scene_view.character_moving,"Character did not stop")
	caption.text = "A12 行走检查｜脚步随移动触发；停步后停止 · 实际程序／自动输入"
	await _until(9.0)
	var file := FileAccess.open(OS.get_environment("YANXIA_WALK_RECORD"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"human_playtest":false,"input":"automated movement actions", "cut_start_frame":origin,"duration_frames":270,"fps":30},"  "))
	file.close()
	print("PASS exported walking movie")
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
