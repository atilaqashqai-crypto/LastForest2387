extends CharacterBody3D

const SPEED = 2.6
const SIGHT = 35.0
const REACH = 1.7
const BITE = 0.5
const COOLDOWN = 1.2
const ATTACK_DURATION = 0.58
const GRAY_RUNNER_SPEED = 4.3

const SKIN = Color(0.24, 0.34, 0.22)
const SKIN_DARK = Color(0.10, 0.16, 0.11)
const SHIRT = Color(0.19, 0.20, 0.17)
const SHIRT_DARK = Color(0.08, 0.09, 0.08)
const PANTS = Color(0.10, 0.11, 0.15)
const BLOOD = Color(0.28, 0.025, 0.018)

var hp = 2.0
var max_hp = 2.0
var health_bar: Node3D = null
var burn_time: float = 0.0
var burn_tick: float = 0.0
var flash_time: float = 0.0
var is_gray_runner: bool = false
var move_speed: float = SPEED
var skin_color: Color = SKIN
var skin_dark_color: Color = SKIN_DARK
var shirt_color: Color = SHIRT
var shirt_dark_color: Color = SHIRT_DARK
var pants_color: Color = PANTS
var blood_color: Color = BLOOD
var cd = 0.0
var player = null
var terrain = null
var wander = Vector3.ZERO
var wt = 0.0
var attack_time = 0.0
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var head_pivot: Node3D
var anim_time = 0.0
var visual_base_transforms: Dictionary = {}
var visual_height_factor: float = 1.0
var applied_factor: float = -1.0
var batches: Dictionary = {}
static var vc_mat: StandardMaterial3D = null
static var eye_mat: StandardMaterial3D = null
static var eye_mesh: BoxMesh = null
# --- multiplayer: server runs the AI, clients show "puppet" copies ---
static var next_net_id: int = 1
var is_puppet := false
var net_id := 0
# spawner bookkeeping: where this zombie "lives" (it respawns there after dying)
var home_pos := Vector3.ZERO
var has_home := false
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var has_target := false
var retarget_t := 0.0

class VBatch:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

const FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]

func _ready():
	if is_gray_runner:
		move_speed = GRAY_RUNNER_SPEED
		max_hp = 3.5
		hp = 3.5
		skin_color = Color(0.62, 0.64, 0.66)
		skin_dark_color = Color(0.25, 0.27, 0.29)
		shirt_color = Color(0.34, 0.36, 0.38)
		shirt_dark_color = Color(0.13, 0.14, 0.16)
		pants_color = Color(0.19, 0.20, 0.22)
		blood_color = Color(0.22, 0.035, 0.035)
	# Slightly taller silhouette without changing the voxel proportions.
	scale.y = 1.08
	player = get_tree().get_first_node_in_group("player")
	terrain = get_tree().current_scene.get_node_or_null("Terrain")
	if is_puppet:
		set_physics_process(false)
	elif net_id == 0:
		net_id = next_net_id
		next_net_id += 1
	if not has_meta("indoor_spawn") and not is_puppet:
		_drop()
	if Network.is_dedicated:
		# Server has no screen: only the collision shape is needed.
		_col()
		return
	_body()
	_cache_visual_transforms()
	_setup_health_bar()

func _setup_health_bar() -> void:
	health_bar = Node3D.new()
	health_bar.set_script(load("res://health_bar_3d.gd"))
	health_bar.position = Vector3(0, 2.35, 0)
	add_child(health_bar)
	if health_bar.has_method("set_health"):
		health_bar.call("set_health", hp, max_hp)

func _in_open_terrain() -> bool:
	# Not in the city (own floor slab), not a hospital / indoor zombie.
	if has_meta("indoor_spawn") or is_in_group("hospital_zombie"):
		return false
	var p := global_position
	return not (p.x > 95.0 and p.x < 255.0 and p.z > -110.0 and p.z < 110.0)

## Terrain collision is only loaded around players. A zombie over an unloaded chunk would fall
## into the void (this is why zombies were missing online). Wait until the ground exists.
func _ground_ok() -> bool:
	if terrain == null or not _in_open_terrain():
		return true
	if not terrain.has_method("has_ground"):
		return true
	var p := global_position
	if not bool(terrain.call("has_ground", p.x, p.z)):
		return false
	# Safety net: if it still got below the ground, put it back on top.
	var h: float = float(terrain.call("height", p.x, p.z))
	if p.y < h - 4.0:
		global_position = Vector3(p.x, h + 1.5, p.z)
		velocity = Vector3.ZERO
	return true

func _physics_process(d):
	if not _ground_ok():
		velocity = Vector3.ZERO
		return
	if player != null and not is_instance_valid(player):
		player = null
	_retarget(d)
	cd = maxf(cd - d, 0.0)
	attack_time = maxf(attack_time - d, 0.0)
	_process_burn(d)
	_process_flash(d)
	_gravity(d)
	_think(d)
	move_and_slide()

func _process(d):
	if Network.is_dedicated:
		return
	anim_time += d
	if is_puppet:
		_puppet_step(d)
	if player != null and is_instance_valid(player):
		if global_position.distance_squared_to(player.global_position) > 2500.0:
			return
	_update_first_person_height(d)
	_animate(d)

func _cache_visual_transforms():
	visual_base_transforms.clear()
	for child in get_children():
		if child is Node3D and not (child is CollisionShape3D):
			visual_base_transforms[child] = {"position": child.position, "scale": child.scale}

func _update_first_person_height(d):
	var target_factor = 1.22 if is_instance_valid(player) and player.is_first_person else 1.0
	if applied_factor == target_factor and visual_height_factor == target_factor:
		return
	visual_height_factor = lerpf(visual_height_factor, target_factor, minf(8.0 * d, 1.0))
	if absf(visual_height_factor - target_factor) < 0.002:
		visual_height_factor = target_factor
	applied_factor = visual_height_factor
	for child in visual_base_transforms:
		if not is_instance_valid(child):
			continue
		var base = visual_base_transforms[child]
		var base_pos: Vector3 = base["position"]
		var base_scale: Vector3 = base["scale"]
		child.position = Vector3(base_pos.x, base_pos.y * visual_height_factor, base_pos.z)
		child.scale = Vector3(base_scale.x, base_scale.y * visual_height_factor, base_scale.z)

func _gravity(d):
	velocity.y -= 9.8 * d * float(not is_on_floor())

func _think(d):
	_look()
	_hunt()
	_idle(d)

func _look():
	chasing = _dist() < DETECT or (chasing and _dist() < LOSE)

func _dist():
	return 9999.0 if player == null else _to_player().length()

func _near():
	return chasing

func _to_player():
	var v = player.global_position - global_position
	v.y = 0.0
	return v

func _hunt():
	if _near():
		_chase()

func _idle(d):
	if not _near():
		_roam(d)

func _chase():
	if player == null:
		return
	var v = _to_player()
	_face(v)
	if v.length() > REACH:
		_walk(v.normalized() * move_speed)
	else:
		_walk(Vector3.ZERO)
		_bite(v)

func _bite(v):
	if v.length() <= REACH and cd <= 0.0 and _has_line_of_sight():
		_attack()

func _has_line_of_sight() -> bool:
	# Damage only lands if the player is really reachable: same floor level and nothing solid in between.
	if player == null or not is_instance_valid(player):
		return false
	if absf(player.global_position.y - global_position.y) > 1.6:
		return false
	var space = get_world_3d().direct_space_state
	for off in [0.0, 0.6]:
		var from = global_position + Vector3(0.0, off, 0.0)
		var to = player.global_position + Vector3(0.0, off, 0.0)
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = [get_rid()]
		query.collision_mask = 1
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var hit = space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider = hit.get("collider")
		if not (collider == player or (collider is Node and player.is_ancestor_of(collider))):
			return false
	return true

func _attack():
	cd = COOLDOWN
	attack_time = ATTACK_DURATION
	if player != null and is_instance_valid(player):
		if Network.is_online and "peer_id" in player and int(player.peer_id) != 0:
			# Online: the bitten player's own game applies the damage.
			Network.hurt_peer(int(player.peer_id), BITE)
		else:
			var stats = player.get_node_or_null("Stats")
			if stats != null:
				stats.hurt(BITE)

func _walk(v):
	velocity.x = v.x
	velocity.z = v.z

func _face(v):
	if v.length() > 0.1:
		rotation.y = atan2(-v.x, -v.z)

func _pick():
	wt = randf_range(2.0, 6.0)
	var a = randf() * TAU
	wander = Vector3(cos(a), 0, sin(a)) * move_speed * 0.4 * float(randf() > 0.4)

func _roam(d):
	wt -= d
	if wt <= 0.0:
		_pick()
	_walk(wander)
	_face(wander)

func _body():
	# Uneven, decayed clothing and exposed infected flesh.
	_leg(-0.19, true)
	_leg(0.19, false)
	_b(0.13, 0.18, 0.31, -0.19, -0.78, -0.12, shirt_dark_color)
	_b(0.66, 0.70, 0.36, 0, 0.19, 0, shirt_color)
	_b(0.25, 0.32, 0.035, -0.17, 0.24, -0.195, blood_color)
	_b(0.12, 0.23, 0.025, 0.22, 0.12, -0.195, skin_dark_color)
	_b(0.18, 0.12, 0.04, -0.24, 0.52, -0.19, blood_color)
	_b(0.11, 0.15, 0.04, 0.18, -0.05, -0.2, blood_color)
	_head()
	_arm(-0.46, true)
	_arm(0.46, false)
	_col()
	_flush_batches()

func _leg(x: float, left: bool):
	var pivot = Node3D.new()
	add_child(pivot)
	pivot.position = Vector3(x, -0.16, 0.0)
	_put(pivot, Vector3(0.29, 0.72, 0.29), Vector3(0.0, -0.36, 0.015 if left else -0.015), pants_color)
	_put(pivot, Vector3(0.31, 0.16, 0.36), Vector3(0.0, -0.69, -0.055), shirt_dark_color)
	if left:
		left_leg = pivot
	else:
		right_leg = pivot

func _head():
	head_pivot = Node3D.new()
	add_child(head_pivot)
	head_pivot.position = Vector3(0, 0.69, 0)
	_put(head_pivot, Vector3(0.42, 0.43, 0.40), Vector3(0, 0.06, 0), skin_color)
	# Torn scalp, sunken cheek and exposed wound.
	_put(head_pivot, Vector3(0.24, 0.10, 0.25), Vector3(-0.10, 0.29, 0.015), skin_dark_color)
	_put(head_pivot, Vector3(0.14, 0.18, 0.06), Vector3(0.17, 0.00, -0.19), blood_color)
	_put(head_pivot, Vector3(0.25, 0.075, 0.035), Vector3(0, -0.13, -0.205), shirt_dark_color)
	# Jagged teeth and a dark open mouth.
	_put(head_pivot, Vector3(0.19, 0.035, 0.025), Vector3(0, -0.105, -0.23), Color(0.72, 0.68, 0.48))
	_put(head_pivot, Vector3(0.06, 0.11, 0.035), Vector3(-0.13, 0.04, -0.215), skin_dark_color)
	_eye(-0.105, head_pivot)
	_eye(0.095, head_pivot)
	_put(head_pivot, Vector3(0.09, 0.045, 0.035), Vector3(0.0, 0.18, -0.22), blood_color)

func _eye(x, parent):
	if eye_mat == null:
		eye_mat = StandardMaterial3D.new()
		eye_mat.albedo_color = Color(0.95, 0.12, 0.025)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(0.8, 0.035, 0.005)
		eye_mat.emission_energy_multiplier = 1.4
		eye_mesh = BoxMesh.new()
		eye_mesh.size = Vector3(0.085, 0.075, 0.035)
	var m = MeshInstance3D.new()
	m.mesh = eye_mesh
	m.position = Vector3(x, 0.095, -0.205)
	m.material_override = eye_mat
	parent.add_child(m)
	_put(parent, Vector3(0.12, 0.035, 0.045), Vector3(x, 0.15, -0.21), skin_dark_color)

func _arm(x, left):
	var p = Node3D.new()
	add_child(p)
	p.position = Vector3(x, 0.49, 0)
	p.rotation.x = 1.25 if left else 1.42
	_put(p, Vector3(0.23, 0.62, 0.23), Vector3(0, -0.31, 0), skin_color)
	_put(p, Vector3(0.25, 0.23, 0.25), Vector3(0, -0.62, -0.015), skin_dark_color)
	# Long, dark claw-like fingers.
	for i in range(3):
		_put(p, Vector3(0.055, 0.19, 0.065), Vector3(-0.075 + i * 0.075, -0.77, -0.045), skin_dark_color)
	_put(p, Vector3(0.10, 0.08, 0.08), Vector3(0.13 if left else -0.13, -0.68, -0.04), blood_color)
	if left:
		left_arm = p
	else:
		right_arm = p

func _animate(d):
	var moving = Vector2(velocity.x, velocity.z).length() > 0.2
	var gait = anim_time * (8.5 if is_gray_runner else 6.5)
	var walk = sin(gait) if moving else 0.0
	var leg_swing = 0.48 if moving else 0.025
	if left_leg != null:
		left_leg.rotation.x = lerpf(left_leg.rotation.x, walk * leg_swing, 9.0 * d)
	if right_leg != null:
		right_leg.rotation.x = lerpf(right_leg.rotation.x, -walk * leg_swing, 9.0 * d)
	var attack = 0.0
	if attack_time > 0.0:
		attack = sin((1.0 - attack_time / ATTACK_DURATION) * PI)
	if left_arm != null:
		left_arm.rotation.x = lerpf(left_arm.rotation.x, 1.25 + walk * 0.10 + attack * 0.9, 10.0 * d)
	if right_arm != null:
		right_arm.rotation.x = lerpf(right_arm.rotation.x, 1.42 - walk * 0.10 + attack * 1.0, 10.0 * d)
	if head_pivot != null:
		head_pivot.rotation.x = lerpf(head_pivot.rotation.x, -0.18 * attack, 9.0 * d)

func _col():
	var c = CollisionShape3D.new()
	var s = CapsuleShape3D.new()
	s.radius = 0.35
	s.height = 1.8
	c.shape = s
	add_child(c)

func _b(sx, sy, sz, x, y, z, c):
	_put(self, Vector3(sx, sy, sz), Vector3(x, y, z), c)

func _put(parent, size, offset, color):
	# Boxes are collected per parent and merged into ONE mesh (far fewer draw calls per zombie).
	var b = batches.get(parent)
	if b == null:
		b = VBatch.new()
		batches[parent] = b
	var h: Vector3 = size * 0.5
	for f in FACES:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var hu: float = absf(u.x) * h.x + absf(u.y) * h.y + absf(u.z) * h.z
		var hv: float = absf(w.x) * h.x + absf(w.y) * h.y + absf(w.z) * h.z
		var ctr: Vector3 = Vector3(nrm.x * h.x, nrm.y * h.y, nrm.z * h.z) + offset
		var base: int = b.v.size()
		b.v.append(ctr - u * hu - w * hv)
		b.v.append(ctr - u * hu + w * hv)
		b.v.append(ctr + u * hu + w * hv)
		b.v.append(ctr + u * hu - w * hv)
		for k in range(4):
			b.n.append(nrm)
			b.c.append(color)
		b.idx.append(base)
		b.idx.append(base + 1)
		b.idx.append(base + 2)
		b.idx.append(base)
		b.idx.append(base + 2)
		b.idx.append(base + 3)

func _flush_batches():
	if vc_mat == null:
		vc_mat = StandardMaterial3D.new()
		vc_mat.vertex_color_use_as_albedo = true
		vc_mat.vertex_color_is_srgb = true
	for parent in batches:
		var b = batches[parent]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.v
		arrays[Mesh.ARRAY_NORMAL] = b.n
		arrays[Mesh.ARRAY_COLOR] = b.c
		arrays[Mesh.ARRAY_INDEX] = b.idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = vc_mat
		parent.add_child(mi)
	batches.clear()

func _mat(color):
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	return m

const DETECT = 18.0
const LOSE = 40.0
var chasing = false

func take_damage(amount):
	if amount <= 0.0:
		return
	if is_puppet:
		# Client: ask the server to apply the hit.
		var scn = get_tree().current_scene
		var zs = scn.get_node_or_null("ZombieSync") if scn != null else null
		if zs != null:
			zs.send_hit(net_id, amount)
		return
	hp = maxf(hp - amount, 0.0)
	flash_time = 0.18
	if health_bar != null and health_bar.has_method("set_health"):
		health_bar.call("set_health", hp, max_hp)
		health_bar.visible = true
	if hp <= 0.0:
		_die()

func apply_burn(duration: float = 2.5) -> void:
	if is_puppet:
		return
	burn_time = maxf(burn_time, duration)
	if Network.is_dedicated:
		return
	var bv = get_node_or_null("BurnVisual")
	if bv == null:
		bv = Node3D.new()
		bv.name = "BurnVisual"
		bv.set_script(load("res://burn_visual.gd"))
		add_child(bv)
	if bv.has_method("start"):
		bv.call("start", duration)

func _process_burn(d: float) -> void:
	if burn_time <= 0.0:
		return
	burn_time -= d
	burn_tick -= d
	if burn_tick <= 0.0:
		burn_tick = 0.45
		take_damage(0.35)

func _process_flash(d: float) -> void:
	if Network.is_dedicated:
		flash_time = 0.0
		return
	if flash_time <= 0.0:
		return
	flash_time -= d
	# Temporary red overlay (shared materials must not be mutated)
	var flash = get_node_or_null("DamageFlash")
	if flash_time > 0.0:
		if flash == null:
			flash = MeshInstance3D.new()
			flash.name = "DamageFlash"
			var sm = SphereMesh.new()
			sm.radius = 0.55
			sm.height = 1.7
			flash.mesh = sm
			flash.position = Vector3(0, 1.0, 0)
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.12, 0.08, 0.35)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.2, 0.05)
			mat.emission_energy_multiplier = 1.8
			flash.material_override = mat
			add_child(flash)
		else:
			var mat2 = flash.material_override as StandardMaterial3D
			if mat2:
				mat2.albedo_color.a = 0.15 + 0.3 * clampf(flash_time / 0.18, 0.0, 1.0)
	elif flash != null:
		flash.queue_free()

func _die():
	var spawner = get_tree().get_first_node_in_group("zombie_spawner")
	if spawner != null and not is_in_group("hospital_zombie") and spawner.has_method("register_zombie_death"):
		spawner.call("register_zombie_death", is_gray_runner, home_pos, has_home)
	queue_free()

func _drop():
	var p = global_position
	if terrain != null:
		global_position = Vector3(p.x, terrain.height(p.x, p.z) + 1.5, p.z)

# ---------------- multiplayer helpers ----------------
func _retarget(d: float) -> void:
	# Chase the nearest player (server: any player, puppet: only the local one).
	retarget_t -= d
	if retarget_t > 0.0:
		return
	retarget_t = 0.4
	var best = null
	var best_d := 1e12
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		if is_puppet and not (p.has_method("is_local") and p.is_local()):
			continue
		var dd: float = global_position.distance_squared_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = p
	player = best

func apply_snapshot(pos: Vector3, yaw: float, new_hp: float, flags: int) -> void:
	if not has_target:
		global_position = pos
		rotation.y = yaw
		has_target = true
	target_pos = pos
	target_yaw = yaw
	var hurt_now: bool = new_hp < hp - 0.001
	hp = new_hp
	if hurt_now:
		flash_time = 0.18
	if health_bar != null and health_bar.has_method("set_health"):
		health_bar.call("set_health", hp, max_hp)
		if hurt_now:
			health_bar.visible = true
	if (flags & 2) != 0 and attack_time <= 0.0:
		attack_time = ATTACK_DURATION

func _puppet_step(d: float) -> void:
	_retarget(d)
	attack_time = maxf(attack_time - d, 0.0)
	_process_flash(d)
	if not has_target:
		return
	var old := global_position
	global_position = global_position.lerp(target_pos, minf(d * 14.0, 1.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(d * 12.0, 1.0))
	var dv := (global_position - old) / maxf(d, 0.001)
	velocity = Vector3(dv.x, 0.0, dv.z)
