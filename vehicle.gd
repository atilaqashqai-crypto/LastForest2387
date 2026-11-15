extends VehicleBody3D
## Off-road pickup.
## Online: the SERVER simulates the car (physics + zombie crushing). Clients keep a
## frozen copy that follows the server's snapshots, so everybody sees the same car.
## The driver's client only sends its steering/throttle to the server.
## Seats: 0 = driver, 1 = front passenger, 2 and 3 = standing in the cargo bed.

@export var paint_color: Color = Color(0.72, 0.025, 0.025)

const DRIVE_FORCE := 3400.0
const REVERSE_FORCE := 1900.0
const MAX_STEER := 0.5
const MAX_SPEED := 28.0

const SEAT_COUNT := 4
const SEAT_ROLES := ["driver", "passenger", "bed", "bed"]
const BED_SEAT_POS := [Vector3(-0.35, 0.86, 1.15), Vector3(0.35, 0.86, 1.75)]
## Where each seat's rider lands when leaving (vehicle-local).
const EXIT_OFFSETS := [
	Vector3(2.6, 0.4, 0.0), Vector3(-2.6, 0.4, 0.0),
	Vector3(-1.4, 0.4, 3.6), Vector3(1.4, 0.4, 3.6),
]
const ENTER_RANGE := 9.0
const STATE_INTERVAL := 0.05
const IDLE_STATE_INTERVAL := 1.0
const SEAT_HEARTBEAT := 2.0
const INPUT_INTERVAL := 0.05
const INPUT_TIMEOUT := 0.6
const CARGO_LOG_CAPACITY := 5

@onready var driver_seat = $Seats/DriverSeat
@onready var passenger_seat = $Seats/PassengerSeat
@onready var cargo_logs_root: Node3D = get_node_or_null("CargoBed/CargoLogs")

var driver = null
var passenger = null
var cargo_log_count := 0

var seats: Array = []
var occupants: Array = [null, null, null, null]   # avatar nodes sitting here (this peer's view)
var seat_ids: Array = [0, 0, 0, 0]                # peer ids (online truth lives on the server)

var _steer_input := 0.0
var _spawned := false
var _puppet := false                # online client: copy only, never simulates

# server side
var net_input := Vector2.ZERO
var net_brake := false
var net_input_age := 99.0
var _state_t := 0.0
var _seat_t := 0.0
var _validate_t := 0.0

# client side
var _input_t := 0.0
var _has_state := false
var _tgt_pos := Vector3.ZERO
var _tgt_rot := Quaternion.IDENTITY
var _tgt_vel := Vector3.ZERO
var _tgt_age := 0.0
var _ignore_me_until := 0

func _ready() -> void:
	add_to_group("drivable_vehicle")
	_apply_paint()
	_build_seats()
	mass = 1200.0
	gravity_scale = 1.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 12
	center_of_mass_mode = 1
	center_of_mass = Vector3(0.0, -0.45, 0.0)
	linear_damp = 0.12
	angular_damp = 0.85

	# Collide with world (layer 1) only — ignore debris rocks/logs (layer 3 / bit value 4)
	collision_layer = 1
	collision_mask = 1

	for child in get_children():
		if child is VehicleWheel3D:
			child.use_as_traction = true
			child.wheel_friction_slip = 6.0
			child.suspension_stiffness = 48.0
			child.suspension_max_force = 14000.0
			child.damping_compression = 0.95
			child.damping_relaxation = 1.25
			child.suspension_travel = 0.4
			child.wheel_rest_length = 0.28

	_puppet = Network.is_client()
	if _puppet:
		# Online client: the server owns the physics. Just follow its snapshots.
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		_spawned = true
		return

	body_entered.connect(_on_body_entered)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_snap_to_ground()
	_spawned = true

func _build_seats() -> void:
	seats = [driver_seat, passenger_seat]
	var root: Node = get_node("Seats")
	for i in range(BED_SEAT_POS.size()):
		var m := Node3D.new()
		m.name = "BedSeat%d" % (i + 1)
		m.position = BED_SEAT_POS[i]
		root.add_child(m)
		seats.append(m)

func _snap_to_ground() -> void:
	var space = get_world_3d().direct_space_state
	var from = global_position + Vector3.UP * 12.0
	var to = global_position + Vector3.DOWN * 60.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collision_mask = 1
	var result = space.intersect_ray(query)
	if result:
		global_position.y = result.position.y + 1.0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

func _on_body_entered(body: Node) -> void:
	# Crush / push zombies (only the simulating peer gets here)
	if body.is_in_group("zombie"):
		if body.has_method("take_damage"):
			body.take_damage(99.0)
		else:
			body.queue_free()
		# small speed loss only
		linear_velocity *= 0.92

func _apply_paint() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = paint_color
	mat.metallic = 0.35
	mat.roughness = 0.32
	for path in [
		"Body", "Hood", "CabinStructure/Roof",
		"CabinStructure/PillarFL", "CabinStructure/PillarFR",
		"CabinStructure/PillarRL", "CabinStructure/PillarRR",
		"LeftDoorPanel", "RightDoorPanel",
		"CargoBed/LeftBedRail", "CargoBed/RightBedRail", "CargoBed/Tailgate"
	]:
		var mesh := get_node_or_null(path)
		if mesh is MeshInstance3D:
			mesh.material_override = mat

# ------------------------------------------------------------------ helpers
func _online() -> bool:
	return Network.is_online and multiplayer.multiplayer_peer != null

func _id_of(player) -> int:
	if _online() and player != null and "peer_id" in player:
		return int(player.peer_id)
	return 0

func _player_by_id(id: int):
	if id == 0:
		return null
	var n = get_tree().get_first_node_in_group("player_%d" % id)
	return n if is_instance_valid(n) else null

func _seat_of(player) -> int:
	for i in range(SEAT_COUNT):
		if occupants[i] == player:
			return i
	return -1

func _seat_taken(i: int) -> bool:
	return seat_ids[i] != 0 or is_instance_valid(occupants[i])

func _free_seat() -> int:
	for i in range(SEAT_COUNT):
		if not _seat_taken(i):
			return i
	return -1

func can_accept_player() -> bool:
	return _free_seat() != -1

func can_interact() -> bool:
	return true

func _set_driver_refs() -> void:
	driver = occupants[0] if is_instance_valid(occupants[0]) else null
	passenger = occupants[1] if is_instance_valid(occupants[1]) else null

# ------------------------------------------------------------------ enter / exit
## Called by the player (Enter button). Runs on whichever peer the player is on.
func interact(player) -> void:
	if _online() and _puppet:
		_client_interact(player)
	else:
		_host_interact(player)

# Single-player, listen-server host or dedicated server: we own the car.
func _host_interact(player) -> void:
	if player.current_vehicle == self:
		exit_player(player)
		return
	var at_rear := _is_at_rear(player)
	if bool(player.get("carried_log")):
		if at_rear:
			load_log_from_player(player)
		return
	if at_rear and cargo_log_count > 0:
		if player.has_method("set_carried_log"):
			player.call("set_carried_log", true)
		cargo_log_count -= 1
		_refresh_cargo_visuals()
		return
	if can_accept_player():
		_server_enter(player, _id_of(player))

func _client_interact(player) -> void:
	if player.current_vehicle == self:
		exit_player(player)
		return
	var at_rear := _is_at_rear(player)
	if bool(player.get("carried_log")):
		if at_rear and cargo_log_count < CARGO_LOG_CAPACITY:
			player.call("set_carried_log", false)
			_rpc_req_load.rpc_id(1)
		return
	if at_rear and cargo_log_count > 0:
		_rpc_req_unload.rpc_id(1)
		return
	if can_accept_player():
		_rpc_req_enter.rpc_id(1)

func _is_at_rear(player) -> bool:
	var rear_position: Vector3 = global_transform * Vector3(0.0, 0.0, 2.25)
	return player.global_position.distance_to(rear_position) <= 4.0

func exit_player(player) -> void:
	if player == null or not is_instance_valid(player) or player.current_vehicle != self:
		return
	if _puppet:
		# Leave immediately on our own screen, then tell the server.
		var s := _seat_of(player)
		if s != -1:
			occupants[s] = null
		_set_driver_refs()
		_detach_player(player, maxi(s, 0))
		_ignore_me_until = Time.get_ticks_msec() + 1200
		_rpc_req_exit.rpc_id(1)
	else:
		_server_exit(player)

func enter_player(player) -> bool:
	if player == null or not can_accept_player():
		return false
	return _server_enter(player, _id_of(player))

# ---- server / single-player side ----
func _server_enter(player, pid: int) -> bool:
	var s := _free_seat()
	if s == -1 or player == null or not is_instance_valid(player):
		return false
	if _online():
		seat_ids[s] = pid
	occupants[s] = player
	_set_driver_refs()
	_attach_player(player, seats[s], SEAT_ROLES[s])
	sleeping = false
	if s == 0:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	_broadcast_seats()
	return true

func _server_exit(player) -> void:
	var s := _seat_of(player)
	if s == -1:
		return
	seat_ids[s] = 0
	occupants[s] = null
	_set_driver_refs()
	_detach_player(player, s)
	if s == 0:
		# Driver left: stop the engine so the car does not run away.
		engine_force = 0.0
		brake = 12.0
		steering = 0.0
	if not _any_occupant():
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = true
		_soft_ground_fix()
	_broadcast_seats()

func _any_occupant() -> bool:
	for i in range(SEAT_COUNT):
		if is_instance_valid(occupants[i]):
			return true
	return false

func _broadcast_seats() -> void:
	if _online() and multiplayer.is_server():
		_rpc_seats.rpc(seat_ids)

# ---- client side: apply what the server says ----
func _apply_seats(ids: Array) -> void:
	var my_id := multiplayer.get_unique_id()
	for i in range(SEAT_COUNT):
		var id := int(ids[i])
		seat_ids[i] = id
		# We just stood up ourselves: ignore stale "you are still seated" messages for a moment.
		if id == my_id and Time.get_ticks_msec() < _ignore_me_until:
			seat_ids[i] = 0
			id = 0
		var want = _player_by_id(id)
		var cur = occupants[i] if is_instance_valid(occupants[i]) else null
		if cur == want:
			continue
		if cur != null:
			occupants[i] = null
			_detach_player(cur, i)
		if want != null and want.current_vehicle == null:
			occupants[i] = want
			_attach_player(want, seats[i], SEAT_ROLES[i])
	_set_driver_refs()

func _attach_player(player, seat, role: String) -> void:
	if player.has_method("set_camera_mode"):
		player.call("set_camera_mode", false)
	player.current_vehicle = self
	player.vehicle_role = role
	player.set_physics_process(false)
	var collision = player.get_node_or_null("CollisionShape3D")
	if collision:
		collision.disabled = true
	# Inside the cab the body is hidden (nobody sees a floating soldier through the windows).
	# Riders standing in the cargo bed stay visible.
	var shown: bool = role == "bed"
	var visual = player.get_node_or_null("CharacterVisual")
	if visual:
		visual.visible = shown
	if player.get("nametag") != null:
		player.nametag.visible = shown
	player.reparent(seat, false)
	player.transform = Transform3D.IDENTITY
	var arm = player.get_node_or_null("CameraPivot/SpringArm3D")
	if arm:
		arm.spring_length = 9.0

func _detach_player(player, seat_idx: int) -> void:
	if player == null or not is_instance_valid(player) or player.current_vehicle != self:
		return
	var exit_pos: Vector3 = global_position + global_transform.basis * EXIT_OFFSETS[clampi(seat_idx, 0, SEAT_COUNT - 1)]
	# While seated, mouse/touch look rotates CameraPivot instead of the player body.
	# Read the camera's WORLD forward direction before detaching the player from the seat.
	var cam_pivot := player.get_node_or_null("CameraPivot") as Node3D
	var exit_yaw: float = global_rotation.y
	if cam_pivot != null:
		var camera_forward: Vector3 = -cam_pivot.global_transform.basis.z
		camera_forward.y = 0.0
		if camera_forward.length_squared() > 0.0001:
			camera_forward = camera_forward.normalized()
			exit_yaw = atan2(-camera_forward.x, -camera_forward.z)

	player.reparent(get_tree().current_scene, true)
	player.global_position = exit_pos
	# Make the body face the direction the camera was facing while driving.
	player.global_rotation = Vector3(0.0, exit_yaw, 0.0)
	if cam_pivot != null:
		cam_pivot.rotation.y = 0.0
		cam_pivot.rotation.x = clampf(cam_pivot.rotation.x, -0.6, 0.35)
		cam_pivot.rotation.z = 0.0

	var vis_back = player.get_node_or_null("CharacterVisual")
	if vis_back:
		vis_back.visible = true
	if player.get("nametag") != null:
		player.nametag.visible = Network.is_online
	player.current_vehicle = null
	player.vehicle_role = ""
	player.set_physics_process(true)
	var collision = player.get_node_or_null("CollisionShape3D")
	if collision:
		collision.disabled = false
	var arm = player.get_node_or_null("CameraPivot/SpringArm3D")
	if arm:
		arm.spring_length = 4.0
	player.velocity = Vector3.ZERO
	player.move_input = Vector2.ZERO
	player.sprinting = false
	# Other peers still think we sit in the car for a moment; hold back position updates.
	if "sync_block" in player:
		player.sync_block = 0.5

	# Ignore collisions with exiting player for a short time (stops physics explosion)
	if player is PhysicsBody3D:
		add_collision_exception_with(player)
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_instance_valid(self) and is_instance_valid(player):
				remove_collision_exception_with(player)
		)

func _soft_ground_fix() -> void:
	# Only lift if clearly buried; do not hard-snap (avoids launch)
	var space = get_world_3d().direct_space_state
	var from = global_position + Vector3.UP * 4.0
	var to = global_position + Vector3.DOWN * 25.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collision_mask = 1
	var result = space.intersect_ray(query)
	if result:
		var min_y = result.position.y + 0.75
		if global_position.y < min_y - 0.35:
			global_position.y = min_y
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

# ------------------------------------------------------------------ per-frame
func _read_input(player) -> Array:
	var input_vec: Vector2 = player.move_input
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vec.y = -1.0
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vec.y = 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vec.x = -1.0
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vec.x = 1.0
	return [input_vec, Input.is_key_pressed(KEY_SPACE)]

func _physics_process(delta: float) -> void:
	if _puppet:
		_client_step(delta)
		return
	if not _spawned:
		return
	if _online() and multiplayer.is_server():
		_server_net_step(delta)

	var drv = occupants[0]
	if not is_instance_valid(drv):
		engine_force = 0.0
		brake = 4.0
		steering = move_toward(steering, 0.0, delta * 2.0)
		if linear_velocity.length() < 0.5:
			linear_velocity = linear_velocity.move_toward(Vector3.ZERO, delta * 3.0)
		return

	var input_vec := Vector2.ZERO
	var handbrake := false
	if drv.has_method("is_local") and drv.is_local():
		var r := _read_input(drv)
		input_vec = r[0]
		handbrake = r[1]
	else:
		net_input_age += delta
		if net_input_age < INPUT_TIMEOUT:
			input_vec = net_input
			handbrake = net_brake
	_drive(input_vec, handbrake, delta)

func _drive(input_vec: Vector2, handbrake: bool, delta: float) -> void:
	# Joystick/WASD: up/W should drive vehicle FORWARD
	var forward_input = -input_vec.y
	var steer_input = -input_vec.x

	_steer_input = move_toward(_steer_input, steer_input, delta * 3.5)
	steering = _steer_input * MAX_STEER

	var forward_speed = -linear_velocity.dot(global_transform.basis.z)

	# Inverted so joystick-forward / W matches vehicle nose
	if forward_input > 0.05 and (-forward_speed) < MAX_SPEED:
		engine_force = -forward_input * DRIVE_FORCE
		brake = 0.0
	elif forward_input < -0.05:
		engine_force = -forward_input * REVERSE_FORCE
		brake = 0.0
	else:
		engine_force = 0.0
		brake = 2.0

	if handbrake:
		brake = 20.0
		engine_force = 0.0

# ---- server: send the car's state to everyone ----
func _server_net_step(delta: float) -> void:
	_state_t -= delta
	if _state_t <= 0.0:
		var moving := linear_velocity.length() > 0.15 or angular_velocity.length() > 0.15 or _any_occupant()
		_state_t = STATE_INTERVAL if moving else IDLE_STATE_INTERVAL
		_rpc_state.rpc(global_position, Quaternion(global_transform.basis.orthonormalized()), linear_velocity, cargo_log_count)
	_seat_t -= delta
	if _seat_t <= 0.0:
		_seat_t = SEAT_HEARTBEAT
		_rpc_seats.rpc(seat_ids)
	_validate_t -= delta
	if _validate_t <= 0.0:
		_validate_t = 0.5
		_free_dead_seats()

func _free_dead_seats() -> void:
	# A rider left the game (or died and was freed): free the seat.
	var changed := false
	for i in range(SEAT_COUNT):
		if seat_ids[i] != 0 and not is_instance_valid(occupants[i]):
			seat_ids[i] = 0
			occupants[i] = null
			changed = true
	if changed:
		_set_driver_refs()
		_broadcast_seats()

# ---- client: follow the server, send our steering ----
func _client_step(delta: float) -> void:
	var drv = occupants[0]
	if is_instance_valid(drv) and drv.has_method("is_local") and drv.is_local():
		_input_t -= delta
		if _input_t <= 0.0:
			_input_t = INPUT_INTERVAL
			var r := _read_input(drv)
			_rpc_input.rpc_id(1, r[0], r[1])
	if not _has_state:
		return
	_tgt_age += delta
	var predicted: Vector3 = _tgt_pos + _tgt_vel * minf(_tgt_age, 0.2)
	var t := minf(delta * 12.0, 1.0)
	var cur := global_transform
	var q := Quaternion(cur.basis.orthonormalized()).slerp(_tgt_rot, t)
	global_transform = Transform3D(Basis(q), cur.origin.lerp(predicted, t))

# ------------------------------------------------------------------ network
@rpc("authority", "unreliable_ordered")
func _rpc_state(pos: Vector3, rot: Quaternion, vel: Vector3, cargo: int) -> void:
	if multiplayer.is_server():
		return
	_tgt_pos = pos
	_tgt_rot = rot
	_tgt_vel = vel
	_tgt_age = 0.0
	if not _has_state:
		_has_state = true
		global_transform = Transform3D(Basis(rot), pos)
	if cargo != cargo_log_count:
		cargo_log_count = cargo
		_refresh_cargo_visuals()

@rpc("authority", "reliable")
func _rpc_seats(ids: Array) -> void:
	if multiplayer.is_server() or ids.size() < SEAT_COUNT:
		return
	_apply_seats(ids)

@rpc("any_peer", "unreliable_ordered")
func _rpc_input(v: Vector2, handbrake: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != seat_ids[0]:
		return
	net_input = v.limit_length(1.0)
	net_brake = handbrake
	net_input_age = 0.0

@rpc("any_peer", "reliable")
func _rpc_req_enter() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var player = _player_by_id(id)
	if player == null or player.current_vehicle != null:
		return
	if player.global_position.distance_to(global_position) > ENTER_RANGE:
		return
	for i in range(SEAT_COUNT):
		if seat_ids[i] == id:
			return
	_server_enter(player, id)

@rpc("any_peer", "reliable")
func _rpc_req_exit() -> void:
	if not multiplayer.is_server():
		return
	var player = _player_by_id(multiplayer.get_remote_sender_id())
	if player != null:
		_server_exit(player)

@rpc("any_peer", "reliable")
func _rpc_req_load() -> void:
	if multiplayer.is_server() and cargo_log_count < CARGO_LOG_CAPACITY:
		cargo_log_count += 1
		_refresh_cargo_visuals()

@rpc("any_peer", "reliable")
func _rpc_req_unload() -> void:
	if not multiplayer.is_server() or cargo_log_count <= 0:
		return
	cargo_log_count -= 1
	_refresh_cargo_visuals()
	_rpc_give_log.rpc_id(multiplayer.get_remote_sender_id())

@rpc("authority", "reliable")
func _rpc_give_log() -> void:
	var p = Network.get_local_player()
	if p != null and p.has_method("set_carried_log"):
		p.call("set_carried_log", true)

func load_log_from_player(player: Node) -> bool:
	if cargo_log_count >= CARGO_LOG_CAPACITY or not bool(player.get("carried_log")):
		return false
	if player.has_method("set_carried_log"):
		player.call("set_carried_log", false)
	cargo_log_count += 1
	_refresh_cargo_visuals()
	return true

func _refresh_cargo_visuals() -> void:
	if cargo_logs_root == null:
		return
	for child in cargo_logs_root.get_children():
		child.queue_free()
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.24, 0.13, 0.065)
	bark.roughness = 0.96
	var end_mat := StandardMaterial3D.new()
	end_mat.albedo_color = Color(0.58, 0.39, 0.2)
	end_mat.roughness = 1.0
	for i in cargo_log_count:
		var row := int(i / 3)
		var col := i % 3
		var log := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.17
		cylinder.bottom_radius = 0.17
		cylinder.height = 1.35
		cylinder.radial_segments = 10
		log.mesh = cylinder
		log.material_override = bark
		log.rotation.x = PI / 2.0
		log.position = Vector3(-0.55 + float(col) * 0.55, 0.98 + float(row) * 0.34, 1.55)
		cargo_logs_root.add_child(log)
		for side in [-1.0, 1.0]:
			var cap := MeshInstance3D.new()
			var cap_mesh := CylinderMesh.new()
			cap_mesh.top_radius = 0.155
			cap_mesh.bottom_radius = 0.155
			cap_mesh.height = 0.025
			cap_mesh.radial_segments = 10
			cap.mesh = cap_mesh
			cap.material_override = end_mat
			cap.rotation.x = PI / 2.0
			cap.position = log.position + Vector3(0.0, 0.0, side * 0.69)
			cargo_logs_root.add_child(cap)

