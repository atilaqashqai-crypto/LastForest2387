extends Node3D

const WORLD_HALF := 275.0
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
    _rng.seed = Network.WORLD_SEED + 1
    terrain = get_node("../Terrain")
    for i in 430:
        var p := Vector3(_rng.randf_range(-WORLD_HALF, WORLD_HALF), 0, _rng.randf_range(-WORLD_HALF, WORLD_HALF))
        if not _inside_city(p.x, p.z) and not _inside_mountain(p.x, p.z) and not _on_rim_mountain(p.x, p.z) and p.length() > 10.0:
            var key := _key_at(p)
            if not placements.has(key): placements[key] = []
            placements[key].append(p)
    _refresh_chunks()

func _process(delta):
    update_timer += delta
    if update_timer >= UPDATE_INTERVAL:
        update_timer = 0.0
        _refresh_chunks()

func _key_at(p: Vector3) -> Vector2i:
    return Vector2i(clampi(floori((p.x - WORLD_ORIGIN) / CHUNK_SIZE), 0, 12), clampi(floori((p.z - WORLD_ORIGIN) / CHUNK_SIZE), 0, 12))

func _refresh_chunks():
    var wanted := {}
    var players = get_tree().get_nodes_in_group("player")
    if players.is_empty(): players = [null]
    for player in players:
        var center: Vector2i = _key_at(player.global_position) if player != null else Vector2i(5, 5)
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
    root.name = "ForestChunk_%d_%d" % [key.x, key.y]
    add_child(root)
    for p in placements.get(key, []): _tree(p, root)
    loaded_chunks[key] = root

func _inside_city(x, z): return x > CITY_MIN_X and x < CITY_MAX_X and z > CITY_MIN_Z and z < CITY_MAX_Z
func _inside_mountain(x, z):
    return x >= MOUNTAIN_MIN_X and x <= MOUNTAIN_MAX_X

func _on_rim_mountain(x, z):
    return maxf(absf(x), absf(z)) > 248.0
func _tree(p, parent):
    var t = StaticBody3D.new()
    t.set_script(load("res://tree.gd"))
    parent.add_child(t)
    t.position = Vector3(p.x, _h(p.x, p.z) - 0.3, p.z)
    t.rotation.y = randf() * TAU
    _shape(t)
func _h(x, z): return terrain.height(x, z)
func _shape(t):
    var h = randf_range(3.0, 6.5)
    var w = randf_range(0.5, 0.9)
    _trunk(t, h, w)
    _crown(t, h)
func _trunk(t, h, w): _box(t, Vector3(w, h, w), Vector3(0, h / 2, 0), Color(0.22, 0.14, 0.08), true)
func _crown(t, h):
    if randf() > 0.2: _leaves(t, h)
func _leaves(t, h):
    for i in 3: _leaf(t, h, i)
func _leaf(t, h, i):
    var w = 3.4 - i * 1.0
    var r = randf() * 0.1
    _box(t, Vector3(w, 1.4, w), Vector3(0, h - 0.5 + i * 1.2, 0), Color(0.04 + r, 0.2 + r, 0.06), false)
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
    m.visibility_range_end = 90.0
    return m
func _mat(c):
    var m = StandardMaterial3D.new()
    m.albedo_color = c
    return m
func _solid(t, s, o, solid):
    if solid: _col(t, s, o)
func _col(t, s, o):
    var c = CollisionShape3D.new()
    var b = BoxShape3D.new()
    b.size = s
    c.shape = b
    c.position = o
    t.add_child(c)
