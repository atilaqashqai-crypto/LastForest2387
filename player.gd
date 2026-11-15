extends CharacterBody3D

const SPEED := 5.0
const SPRINT_SPEED := 8.5
const INTERACT_DISTANCE := 6.0
const WOOD_LOG_SCENE: PackedScene = preload("res://wood_log.tscn")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var move_input := Vector2.ZERO
var sprinting := false
var current_vehicle: Node3D = null
var vehicle_role := ""
var peer_id: int = 0
var outfit_color: Color = Color(0.25, 0.3, 0.22)
var player_name: String = ""
var nametag: Label3D = null
var is_first_person: bool = false
var carried_log: bool = false
var carried_log_visual: MeshInstance3D = null
## >0 = just left a vehicle: other peers may still have us seated, so don't send position yet.
var sync_block: float = 0.0

func _ready() -> void:
	add_to_group("player")
	collision_mask = 1 | 4
	floor_snap_length = 0.5
	if peer_id != 0:
		add_to_group("player_%d" % peer_id)
		set_multiplayer_authority(peer_id)
	_apply_outfit()
	_setup_camera_authority()
	_setup_nametag()

func _apply_outfit() -> void:
	var vis = get_node_or_null("CharacterVisual")
	if vis and vis.has_method("set_outfit_color"):
		vis.call("set_outfit_color", outfit_color)

func _setup_camera_authority() -> void:
	var cam = get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if cam == null:
		return
	# Only local player camera is active
	var local := multiplayer.multiplayer_peer == null or is_multiplayer_authority()
	cam.current = local

func is_local() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	return is_multiplayer_authority()

func _physics_process(delta: float) -> void:
	if not is_local():
		return
	sync_block = maxf(sync_block - delta, 0.0)
	if current_vehicle != null:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	_move()
	move_and_slide()
	# Sync transform to others
	if multiplayer.multiplayer_peer != null and is_multiplayer_authority() and sync_block <= 0.0:
		_rpc_sync.rpc(global_position, rotation.y, velocity)

@rpc("any_peer", "unreliable_ordered")
func _rpc_sync(pos: Vector3, yaw: float, vel: Vector3) -> void:
	if is_multiplayer_authority():
		return
	global_position = global_position.lerp(pos, 0.5)
	rotation.y = lerp_angle(rotation.y, yaw, 0.5)
	velocity = vel

func _move() -> void:
	var direction := (transform.basis * Vector3(move_input.x, 0.0, move_input.y)).normalized()
	var speed := SPRINT_SPEED if sprinting else SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

func set_camera_mode(first_person: bool) -> void:
	if not is_local():
		return
	# First-person view is disabled while seated in a vehicle.
	if current_vehicle != null:
		first_person = false
	is_first_person = first_person
	var pivot := get_node_or_null("CameraPivot") as Node3D
	var arm := get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	var visual := get_node_or_null("CharacterVisual")
	if pivot != null:
		pivot.position.y = 2.25 if is_first_person else 1.5
	if arm != null:
		arm.spring_length = 0.05 if is_first_person else 4.0
	if visual != null and visual.has_method("set_first_person_view"):
		visual.call("set_first_person_view", is_first_person)

func toggle_camera_mode() -> void:
	if current_vehicle != null:
		return
	set_camera_mode(not is_first_person)

func rotate_cam(relative_motion: Vector2) -> void:
	if not is_local():
		return
	if current_vehicle != null:
		$CameraPivot.rotation.y -= relative_motion.x * 0.005
	else:
		rotation.y -= relative_motion.x * 0.005
	$CameraPivot.rotation.x = clampf($CameraPivot.rotation.x - relative_motion.y * 0.005, -1.0, 0.5)

func jump() -> void:
	if not is_local():
		return
	if current_vehicle == null and is_on_floor():
		velocity.y = 4.5

func sprint() -> void:
	if not is_local():
		return
	if current_vehicle == null:
		sprinting = true

func switch_item() -> void:
	if not is_local():
		return
	if current_vehicle == null:
		var inv = get_node_or_null("Inventory")
		if inv:
			inv.next()

func set_carried_log(value: bool) -> void:
	carried_log = value
	if value:
		if carried_log_visual == null:
			carried_log_visual = MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.16
			mesh.bottom_radius = 0.16
			mesh.height = 1.25
			mesh.radial_segments = 8
			carried_log_visual.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.24, 0.13, 0.065)
			mat.roughness = 1.0
			carried_log_visual.material_override = mat
			carried_log_visual.rotation = Vector3(0.0, 0.0, PI / 2.0)
			carried_log_visual.position = Vector3(0.0, 1.45, 0.42)
			add_child(carried_log_visual)
		carried_log_visual.visible = true
	else:
		if is_instance_valid(carried_log_visual):
			carried_log_visual.visible = false

func use_item() -> void:
	if not is_local():
		return
	var build_system = get_tree().current_scene.get_node_or_null("BuildSystem") if get_tree().current_scene else null
	if build_system != null and bool(build_system.get("is_placing")):
		build_system.call("confirm_placement", self)
		return
	if current_vehicle != null:
		current_vehicle.call("exit_player", self)
		return
	var nearest: Node3D = null
	var nearest_distance := INTERACT_DISTANCE
	# Vehicles
	for vehicle in get_tree().get_nodes_in_group("drivable_vehicle"):
		if not is_instance_valid(vehicle) or not vehicle.has_method("interact"):
			continue
		var distance := global_position.distance_to(vehicle.global_position)
		var vehicle_interactable: bool = false
		if vehicle.has_method("can_interact"):
			vehicle_interactable = bool(vehicle.call("can_interact"))
		else:
			vehicle_interactable = bool(vehicle.call("can_accept_player"))
		if distance < nearest_distance and vehicle_interactable:
			nearest = vehicle
			nearest_distance = distance
	# Cabin door / other interactables
	for node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node) or not node.has_method("interact"):
			continue
		var p = node.global_position if node is Node3D else global_position
		if node is Node3D:
			p = node.global_position
		var distance := global_position.distance_to(p)
		if distance < nearest_distance:
			nearest = node
			nearest_distance = distance
	if nearest != null:
		nearest.call("interact", self)
	elif carried_log:
		_drop_carried_log()
	else:
		var inv = get_node_or_null("Inventory")
		if inv:
			inv.use()

func _drop_carried_log() -> void:
	if not carried_log:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var dropped_log: RigidBody3D = WOOD_LOG_SCENE.instantiate() as RigidBody3D
	scene_root.add_child(dropped_log)
	var forward: Vector3 = -global_transform.basis.z
	var ray_start: Vector3 = global_position + forward * 1.1 + Vector3.UP * 3.0
	var ray_end: Vector3 = ray_start + Vector3.DOWN * 8.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var drop_position: Vector3 = global_position + forward * 1.1
	if not hit.is_empty():
		drop_position = hit["position"]
	dropped_log.global_position = drop_position + Vector3.UP * 0.85
	dropped_log.rotation.y = rotation.y
	dropped_log.apply_central_impulse(forward * 1.0 + Vector3.UP * 0.35)
	set_carried_log(false)

func shoot() -> void:
	if not is_local():
		return
	if current_vehicle == null:
		var inv = get_node_or_null("Inventory")
		if inv:
			print("shoot: ", inv.current())

func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_E:
			use_item()

func _setup_nametag() -> void:
	# Only show names in online multiplayer, and never above your own head
	if not Network.is_online:
		return
	if is_local():
		return
	nametag = Label3D.new()
	nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nametag.font_size = 48
	nametag.modulate = Color(1, 1, 1)
	nametag.outline_modulate = Color(0, 0, 0)
	nametag.outline_size = 8
	nametag.position = Vector3(0, 2.35, 0)
	nametag.no_depth_test = true
	nametag.pixel_size = 0.012
	nametag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(nametag)
	_refresh_nametag()

func _refresh_nametag() -> void:
	if nametag == null:
		return
	if not Network.is_online:
		nametag.visible = false
		return
	var n := player_name.strip_edges()
	if n.is_empty() and peer_id != 0 and Network.players.has(peer_id):
		n = str(Network.players[peer_id].get("name", ""))
	if n.is_empty():
		n = "Player"
	nametag.text = n
	nametag.visible = true

