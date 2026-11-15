extends Node3D
## Placeable fire pit. Starts unlit. Add logs to light the fire.
## When lit, burns zombies and damages the player.

const REQUIRED_LOGS := 1
const STONE := Color(0.38, 0.36, 0.33)
const STONE_DARK := Color(0.22, 0.20, 0.18)
const ASH := Color(0.18, 0.15, 0.12)
const WOOD := Color(0.40, 0.26, 0.14)
const BURN_RADIUS := 1.15
const PLAYER_BURN_DAMAGE := 0.4
const PLAYER_BURN_INTERVAL := 0.5

var logs_added := 0
var is_built := false
var progress_label: Label3D
var _fire_node: Node3D = null
var _burn_area: Area3D = null
var _player_burn_cd: float = 0.0
var _bodies_in_fire: Dictionary = {}  # instance_id -> body

func _ready() -> void:
	add_to_group("interactable")
	_build_pit()
	_create_progress_label()
	_update_progress()

func _process(delta: float) -> void:
	if not is_built:
		return
	_player_burn_cd = maxf(_player_burn_cd - delta, 0.0)
	# Continuous burn for bodies still inside
	for id in _bodies_in_fire.keys():
		var body = _bodies_in_fire[id]
		if not is_instance_valid(body):
			_bodies_in_fire.erase(id)
			continue
		_apply_burn_to(body)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	return m

func _box(size: Vector3, pos: Vector3, color: Color, col: bool = true) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	add_child(mi)
	if col:
		var body := StaticBody3D.new()
		body.position = pos
		add_child(body)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)

func _build_pit() -> void:
	_box(Vector3(1.35, 0.22, 1.35), Vector3(0, 0.12, 0), STONE)
	_box(Vector3(1.05, 0.18, 1.05), Vector3(0, 0.22, 0), STONE_DARK, false)
	_box(Vector3(0.75, 0.08, 0.75), Vector3(0, 0.18, 0), ASH, false)
	_box(Vector3(0.55, 0.10, 0.12), Vector3(0.05, 0.28, 0.08), WOOD, false)
	_box(Vector3(0.48, 0.09, 0.11), Vector3(-0.12, 0.27, -0.1), WOOD, false)
	_box(Vector3(0.42, 0.08, 0.10), Vector3(0.15, 0.26, -0.15), WOOD, false)

func _create_progress_label() -> void:
	progress_label = Label3D.new()
	progress_label.position = Vector3(0.0, 1.35, 0.0)
	progress_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	progress_label.font_size = 40
	progress_label.pixel_size = 0.009
	progress_label.modulate = Color(1.0, 0.88, 0.55)
	progress_label.outline_size = 8
	progress_label.outline_modulate = Color(0.05, 0.03, 0.01)
	progress_label.no_depth_test = true
	add_child(progress_label)

func _update_progress() -> void:
	if progress_label == null:
		return
	if is_built:
		progress_label.visible = false
	else:
		progress_label.visible = true
		progress_label.text = "FIRE %d/%d LOGS" % [logs_added, REQUIRED_LOGS]

func interact(player: Node = null) -> void:
	if player == null or is_built:
		return
	if bool(player.get("carried_log")):
		if player.has_method("set_carried_log"):
			player.call("set_carried_log", false)
		_add_log_request()

func _light_fire() -> void:
	is_built = true
	_update_progress()
	_fire_node = Node3D.new()
	_fire_node.set_script(load("res://fire_effect.gd"))
	_fire_node.position = Vector3(0, 0.22, 0)
	add_child(_fire_node)
	_setup_burn_area()

func _setup_burn_area() -> void:
	_burn_area = Area3D.new()
	_burn_area.position = Vector3(0, 0.6, 0)
	_burn_area.monitoring = true
	_burn_area.monitorable = false
	_burn_area.collision_layer = 0
	_burn_area.collision_mask = 1 | 2 | 4  # players / characters
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BURN_RADIUS
	shape.shape = sphere
	_burn_area.add_child(shape)
	add_child(_burn_area)
	_burn_area.body_entered.connect(_on_body_entered)
	_burn_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if not is_built or body == null:
		return
	_bodies_in_fire[body.get_instance_id()] = body
	_apply_burn_to(body)

func _on_body_exited(body: Node3D) -> void:
	if body == null:
		return
	_bodies_in_fire.erase(body.get_instance_id())

func _apply_burn_to(body: Node) -> void:
	# Zombie
	if body.has_method("apply_burn"):
		body.call("apply_burn", 2.8)
		return
	if body.has_method("take_damage") and body.get("hp") != null:
		body.call("take_damage", 0.35)
		return
	# Player (has Stats child). Online: each game only burns its own local player.
	if body.is_in_group("player") or str(body.name).begins_with("Player"):
		if body.has_method("is_local") and not body.is_local():
			return
		if _player_burn_cd > 0.0:
			return
		var stats = body.get_node_or_null("Stats")
		if stats != null and stats.has_method("hurt"):
			stats.call("hurt", PLAYER_BURN_DAMAGE)
			_player_burn_cd = PLAYER_BURN_INTERVAL
		# Burning visual on player
		var bv = body.get_node_or_null("BurnVisual")
		if bv == null:
			bv = Node3D.new()
			bv.name = "BurnVisual"
			bv.set_script(load("res://burn_visual.gd"))
			body.add_child(bv)
		if bv.has_method("start"):
			bv.call("start", 2.0)

# ---------- multiplayer: BuildSync keeps every player's copy identical ----------
var net_id := ""

func _add_log_request() -> void:
	if net_id != "" and Network.is_online:
		var bs = get_tree().current_scene.get_node_or_null("BuildSync")
		if bs != null:
			bs.request_log(net_id)
			return
	net_set_logs(logs_added + 1)

func net_set_logs(n: int) -> void:
	if is_built:
		return
	logs_added = n
	_update_progress()
	if logs_added >= REQUIRED_LOGS:
		_light_fire()
