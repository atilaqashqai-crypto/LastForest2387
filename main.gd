extends Node3D

var tid := -1
var start := Vector2.ZERO
var player: CharacterBody3D = null
var enter_btn: Button = null
var pause_btn: Button = null
var camera_btn: Button = null
var build_btn: Button = null
var build_menu: Panel = null
var build_system: Node = null
var pause_panel: Panel = null
const PLAYER_SCENE := preload("res://player.tscn")
const UIStyleScript := preload("res://ui_style.gd")

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size

func _half() -> float:
	return _vp().x / 2.0

func _ready() -> void:
	if Network.is_dedicated:
		# Dedicated server: no screen, no buttons, no local player.
		_setup_multiplayer()
		return
	if Network.is_online and multiplayer.multiplayer_peer != null:
		_setup_multiplayer()
	else:
		player = $Player as CharacterBody3D
	_setup_jump_button()
	if player:
		_make_btn("Sprint", Vector2(30, _vp().y - 280), player.sprint)
		_make_btn("Shoot", Vector2(_vp().x - 230, _vp().y - 280), player.shoot)
		_make_btn("Switch", Vector2(_vp().x - 230, _vp().y - 180), player.switch_item)
	_make_enter_exit_button()
	_make_build_button()
	call_deferred("_place_enter_btn")
	_make_pause_button()
	_make_camera_button()

func _setup_multiplayer() -> void:
	# Remove the single-player placeholder if present
	var old = get_node_or_null("Player")
	if old:
		old.queue_free()
	# Server -> clients zombie sync (same node path on every peer)
	var zs := Node.new()
	zs.name = "ZombieSync"
	zs.set_script(load("res://zombie_sync.gd"))
	add_child(zs)
	var bsync := Node.new()
	bsync.name = "BuildSync"
	bsync.set_script(load("res://build_sync.gd"))
	add_child(bsync)
	# Players can join or leave at any time: keep avatars in sync with the roster.
	Network.players_changed.connect(_sync_player_nodes)
	_sync_player_nodes()

func _sync_player_nodes() -> void:
	var ids: Array = Network.players.keys()
	var my_id := multiplayer.get_unique_id()
	if not Network.is_dedicated and not ids.has(my_id):
		ids.append(my_id)
	ids.sort()
	for id in ids:
		if get_node_or_null("Player_%d" % int(id)) == null:
			_spawn_player(int(id))

func _spawn_player(id: int) -> void:
	var p: CharacterBody3D = PLAYER_SCENE.instantiate()
	p.name = "Player_%d" % id
	p.peer_id = id
	var info = Network.players.get(id, {})
	p.outfit_color = Network.color_from_info(info) if info else Network._color_for_id(id)
	p.player_name = str(info.get("name", "Player %d" % id))
	# Spread spawn a bit so they don't stack
	p.position = Vector3(float(abs(id) % 6) * 2.5, 3.0, 0.0)
	add_child(p)
	# Only the local player gets inventory/combat (server and remote avatars do not)
	if id == multiplayer.get_unique_id() and not Network.is_dedicated:
		player = p
		_attach_player_modules(p)

func _attach_player_modules(p: Node) -> void:
	if p.get_node_or_null("Inventory") == null:
		var inv := Node.new()
		inv.name = "Inventory"
		inv.set_script(load("res://inventory.gd"))
		p.add_child(inv)
	if p.get_node_or_null("Combat") == null:
		var combat := Node.new()
		combat.name = "Combat"
		combat.set_script(load("res://combat.gd"))
		p.add_child(combat)

func _make_build_button() -> void:
	build_system = Node.new()
	build_system.name = "BuildSystem"
	build_system.set_script(load("res://build_system.gd"))
	add_child(build_system)

	build_btn = Button.new()
	$CanvasLayer.add_child(build_btn)
	build_btn.text = "Build"
	build_btn.size = Vector2(150, 56)
	build_btn.z_index = 22
	build_btn.pressed.connect(_on_build_button_pressed)
	UIStyleScript.apply_button(build_btn, "build")

	build_menu = Panel.new()
	$CanvasLayer.add_child(build_menu)
	build_menu.size = Vector2(210, 230)
	build_menu.z_index = 24
	build_menu.visible = false
	UIStyleScript.apply_panel(build_menu)
	var menu_box := VBoxContainer.new()
	menu_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_box.add_theme_constant_override("separation", 6)
	menu_box.offset_left = 8
	menu_box.offset_top = 8
	menu_box.offset_right = -8
	menu_box.offset_bottom = -8
	build_menu.add_child(menu_box)

	var cabin_option := Button.new()
	cabin_option.text = "Cabin  •  5 logs"
	cabin_option.custom_minimum_size = Vector2(0, 62)
	cabin_option.pressed.connect(_select_cabin_to_build)
	UIStyleScript.apply_button(cabin_option, "default")
	menu_box.add_child(cabin_option)

	var fence_option := Button.new()
	fence_option.text = "Farm Fence  •  1 log"
	fence_option.custom_minimum_size = Vector2(0, 62)
	fence_option.pressed.connect(_select_fence_to_build)
	UIStyleScript.apply_button(fence_option, "sprint")
	menu_box.add_child(fence_option)

	var fire_option := Button.new()
	fire_option.text = "Fire  •  1 log"
	fire_option.custom_minimum_size = Vector2(0, 62)
	fire_option.pressed.connect(_select_fire_to_build)
	UIStyleScript.apply_button(fire_option, "shoot")
	menu_box.add_child(fire_option)

	_position_build_ui()

func _position_build_ui() -> void:
	if build_btn == null:
		return
	var vp := _vp()
	build_btn.position = Vector2(vp.x * 0.5 - 75.0, 14.0)
	if build_menu != null:
		build_menu.position = Vector2(vp.x * 0.5 - 105.0, 76.0)

func _on_build_button_pressed() -> void:
	if build_system == null or not is_instance_valid(player):
		return
	if bool(build_system.get("is_placing")):
		build_system.call("confirm_placement", player)
		_update_build_button()
	else:
		build_menu.visible = not build_menu.visible

func _select_cabin_to_build() -> void:
	_start_build_placement("cabin")

func _select_fence_to_build() -> void:
	_start_build_placement("fence")

func _select_fire_to_build() -> void:
	_start_build_placement("fire")

func _start_build_placement(kind: String) -> void:
	if build_system == null or not is_instance_valid(player):
		return
	build_menu.visible = false
	build_system.call("toggle_placement", player, kind)
	_update_build_button()

func _update_build_button() -> void:
	if build_btn == null or build_system == null:
		return
	build_btn.text = "Place Blueprint" if bool(build_system.get("is_placing")) else "Build"

func _make_enter_exit_button() -> void:
	enter_btn = Button.new()
	$CanvasLayer.add_child(enter_btn)
	enter_btn.text = "Enter/Exit"
	enter_btn.custom_minimum_size = Vector2(200, 84)
	enter_btn.size = Vector2(200, 84)
	enter_btn.pressed.connect(_on_enter_exit)
	UIStyleScript.apply_button(enter_btn, "action")

func _place_enter_btn() -> void:
	if enter_btn == null:
		return
	var vp := _vp()
	enter_btn.size = Vector2(200, 84)
	enter_btn.position = Vector2(vp.x * 0.5 - 100.0, vp.y - 110.0)
	enter_btn.z_index = 20

func _on_enter_exit() -> void:
	if not is_instance_valid(player):
		return
	player.use_item()
	_update_vehicle_camera()

func _update_vehicle_camera() -> void:
	if not is_instance_valid(player):
		return
	var arm = player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	if arm == null:
		return
	if player.current_vehicle != null:
		arm.spring_length = 9.0
	else:
		# Preserve the selected camera mode when Enter/Exit is pressed on foot.
		arm.spring_length = 0.05 if player.is_first_person else 4.0

func _setup_jump_button() -> void:
	var b: Button = $CanvasLayer/JumpButton
	b.size = Vector2(180, 80)
	b.position = Vector2(30, _vp().y - 180)
	UIStyleScript.apply_button(b, "default")
	if player:
		b.pressed.connect(player.jump)

func _make_btn(txt: String, pos: Vector2, fn: Callable) -> Button:
	var b := Button.new()
	$CanvasLayer.add_child(b)
	b.text = txt
	b.size = Vector2(180, 80)
	b.position = pos
	b.pressed.connect(fn)
	var kind := "default"
	if txt == "Shoot":
		kind = "shoot"
	elif txt == "Sprint":
		kind = "sprint"
	elif txt == "Switch":
		kind = "action"
	UIStyleScript.apply_button(b, kind)
	return b

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_press(e)
		_release(e)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenDrag:
		_drag(e)
		_look(e)
	if e is InputEventKey and e.pressed and e.keycode == KEY_E:
		call_deferred("_update_vehicle_camera")

func _press(e: InputEventScreenTouch) -> void:
	if e.pressed and tid == -1 and e.position.x < _half():
		tid = e.index
		start = e.position

func _release(e: InputEventScreenTouch) -> void:
	if not e.pressed and e.index == tid:
		tid = -1
		if is_instance_valid(player):
			player.move_input = Vector2.ZERO
			player.sprinting = false

func _drag(e: InputEventScreenDrag) -> void:
	if e.index == tid and is_instance_valid(player):
		player.move_input = ((e.position - start) / 100.0).limit_length(1.0)

func _look(e: InputEventScreenDrag) -> void:
	if e.index != tid and is_instance_valid(player):
		if e.position.x > _half():
			player.rotate_cam(e.relative)

var spawn_timer := 28.0
var max_zombies := 0

func _process(_delta: float) -> void:
	if enter_btn:
		var vp := _vp()
		enter_btn.position = Vector2(vp.x * 0.5 - 100.0, vp.y - 110.0)
	if pause_btn:
		var vp2 := _vp()
		pause_btn.position = Vector2(vp2.x - 145.0, 64.0)
	if camera_btn:
		var vp3 := _vp()
		camera_btn.position = Vector2(vp3.x - 145.0, 12.0)
		camera_btn.disabled = not is_instance_valid(player) or player.current_vehicle != null
		if is_instance_valid(player):
			camera_btn.text = "Camera: 1P" if player.is_first_person else "Camera: 3P"
	if build_btn:
		_position_build_ui()
		_update_build_button()

func _spawn_zombie() -> void:
	pass


func _make_pause_button() -> void:
	pause_btn = Button.new()
	$CanvasLayer.add_child(pause_btn)
	pause_btn.text = "Settings"
	pause_btn.size = Vector2(130, 44)
	pause_btn.custom_minimum_size = Vector2(130, 44)
	pause_btn.z_index = 30
	pause_btn.pressed.connect(_toggle_pause_panel)
	UIStyleScript.apply_button(pause_btn, "default")
	_build_pause_panel()
	var vp := _vp()
	pause_btn.position = Vector2(vp.x - 145.0, 64.0)

func _make_camera_button() -> void:
	camera_btn = Button.new()
	$CanvasLayer.add_child(camera_btn)
	camera_btn.text = "Camera: 3P"
	camera_btn.size = Vector2(130, 44)
	camera_btn.custom_minimum_size = Vector2(130, 44)
	camera_btn.z_index = 30
	camera_btn.pressed.connect(_toggle_camera_mode)
	UIStyleScript.apply_button(camera_btn, "action")
	var vp := _vp()
	camera_btn.position = Vector2(vp.x - 145.0, 12.0)

func _toggle_camera_mode() -> void:
	if not is_instance_valid(player) or player.current_vehicle != null:
		return
	player.toggle_camera_mode()
	if camera_btn:
		camera_btn.text = "Camera: 1P" if player.is_first_person else "Camera: 3P"

func _build_pause_panel() -> void:
	pause_panel = Panel.new()
	pause_panel.visible = false
	pause_panel.z_index = 40
	$CanvasLayer.add_child(pause_panel)
	pause_panel.size = Vector2(320, 300)
	UIStyleScript.apply_panel(pause_panel)
	var vp := _vp()
	pause_panel.position = Vector2(vp.x * 0.5 - 160.0, vp.y * 0.5 - 150.0)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	pause_panel.add_child(vbox)
	# margins via offset
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.offset_right = -16
	vbox.offset_bottom = -16

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var vol_l := Label.new()
	vol_l.text = "Volume"
	vbox.add_child(vol_l)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = GameSettings.master_volume
	slider.value_changed.connect(func(v): GameSettings.set_volume(v))
	vbox.add_child(slider)

	var gfx_l := Label.new()
	gfx_l.text = "Graphics"
	vbox.add_child(gfx_l)

	var row := HBoxContainer.new()
	vbox.add_child(row)
	var med := Button.new()
	med.text = "Medium"
	med.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	med.pressed.connect(func(): GameSettings.set_graphics("medium"))
	row.add_child(med)
	var high := Button.new()
	high.text = "High"
	high.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	high.pressed.connect(func(): GameSettings.set_graphics("high"))
	row.add_child(high)

	var menu_btn := Button.new()
	UIStyleScript.apply_button(menu_btn, "action")
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(0, 44)
	menu_btn.pressed.connect(_go_main_menu)
	vbox.add_child(menu_btn)

	var close_btn := Button.new()
	close_btn.text = "Resume"
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.pressed.connect(_toggle_pause_panel)
	vbox.add_child(close_btn)

func _toggle_pause_panel() -> void:
	if pause_panel == null:
		return
	pause_panel.visible = not pause_panel.visible
	if pause_panel.visible:
		var vp := _vp()
		pause_panel.position = Vector2(vp.x * 0.5 - 160.0, vp.y * 0.5 - 150.0)

func _go_main_menu() -> void:
	if Network.is_online:
		Network.disconnect_game()
	get_tree().change_scene_to_file("res://main_menu.tscn")

