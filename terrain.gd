extends MeshInstance3D

# Streamed terrain: 10 x 10 chunks, 60m each (600m world).
const S: float = 6.0
const CHUNK_CELLS: int = 8
const CHUNK_SIZE: float = S * CHUNK_CELLS
const CHUNKS_PER_AXIS: int = 13
const WORLD_HALF: float = 300.0
const CITY_MIN_X: float = 100.0
const CITY_MAX_X: float = 250.0
const CITY_MIN_Z: float = -105.0
const CITY_MAX_Z: float = 105.0

var nz: FastNoiseLite = FastNoiseLite.new()
var city_ground_y: float = 0.0
var loaded_chunks: Dictionary = {}
var update_timer: float = 0.0
const UPDATE_INTERVAL := 0.5
const ACTIVE_RADIUS := 1

func _init() -> void:
    nz.seed = 7
    nz.frequency = 0.008
    city_ground_y = nz.get_noise_2d(175.0, 0.0) * 18.0

func height(x: float, z: float) -> float:
    var city_blend: float = _city_blend(x, z)
    var noise_value: float = nz.get_noise_2d(x, z)
    var flat_factor: float = _flat(x, z)
    var natural: float = noise_value * 18.0 * flat_factor
    var wall_height: float = _wall(x, z)
    return city_ground_y if city_blend >= 1.0 else lerpf(natural + wall_height, city_ground_y, city_blend)

## True when the collision of the chunk under (x, z) is loaded.
## Chunks only exist near players, so zombies far away must wait instead of falling through the world.
func has_ground(x: float, z: float) -> bool:
    return loaded_chunks.has(chunk_key_at(Vector3(x, 0.0, z)))

func chunk_key_at(pos: Vector3) -> Vector2i:
    return Vector2i(
        clampi(floori((pos.x + WORLD_HALF) / CHUNK_SIZE), 0, CHUNKS_PER_AXIS - 1),
        clampi(floori((pos.z + WORLD_HALF) / CHUNK_SIZE), 0, CHUNKS_PER_AXIS - 1)
    )

func _flat(x: float, z: float) -> float:
    var distance_from_origin: float = Vector2(x, z).length()
    var result: float = smoothstep(8.0, 18.0, distance_from_origin)
    result *= _c(x, z, Vector2(40.0, 30.0))
    result *= _c(x, z, Vector2(-70.0, 60.0))
    result *= _c(x, z, Vector2(20.0, -85.0))
    return clampf(result, 0.0, 1.0)

func _city_blend(x: float, z: float) -> float:
    if x < CITY_MIN_X or x > CITY_MAX_X or z < CITY_MIN_Z or z > CITY_MAX_Z:
        return 0.0
    var edge_x: float = minf(x - CITY_MIN_X, CITY_MAX_X - x)
    var edge_z: float = minf(z - CITY_MIN_Z, CITY_MAX_Z - z)
    return clampf(smoothstep(0.0, 10.0, minf(edge_x, edge_z)), 0.0, 1.0)

func _c(x: float, z: float, c: Vector2) -> float:
    return clampf(smoothstep(12.0, 24.0, Vector2(x, z).distance_to(c)), 0.0, 1.0)

func _wall(x: float, z: float) -> float:
    return smoothstep(260.0, 295.0, maxf(absf(x), absf(z))) * 90.0

func _ready() -> void:
    _refresh_chunks()

func _process(delta: float) -> void:
    update_timer += delta
    if update_timer >= UPDATE_INTERVAL:
        update_timer = 0.0
        _refresh_chunks()

func _player_chunk() -> Vector2i:
    var player = get_tree().get_first_node_in_group("player")
    return chunk_key_at(player.global_position) if player else Vector2i(5, 5)

func _refresh_chunks() -> void:
    var wanted: Dictionary = {}
    var players := get_tree().get_nodes_in_group("player")
    if players.is_empty():
        players = [null]
    for player in players:
        var center: Vector2i = chunk_key_at(player.global_position) if player != null else Vector2i(5, 5)
        for x in range(maxi(0, center.x - ACTIVE_RADIUS), mini(CHUNKS_PER_AXIS, center.x + ACTIVE_RADIUS + 1)):
            for z in range(maxi(0, center.y - ACTIVE_RADIUS), mini(CHUNKS_PER_AXIS, center.y + ACTIVE_RADIUS + 1)):
                var key := Vector2i(x, z)
                wanted[key] = true
                if not loaded_chunks.has(key):
                    _load_chunk(key)
    for key in loaded_chunks.keys():
        if not wanted.has(key):
            var old = loaded_chunks[key]
            if is_instance_valid(old):
                old.queue_free()
            loaded_chunks.erase(key)

func _load_chunk(key: Vector2i) -> void:
    var chunk := Node3D.new()
    chunk.name = "TerrainChunk_%d_%d" % [key.x, key.y]
    add_child(chunk)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_smooth_group(-1)
    var x0 := -WORLD_HALF + float(key.x) * CHUNK_SIZE
    var z0 := -WORLD_HALF + float(key.y) * CHUNK_SIZE
    var cells_x := mini(CHUNK_CELLS, ceili((WORLD_HALF - x0) / S))
    var cells_z := mini(CHUNK_CELLS, ceili((WORLD_HALF - z0) / S))
    for i in cells_x:
        for j in cells_z:
            _quad(st, x0 + i * S, z0 + j * S)
    st.generate_normals()
    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    mi.material_override = _mat()
    chunk.add_child(mi)
    mi.create_trimesh_collision()
    loaded_chunks[key] = chunk

func _quad(st: SurfaceTool, x: float, z: float) -> void:
    _tri(st, x, z, x + S, z, x, z + S)
    _tri(st, x + S, z, x + S, z + S, x, z + S)

func _tri(st: SurfaceTool, ax: float, az: float, bx: float, bz: float, cx: float, cz: float) -> void:
    _v(st, ax, az)
    _v(st, bx, bz)
    _v(st, cx, cz)

func _v(st: SurfaceTool, x: float, z: float) -> void:
    var y := height(x, z)
    st.set_color(_color(y, x, z))
    st.add_vertex(Vector3(x, y, z))

func _color(y: float, x: float, z: float) -> Color:
    if x >= CITY_MIN_X - 6.0 and x <= CITY_MAX_X + 6.0 and z >= CITY_MIN_Z - 6.0 and z <= CITY_MAX_Z + 6.0:
        return Color(0.055, 0.058, 0.062)
    return Color(0.1, 0.16, 0.07).lerp(Color(0.3, 0.3, 0.32), clampf((y - 9.0) / 10.0, 0.0, 1.0))

func _mat() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    return m
