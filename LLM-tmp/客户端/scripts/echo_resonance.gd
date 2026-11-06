extends Control
## A remembered layer can retire without changing the underlying room or bowl.
signal drum_pressed

var host: Node
var memory_id := ""
var living := false
var retiring := false
var interactive := false
var strength := 0.0
var elapsed := 0.0
var age := 0.0
var pulse := -5.0
var last_child_echo := false
var picture: Texture2D
var bowl: Texture2D
var physical_audio: AudioStreamPlayer
var image_rect := Rect2()
var bowl_point := Vector2(.60,.81)

func _ready() -> void:
	custom_minimum_size = Vector2(520,350)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	var events := {"yan_ping_an":"prologue_bridge", "she_cheng_xiang":"temple_incense", "she_ning_an":"temple_guest", "she_hui_chun":"temple_drum"}
	picture = host._event_background(str(events.get(memory_id,host.current_event.id)))
	bowl = load("res://assets/echo_v1/empty_bowl.png")
	var result: Dictionary = GameState.player.completed_events.get("temple:temple_guest",{})
	if result.get("stage_placements") is Dictionary and result.stage_placements.has("guest_place"):
		bowl_point = Vector2(result.stage_placements.guest_place[0],result.stage_placements.guest_place[1])
	elif str(host.current_event.id) == "temple_guest" and GameState.session.get("stage_placements") is Dictionary and GameState.session.stage_placements.has("guest_place"):
		bowl_point = Vector2(GameState.session.stage_placements.guest_place[0],GameState.session.stage_placements.guest_place[1])
	physical_audio = AudioStreamPlayer.new()
	physical_audio.stream = load("res://assets/echo_v1/foley/drum_body.wav")
	physical_audio.volume_db = -9
	add_child(physical_audio)
	strength = 1.0 if living or retiring else 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	age += delta
	if not host.reduced_motion: elapsed += delta
	pulse += delta
	strength = (0.0 if host.reduced_motion else maxf(0,1.0-age/1.2)) if retiring else (1.0 if living else 0.0)
	queue_redraw()

func _exit_tree() -> void:
	if is_instance_valid(physical_audio):
		physical_audio.stop()
		physical_audio.stream = null

func _point(p: Vector2) -> Vector2:
	return image_rect.position+p*image_rect.size

func _glow(point: Vector2, radius: float, alpha: float) -> void:
	for i in range(8,0,-1):
		draw_circle(point,radius*float(i)/8,Color(.96,.76,.43,alpha*.045))

func _draw() -> void:
	if picture == null: return
	var extent := picture.get_size()
	var factor := minf(size.x/extent.x,size.y/extent.y)
	image_rect = Rect2((size-extent*factor)*.5,extent*factor)
	if memory_id == "she_cheng_xiang":
		preload("res://scripts/echo_hall.gd").paint(self,image_rect)
		preload("res://scripts/echo_props.gd").remembered_hands(self,image_rect,strength)
	else:
		draw_texture_rect(picture,image_rect,false)
		var event_id := "temple_guest" if memory_id == "she_ning_an" else ("temple_drum" if memory_id == "she_hui_chun" else "")
		preload("res://scripts/echo_props.gd").paint(self,image_rect,event_id)
	var alpha := strength*(.68+.16*sin(elapsed*2.2))
	if memory_id == "she_ning_an":
		var p := _point(bowl_point)
		# The same physical bowl is drawn in both states and at the saved point.
		var width := image_rect.size.x*.105
		draw_texture_rect(bowl,Rect2(p-Vector2(width*.5,width*.522),Vector2(width,width*.674)),false)
		_glow(p-Vector2(0,width*.15),width*.52,alpha)
	elif memory_id == "she_cheng_xiang":
		pass
	elif memory_id == "yan_ping_an":
		for i in range(5):
			var p := _point(Vector2(.50+float(i)*.018,.77-float(i)*.058))
			var phase := fmod(elapsed*.8+float(i)*.22,1.0)
			_glow(p+Vector2(-5 if i%2 == 0 else 5,0),13,alpha*(1-phase))
	elif memory_id == "she_hui_chun":
		var center := _point(Vector2(.48,.47))
		if interactive and pulse >= 0 and pulse < 1.1:
			var a := 1-pulse/1.1
			draw_arc(center,22+pulse*90,0,TAU,72,Color(.87,.84,.75,a*.8),2,true)
		if strength > 0:
			for i in range(3):
				var p := _point(Vector2(.34+float(i)*.12,.81))
				var a := alpha*(.55+.45*sin(elapsed*3.5-float(i)))
				_glow(p,18,a)
				if interactive and last_child_echo and pulse > .3+float(i)*.2 and pulse < .9+float(i)*.2:
					draw_arc(p,12+(pulse-.3-float(i)*.2)*20,0,TAU,32,Color(.96,.78,.48,a),1.5,true)
	if interactive:
		var center := _point(Vector2(.48,.47))
		draw_arc(center,30,0,TAU,64,Color("#c9ac70"),1.5,true)
		var font := preload("res://scripts/ink_theme.gd").font()
		draw_string(font,center+Vector2(-70,58),"点一下，敲响鼓",HORIZONTAL_ALIGNMENT_CENTER,140,18,Color("#efe5cd"))

func sound_drum(child_echo: bool) -> void:
	last_child_echo = child_echo
	living = child_echo
	pulse = 0.0
	physical_audio.play()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not interactive or host.busy: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var target := _point(Vector2(.48,.47))
		if event.position.distance_to(target) < image_rect.size.x*.19: drum_pressed.emit()
