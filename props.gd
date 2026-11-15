extends Node3D

const LAYER_WORLD := 1
const LAYER_DEBRIS := 4
const WORLD_HALF := 270.0
const CITY_MIN_X := 92.0
const CITY_MAX_X := 258.0
const CITY_MIN_Z := -115.0
const CITY_MAX_Z := 115.0
const MOUNTAIN_MIN_X := -300.0
const MOUNTAIN_MAX_X := -258.0
const CHUNK_SIZE := 48.0
const WORLD_ORIGIN := -300.0
const ACTIVE_RADIUS := 1
const UPDATE_INTERVAL := 0.6

var terrain
var placements: Dictionary = {}
var loaded_chunks: Dictionary = {}
var update_timer := 0.0
var _rng := RandomNumberGenerator.new()

func _ready():
	_rng.seed = Network.WORLD_SEED + 2
	terrain = get_node("../Terrain")
	_many(0, 300)
	_many(1, 220)
	_many(2, 90)
	_refresh_chunks()

func _process(delta):
	update_timer += delta
	if update_timer >= UPDATE_INTERVAL:
		update_timer = 0.0
		_refresh_chunks()

func _many(k, count):
	for i in count:
		var p = Vector2(_rng.randf_range(-WORLD_HALF, WORLD_HALF), _rng.randf_range(-WORLD_HALF, WORLD_HALF))
		if not _inside_city(p.x, p.y) and not _inside_mountain(p.x, p.y) and not _on_rim_mountain(p.x, p.y) and p.length() > 10.0:
			var key := _key_at(p)
			if not placements.has(key): placements[key] = []
			placements[key].append({"kind": k, "position": p})

func _key_at(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x - WORLD_ORIGIN) / CHUNK_SIZE), 0, 12), clampi(floori((p.y - WORLD_ORIGIN) / CHUNK_SIZE), 0, 12))

func _refresh_chunks():
	var wanted := {}
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty(): players = [null]
	for player in players:
		var center: Vector2i = _key_at(Vector2(player.global_position.x, player.global_position.z)) if player != null else Vector2i(5, 5)
		for x in range(maxi(0, center.x - ACTIVE_RADIUS), mini(13, center.x + ACTIVE_RADIUS + 1)):
			for z in range(maxi(0, center.y - ACTIVE_RADIUS), mini(13, center.y + ACTIVE_RADIUS + 1)):
				var key := Vector2i(x, z)
				wanted[key] = true
				if not loaded_chunks.has(key): _load_chunk(key)
	for key in loaded_chunks.keys():
		if not wanted.has(key):
			if is_instance_valid(loaded_chunks[key]): loaded_chunks[key].queue_free()
			loaded_chunks.erase(key)

func _load_chunk(key: Vector2i):
	var root := Node3D.new()
	root.name = "PropsChunk_%d_%d" % [key.x, key.y]
	add_child(root)
	for item in placements.get(key, []):
		_place(item["kind"], item["position"], root)
	loaded_chunks[key] = root

func _inside_city(x, z): return x > CITY_MIN_X and x < CITY_MAX_X and z > CITY_MIN_Z and z < CITY_MAX_Z
func _inside_mountain(x, z):
	return x >= MOUNTAIN_MIN_X and x <= MOUNTAIN_MAX_X

func _on_rim_mountain(x, z):
	return maxf(absf(x), absf(z)) > 248.0

func _place(k, p, parent):
	var t = StaticBody3D.new()
	parent.add_child(t)
	t.position = Vector3(p.x, terrain.height(p.x, p.y), p.y)
	t.rotation.y = randf() * TAU
	_make(t, k)

func _make(t, k):
	match k:
		0:
			_rock(t)
		1:
			_bush(t)
		2:
			_log(t)

func _rock(t):
	t.collision_layer = LAYER_DEBRIS
	t.collision_mask = 0
	var s = randf_range(0.8, 2.5)
	_box(t, Vector3(s, s * 0.7, s * 1.2), Vector3(0, s * 0.2, 0), Color(0.28, 0.28, 0.3), true)
	_pebble(t, s)

func _pebble(t, s):
	_box(t, Vector3(s * 0.6, s * 0.5, s * 0.6), Vector3(s * 0.7, s * 0.1, 0.4), Color(0.22, 0.22, 0.25), true)

func _bush(t):
	t.collision_layer = LAYER_DEBRIS
	t.collision_mask = 0
	var s = randf_range(0.8, 1.4)
	_box(t, Vector3(s, s * 0.8, s), Vector3(0, s * 0.3, 0), Color(0.06, 0.2, 0.07), false)
	_tuft(t, s)

func _tuft(t, s):
	_box(t, Vector3(s * 0.7, s * 0.6, s * 0.7), Vector3(s * 0.5, s * 0.2, 0.4), Color(0.05, 0.17, 0.06), false)

func _log(t):
	t.collision_layer = LAYER_DEBRIS
	t.collision_mask = 0
	var l = randf_range(3.0, 5.0)
	_box(t, Vector3(0.7, 0.7, l), Vector3(0, 0.3, 0), Color(0.2, 0.12, 0.07), true)

func _box(t, s, o, c, solid):
	t.add_child(_mesh(s, o, c))
	_solid(t, s, o, solid)

func _mesh(s, o, c):
	var m = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = s
	m.mesh = b
	m.position = o
	m.material_override = _mat(c)
	m.visibility_range_end = 70.0
	return m

func _mat(c):
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	return m

func _solid(t, s, o, solid):
	if solid:
		_col(t, s, o)

func _col(t, s, o):
	var c = CollisionShape3D.new()
	var b = BoxShape3D.new()
	b.size = s
	c.shape = b
	c.position = o
	t.add_child(c)
