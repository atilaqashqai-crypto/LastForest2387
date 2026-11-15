extends Node
## Zombie population manager (runs on the server / single-player only).
##
## Old system: a fixed ring of zombies around the player that popped back in
## 18 seconds after every kill, right where the player was walking.
##
## New system:
##  1. HOME zombies live all over the map (spread out once at match start).
##     When one dies it comes back 60-120 s later, at ITS OWN HOME, and only if
##     no player is close to it and none can see that spot. Clearing an area
##     therefore stays cleared for a while and nothing pops up in your face.
##  2. AMBIENT wanderers: if a player has fewer than AMBIENT_MIN zombies around
##     him, one slowly appears from outside his view (behind him, or hidden by
##     terrain) every ~15 s. They vanish silently when left far behind and never
##     "respawn", so there is no endless farm and no constant pressure.
##  3. A population cap grows with the number of players on the server.

const ZombieScript := preload("res://zombie.gd")

const HOME_FIELD := 60
const HOME_GRAY := 8
const START_SAFE_DIST := 25.0        # no home closer than this to the spawn point (0,0)

const RESPAWN_MIN := 60.0
const RESPAWN_MAX := 120.0
const RESPAWN_SAFE_DIST := 80.0      # a player this close blocks a respawn
const RESPAWN_RETRY_MIN := 3.0
const RESPAWN_RETRY_MAX := 7.0

const AMBIENT_MIN := 6               # zombies each player should have within AMBIENT_NEAR
const AMBIENT_NEAR := 100.0
const AMBIENT_COOLDOWN := 8.0
const AMBIENT_SPAWN_MIN := 40.0
const AMBIENT_SPAWN_MAX := 80.0
const AMBIENT_DESPAWN := 170.0
const AMBIENT_GRAY_CHANCE := 0.12

const SEEN_DIST := 140.0             # a spot closer than this, in front of a player with a clear line, counts as "seen"
const FRONT_COS := 0.30              # cos(~72 deg): the half-angle of "in front of the player"

const MAX_BASE := 80
const MAX_PER_EXTRA_PLAYER := 8
const MAX_TOTAL := 90

const SLEEP_DISTANCE := 90.0
const HOSPITAL_WAKE_DISTANCE := 70.0
const MOUNTAIN_MAX_HEIGHT := 34.0
const MAP_HALF := 250.0
const SPAWN_TRIES := 30
const ACTIVITY_INTERVAL := 0.5
const MAINTAIN_INTERVAL := 2.0
# The city has its own layout (and hospital defenders): keep wild zombies out of the walls.
const CITY_MIN := Vector2(95.0, -110.0)
const CITY_MAX := Vector2(255.0, 110.0)

var respawn_queue: Array = []        # { time, gray, home }
var activity_timer := 0.0
var maintain_timer := 0.0
var _ambient_cd: Dictionary = {}     # player instance id -> seconds left
var _terrain: Node = null

func _ready() -> void:
	add_to_group("zombie_spawner")
	if Network.is_client():
		# Online clients only show zombies sent by the server.
		set_process(false)
		return
	_populate_homes.call_deferred()

func _populate_homes() -> void:
	_terrain = get_parent().get_node_or_null("Terrain")
	for i in HOME_FIELD:
		_spawn_home(false)
	for i in HOME_GRAY:
		_spawn_home(true)

func _spawn_home(gray: bool) -> void:
	for _i in range(SPAWN_TRIES):
		var pos = _map_point(Vector3(randf_range(-MAP_HALF, MAP_HALF), 0.0, randf_range(-MAP_HALF, MAP_HALF)))
		if pos == null:
			continue
		if Vector2(pos.x, pos.z).length() < START_SAFE_DIST:
			continue
		_make(pos, gray, pos, true)
		return

func _process(d: float) -> void:
	_process_respawns(d)
	activity_timer += d
	if activity_timer >= ACTIVITY_INTERVAL:
		activity_timer = 0.0
		_update_zombie_activity()
	maintain_timer += d
	if maintain_timer >= MAINTAIN_INTERVAL:
		_ambient_top_up(maintain_timer)
		maintain_timer = 0.0

# ---------------------------------------------------------------- helpers
func _players() -> Array:
	var out: Array = []
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			out.append(p)
	return out

func _cap(player_count: int) -> int:
	return mini(MAX_BASE + MAX_PER_EXTRA_PLAYER * maxi(player_count - 1, 0), MAX_TOTAL)

func _field_zombies() -> Array:
	var out: Array = []
	for z in get_tree().get_nodes_in_group("zombie"):
		if is_instance_valid(z) and not z.is_queued_for_deletion() and not z.is_in_group("hospital_zombie"):
			out.append(z)
	return out

func _in_city(x: float, z: float) -> bool:
	return x > CITY_MIN.x and x < CITY_MAX.x and z > CITY_MIN.y and z < CITY_MAX.y

## Puts a flat (x, z) candidate on the ground. Returns null for mountains / the city.
func _map_point(c: Vector3):
	var x := clampf(c.x, -MAP_HALF, MAP_HALF)
	var z := clampf(c.z, -MAP_HALF, MAP_HALF)
	if _in_city(x, z):
		return null
	var y := 1.5
	if _terrain != null and _terrain.has_method("height"):
		var h: float = float(_terrain.call("height", x, z))
		if h > MOUNTAIN_MAX_HEIGHT:
			return null
		y = h + 1.5
	return Vector3(x, y, z)

func _facing(p) -> Vector3:
	var veh = p.get("current_vehicle")
	if veh != null and is_instance_valid(veh):
		var v: Vector3 = veh.linear_velocity
		v.y = 0.0
		if v.length() > 3.0:
			return v.normalized()
		return Vector3.ZERO          # parked car: the player may look anywhere
	var f: Vector3 = -p.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.ZERO

func _in_view(p, dir: Vector3, pos: Vector3) -> bool:
	var f := _facing(p)
	if f != Vector3.ZERO and f.dot(dir) < FRONT_COS:
		return false                 # behind or beside the player
	var space = get_parent().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0.0, 1.5, 0.0), pos, 1)
	q.exclude = [p.get_rid()]
	return space.intersect_ray(q).is_empty()   # nothing in the way = the player could see it

## True when spawning at pos would be too close to, or visible by, any player.
func _blocked(pos: Vector3, players: Array, min_dist: float) -> bool:
	for p in players:
		var to: Vector3 = pos - p.global_position
		to.y = 0.0
		var dist := to.length()
		if dist < min_dist:
			return true
		if dist < SEEN_DIST and _in_view(p, to / maxf(dist, 0.001), pos):
			return true
	return false

func _nearest_distance(pos: Vector3, players: Array) -> float:
	var best := 1e12
	for p in players:
		best = minf(best, pos.distance_to(p.global_position))
	return best

func _make(pos: Vector3, gray: bool, home: Vector3, has_home: bool) -> void:
	var z = CharacterBody3D.new()
	z.set_script(ZombieScript)
	z.is_gray_runner = gray
	z.home_pos = home
	z.has_home = has_home
	z.add_to_group("zombie")
	if gray:
		z.add_to_group("gray_zombie")
	z.position = pos
	get_parent().call_deferred("add_child", z)

# ---------------------------------------------------------------- respawn at home
## Called by zombie.gd when a zombie dies.
func register_zombie_death(gray: bool = false, home: Vector3 = Vector3.ZERO, has_home: bool = false) -> void:
	if not has_home:
		return                       # ambient wanderers do not come back
	respawn_queue.append({"time": randf_range(RESPAWN_MIN, RESPAWN_MAX), "gray": gray, "home": home})

func _process_respawns(d: float) -> void:
	if respawn_queue.is_empty():
		return
	var players := _players()
	var cap := _cap(players.size())
	var field := -1
	for i in range(respawn_queue.size() - 1, -1, -1):
		var e: Dictionary = respawn_queue[i]
		e["time"] = float(e["time"]) - d
		if float(e["time"]) > 0.0:
			continue
		if field < 0:
			field = _field_zombies().size()
		if field >= cap:
			e["time"] = randf_range(RESPAWN_RETRY_MIN, RESPAWN_RETRY_MAX)
			continue
		var pos = _respawn_point(e["home"], players)
		if pos == null:
			# Somebody is near, or looking at it: try again shortly.
			e["time"] = randf_range(RESPAWN_RETRY_MIN, RESPAWN_RETRY_MAX)
			continue
		_make(pos, bool(e["gray"]), e["home"], true)
		field += 1
		respawn_queue.remove_at(i)

func _respawn_point(home: Vector3, players: Array):
	for _i in range(6):
		var a := randf() * TAU
		var r := randf_range(0.0, 10.0)
		var c = _map_point(home + Vector3(cos(a) * r, 0.0, sin(a) * r))
		if c == null:
			continue
		if _blocked(c, players, RESPAWN_SAFE_DIST):
			continue
		return c
	return null

# ---------------------------------------------------------------- ambient wanderers
func _ambient_top_up(dt: float) -> void:
	var players := _players()
	if players.is_empty():
		return
	var cap := _cap(players.size())
	var field := _field_zombies()
	if field.size() >= cap:
		return
	var count := field.size()
	for p in players:
		if count >= cap:
			return
		var key: int = p.get_instance_id()
		var cd: float = float(_ambient_cd.get(key, 0.0)) - dt
		if cd > 0.0:
			_ambient_cd[key] = cd
			continue
		var near := 0
		for z in field:
			if z.global_position.distance_to(p.global_position) < AMBIENT_NEAR:
				near += 1
		if near >= AMBIENT_MIN:
			_ambient_cd[key] = 0.0
			continue
		var pos = _ambient_point(p, players)
		if pos == null:
			_ambient_cd[key] = 3.0
			continue
		_make(pos, randf() < AMBIENT_GRAY_CHANCE, Vector3.ZERO, false)
		count += 1
		_ambient_cd[key] = randf_range(AMBIENT_COOLDOWN * 0.7, AMBIENT_COOLDOWN * 1.3)

func _ambient_point(p, players: Array):
	var center: Vector3 = p.global_position
	for _i in range(SPAWN_TRIES):
		var a := randf() * TAU
		var r := randf_range(AMBIENT_SPAWN_MIN, AMBIENT_SPAWN_MAX)
		var c = _map_point(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
		if c == null:
			continue
		if _blocked(c, players, AMBIENT_SPAWN_MIN - 5.0):
			continue
		return c
	return null

# ---------------------------------------------------------------- sleep / wake / cleanup
func _update_zombie_activity() -> void:
	var players := _players()
	if players.is_empty():
		# Empty server: let zombies rest.
		for z0 in get_tree().get_nodes_in_group("zombie"):
			if is_instance_valid(z0):
				z0.set_physics_process(false)
		return
	for z in get_tree().get_nodes_in_group("zombie"):
		if not is_instance_valid(z) or z.is_queued_for_deletion():
			continue
		var distance := _nearest_distance(z.global_position, players)
		if z.is_in_group("hospital_zombie"):
			var awake: bool = distance < HOSPITAL_WAKE_DISTANCE
			z.set_physics_process(awake)
			z.set_process(awake)
			continue
		if not bool(z.get("has_home")) and distance > AMBIENT_DESPAWN:
			z.queue_free()           # wanderer left behind: just remove it
		elif distance > SLEEP_DISTANCE:
			z.set_physics_process(false)
			z.set_process(false)
		else:
			z.set_physics_process(true)
			z.set_process(true)
