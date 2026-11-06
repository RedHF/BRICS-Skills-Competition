extends SceneTree
## External recording director; never included in the shipped PCK. It issues
## real UI actions against the exported client and labels its automated input.
var main: Node
var game: SubViewport
var caption: Label
var origin := 0
var mode := ""
var cues: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if condition: return
	push_error(message)
	quit(98)

func _run() -> void:
	_check(OS.has_feature("movie"),"Movie Writer mode is required")
	game = SubViewport.new()
	game.size = Vector2i(1920,990)
	game.size_2d_override = Vector2i(1280,660)
	game.size_2d_override_stretch = true
	game.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game.gui_embed_subwindows = true
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
	mode = str(main.demo_mode)
	_check(mode in ["repair","choice"] and main.server_pid > 0,"Expected an isolated exported demo")
	origin = Engine.get_process_frames()
	_cue("片段一｜接梁：先承住，再接合" if mode == "repair" else "片段二｜取舍：看过回应，再作决定")
	await _until(2)
	await _press("开始接梁片段" if mode == "repair" else "开始取舍片段",main.front.overlay)
	if mode == "repair": await _repair()
	else: await _choice()
	var duration := 50 if mode == "repair" else 70
	await _until(duration)
	var record := {"kind":"exported-game-recording","mode":mode,"human_playtest":false,"input":"automated UI actions",
		"cut_start_frame":origin,"cut_duration_frames":duration*30,"fps":30,"movie_native_size":[1920,1080],
		"game_native_size":[1920,990],"caption_height":90,"cues":cues,"profile_root":main.profile_root}
	var file := FileAccess.open(OS.get_environment("YANXIA_MOVIE_RECORD"),FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"  "))
	file.close()
	print("PASS exported movie: "+mode)
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func _repair() -> void:
	_check(main.flow == "puzzle" and main.current_event.id == "temple_incense","Repair seed did not restore")
	var stage: Control = main.echo_stage
	var canvas: Control = stage.canvas
	await _until(4)
	_cue("接梁｜先核对余料上的旧痕，记号来自不同人家")
	await _press("旧痕与操作说明…")
	await _press("再看 · 余料记号")
	await _until(8)
	await _press("返回场景，继续 →")
	await _until(10)
	_cue("接梁｜先稳住梁，才开始安放木件")
	await _press("选用斗拱")
	await _until(12)
	await _click(canvas,canvas.support_rect.get_center())
	await _until(16)
	_cue("接梁｜斜痕对应右口；左右两端都能先装")
	await _click(canvas,canvas.piece_rects[1].get_center())
	await _until(19)
	await _click(canvas,canvas.slot_rects["SLOT-R"].get_center())
	await _until(23)
	_cue("接梁｜双短痕件需要转向，让凸榫朝向凹口")
	await _click(canvas,canvas.piece_rects[0].get_center())
	await _until(25)
	await _press("将所选木件转半圈 · R")
	await _until(28)
	await _click(canvas,canvas.slot_rects["SLOT-L"].get_center())
	await _until(32)
	_cue("接梁｜两端接住后，中部才能合拢")
	await _click(canvas,canvas.piece_rects[2].get_center())
	await _until(35)
	await _click(canvas,canvas.slot_rects["SLOT-C"].get_center())
	await _until(39)
	_cue("接梁｜撤下临撑，梁稳住了，旧拼缝仍在")
	await _press("撤下临撑")
	_check(stage.complete,"Repair was not completed")
	await _until(42)
	await main._resume()
	await _until(44)
	await _press("收入心舍")
	_cue("接梁｜这次抬梁的手影随身回应；实体修复另行保留")
	_check(main.echo_journey.held("she_cheng_xiang"),"Living labor memory was not retained")

func _choice() -> void:
	_check(main.flow == "choice" and main.current_event.id == "temple_drum","Choice seed did not restore")
	await _until(5)
	main.echo_journey._select("she_cheng_xiang")
	await _until(8)
	_cue("取舍｜确认前，可以先看一看旧回应")
	await _press("看看旧回应，再决定")
	await _until(14)
	await _press("重听这段回声")
	await _until(23)
	await _press("返回取舍")
	await _until(26)
	_cue("取舍｜新回声来自鼓边数拍的孩子")
	await _press("看看新回应")
	await _until(28)
	await _press("重听这段回声")
	await _until(36)
	await _press("返回取舍")
	await _until(40)
	_cue("取舍｜这次只留下新回声的记录，保留原有三段")
	await _press("只留下这段新回声的记录…")
	_check(main.archive_prompt.visible,"Archive confirmation is missing")
	await _until(46)
	main.archive_prompt.accept()
	await _idle()
	_check(not main.echo_journey.held("she_hui_chun"),"New child memory was not archived")
	await _until(52)
	await main._resume()
	_check(main.flow == "response","Physical drum response is missing")
	await _until(55)
	_cue("取舍｜亲手敲鼓：真实鼓声仍响起，独有的童声不再跟来")
	await _press("敲一下鼓")
	_check(main.echo_journey.preview.physical_audio.playing,"Physical drum is silent")
	_check(not main.echo_journey.preview.last_child_echo and not main.event_audio.playing,"Archived child still responds")
	await _until(62)
	await main._resume()
	_check(main.flow == "settlement" and int(root.get_node("GameState").player.capacity) == 4,"Capacity did not expand after the response")
	_cue("取舍｜事实、修复与技艺保留；心舍在章末展开一格")

func _until(second: int) -> void:
	while Engine.get_process_frames() < origin+second*30: await process_frame

func _cue(value: String) -> void:
	caption.text = value+"    · 实际程序节选／自动输入"
	cues.append({"frame":Engine.get_process_frames()-origin,"caption":value})

func _idle() -> void:
	await process_frame
	while main.busy: await process_frame
	await process_frame

func _press(title: String, node: Node = null) -> void:
	var parent: Node = main.page if node == null else node
	var found := _button(parent,title)
	_check(found != null,"Missing recording action: "+title)
	found.pressed.emit()
	await _idle()

func _button(node: Node, title: String) -> Button:
	if node is Button and node.text == title: return node
	for child in node.get_children():
		var found := _button(child,title)
		if found != null: return found
	return null

func _click(canvas: Control, point: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	canvas._gui_input(down)
	await _idle()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	canvas._gui_input(up)
	await _idle()
