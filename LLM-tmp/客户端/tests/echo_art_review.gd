extends SceneTree

class ReferenceBoard extends Control:
	var font: Font
	var textures: Dictionary = {}

	func _ready() -> void:
		font = preload("res://scripts/ink_theme.gd").font()
		for item in ["temple_hall_master","artisan_standing","artisan_walking","artisan_casting","empty_bowl","drum_face"]:
			textures[item] = load("res://assets/echo_v1/" + item + ".png")
		textures["rubbing"] = load("res://assets/rubbings/she_cheng_xiang.png")
		textures["ink"] = load("res://assets/ink_ui/ink.png")
		queue_redraw()

	func words(at: Vector2, value: String, font_size: int = 24, color: Color = Color("#302c28")) -> void:
		draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

	func art(id: String, rect: Rect2) -> void:
		var texture: Texture2D = textures[id]
		var extent := texture.get_size()
		var factor := minf(rect.size.x/extent.x,rect.size.y/extent.y)
		draw_texture_rect(texture,Rect2(rect.get_center()-extent*factor*.5,extent*factor),false)

	func _draw() -> void:
		if textures.is_empty(): return
		draw_rect(Rect2(0,0,1920,1080),Color("#f0e9dc"))
		words(Vector2(50,75),"檐下千秋 · 回响版美术基准",42)
		words(Vector2(52,120),"沿用既有的水墨古建、旧木、纸墨与成年拓印师；暖色落在人使用过的痕迹上。",25)
		art("temple_hall_master",Rect2(50,160,900,510))
		words(Vector2(54,710),"环境：原构图参考编辑 · 灰黑旧木、米灰墙面",25)
		art("empty_bowl",Rect2(65,750,240,200))
		art("drum_face",Rect2(350,750,230,230))
		art("rubbing",Rect2(650,750,180,230))
		words(Vector2(80,1005),"旧陶空碗",23)
		words(Vector2(375,1005),"鼓面旧纹",23)
		words(Vector2(650,1005),"沿用原拓片",23)
		draw_line(Vector2(985,160),Vector2(985,1010),Color("#b9ab92"),1)
		art("artisan_standing",Rect2(1010,170,475,805))
		words(Vector2(1510,225),"人物身份",30)
		words(Vector2(1510,270),"同一发束与头带",24)
		words(Vector2(1510,310),"墨黑外袍、米白衣片",24)
		words(Vector2(1510,350),"右手长笔、左手谱册",24)
		words(Vector2(1510,390),"正常头身、完整双脚",24)
		words(Vector2(1510,465),"界面与用色",30)
		var palette := ["#302c28","#85796b","#eee5d4","#a34838","#b99a5c"]
		for i in range(palette.size()): draw_rect(Rect2(1510+i*66,500,52,52),Color(palette[i]))
		words(Vector2(1510,592),"炭墨 / 暖灰 / 纸白",23)
		words(Vector2(1510,630),"朱色 / 克制的暖金",23)
		draw_texture_rect(textures["ink"],Rect2(1505,680,340,68),false)
		words(Vector2(1540,724),"沿用墨刷按钮",22,Color("#eee5d4"))
		art("artisan_walking",Rect2(1500,760,150,220))
		art("artisan_casting",Rect2(1680,760,150,220))
		words(Vector2(1538,1008),"行走",21)
		words(Vector2(1718,1008),"抬笔",21)
		words(Vector2(55,1050),"参考板由现有与已生成资产排版；三关键姿态已接入回响版。此图不作为实机玩法截图。",20)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(20).timeout.connect(func(): quit(99))
	var surface := SubViewport.new()
	surface.size = Vector2i(1920,1080)
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(surface)
	var board := ReferenceBoard.new()
	surface.add_child(board)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	var target := OS.get_environment("YANXIA_ART_BOARD")
	assert(not target.is_empty())
	var snapshot := surface.get_texture().get_image()
	assert(snapshot.get_size() == Vector2i(1920,1080),"Art board was clamped by the window manager")
	assert(snapshot.save_png(target) == OK)
	print("PASS art reference board: 1920x1080 layout, existing materials and generated adult reference; no runtime-animation claim")
	quit(0)
