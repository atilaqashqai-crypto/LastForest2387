extends Node3D

const STEEL_EDGE := Color(0.08, 0.09, 0.10)
# Abandoned city. No floating English signs: visual storytelling only.
# The hospital is a fully enterable three-floor horror landmark built from primitives.

const CITY_MIN_X: float = 100.0
const CITY_MAX_X: float = 250.0
const CITY_MIN_Z: float = -105.0
const CITY_MAX_Z: float = 105.0
const GROUND_Y: float = 0.04
const ROAD_Y: float = 0.08

const ROAD := Color(0.055, 0.058, 0.062)
const SIDEWALK := Color(0.22, 0.23, 0.22)
const CONCRETE := Color(0.25, 0.27, 0.29)
const CONCRETE_DARK := Color(0.12, 0.13, 0.14)
const WINDOW := Color(0.08, 0.18, 0.20)
const WINDOW_LIT := Color(0.72, 0.78, 0.70)
const ROOF := Color(0.07, 0.075, 0.08)
const BLOOD := Color(0.22, 0.008, 0.006)
const BLOOD_DARK := Color(0.075, 0.003, 0.002)
const HOSPITAL_WHITE := Color(0.42, 0.44, 0.43)
const HOSPITAL_FLOOR := Color(0.12, 0.14, 0.14)
const FLUORESCENT := Color(0.78, 0.88, 0.84)

const HOSP_X: float = 145.0
const HOSP_Z: float = 76.0
const HOSP_W: float = 52.0
const HOSP_D: float = 40.0
const FLOOR_H: float = 3.8
const WALL_H: float = 3.8
const WALL_T: float = 0.35

# Stairs: a gentle ramp (about 30 degrees) with painted step lines. CharacterBody3D cannot climb tall vertical
# step edges, so the walkable collision is a smooth slab and the steps are only visual lines on it.
const STAIR_W: float = 2.4
const STAIR_RUN: float = 6.0
const STAIR_THICK: float = 0.25
const STAIR_LINE := Color(0.46, 0.46, 0.43)
const H_STAIR_X: float = 5.0
const H_STAIR_Z0: float = -14.0
const H_STAIR_Z1: float = -7.5

# Performance: static boxes are merged into a few meshes; far geometry and lights are switched off.
const VIS_RANGE: float = 150.0
const LIGHT_RANGE: float = 42.0
const LIGHT_CHECK: float = 0.4

const FACES := [
    [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
    [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
    [Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
    [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
    [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
    [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]

class VBatch:
    var parent: Node3D
    var v := PackedVector3Array()
    var n := PackedVector3Array()
    var c := PackedColorArray()
    var idx := PackedInt32Array()

var _batches: Dictionary = {}
var _mat_cache: Dictionary = {}
var _vertex_mat: StandardMaterial3D = null
var _lights: Array = []
var _light_timer: float = 0.0
var _flickers: Array = []
var _flicker_timer: float = 0.0
var _terrain: Node = null

func _ready() -> void:
    call_deferred("_align_to_flat_terrain_and_build")

func _process(delta: float) -> void:
    if _lights.is_empty():
        return
    _flicker_timer += delta
    if _flicker_timer >= 0.08:
        _flicker_timer = 0.0
        _update_flicker()
    _light_timer += delta
    if _light_timer < LIGHT_CHECK:
        return
    _light_timer = 0.0
    _update_lights()

func _update_flicker() -> void:
    for f in _flickers:
        var l: Light3D = f["light"]
        if not is_instance_valid(l) or not l.visible:
            continue
        var base: float = f["base"]
        var r: float = randf()
        if r < 0.10:
            l.light_energy = base * 0.05
        elif r < 0.18:
            l.light_energy = base * 0.45
        else:
            l.light_energy = base

func _update_lights() -> void:
    var players := get_tree().get_nodes_in_group("player")
    if players.is_empty():
        return
    var limit: float = LIGHT_RANGE * LIGHT_RANGE
    for l in _lights:
        if not is_instance_valid(l):
            continue
        var near: bool = false
        for p in players:
            if l.global_position.distance_squared_to(p.global_position) < limit:
                near = true
                break
        l.visible = near

func _register_light(l: Light3D, flicker: bool = false) -> void:
    l.visible = false
    _lights.append(l)
    if flicker:
        _flickers.append({"light": l, "base": l.light_energy})

func _align_to_flat_terrain_and_build() -> void:
    var terrain := get_node_or_null("../Terrain")
    _terrain = terrain
    if terrain != null and terrain.has_method("height"):
        # Terrain exposes the exact flat city height at its center.
        global_position.y = float(terrain.call("height", 175.0, 0.0))
    _build_city()

func _build_city() -> void:
    _build_city_ground()
    _build_main_roads()
    _build_side_roads()
    _build_buildings()
    _build_hospital()
    _build_street_lights()
    _build_city_details()
    _build_city_skirt()
    _flush_batches()

func _build_city_ground() -> void:
    # A dedicated flat slab only under the city. This prevents asphalt from following forest terrain.
    _box(Vector3(152.0, 0.08, 212.0), Vector3(175.0, 0.0, 0.0), ROAD, true)

func _build_main_roads() -> void:
    # Roads sit only in the open corridors between building blocks.
    # Split the west street around the hospital footprint.
    _road(Vector3(7, 0.10, 94), Vector3(125, ROAD_Y, -8))
    _road(Vector3(7, 0.10, 50), Vector3(125, ROAD_Y, 77))
    _road(Vector3(7, 0.10, 190), Vector3(185, ROAD_Y, 0))
    _road(Vector3(7, 0.10, 190), Vector3(220, ROAD_Y, 0))

func _build_side_roads() -> void:
    # Roads are placed in the gaps between building lots, so asphalt never passes under buildings.
    # Horizontal streets occupy the gaps between rows, never the building footprints.
    for z in [-42.0, 0.0, 42.0]:
        _road(Vector3(142, 0.10, 7), Vector3(178, ROAD_Y - 0.02, z))

func _road(size: Vector3, pos: Vector3) -> void:
    _box(size, pos, ROAD, false)
    if size.x > size.z:
        for x in range(int(pos.x - size.x / 2.0) + 5, int(pos.x + size.x / 2.0) - 4, 10):
            _box(Vector3(4.0, 0.025, 0.16), Vector3(x, pos.y + 0.07, pos.z), Color(0.46, 0.40, 0.17), false)
    else:
        for z in range(int(pos.z - size.z / 2.0) + 5, int(pos.z + size.z / 2.0) - 4, 10):
            _box(Vector3(0.16, 0.025, 4.0), Vector3(pos.x, pos.y + 0.07, z), Color(0.46, 0.40, 0.17), false)

func _build_buildings() -> void:
    # Half the lots stay as 2-storey buildings. Cleared lots become landmarks.
    # Hospital is built separately and is never removed.
    var lots: Array[Vector3] = [
        Vector3(110, 0, -65), Vector3(140, 0, -65), Vector3(170, 0, -65), Vector3(205, 0, -65), Vector3(235, 0, -65),
        Vector3(110, 0, -20), Vector3(140, 0, -20), Vector3(170, 0, -20), Vector3(205, 0, -20), Vector3(235, 0, -20),
        Vector3(110, 0, 20), Vector3(140, 0, 20), Vector3(170, 0, 20), Vector3(205, 0, 20), Vector3(235, 0, 20),
        Vector3(110, 0, 65), Vector3(205, 0, 65), Vector3(235, 0, 65)
    ]
    # Deterministic keep-mask: about half of the residential lots remain.
    var keep: Array[bool] = [
        true, false, false, true, true,
        false, true, true, false, true,
        true, false, true, false, true,
        false, true, false
    ]
    # Landmarks occupy cleared space (gas station spans two southern lots).
    _build_gas_station(Vector3(155, 0, -65))
    _build_supermarket(Vector3(140, 0, 20))
    _build_ruined_restaurant(Vector3(170, 0, -20))

    var idx: int = 0
    for p in lots:
        if idx < keep.size() and not keep[idx]:
            idx += 1
            continue
        # Skip lots claimed by landmarks
        if p.distance_to(Vector3(140, 0, -65)) < 5.0 or p.distance_to(Vector3(170, 0, -65)) < 5.0:
            idx += 1
            continue
        if p.distance_to(Vector3(140, 0, 20)) < 5.0 or p.distance_to(Vector3(170, 0, -20)) < 5.0:
            idx += 1
            continue
        var w: float = 18.0 + float((idx * 5) % 6)
        var d: float = 18.0 + float((idx * 7) % 6)
        _build_building(p, Vector3(w, 7.0, d), idx)
        idx += 1

func _build_building(center: Vector3, size: Vector3, idx: int) -> void:
    var floors: int = 2
    var floor_h: float = 3.45
    var total_h: float = floor_h * float(floors)
    var body := StaticBody3D.new()
    body.position = Vector3(center.x, GROUND_Y + total_h / 2.0, center.z)
    body.set_meta("batch", true)
    add_child(body)

    var style: int = idx % 6
    var facade := Color(0.30, 0.13, 0.09) if style == 1 or style == 4 else Color(0.20, 0.22, 0.24)
    if style == 2:
        facade = Color(0.34, 0.28, 0.22)
    elif style == 3:
        facade = Color(0.16, 0.19, 0.21)
    elif style == 5:
        facade = Color(0.28, 0.28, 0.25)

    # Open interior: four walkable floor plates and perimeter walls, not a solid block.
    for floor in range(floors):
        var fy: float = -total_h / 2.0 + float(floor) * floor_h
        _build_building_floor_with_stairwell(body, size, fy, floor, CONCRETE_DARK if floor == 0 else Color(0.25, 0.25, 0.23))
        var wall_y: float = fy + floor_h / 2.0
        _box_local(body, Vector3(size.x, floor_h, 0.28), Vector3(0, wall_y, size.z / 2.0), facade, true)
        _box_local(body, Vector3(0.28, floor_h, size.z), Vector3(-size.x / 2.0, wall_y, 0), facade, true)
        _box_local(body, Vector3(0.28, floor_h, size.z), Vector3(size.x / 2.0, wall_y, 0), facade, true)
        # Front wall is split to leave a real entrance opening at ground level.
        if floor == 0:
            var side_w: float = (size.x - 3.2) / 2.0
            _box_local(body, Vector3(side_w, floor_h, 0.28), Vector3(-size.x / 2.0 + side_w / 2.0, wall_y, -size.z / 2.0), facade, true)
            _box_local(body, Vector3(side_w, floor_h, 0.28), Vector3(size.x / 2.0 - side_w / 2.0, wall_y, -size.z / 2.0), facade, true)
            _box_local(body, Vector3(3.2, 0.65, 0.28), Vector3(0, wall_y + floor_h / 2.0 - 0.325, -size.z / 2.0), facade, true)
        else:
            _box_local(body, Vector3(size.x, floor_h, 0.28), Vector3(0, wall_y, -size.z / 2.0), facade, true)

        # Window styles vary by building and by floor.
        var window_color: Color = WINDOW_LIT if (idx + floor) % 4 == 0 else WINDOW
        var win_w: float = 2.2 if style % 2 == 0 else 1.35
        var win_h: float = 1.35 if style % 3 != 0 else 2.0
        for col in range(3):
            var wx: float = -size.x * 0.30 + float(col) * size.x * 0.30
            var wy: float = fy + 1.85
            var wz: float = -size.z / 2.0 - 0.17
            # Keep the center of the ground-floor front facade clear: it is the real doorway.
            var is_front_door_window: bool = floor == 0 and col == 1
            if not is_front_door_window:
                _box_local(body, Vector3(win_w, win_h, 0.08), Vector3(wx, wy, wz), window_color, false)
            if style == 2 or style == 5:
                _box_local(body, Vector3(win_w, win_h, 0.08), Vector3(wx, wy, size.z / 2.0 + 0.17), window_color, false)
        if style == 1 or style == 4:
            _box_local(body, Vector3(size.x + 0.04, 0.07, 0.08), Vector3(0, fy + 0.35, -size.z / 2.0 - 0.18), Color(0.16, 0.08, 0.06), false)

    # Roof cap and parapet.
    _box_local(body, Vector3(size.x + 0.7, 0.25, size.z + 0.7), Vector3(0, total_h / 2.0, 0), ROOF, true)
    _box_local(body, Vector3(size.x + 0.4, 0.65, 0.25), Vector3(0, total_h / 2.0 + 0.42, -size.z / 2.0), facade, true)

    # Connect every floor with a real stairwell inside the building.
    _build_building_stairs(body, size, floor_h, total_h)

    # City doors are manually toggled with the interaction key, not proximity triggers.
    var door_color: Color = CONCRETE_DARK if style % 2 == 0 else Color(0.20, 0.10, 0.06)
    _make_openable_door(body, 3.0, 2.9, Vector3(-1.5, -total_h / 2.0, -size.z / 2.0 - 0.18), door_color)
    # Unique horror interior props per building so they do not feel identical.
    _decorate_building_interior(body, size, floor_h, total_h, style, idx)
    _decorate_common(body, size, floor_h, total_h, idx)
    _decorate_upper_floor(body, size, floor_h, total_h, style, idx)
    _scatter_building_loot(center, idx)
    _scatter_upper_loot(center, size, idx, floor_h)

func _build_building_floor_with_stairwell(parent: Node3D, size: Vector3, fy: float, lv: int, color: Color) -> void:
    # Ground floor is solid. Floors 1..3 have an opening exactly where the stair ramp below arrives.
    var slab_x: float = size.x - 0.5
    var slab_z: float = size.z - 0.5
    if lv == 0:
        _box_local(parent, Vector3(slab_x, 0.22, slab_z), Vector3(0, fy, 0), color, true)
        return
    var hw: float = STAIR_W * 0.5
    var z_a: float = size.z * 0.22 - STAIR_RUN * 0.5
    var z_b: float = size.z * 0.22 + STAIR_RUN * 0.5
    var side_w: float = (slab_x - STAIR_W) * 0.5
    _box_local(parent, Vector3(side_w, 0.22, slab_z), Vector3(-(hw + side_w * 0.5), fy, 0), color, true)
    _box_local(parent, Vector3(side_w, 0.22, slab_z), Vector3(hw + side_w * 0.5, fy, 0), color, true)
    var front_d: float = z_a + slab_z * 0.5
    if front_d > 0.1:
        _box_local(parent, Vector3(STAIR_W, 0.22, front_d), Vector3(0, fy, -slab_z * 0.5 + front_d * 0.5), color, true)
    var back_d: float = slab_z * 0.5 - z_b
    if back_d > 0.1:
        _box_local(parent, Vector3(STAIR_W, 0.22, back_d), Vector3(0, fy, slab_z * 0.5 - back_d * 0.5), color, true)

func _build_building_stairs(parent: Node3D, size: Vector3, floor_h: float, total_h: float) -> void:
    # One straight ramp per storey, all in the same shaft. Each ramp ends at the edge of the next floor.
    var z_a: float = size.z * 0.22 - STAIR_RUN * 0.5
    var z_b: float = size.z * 0.22 + STAIR_RUN * 0.5
    var key: String = "b%d" % parent.get_instance_id()
    var levels: int = maxi(int(round(total_h / floor_h)) - 1, 0)
    for lv in range(levels):
        var y_a: float = -total_h * 0.5 + float(lv) * floor_h + 0.11
        _make_ramp(parent, key, parent, 0.0, STAIR_W, z_a, z_b, y_a, y_a + floor_h, CONCRETE_DARK)

func _make_ramp(phys_parent: Node3D, vis_key: String, vis_parent: Node3D, x: float, width: float, z_a: float, z_b: float, y_a: float, y_b: float, color: Color) -> void:
    # y_a / y_b are the walking-surface heights at z_a / z_b.
    var rise: float = y_b - y_a
    var run_len: float = z_b - z_a
    var slope_len: float = sqrt(run_len * run_len + rise * rise)
    var theta: float = atan2(rise, run_len)
    var tilt := Basis(Vector3.RIGHT, -theta)
    var normal: Vector3 = tilt * Vector3.UP
    var mid := Vector3(x, (y_a + y_b) * 0.5, (z_a + z_b) * 0.5)
    var center: Vector3 = mid - normal * (STAIR_THICK * 0.5)
    var xf := Transform3D(tilt, center)
    var cs := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(width, STAIR_THICK, slope_len)
    cs.shape = shape
    cs.transform = xf
    phys_parent.add_child(cs)
    _vis_add(vis_key, vis_parent, Vector3(width, STAIR_THICK, slope_len), xf, color)
    var lines: int = int(slope_len / 0.5)
    for i in range(lines):
        var lz: float = -slope_len * 0.5 + 0.3 + float(i) * 0.5
        var lxf := Transform3D(tilt, center + tilt * Vector3(0.0, STAIR_THICK * 0.5 + 0.012, lz))
        _vis_add(vis_key, vis_parent, Vector3(width - 0.1, 0.03, 0.10), lxf, STAIR_LINE)



func _scatter_building_loot(center: Vector3, idx: int) -> void:
    # Sparse random supplies inside ordinary city buildings only.
    var rng := RandomNumberGenerator.new()
    rng.seed = int(center.x * 13.0 + center.z * 7.0 + float(idx) * 97.0)
    var kinds: Array[String] = ["food", "water", "ammo_pistol", "medkits", "ammo_shotgun"]
    var count: int = rng.randi_range(1, 2)
    for i in range(count):
        var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
        var ox: float = rng.randf_range(-5.0, 5.0)
        var oz: float = rng.randf_range(-5.0, 5.0)
        _city_pickup(kind, Vector3(center.x + ox, GROUND_Y + 0.7, center.z + oz))

func _decorate_building_interior(parent: Node3D, size: Vector3, floor_h: float, total_h: float, style: int, idx: int) -> void:
    # Ground-floor interior props. Each theme is different so buildings feel unique and unsettling.
    var y0: float = -total_h / 2.0 + 0.15
    var theme: int = (style + idx * 3) % 6
    match theme:
        0:
            # Ruined apartment
            _box_local(parent, Vector3(2.2, 0.25, 1.1), Vector3(-2.5, y0 + 0.2, 1.5), Color(0.25, 0.18, 0.14), true)
            _box_local(parent, Vector3(2.0, 0.12, 0.95), Vector3(-2.5, y0 + 0.38, 1.5), Color(0.35, 0.12, 0.10), false)
            _box_local(parent, Vector3(1.4, 0.08, 0.8), Vector3(2.2, y0 + 0.55, -1.2), Color(0.28, 0.22, 0.16), false)
            _box_local(parent, Vector3(0.12, 0.55, 0.12), Vector3(1.7, y0 + 0.3, -1.5), Color(0.18, 0.12, 0.08), false)
            _box_local(parent, Vector3(0.12, 0.55, 0.12), Vector3(2.7, y0 + 0.3, -0.9), Color(0.18, 0.12, 0.08), false)
            _box_local(parent, Vector3(1.6, 0.02, 0.5), Vector3(0.2, y0 + 0.03, 0.5), BLOOD_DARK, false)
            _box_local(parent, Vector3(0.7, 0.02, 0.9), Vector3(-1.0, y0 + 0.03, 2.0), BLOOD, false)
        1:
            # Looted shop
            for i in range(3):
                var zx: float = -2.5 + float(i) * 2.2
                _box_local(parent, Vector3(0.9, 2.2, 0.35), Vector3(zx, y0 + 1.2, size.z * 0.28), Color(0.22, 0.20, 0.17), true)
                _box_local(parent, Vector3(0.85, 0.05, 0.3), Vector3(zx, y0 + 0.7, size.z * 0.28), Color(0.30, 0.28, 0.24), false)
                _box_local(parent, Vector3(0.85, 0.05, 0.3), Vector3(zx, y0 + 1.4, size.z * 0.28), Color(0.30, 0.28, 0.24), false)
            _box_local(parent, Vector3(2.5, 1.0, 0.7), Vector3(0.5, y0 + 0.55, -size.z * 0.2), Color(0.18, 0.16, 0.14), true)
            _box_local(parent, Vector3(0.5, 0.35, 0.4), Vector3(-2.0, y0 + 0.25, -1.5), Color(0.40, 0.28, 0.12), false)
            _box_local(parent, Vector3(0.45, 0.3, 0.35), Vector3(2.8, y0 + 0.22, 0.8), Color(0.35, 0.22, 0.10), false)
        2:
            # Dead office
            _box_local(parent, Vector3(1.6, 0.08, 0.9), Vector3(-2.0, y0 + 0.85, -1.0), Color(0.32, 0.30, 0.26), true)
            _box_local(parent, Vector3(0.08, 0.8, 0.08), Vector3(-2.6, y0 + 0.4, -1.3), Color(0.15, 0.12, 0.10), false)
            _box_local(parent, Vector3(0.08, 0.8, 0.08), Vector3(-1.4, y0 + 0.4, -0.7), Color(0.15, 0.12, 0.10), false)
            _box_local(parent, Vector3(1.5, 0.08, 0.85), Vector3(2.2, y0 + 0.85, 1.5), Color(0.28, 0.26, 0.22), true)
            _box_local(parent, Vector3(0.55, 1.0, 0.55), Vector3(0.2, y0 + 0.55, 0.3), Color(0.12, 0.13, 0.14), false)
            _box_local(parent, Vector3(0.4, 0.02, 0.5), Vector3(-0.5, y0 + 0.04, -2.0), Color(0.75, 0.72, 0.65), false)
            _box_local(parent, Vector3(0.35, 0.02, 0.45), Vector3(1.0, y0 + 0.04, -1.5), Color(0.70, 0.68, 0.60), false)
            _box_local(parent, Vector3(1.2, 0.02, 0.4), Vector3(2.0, y0 + 0.03, 0.2), BLOOD_DARK, false)
        3:
            # Barricaded room
            _box_local(parent, Vector3(1.8, 1.4, 0.5), Vector3(-size.x * 0.25, y0 + 0.75, size.z * 0.15), Color(0.20, 0.14, 0.10), true)
            _box_local(parent, Vector3(1.2, 0.9, 0.7), Vector3(-size.x * 0.2, y0 + 0.5, size.z * 0.05), Color(0.16, 0.12, 0.09), true)
            _box_local(parent, Vector3(0.9, 0.02, 1.5), Vector3(1.5, y0 + 0.03, -0.5), BLOOD, false)
            _box_local(parent, Vector3(0.5, 0.02, 0.8), Vector3(2.5, y0 + 0.03, 1.2), BLOOD_DARK, false)
            _box_local(parent, Vector3(0.08, 1.6, 0.6), Vector3(size.x * 0.3, y0 + 1.5, -size.z * 0.15), Color(0.15, 0.05, 0.04), false)
            _box_local(parent, Vector3(0.6, 0.4, 0.35), Vector3(0.0, y0 + 0.25, -2.0), Color(0.08, 0.08, 0.09), false)
        4:
            # Storage crates
            for i in range(4):
                var cx: float = -2.8 + float(i % 2) * 1.4
                var cz: float = -1.5 + float(i / 2) * 1.5
                _box_local(parent, Vector3(0.9, 0.7 + float(i % 2) * 0.3, 0.9), Vector3(cx, y0 + 0.4, cz), Color(0.30, 0.22, 0.12), true)
            _box_local(parent, Vector3(0.7, 1.1, 0.7), Vector3(2.5, y0 + 0.6, 2.0), Color(0.18, 0.20, 0.16), true)
            _box_local(parent, Vector3(0.7, 1.1, 0.7), Vector3(3.3, y0 + 0.6, 2.0), Color(0.16, 0.18, 0.14), true)
            _box_local(parent, Vector3(1.0, 0.02, 0.6), Vector3(-1.0, y0 + 0.03, 2.5), BLOOD_DARK, false)
        _:
            # Quiet chapel horror
            _box_local(parent, Vector3(1.2, 0.5, 0.4), Vector3(-2.0, y0 + 0.35, 0.5), Color(0.18, 0.12, 0.08), true)
            _box_local(parent, Vector3(1.2, 0.5, 0.4), Vector3(0.5, y0 + 0.35, 0.5), Color(0.18, 0.12, 0.08), true)
            _box_local(parent, Vector3(1.2, 0.5, 0.4), Vector3(2.5, y0 + 0.35, -0.8), Color(0.16, 0.11, 0.07), true)
            _box_local(parent, Vector3(1.5, 1.0, 0.6), Vector3(0.0, y0 + 0.55, -size.z * 0.25), Color(0.12, 0.10, 0.09), true)
            _box_local(parent, Vector3(0.08, 0.25, 0.08), Vector3(-0.3, y0 + 1.15, -size.z * 0.25), Color(0.55, 0.45, 0.25), false)
            _box_local(parent, Vector3(0.08, 0.2, 0.08), Vector3(0.3, y0 + 1.12, -size.z * 0.25), Color(0.50, 0.40, 0.20), false)
            _box_local(parent, Vector3(0.8, 0.02, 1.2), Vector3(0.0, y0 + 0.03, 1.5), BLOOD_DARK, false)
    # Shared entrance debris
    var ox: float = float((idx % 3) - 1) * 0.8
    _box_local(parent, Vector3(0.5, 0.35, 0.4), Vector3(ox + 1.5, y0 + 0.2, -size.z * 0.35), Color(0.22, 0.18, 0.14), false)
    _box_local(parent, Vector3(0.35, 0.25, 0.3), Vector3(ox - 1.8, y0 + 0.15, -size.z * 0.3), Color(0.15, 0.14, 0.12), false)
    if idx % 2 == 0:
        _box_local(parent, Vector3(0.6, 0.02, 0.35), Vector3(ox, y0 + 0.03, -size.z * 0.28), BLOOD, false)


# ======================================================================
# Building interiors v2: details on every floor, a different 2nd floor per building
# ======================================================================
func _decorate_common(parent: Node3D, size: Vector3, floor_h: float, total_h: float, idx: int) -> void:
    var hx: float = size.x * 0.5
    var hz: float = size.z * 0.5
    var base_col := Color(0.11, 0.10, 0.09)
    var lamp_col := Color(0.80, 0.78, 0.66)
    for f in range(2):
        var fy: float = -total_h / 2.0 + float(f) * floor_h
        # Baseboards along the back and side walls
        _box_local(parent, Vector3(size.x - 0.6, 0.18, 0.05), Vector3(0, fy + 0.24, hz - 0.19), base_col, false)
        _box_local(parent, Vector3(0.05, 0.18, size.z - 0.6), Vector3(-hx + 0.19, fy + 0.24, 0), base_col, false)
        _box_local(parent, Vector3(0.05, 0.18, size.z - 0.6), Vector3(hx - 0.19, fy + 0.24, 0), base_col, false)
        # Ceiling lamps (one dead, one hanging by a wire)
        var cy: float = fy + floor_h - 0.22
        _box_local(parent, Vector3(1.3, 0.06, 0.32), Vector3(-hx * 0.45, cy, -hz * 0.25), lamp_col, false)
        _box_local(parent, Vector3(1.3, 0.06, 0.32), Vector3(hx * 0.45, cy, hz * 0.3), Color(0.20, 0.20, 0.19), false)
        _box_local(parent, Vector3(0.03, 0.4, 0.03), Vector3(hx * 0.45, cy + 0.2, hz * 0.3), Color(0.05, 0.05, 0.05), false)
        # Door mat / water stain and a bit of ceiling damage
        _box_local(parent, Vector3(2.2, 0.02, 1.2), Vector3(hx * 0.3, fy + 0.13, -hz * 0.55), Color(0.10, 0.08, 0.06), false)
        _box_local(parent, Vector3(1.8, 0.02, 1.8), Vector3(-hx * 0.5, fy + floor_h - 0.12, hz * 0.4), Color(0.17, 0.15, 0.10), false)
        var l := OmniLight3D.new()
        l.position = Vector3(-hx * 0.45, cy - 0.4, -hz * 0.25)
        l.light_color = Color(1.0, 0.86, 0.62)
        l.light_energy = 0.42
        l.omni_range = 10.0
        parent.add_child(l)
        _register_light(l, (idx + f) % 3 == 0)
    # Railings around the stairwell opening on the upper floor
    var fy1: float = -total_h / 2.0 + floor_h
    var z_a: float = size.z * 0.22 - STAIR_RUN * 0.5
    var z_b: float = size.z * 0.22 + STAIR_RUN * 0.5
    var rail := Color(0.12, 0.12, 0.13)
    for sx in [-1.0, 1.0]:
        var rx: float = float(sx) * (STAIR_W * 0.5 + 0.03)
        _box_local(parent, Vector3(0.06, 0.95, z_b - z_a), Vector3(rx, fy1 + 0.6, (z_a + z_b) * 0.5), rail, true)
    _box_local(parent, Vector3(STAIR_W + 0.12, 0.95, 0.06), Vector3(0, fy1 + 0.6, z_a), rail, true)

func _decorate_upper_floor(parent: Node3D, size: Vector3, floor_h: float, total_h: float, style: int, idx: int) -> void:
    var yb: float = -total_h / 2.0 + floor_h + 0.15
    var theme: int = (idx * 2 + style) % 5
    match theme:
        0:
            _upper_bedrooms(parent, size, yb)
        1:
            _upper_office(parent, size, yb)
        2:
            _upper_archive(parent, size, yb)
        3:
            _upper_camp(parent, size, yb)
        _:
            _upper_apartment(parent, size, yb)
    # A little blood on every second building's upper landing
    if idx % 2 == 1:
        _box_local(parent, Vector3(1.4, 0.02, 0.9), Vector3(size.x * 0.22, yb - 0.02, size.z * 0.42), BLOOD, false)
        _box_local(parent, Vector3(0.5, 0.02, 2.2), Vector3(size.x * 0.22, yb - 0.02, size.z * 0.28), BLOOD_DARK, false)

func _bed(parent: Node3D, x: float, z: float, yb: float, along_x: bool, sheet: Color) -> void:
    var dm: Vector3 = Vector3(2.1, 0.35, 1.1) if along_x else Vector3(1.1, 0.35, 2.1)
    _box_local(parent, dm, Vector3(x, yb + 0.18, z), Color(0.20, 0.13, 0.09), true)
    _box_local(parent, Vector3(dm.x - 0.12, 0.16, dm.z - 0.12), Vector3(x, yb + 0.43, z), sheet, false)
    var pil: Vector3 = Vector3(0.4, 0.12, 0.8) if along_x else Vector3(0.8, 0.12, 0.4)
    var po: Vector3 = Vector3(-0.75, 0.57, 0.0) if along_x else Vector3(0.0, 0.57, -0.75)
    _box_local(parent, pil, Vector3(x, yb, z) + po, Color(0.72, 0.70, 0.64), false)

func _desk(parent: Node3D, x: float, z: float, yb: float) -> void:
    _box_local(parent, Vector3(1.6, 0.06, 0.8), Vector3(x, yb + 0.78, z), Color(0.30, 0.25, 0.19), true)
    _box_local(parent, Vector3(0.06, 0.76, 0.8), Vector3(x - 0.75, yb + 0.38, z), Color(0.20, 0.16, 0.12), true)
    _box_local(parent, Vector3(0.06, 0.76, 0.8), Vector3(x + 0.75, yb + 0.38, z), Color(0.20, 0.16, 0.12), true)
    _box_local(parent, Vector3(0.55, 0.40, 0.05), Vector3(x - 0.3, yb + 1.04, z - 0.15), Color(0.07, 0.08, 0.09), false)
    _box_local(parent, Vector3(0.18, 0.08, 0.18), Vector3(x - 0.3, yb + 0.85, z - 0.15), Color(0.10, 0.10, 0.10), false)
    _box_local(parent, Vector3(0.5, 0.06, 0.5), Vector3(x + 0.1, yb + 0.45, z + 0.85), Color(0.14, 0.14, 0.16), false)
    _box_local(parent, Vector3(0.5, 0.5, 0.06), Vector3(x + 0.1, yb + 0.72, z + 1.1), Color(0.14, 0.14, 0.16), false)
    _box_local(parent, Vector3(0.08, 0.45, 0.08), Vector3(x + 0.1, yb + 0.22, z + 0.85), Color(0.08, 0.08, 0.08), false)

func _upper_bedrooms(parent: Node3D, size: Vector3, yb: float) -> void:
    var hx: float = size.x * 0.5
    var hz: float = size.z * 0.5
    _bed(parent, -hx + 2.3, -hz + 2.4, yb, true, Color(0.28, 0.30, 0.42))
    _bed(parent, -hx + 2.3, -hz + 5.0, yb, true, Color(0.40, 0.20, 0.20))
    _bed(parent, hx - 2.3, -hz + 2.4, yb, true, Color(0.18, 0.30, 0.24))
    _box_local(parent, Vector3(0.5, 0.5, 0.5), Vector3(-hx + 0.9, yb + 0.25, -hz + 3.7), Color(0.22, 0.16, 0.11), true)
    _box_local(parent, Vector3(0.5, 0.5, 0.5), Vector3(hx - 0.9, yb + 0.25, -hz + 3.7), Color(0.22, 0.16, 0.11), true)
    # wardrobes against the back wall, one with its door hanging open
    _box_local(parent, Vector3(1.3, 2.2, 0.6), Vector3(-hx + 1.8, yb + 1.1, hz - 0.5), Color(0.24, 0.17, 0.11), true)
    _box_local(parent, Vector3(1.3, 2.2, 0.6), Vector3(hx - 1.8, yb + 1.1, hz - 0.5), Color(0.24, 0.17, 0.11), true)
    _box_local(parent, Vector3(0.7, 2.1, 0.05), Vector3(hx - 2.7, yb + 1.05, hz - 0.95), Color(0.30, 0.21, 0.14), false)
    # dresser with a cracked mirror
    _box_local(parent, Vector3(1.2, 0.9, 0.5), Vector3(-hx + 0.5, yb + 0.45, 0.2), Color(0.26, 0.18, 0.12), true)
    _box_local(parent, Vector3(0.05, 0.9, 0.8), Vector3(-hx + 0.22, yb + 1.45, 0.2), Color(0.45, 0.52, 0.55), false)
    # rug and scattered clothes
    _box_local(parent, Vector3(3.0, 0.02, 2.2), Vector3(-hx + 5.0, yb - 0.02, -hz + 4.0), Color(0.30, 0.12, 0.10), false)
    _box_local(parent, Vector3(0.7, 0.03, 0.5), Vector3(-hx + 6.5, yb - 0.01, -hz + 6.5), Color(0.20, 0.26, 0.34), false)
    _box_local(parent, Vector3(0.5, 0.03, 0.6), Vector3(hx - 5.0, yb - 0.01, -hz + 5.0), Color(0.55, 0.50, 0.40), false)
    _box_local(parent, Vector3(1.2, 0.02, 0.8), Vector3(hx - 4.0, yb - 0.02, -hz + 6.0), BLOOD_DARK, false)

func _upper_office(parent: Node3D, size: Vector3, yb: float) -> void:
    var hx: float = size.x * 0.5
    var hz: float = size.z * 0.5
    _desk(parent, -hx + 3.4, -hz + 3.0, yb)
    _desk(parent, -hx + 3.4, -hz + 7.0, yb)
    _desk(parent, hx - 3.4, -hz + 3.0, yb)
    _desk(parent, hx - 3.4, -hz + 7.0, yb)
    for i in range(3):
        _box_local(parent, Vector3(0.6, 1.4, 0.5), Vector3(-hx + 1.0 + float(i) * 0.65, yb + 0.7, hz - 0.5), Color(0.34, 0.36, 0.36), true)
    _box_local(parent, Vector3(3.2, 1.3, 0.06), Vector3(hx - 4.0, yb + 1.6, hz - 0.2), Color(0.78, 0.78, 0.74), false)
    _box_local(parent, Vector3(2.4, 0.05, 0.04), Vector3(hx - 4.0, yb + 1.9, hz - 0.23), Color(0.55, 0.05, 0.05), false)
    _box_local(parent, Vector3(0.4, 1.1, 0.4), Vector3(hx - 1.0, yb + 0.55, -hz + 1.0), Color(0.80, 0.82, 0.82), true)
    _box_local(parent, Vector3(0.34, 0.35, 0.34), Vector3(hx - 1.0, yb + 1.28, -hz + 1.0), Color(0.30, 0.55, 0.75), false)
    for i in range(4):
        _box_local(parent, Vector3(0.4, 0.02, 0.3), Vector3(-hx + 5.5 + float(i) * 1.1, yb - 0.02, -hz + 5.2 + float(i % 2) * 1.3), Color(0.76, 0.74, 0.68), false)
    _box_local(parent, Vector3(1.4, 0.02, 0.9), Vector3(-hx + 4.8, yb - 0.02, -hz + 4.8), BLOOD_DARK, false)

func _upper_archive(parent: Node3D, size: Vector3, yb: float) -> void:
    var hx: float = size.x * 0.5
    var hz: float = size.z * 0.5
    var wood := Color(0.24, 0.19, 0.13)
    var cardboard := Color(0.42, 0.32, 0.20)
    for sx in [-1.0, 1.0]:
        var x: float = float(sx) * (hx - 2.6)
        _box_local(parent, Vector3(0.5, 2.3, 7.0), Vector3(x, yb + 1.15, -hz + 5.0), wood, true)
        for tier in range(3):
            for k in range(4):
                var c: Color = cardboard if (k + tier) % 2 == 0 else Color(0.30, 0.30, 0.28)
                _box_local(parent, Vector3(0.42, 0.3, 0.55), Vector3(x + float(sx) * 0.02, yb + 0.55 + float(tier) * 0.7, -hz + 2.2 + float(k) * 1.5 + float(tier) * 0.2), c, false)
    _box_local(parent, Vector3(1.0, 0.9, 1.0), Vector3(-hx + 1.0, yb + 0.45, hz - 1.0), cardboard, true)
    _box_local(parent, Vector3(0.9, 0.7, 0.9), Vector3(-hx + 2.1, yb + 0.35, hz - 1.0), cardboard, true)
    _box_local(parent, Vector3(0.8, 0.5, 0.8), Vector3(-hx + 1.5, yb + 1.15, hz - 1.0), cardboard, true)
    _box_local(parent, Vector3(1.8, 0.9, 1.0), Vector3(hx - 2.0, yb + 0.45, hz - 1.0), Color(0.18, 0.22, 0.16), true)
    # a shelf that fell over and spilled its boxes
    _box_local(parent, Vector3(2.8, 0.35, 0.5), Vector3(0, yb + 0.18, -hz + 2.0), wood, true)
    for i in range(5):
        _box_local(parent, Vector3(0.4, 0.3, 0.5), Vector3(-1.2 + float(i) * 0.7, yb + 0.15, -hz + 3.0 + float(i % 2) * 0.6), cardboard, false)

func _upper_camp(parent: Node3D, size: Vector3, yb: float) -> void:
    var hx: float = size.x * 0.5
    var hz: float = size.z * 0.5
    # Survivors barricaded in: planks over the windows, mattresses, a stash of cans.
    for i in range(3):
        _box_local(parent, Vector3(size.x * 0.5, 0.16, 0.1), Vector3(0, yb + 1.25 + float(i) * 0.38, -hz + 0.25), Color(0.30, 0.22, 0.14), false)
    _box_local(parent, Vector3(0.14, 1.4, 0.1), Vector3(-size.x * 0.18, yb + 1.6, -hz + 0.25), Color(0.26, 0.19, 0.12), false)
    _box_local(parent, Vector3(0.14, 1.4, 0.1), Vector3(size.x * 0.18, yb + 1.6, -hz + 0.25), Color(0.26, 0.19, 0.12), false)
    _box_local(parent, Vector3(1.9, 0.18, 0.95), Vector3(-hx + 2.0, yb + 0.0, -hz + 3.0), Color(0.30, 0.32, 0.26), false)
    _box_local(parent, Vector3(1.9, 0.18, 0.95), Vector3(-hx + 2.0, yb + 0.0, -hz + 4.4), Color(0.36, 0.24, 0.22), false)
    _box_local(parent, Vector3(0.95, 0.18, 1.9), Vector3(hx - 2.0, yb + 0.0, -hz + 3.0), Color(0.26, 0.30, 0.36), false)
    _box_local(parent, Vector3(1.6, 0.8, 1.0), Vector3(hx - 3.2, yb + 0.4, hz - 1.5), Color(0.28, 0.21, 0.14), true)
    for i in range(5):
        _box_local(parent, Vector3(0.14, 0.2, 0.14), Vector3(hx - 3.7 + float(i) * 0.25, yb + 0.9, hz - 1.5), Color(0.55 - float(i) * 0.06, 0.45, 0.25), false)
    _box_local(parent, Vector3(0.5, 0.3, 0.5), Vector3(hx - 5.5, yb + 0.15, hz - 2.0), Color(0.12, 0.14, 0.10), true)
    _box_local(parent, Vector3(0.16, 0.26, 0.16), Vector3(-hx + 4.5, yb + 0.12, -hz + 3.7), Color(0.85, 0.65, 0.20), false)
    # crates stacked in a corner and a warning scrawled in blood
    _box_local(parent, Vector3(0.9, 0.7, 0.9), Vector3(-hx + 1.0, yb + 0.35, hz - 1.0), Color(0.30, 0.22, 0.12), true)
    _box_local(parent, Vector3(0.9, 0.7, 0.9), Vector3(-hx + 1.0, yb + 1.05, hz - 1.0), Color(0.28, 0.20, 0.11), true)
    _box_local(parent, Vector3(2.2, 0.5, 0.04), Vector3(hx * 0.3, yb + 1.5, hz - 0.2), BLOOD, false)
    _box_local(parent, Vector3(0.3, 1.2, 0.04), Vector3(hx * 0.3 + 1.4, yb + 1.3, hz - 0.2), BLOOD_DARK, false)

func _upper_apartment(parent: Node3D, size: Vector3, yb: float) -> void:
    var hx: float = size.x * 0.5
    var hz: float = size.z * 0.5
    # living room: sofa facing a TV
    _box_local(parent, Vector3(0.25, 0.9, 2.3), Vector3(-hx + 0.5, yb + 0.45, -hz + 5.0), Color(0.22, 0.28, 0.30), true)
    _box_local(parent, Vector3(0.9, 0.45, 2.3), Vector3(-hx + 1.1, yb + 0.22, -hz + 5.0), Color(0.26, 0.32, 0.34), true)
    _box_local(parent, Vector3(1.0, 0.4, 1.4), Vector3(-hx + 2.8, yb + 0.2, -hz + 5.0), Color(0.24, 0.17, 0.11), true)
    _box_local(parent, Vector3(0.5, 0.5, 1.4), Vector3(-hx + 5.4, yb + 0.25, -hz + 5.0), Color(0.18, 0.13, 0.09), true)
    _box_local(parent, Vector3(0.1, 0.7, 1.2), Vector3(-hx + 5.4, yb + 0.85, -hz + 5.0), Color(0.04, 0.05, 0.06), false)
    # kitchenette along the right wall
    _box_local(parent, Vector3(0.7, 0.9, 3.4), Vector3(hx - 0.6, yb + 0.45, -hz + 3.0), Color(0.62, 0.62, 0.58), true)
    _box_local(parent, Vector3(0.74, 0.05, 3.5), Vector3(hx - 0.6, yb + 0.92, -hz + 3.0), Color(0.18, 0.18, 0.17), false)
    _box_local(parent, Vector3(0.5, 0.1, 0.7), Vector3(hx - 0.6, yb + 0.95, -hz + 2.0), Color(0.55, 0.57, 0.58), false)
    _box_local(parent, Vector3(0.8, 1.9, 0.8), Vector3(hx - 0.7, yb + 0.95, -hz + 5.3), Color(0.80, 0.80, 0.78), true)
    # dining table with two chairs, one knocked over
    _box_local(parent, Vector3(1.5, 0.06, 1.0), Vector3(hx - 3.6, yb + 0.76, -hz + 4.4), Color(0.30, 0.22, 0.14), true)
    _box_local(parent, Vector3(0.08, 0.74, 0.08), Vector3(hx - 4.2, yb + 0.37, -hz + 4.8), Color(0.2, 0.14, 0.09), false)
    _box_local(parent, Vector3(0.08, 0.74, 0.08), Vector3(hx - 3.0, yb + 0.37, -hz + 4.0), Color(0.2, 0.14, 0.09), false)
    _box_local(parent, Vector3(0.45, 0.06, 0.45), Vector3(hx - 3.6, yb + 0.45, -hz + 3.4), Color(0.25, 0.18, 0.12), false)
    _box_local(parent, Vector3(0.45, 0.45, 0.06), Vector3(hx - 2.2, yb + 0.1, -hz + 5.2), Color(0.25, 0.18, 0.12), false)
    # bookcase and a spilled dinner
    _box_local(parent, Vector3(1.6, 2.0, 0.4), Vector3(-hx + 3.0, yb + 1.0, hz - 0.4), Color(0.22, 0.16, 0.10), true)
    _box_local(parent, Vector3(0.9, 0.02, 0.7), Vector3(hx - 3.6, yb - 0.02, -hz + 5.4), BLOOD_DARK, false)

func _scatter_upper_loot(center: Vector3, size: Vector3, idx: int, floor_h: float) -> void:
    # Something worth climbing the stairs for.
    var rng := RandomNumberGenerator.new()
    rng.seed = int(center.x * 11.0 + center.z * 5.0 + float(idx) * 131.0)
    var kinds: Array[String] = ["food", "water", "medkits", "ammo_pistol", "ammo_shotgun", "ammo_ak", "pistol"]
    var count: int = rng.randi_range(1, 2)
    for i in range(count):
        var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
        var side: float = -1.0 if rng.randf() < 0.5 else 1.0
        var ox: float = side * rng.randf_range(2.8, size.x * 0.5 - 1.6)
        var oz: float = rng.randf_range(-size.z * 0.5 + 2.0, size.z * 0.5 - 1.6)
        _city_pickup(kind, Vector3(center.x + ox, GROUND_Y + floor_h + 0.75 + float(i) * 0.01, center.z + oz))


func _make_openable_door(parent: Node3D, width: float, height: float, hinge_pos: Vector3, color: Color) -> void:
    var hinge := Node3D.new()
    hinge.name = "ManualCityDoor"
    hinge.position = hinge_pos
    hinge.set_script(load("res://city_door.gd"))
    parent.add_child(hinge)

    var door_body := StaticBody3D.new()
    door_body.position = Vector3(width / 2.0, height / 2.0, 0)
    hinge.add_child(door_body)
    _box_local(door_body, Vector3(width, height, 0.16), Vector3.ZERO, color, true)
    # Handle sits ON the door: near the free edge (far from the hinge), about 1 m above the floor, on both faces.
    var metal := Color(0.62, 0.52, 0.25)
    var hx: float = width * 0.5 - 0.28
    var hy: float = 1.0 - height * 0.5
    _box_local(door_body, Vector3(0.05, 0.05, 0.30), Vector3(hx, hy, 0.0), metal, false)
    for side in [-1.0, 1.0]:
        var s: float = float(side)
        _box_local(door_body, Vector3(0.07, 0.24, 0.02), Vector3(hx, hy, s * 0.09), metal, false)
        _box_local(door_body, Vector3(0.22, 0.04, 0.05), Vector3(hx - 0.09, hy, s * 0.13), metal, false)


func _build_gas_station(center: Vector3) -> void:
    # Large station ~ size of two building lots.
    var root := Node3D.new()
    root.name = "GasStation"
    root.position = Vector3(center.x, GROUND_Y, center.z)
    add_child(root)
    _box_local(root, Vector3(42.0, 0.12, 28.0), Vector3(0, ROAD_Y - GROUND_Y - 0.06, 0), Color(0.14, 0.14, 0.13), true)
    _box_local(root, Vector3(36.0, 0.35, 18.0), Vector3(0, 5.2, -2.0), Color(0.55, 0.12, 0.08), true)
    for x in [-14.0, -5.0, 5.0, 14.0]:
        for z in [-7.0, 3.0]:
            _box_local(root, Vector3(0.45, 5.0, 0.45), Vector3(x, 2.5, z - 2.0), Color(0.25, 0.25, 0.24), true)
    for px in [-8.0, 8.0]:
        _box_local(root, Vector3(1.4, 1.6, 1.0), Vector3(px, 0.9, -2.0), Color(0.75, 0.75, 0.72), true)
        _box_local(root, Vector3(0.35, 1.1, 0.35), Vector3(px - 0.4, 1.9, -2.0), Color(0.08, 0.08, 0.08), false)
        _box_local(root, Vector3(0.35, 1.1, 0.35), Vector3(px + 0.4, 1.9, -2.0), Color(0.08, 0.08, 0.08), false)
        _box_local(root, Vector3(1.5, 0.12, 0.12), Vector3(px, 2.5, -2.0), Color(0.7, 0.1, 0.08), false)
        _box_local(root, Vector3(3.5, 0.25, 2.2), Vector3(px, 0.2, -2.0), Color(0.35, 0.35, 0.32), true)
    # Walls of the shop booth (hollow now: walk in through the doorway at the front)
    var booth_wall := Color(0.22, 0.23, 0.22)
    _box_local(root, Vector3(10.0, 3.4, 0.3), Vector3(0, 1.75, 12.0), booth_wall, true)
    _box_local(root, Vector3(0.3, 3.4, 8.0), Vector3(-5.0, 1.75, 8.0), booth_wall, true)
    _box_local(root, Vector3(0.3, 3.4, 8.0), Vector3(5.0, 1.75, 8.0), booth_wall, true)
    _box_local(root, Vector3(9.6, 0.03, 7.6), Vector3(0, 0.1, 8.0), Color(0.28, 0.27, 0.24), false)
    # counter, shelves, weapon rack, crates
    _box_local(root, Vector3(4.0, 1.0, 0.8), Vector3(-2.8, 0.58, 5.6), Color(0.25, 0.17, 0.10), true)
    _box_local(root, Vector3(4.2, 0.08, 1.0), Vector3(-2.8, 1.12, 5.6), Color(0.55, 0.52, 0.46), false)
    for sx in [-3.2, 0.0, 3.2]:
        _box_local(root, Vector3(2.4, 2.0, 0.5), Vector3(sx, 1.1, 11.6), Color(0.30, 0.26, 0.18), true)
        for tier in range(3):
            _box_local(root, Vector3(0.5, 0.25, 0.35), Vector3(sx - 0.7 + float(tier) * 0.7, 0.55 + float(tier) * 0.6, 11.3), Color(0.55 - float(tier) * 0.1, 0.30, 0.15), false)
    _box_local(root, Vector3(0.3, 1.8, 3.4), Vector3(4.7, 1.0, 9.0), Color(0.12, 0.12, 0.13), true)    # weapon rack
    for i in range(4):
        _box_local(root, Vector3(0.05, 0.05, 0.7), Vector3(4.5, 1.9 - float(i) * 0.3, 8.0 + float(i % 2) * 1.6), Color(0.35, 0.35, 0.33), false)
    _box_local(root, Vector3(1.0, 0.8, 1.0), Vector3(-4.0, 0.5, 10.4), Color(0.18, 0.22, 0.16), true)   # ammo crate
    _box_local(root, Vector3(0.9, 0.7, 0.9), Vector3(-2.9, 0.45, 10.6), Color(0.30, 0.22, 0.12), true)
    _box_local(root, Vector3(1.0, 1.4, 0.7), Vector3(3.2, 0.8, 7.0), Color(0.40, 0.42, 0.40), true)     # old safe, door open
    _box_local(root, Vector3(1.4, 0.02, 0.8), Vector3(1.0, 0.12, 6.8), BLOOD_DARK, false)
    var booth_light := OmniLight3D.new()
    booth_light.position = Vector3(0, 3.0, 8.0)
    booth_light.light_color = Color(1.0, 0.85, 0.55)
    booth_light.light_energy = 0.5
    booth_light.omni_range = 9.0
    root.add_child(booth_light)
    _register_light(booth_light, true)
    _box_local(root, Vector3(9.6, 0.25, 7.6), Vector3(0, 3.5, 8.0), ROOF, true)
    _box_local(root, Vector3(3.2, 0.25, 0.2), Vector3(0, 3.15, 3.9), Color(0.22, 0.23, 0.22), true)
    _box_local(root, Vector3(3.4, 2.9, 0.15), Vector3(-3.3, 1.55, 3.9), Color(0.18, 0.18, 0.17), true)
    _box_local(root, Vector3(3.4, 2.9, 0.15), Vector3(3.3, 1.55, 3.9), Color(0.18, 0.18, 0.17), true)
    _box_local(root, Vector3(0.35, 7.5, 0.35), Vector3(-18.0, 3.8, 8.0), Color(0.2, 0.2, 0.2), true)
    _box_local(root, Vector3(4.5, 2.2, 0.25), Vector3(-18.0, 7.2, 8.0), Color(0.55, 0.12, 0.08), false)
    _box_local(root, Vector3(3.0, 0.03, 2.0), Vector3(-6.0, 0.16, -4.0), Color(0.05, 0.05, 0.04), false)
    _box_local(root, Vector3(2.2, 0.03, 1.5), Vector3(5.0, 0.16, 0.0), Color(0.06, 0.05, 0.04), false)
    for x in [-10.0, 0.0, 10.0]:
        var light := OmniLight3D.new()
        light.position = Vector3(x, 4.9, -2.0)
        light.light_color = Color(1.0, 0.85, 0.55)
        light.light_energy = 0.55
        light.omni_range = 10.0
        root.add_child(light)
        _register_light(light, false)
    # Weapons and ammo inside the shop (same pickups / look as the rest of the game)
    _city_pickup("pistol", center + Vector3(-3.5, 1.35, 5.6))
    _city_pickup("ammo_pistol", center + Vector3(-2.2, 1.35, 5.6))
    _city_pickup("pistol", center + Vector3(-4.0, 1.4, 10.4))
    _city_pickup("pistol", center + Vector3(2.5, 0.7, 10.8))
    _city_pickup("shotgun", center + Vector3(4.0, 1.1, 8.0))
    _city_pickup("shotgun", center + Vector3(-1.0, 0.7, 10.2))
    _city_pickup("ak", center + Vector3(4.0, 1.1, 9.8))
    _city_pickup("ak", center + Vector3(3.2, 1.65, 7.0))
    _city_pickup("ammo_pistol", center + Vector3(-2.9, 1.0, 10.6))
    _city_pickup("ammo_pistol", center + Vector3(0.0, 0.7, 6.8))
    _city_pickup("ammo_shotgun", center + Vector3(1.5, 0.7, 9.0))
    _city_pickup("ammo_shotgun", center + Vector3(-4.0, 1.0, 7.5))
    _city_pickup("ammo_ak", center + Vector3(2.0, 0.7, 11.0))
    _city_pickup("ammo_ak", center + Vector3(4.0, 0.7, 6.2))
    _city_pickup("ammo_ak", center + Vector3(-0.5, 0.7, 11.0))
    # And some left lying around the pumps outside
    _city_pickup("ammo_pistol", center + Vector3(-12.0, 0.7, -6.0))
    _city_pickup("ammo_shotgun", center + Vector3(12.0, 0.7, -5.0))
    _city_pickup("pistol", center + Vector3(16.0, 0.7, 6.0))

func _build_supermarket(center: Vector3) -> void:
    # Single-storey market with glass storefront, shelves and interior lights.
    var root := Node3D.new()
    root.name = "Supermarket"
    root.position = Vector3(center.x, GROUND_Y, center.z)
    add_child(root)
    var w := 28.0
    var d := 20.0
    var h := 4.2
    _box_local(root, Vector3(w, 0.12, d), Vector3(0, ROAD_Y - GROUND_Y - 0.06, 0), Color(0.18, 0.18, 0.17), true)
    _box_local(root, Vector3(w, h, 0.35), Vector3(0, h * 0.5, d * 0.5), Color(0.32, 0.34, 0.30), true)
    _box_local(root, Vector3(0.35, h, d), Vector3(-w * 0.5, h * 0.5, 0), Color(0.32, 0.34, 0.30), true)
    _box_local(root, Vector3(0.35, h, d), Vector3(w * 0.5, h * 0.5, 0), Color(0.32, 0.34, 0.30), true)
    var glass := Color(0.35, 0.55, 0.60)
    var frame := Color(0.12, 0.12, 0.12)
    var side_w := (w - 4.0) * 0.5
    _box_local(root, Vector3(0.4, h, 0.4), Vector3(-w * 0.5 + 0.3, h * 0.5, -d * 0.5), frame, true)
    _box_local(root, Vector3(0.4, h, 0.4), Vector3(w * 0.5 - 0.3, h * 0.5, -d * 0.5), frame, true)
    _box_local(root, Vector3(side_w - 0.5, h - 1.0, 0.08), Vector3(-w * 0.25, h * 0.5 + 0.2, -d * 0.5), glass, false)
    _box_local(root, Vector3(side_w - 0.5, h - 1.0, 0.08), Vector3(w * 0.25, h * 0.5 + 0.2, -d * 0.5), glass, false)
    _box_local(root, Vector3(side_w - 0.5, 0.7, 0.2), Vector3(-w * 0.25, 0.4, -d * 0.5), frame, true)
    _box_local(root, Vector3(side_w - 0.5, 0.7, 0.2), Vector3(w * 0.25, 0.4, -d * 0.5), frame, true)
    _box_local(root, Vector3(w, 0.5, 0.35), Vector3(0, h - 0.2, -d * 0.5), frame, true)
    _box_local(root, Vector3(w + 0.8, 0.3, d + 0.8), Vector3(0, h + 0.1, 0), Color(0.15, 0.16, 0.15), true)
    _box_local(root, Vector3(w * 0.7, 1.0, 0.25), Vector3(0, h + 0.7, -d * 0.5 - 0.1), Color(0.08, 0.35, 0.22), false)
    for row in range(4):
        var zz: float = -5.0 + float(row) * 3.5
        for col in range(5):
            var xx: float = -10.0 + float(col) * 5.0
            _box_local(root, Vector3(3.2, 2.4, 0.45), Vector3(xx, 1.3, zz), Color(0.55, 0.55, 0.52), true)
            _box_local(root, Vector3(3.0, 0.06, 0.4), Vector3(xx, 0.7, zz), Color(0.7, 0.7, 0.68), false)
            _box_local(root, Vector3(3.0, 0.06, 0.4), Vector3(xx, 1.3, zz), Color(0.7, 0.7, 0.68), false)
            _box_local(root, Vector3(3.0, 0.06, 0.4), Vector3(xx, 1.9, zz), Color(0.7, 0.7, 0.68), false)
            if (row + col) % 2 == 0:
                _box_local(root, Vector3(0.35, 0.3, 0.25), Vector3(xx - 0.8, 1.05, zz - 0.1), Color(0.7, 0.2, 0.15), false)
            if (row + col) % 3 == 0:
                _box_local(root, Vector3(0.3, 0.35, 0.25), Vector3(xx + 0.6, 1.65, zz - 0.1), Color(0.2, 0.45, 0.7), false)
    for cx in [-6.0, 0.0, 6.0]:
        _box_local(root, Vector3(2.4, 1.1, 1.0), Vector3(cx, 0.65, -7.5), Color(0.25, 0.25, 0.24), true)
    for x in [-8.0, 0.0, 8.0]:
        for z in [-4.0, 2.0, 6.0]:
            var light := OmniLight3D.new()
            light.position = Vector3(x, h - 0.35, z)
            light.light_color = Color(0.92, 0.95, 0.88)
            light.light_energy = 0.7
            light.omni_range = 9.0
            root.add_child(light)
            _register_light(light, (int(x) + int(z)) % 5 == 0)
            _box_local(root, Vector3(2.4, 0.08, 0.25), Vector3(x, h - 0.2, z), Color(0.75, 0.78, 0.72), false)
    _box_local(root, Vector3(0.9, 0.7, 0.55), Vector3(10.0, 0.4, -6.0), Color(0.4, 0.4, 0.38), false)
    _box_local(root, Vector3(1.2, 0.03, 0.8), Vector3(-9.0, 0.2, 5.0), BLOOD_DARK, false)
    # Food / water / ammo samples on shelves and floor
    _city_pickup("food", center + Vector3(-8.0, 0.7, -2.0))
    _city_pickup("food", center + Vector3(6.0, 0.7, 1.0))
    _city_pickup("food", center + Vector3(0.0, 0.7, 5.0))
    _city_pickup("water", center + Vector3(-4.0, 0.7, 2.0))
    _city_pickup("water", center + Vector3(8.0, 0.7, -3.0))
    _city_pickup("water", center + Vector3(2.0, 0.7, 6.5))
    _city_pickup("ammo_pistol", center + Vector3(-6.0, 0.7, 4.0))
    _city_pickup("ammo_shotgun", center + Vector3(4.0, 0.7, -1.0))
    _city_pickup("ammo_ak", center + Vector3(9.0, 0.7, 3.0))

func _build_ruined_restaurant(center: Vector3) -> void:
    # "Mel's Diner": an old roadside diner. The back half still has a roof, the front-right
    # corner has collapsed. Booths, a counter with stools, a kitchen, a jukebox and a sign.
    var root := Node3D.new()
    root.name = "RuinedRestaurant"
    root.position = Vector3(center.x, GROUND_Y, center.z)
    root.set_meta("batch", true)
    add_child(root)
    var w := 22.0
    var d := 16.0
    var h := 3.8
    var hw := w * 0.5
    var hd := d * 0.5
    var wall := Color(0.28, 0.18, 0.12)
    var wall_dark := Color(0.20, 0.13, 0.09)
    var steel := Color(0.52, 0.54, 0.54)
    var vinyl := Color(0.45, 0.07, 0.06)
    var wood := Color(0.25, 0.17, 0.10)

    # --- floor: dirty checkerboard
    _box_local(root, Vector3(w, 0.12, d), Vector3(0, ROAD_Y - GROUND_Y - 0.06, 0), Color(0.16, 0.12, 0.10), true)
    for ix in range(10):
        for iz in range(7):
            if (ix + iz) % 2 == 0:
                _box_local(root, Vector3(2.0, 0.02, 2.0), Vector3(-hw + 1.1 + float(ix) * 2.0, 0.05, -hd + 1.1 + float(iz) * 2.0), Color(0.34, 0.32, 0.28), false)
    _box_local(root, Vector3(w + 4.0, 0.05, 7.0), Vector3(0, 0.02, -hd - 4.5), Color(0.08, 0.08, 0.08), false)
    for i in range(5):
        _box_local(root, Vector3(0.12, 0.02, 3.0), Vector3(-8.0 + float(i) * 4.0, 0.06, -hd - 4.5), Color(0.55, 0.55, 0.50), false)

    # --- front wall: low sills, broken-window openings, a doorway at x = -3
    var fz: float = -hd
    _box_local(root, Vector3(6.4, 1.0, 0.3), Vector3(-7.8, 0.5, fz), wall, true)
    _box_local(root, Vector3(12.4, 1.0, 0.3), Vector3(4.8, 0.5, fz), wall, true)
    _box_local(root, Vector3(6.4, 0.9, 0.3), Vector3(-7.8, h - 0.45, fz), wall, true)
    _box_local(root, Vector3(12.4, 0.9, 0.3), Vector3(4.8, h - 0.45, fz), wall, true)
    _box_local(root, Vector3(3.2, 0.9, 0.3), Vector3(-3.0, h - 0.45, fz), wall, true)
    for px in [-10.85, -4.75, -1.25, 3.0, 7.0, 10.85]:
        _box_local(root, Vector3(0.5, h, 0.3), Vector3(px, h * 0.5, fz), wall_dark, true)
    # glass teeth left in the window frames
    for gx in [-8.5, -6.2, 0.6, 1.9, 5.0, 9.0]:
        _box_local(root, Vector3(0.08, 0.5, 0.04), Vector3(gx, 1.25, fz), Color(0.55, 0.68, 0.70), false)
    # --- other walls
    _box_local(root, Vector3(w, h, 0.3), Vector3(0, h * 0.5, hd), wall, true)
    _box_local(root, Vector3(0.3, h, d), Vector3(-hw, h * 0.5, 0), wall, true)
    _box_local(root, Vector3(0.3, h * 0.65, d * 0.62), Vector3(hw, h * 0.325, d * 0.19), wall, true)
    _box_local(root, Vector3(0.3, 0.9, 3.0), Vector3(hw, h * 0.65 + 0.45, 4.8), wall_dark, true)
    # --- roof over the back half, a collapsed slab and bare rafters over the front
    _box_local(root, Vector3(w * 0.96, 0.3, d * 0.52), Vector3(0, h - 0.05, hd - d * 0.26), Color(0.13, 0.11, 0.10), true)
    _add_tilted_solid(root, Vector3(9.0, 0.3, 6.0), Vector3(-5.5, 2.4, -3.2), Vector3(14, 0, -24), Color(0.12, 0.10, 0.09))
    _add_tilted_solid(root, Vector3(3.0, 0.5, 4.0), Vector3(hw - 1.2, 0.55, -4.5), Vector3(5, 20, 12), Color(0.18, 0.15, 0.13))
    for i in range(6):
        _box_local(root, Vector3(0.22, 0.28, d * 0.45), Vector3(-9.0 + float(i) * 3.6, h - 0.3, -hd + d * 0.225 + 0.2), wood, false)
    # --- sign by the road
    _box_local(root, Vector3(0.3, 6.0, 0.3), Vector3(-9.0, 3.0, -hd - 3.0), Color(0.20, 0.20, 0.20), true)
    _box_local(root, Vector3(4.4, 1.5, 0.25), Vector3(-9.0, 6.3, -hd - 3.0), Color(0.55, 0.08, 0.06), false)
    var sign_label := Label3D.new()
    sign_label.text = "DINER"
    sign_label.font_size = 120
    sign_label.pixel_size = 0.012
    sign_label.modulate = Color(1.0, 0.85, 0.5)
    sign_label.outline_size = 8
    sign_label.position = Vector3(-9.0, 6.3, -hd - 3.0 - 0.14)
    sign_label.rotation.y = PI
    root.add_child(sign_label)

    # --- counter with stools
    _box_local(root, Vector3(10.0, 1.1, 1.0), Vector3(2.0, 0.6, 2.0), wood, true)
    _box_local(root, Vector3(10.4, 0.1, 1.3), Vector3(2.0, 1.17, 2.0), Color(0.60, 0.58, 0.52), true)
    for i in range(6):
        var sx: float = -2.0 + float(i) * 1.7
        _box_local(root, Vector3(0.1, 0.6, 0.1), Vector3(sx, 0.35, 0.7), steel, false)
        _box_local(root, Vector3(0.45, 0.1, 0.45), Vector3(sx, 0.7, 0.7), vinyl, false)
    _box_local(root, Vector3(0.45, 0.1, 0.45), Vector3(5.6, 0.1, 0.1), vinyl, false)   # a stool on its side
    # --- kitchen behind the counter
    _box_local(root, Vector3(2.4, 0.9, 1.0), Vector3(6.0, 0.5, 6.8), steel, true)
    _box_local(root, Vector3(2.6, 0.6, 1.2), Vector3(6.0, 2.7, 6.8), Color(0.30, 0.31, 0.31), false)
    _box_local(root, Vector3(3.0, 0.9, 1.0), Vector3(1.5, 0.5, 6.8), steel, true)
    _box_local(root, Vector3(1.1, 2.0, 1.0), Vector3(-1.0, 1.05, 7.2), Color(0.72, 0.72, 0.68), true)
    _box_local(root, Vector3(0.06, 0.5, 0.06), Vector3(-0.38, 1.4, 6.65), Color(0.20, 0.20, 0.20), false)
    _box_local(root, Vector3(3.0, 2.0, 0.5), Vector3(-5.5, 1.05, 7.6), wood, true)
    for i in range(6):
        _box_local(root, Vector3(0.2, 0.25, 0.2), Vector3(-6.5 + float(i) * 0.45, 0.85 + float(i % 3) * 0.5, 7.4), Color(0.5 - float(i) * 0.05, 0.4, 0.25), false)
    _box_local(root, Vector3(3.0, 1.2, 0.08), Vector3(3.0, 2.4, hd - 0.2), Color(0.06, 0.07, 0.06), false)    # menu board
    for i in range(4):
        _box_local(root, Vector3(2.2, 0.05, 0.03), Vector3(3.0, 2.8 - float(i) * 0.25, hd - 0.25), Color(0.80, 0.80, 0.74), false)
    # --- booths along the left wall
    for i in range(3):
        var bz: float = -4.8 + float(i) * 3.6
        _box_local(root, Vector3(0.3, 1.1, 1.8), Vector3(-hw + 0.45, 0.65, bz), vinyl, true)
        _box_local(root, Vector3(0.8, 0.45, 1.8), Vector3(-hw + 0.95, 0.25, bz), vinyl, true)
        _box_local(root, Vector3(0.8, 0.08, 1.4), Vector3(-hw + 2.1, 0.78, bz), Color(0.62, 0.60, 0.55), true)
        _box_local(root, Vector3(0.1, 0.74, 0.1), Vector3(-hw + 2.1, 0.37, bz), steel, false)
        _box_local(root, Vector3(0.8, 0.45, 1.8), Vector3(-hw + 3.3, 0.25, bz), vinyl, true)
        _box_local(root, Vector3(0.3, 1.1, 1.8), Vector3(-hw + 3.85, 0.65, bz), vinyl, true)
        _box_local(root, Vector3(0.14, 0.2, 0.14), Vector3(-hw + 2.1, 0.92, bz + 0.3), Color(0.70, 0.15, 0.12), false)   # ketchup
    # --- loose tables, one flipped, chairs everywhere
    _box_local(root, Vector3(1.2, 0.08, 1.2), Vector3(2.0, 0.78, -4.0), Color(0.55, 0.52, 0.46), true)
    _box_local(root, Vector3(0.1, 0.74, 0.1), Vector3(2.0, 0.37, -4.0), steel, false)
    _box_local(root, Vector3(0.45, 0.06, 0.45), Vector3(2.0, 0.45, -5.0), wood, false)
    _box_local(root, Vector3(0.45, 0.06, 0.45), Vector3(2.0, 0.45, -3.0), wood, false)
    _box_local(root, Vector3(1.2, 0.08, 1.2), Vector3(6.5, 0.7, -2.0), Color(0.55, 0.52, 0.46), true)   # flipped table
    _box_local(root, Vector3(0.08, 0.7, 0.08), Vector3(6.1, 0.35, -2.4), steel, false)
    _box_local(root, Vector3(0.08, 0.7, 0.08), Vector3(6.9, 0.35, -1.6), steel, false)
    _box_local(root, Vector3(0.45, 0.45, 0.06), Vector3(4.4, 0.1, -2.6), wood, false)
    _box_local(root, Vector3(0.45, 0.06, 0.45), Vector3(8.0, 0.1, -5.0), wood, false)
    # --- jukebox in the back-left corner
    _box_local(root, Vector3(0.9, 1.6, 0.7), Vector3(-hw + 1.0, 0.85, hd - 0.9), Color(0.55, 0.12, 0.10), true)
    _box_local(root, Vector3(0.7, 0.7, 0.05), Vector3(-hw + 1.0, 1.15, hd - 1.27), Color(0.95, 0.75, 0.25), false)
    _box_local(root, Vector3(0.8, 0.2, 0.05), Vector3(-hw + 1.0, 0.55, hd - 1.27), Color(0.15, 0.55, 0.60), false)
    # --- mess: shards, blood trail from the door to the kitchen, scorch mark under the hole
    for i in range(7):
        _box_local(root, Vector3(0.12, 0.02, 0.08), Vector3(-9.0 + float(i) * 2.9, 0.07, -6.8 + float(i % 3) * 0.5), Color(0.55, 0.68, 0.70), false)
    _box_local(root, Vector3(0.9, 0.02, 1.8), Vector3(-3.0, 0.07, -5.5), BLOOD, false)
    _box_local(root, Vector3(0.7, 0.02, 2.2), Vector3(-3.4, 0.07, -3.2), BLOOD_DARK, false)
    _box_local(root, Vector3(1.0, 0.02, 2.6), Vector3(-4.0, 0.07, 0.0), BLOOD, false)
    _box_local(root, Vector3(0.6, 0.02, 3.0), Vector3(-4.2, 0.07, 3.6), BLOOD_DARK, false)
    _box_local(root, Vector3(4.0, 0.04, 3.0), Vector3(5.0, 0.07, -3.5), Color(0.05, 0.04, 0.03), false)
    # --- pendant lamps and lights
    for lp in [Vector3(-4.0, 0.0, 2.5), Vector3(4.0, 0.0, 4.5), Vector3(-7.0, 0.0, -2.0)]:
        _box_local(root, Vector3(0.03, 0.6, 0.03), Vector3(lp.x, h - 0.65, lp.z), Color(0.05, 0.05, 0.05), false)
        _box_local(root, Vector3(0.55, 0.2, 0.55), Vector3(lp.x, h - 1.05, lp.z), Color(0.70, 0.62, 0.35), false)
    var glow := OmniLight3D.new()
    glow.position = Vector3(0, 2.2, 3.0)
    glow.light_color = Color(1.0, 0.5, 0.2)
    glow.light_energy = 0.5
    glow.omni_range = 12.0
    root.add_child(glow)
    _register_light(glow, true)
    var neon := OmniLight3D.new()
    neon.position = Vector3(-9.0, 5.0, -hd - 4.0)
    neon.light_color = Color(1.0, 0.15, 0.1)
    neon.light_energy = 0.6
    neon.omni_range = 9.0
    root.add_child(neon)
    _register_light(neon, true)
    # --- supplies: the kitchen and the counter still hold something
    _city_pickup("food", center + Vector3(0.0, 1.45, 2.0))
    _city_pickup("water", center + Vector3(-5.5, 0.7, 6.4))
    _city_pickup("food", center + Vector3(-hw + 2.1, 1.05, 2.4))
    _city_pickup("medkits", center + Vector3(1.5, 1.2, 6.2))
    _city_pickup("ammo_pistol", center + Vector3(-hw + 1.0, 0.7, hd - 2.4))

func _build_hospital() -> void:
    # Three floors, large footprint, open interior, stair/elevator core, treatment rooms and horror dressing.
    var base := Vector3(HOSP_X, GROUND_Y, HOSP_Z)
    _box(Vector3(HOSP_W + 3.0, 0.25, HOSP_D + 3.0), base + Vector3(0, -0.03, 0), Color(0.10, 0.11, 0.11), true)

    for floor in range(3):
        var fy: float = GROUND_Y + float(floor) * FLOOR_H
        _hospital_floor(fy, floor)
        _hospital_perimeter(fy, floor)
        _hospital_rooms(fy, floor)
        _hospital_lights(fy, floor)
        _hospital_blood(floor)
        _hospital_horror(floor)

    _hospital_stairs()
    _hospital_elevator_shaft()
    _hospital_roof_ruins()
    _hospital_loot()
    _hospital_zombies()


func _hospital_loot() -> void:
    # The hospital is the city's reliable medical/water source: every floor has both supplies.
    for floor in range(3):
        var y: float = GROUND_Y + float(floor) * FLOOR_H + 0.08
        _hospital_pickup("medkits", Vector3(HOSP_X - 15.0, y, HOSP_Z - 9.0))
        _hospital_pickup("medkits", Vector3(HOSP_X + 15.0, y, HOSP_Z + 9.0))
        _hospital_pickup("water", Vector3(HOSP_X - 15.0, y, HOSP_Z + 9.0))
        _hospital_pickup("water", Vector3(HOSP_X + 15.0, y, HOSP_Z - 9.0))
        _hospital_pickup("water", Vector3(HOSP_X, y, HOSP_Z + 12.0))
        # Two extra medkits on every floor.
        _hospital_pickup("medkits", Vector3(HOSP_X - 7.5, y, HOSP_Z + 15.5))
        _hospital_pickup("medkits", Vector3(HOSP_X + 8.0, y, HOSP_Z - 1.0))


func _city_pickup(kind: String, pos: Vector3) -> void:
    var area := Area3D.new()
    area.name = "CityLoot_%s" % kind
    area.position = pos
    add_child(area)
    var cs := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = 1.25
    cs.shape = shape
    area.add_child(cs)
    # Reuse the same visual language as world loot (loot.gd).
    var loot_node = get_tree().current_scene.get_node_or_null("Loot") if get_tree().current_scene else null
    if loot_node != null and loot_node.has_method("_look"):
        loot_node.call("_look", area, kind)
    else:
        _box_local(area, Vector3(0.35, 0.35, 0.35), Vector3(0, 0.2, 0), Color(0.85, 0.75, 0.3), false)
    _register_loot(area)
    area.body_entered.connect(_city_pickup_taken.bind(area, kind))

func _loot_key(area: Node3D) -> String:
    return "C%d_%d_%d" % [int(round(area.position.x * 10.0)), int(round(area.position.y * 10.0)), int(round(area.position.z * 10.0))]

func _loot_node() -> Node:
    return get_node_or_null("../Loot")

func _register_loot(area: Node3D) -> void:
    var ln := _loot_node()
    if ln != null and ln.has_method("register"):
        ln.call("register", _loot_key(area), area)

func _claim_loot(body: Node, area: Node3D, kind: String) -> void:
    var ln := _loot_node()
    if ln != null and ln.has_method("try_pickup"):
        ln.call("try_pickup", body, area, kind, _loot_key(area))

func _city_pickup_taken(body: Node, area: Area3D, kind: String) -> void:
    _claim_loot(body, area, kind)

func _hospital_pickup(kind: String, pos: Vector3) -> void:
    var area := Area3D.new()
    area.name = "Hospital_%s" % kind
    area.position = pos + Vector3(0, 0.6, 0)
    add_child(area)
    var cs := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = 1.35
    cs.shape = shape
    area.add_child(cs)
    if kind == "medkits":
        _box_local(area, Vector3(0.55, 0.32, 0.40), Vector3(0, 0.18, 0), Color(0.88, 0.86, 0.78), false)
        _box_local(area, Vector3(0.13, 0.25, 0.04), Vector3(0, 0.19, -0.22), Color(0.78, 0.04, 0.04), false)
        _box_local(area, Vector3(0.28, 0.10, 0.04), Vector3(0, 0.19, -0.23), Color(0.78, 0.04, 0.04), false)
    else:
        _box_local(area, Vector3(0.27, 0.50, 0.27), Vector3(0, 0.25, 0), Color(0.12, 0.38, 0.68), false)
        _box_local(area, Vector3(0.16, 0.08, 0.16), Vector3(0, 0.52, 0), Color(0.78, 0.80, 0.75), false)
    _register_loot(area)
    area.body_entered.connect(_hospital_pickup_taken.bind(area, kind))

func _hospital_pickup_taken(body: Node, area: Area3D, kind: String) -> void:
    _claim_loot(body, area, kind)

func _hospital_zombies() -> void:
    if Network.is_client():
        return
    # Two gray runners on each of the three floors: 6 hospital defenders total.
    var spots := [
        Vector3(-15.0, 0.0, -10.0), Vector3(14.0, 0.0, 10.0)
    ]
    for floor in range(3):
        var y: float = GROUND_Y + float(floor) * FLOOR_H + 1.5
        for local_pos in spots:
            var z := CharacterBody3D.new()
            z.set_script(load("res://zombie.gd"))
            z.is_gray_runner = true
            z.add_to_group("zombie")
            z.add_to_group("gray_zombie")
            z.add_to_group("hospital_zombie")
            z.set_meta("indoor_spawn", true)
            z.position = Vector3(HOSP_X + local_pos.x, y, HOSP_Z + local_pos.z)
            add_child(z)

func _hospital_floor(y: float, lv: int) -> void:
    if lv == 0:
        _box(Vector3(HOSP_W, 0.22, HOSP_D), Vector3(HOSP_X, y, HOSP_Z), HOSPITAL_FLOOR, true)
        return
    # Floors 1 and 2 have an opening where the stair ramp from the floor below arrives.
    var cx: float = HOSP_X + H_STAIR_X
    var hw: float = STAIR_W * 0.5
    var z_a: float = HOSP_Z + H_STAIR_Z0
    var z_b: float = HOSP_Z + H_STAIR_Z1
    var x_min: float = HOSP_X - HOSP_W * 0.5
    var x_max: float = HOSP_X + HOSP_W * 0.5
    var lw: float = (cx - hw) - x_min
    var rw: float = x_max - (cx + hw)
    _box(Vector3(lw, 0.22, HOSP_D), Vector3(x_min + lw * 0.5, y, HOSP_Z), HOSPITAL_FLOOR, true)
    _box(Vector3(rw, 0.22, HOSP_D), Vector3(cx + hw + rw * 0.5, y, HOSP_Z), HOSPITAL_FLOOR, true)
    var front_d: float = z_a - (HOSP_Z - HOSP_D * 0.5)
    _box(Vector3(STAIR_W, 0.22, front_d), Vector3(cx, y, HOSP_Z - HOSP_D * 0.5 + front_d * 0.5), HOSPITAL_FLOOR, true)
    var back_d: float = (HOSP_Z + HOSP_D * 0.5) - z_b
    _box(Vector3(STAIR_W, 0.22, back_d), Vector3(cx, y, z_b + back_d * 0.5), HOSPITAL_FLOOR, true)

func _hospital_perimeter(y: float, floor: int) -> void:
    var cy: float = y + WALL_H / 2.0
    # Back and sides are solid. Front has a wide entrance opening on every floor.
    _box(Vector3(HOSP_W, WALL_H, WALL_T), Vector3(HOSP_X, cy, HOSP_Z + HOSP_D / 2.0), HOSPITAL_WHITE, true)
    _box(Vector3(WALL_T, WALL_H, HOSP_D), Vector3(HOSP_X - HOSP_W / 2.0, cy, HOSP_Z), HOSPITAL_WHITE, true)
    _box(Vector3(WALL_T, WALL_H, HOSP_D), Vector3(HOSP_X + HOSP_W / 2.0, cy, HOSP_Z), HOSPITAL_WHITE, true)
    # Ground floor has a front door; upper floors are continuous. A large red medical cross sits on the first-floor facade.
    var front_z: float = HOSP_Z - HOSP_D / 2.0
    if floor == 0:
        # Ground floor: real entrance (3.2 m opening) with a door that opens with the interaction button.
        var side_w: float = (HOSP_W - 3.2) / 2.0
        _box(Vector3(side_w, WALL_H, WALL_T), Vector3(HOSP_X - HOSP_W / 2.0 + side_w / 2.0, cy, front_z), HOSPITAL_WHITE, true)
        _box(Vector3(side_w, WALL_H, WALL_T), Vector3(HOSP_X + HOSP_W / 2.0 - side_w / 2.0, cy, front_z), HOSPITAL_WHITE, true)
        _box(Vector3(3.2, WALL_H - 2.9, WALL_T), Vector3(HOSP_X, y + 2.9 + (WALL_H - 2.9) / 2.0, front_z), HOSPITAL_WHITE, true)
        _make_openable_door(self, 3.0, 2.9, Vector3(HOSP_X - 1.5, y + 0.11, front_z - 0.18), CONCRETE_DARK)
    else:
        _box(Vector3(HOSP_W, WALL_H, WALL_T), Vector3(HOSP_X, cy, front_z), HOSPITAL_WHITE, true)
    if floor == 1:
        _hospital_cross(Vector3(HOSP_X, cy + 0.10, front_z - 0.22))

func _hospital_rooms(y: float, floor: int) -> void:
    var cy: float = y + WALL_H / 2.0
    # Long corridor with rooms on both sides. Door gaps are intentionally left open.
    var left_x: float = HOSP_X - 10.0
    var right_x: float = HOSP_X + 10.0
    for z in [HOSP_Z - 11.0, HOSP_Z + 1.0, HOSP_Z + 13.0]:
        _box(Vector3(0.25, WALL_H, 9.0), Vector3(left_x, cy, z), HOSPITAL_WHITE, true)
        _box(Vector3(0.25, WALL_H, 9.0), Vector3(right_x, cy, z), HOSPITAL_WHITE, true)
        _doorway_frame(Vector3(left_x, y, z - 3.5))
        _doorway_frame(Vector3(right_x, y, z + 3.5))
    # Cross wall sections create a maze-like hospital layout while preserving circulation.
    _box(Vector3(10.0, WALL_H, 0.25), Vector3(HOSP_X - 16.0, cy, HOSP_Z + 6.0), HOSPITAL_WHITE, true)
    _box(Vector3(10.0, WALL_H, 0.25), Vector3(HOSP_X + 16.0, cy, HOSP_Z - 6.0), HOSPITAL_WHITE, true)

    # Floor-specific atmosphere props.
    if floor == 0:
        _hospital_room_props(y, true)
    elif floor == 1:
        _hospital_room_props(y, false)
        _box(Vector3(0.8, 2.4, 0.8), Vector3(HOSP_X + 17, y + 1.2, HOSP_Z + 12), BLOOD_DARK, false)
    else:
        _hospital_room_props(y, false)
        # A dark isolation room on the top floor (solid walls so players cannot walk through).
        _box(Vector3(0.28, 2.8, 6.0), Vector3(HOSP_X - 21, y + 1.4, HOSP_Z + 10), CONCRETE_DARK, true)
        _box(Vector3(6.0, 2.8, 0.28), Vector3(HOSP_X - 18.5, y + 1.4, HOSP_Z + 13.0), CONCRETE_DARK, true)
        _box(Vector3(6.0, 2.8, 0.28), Vector3(HOSP_X - 18.5, y + 1.4, HOSP_Z + 7.0), CONCRETE_DARK, true)

func _doorway_frame(pos: Vector3) -> void:
    _box(Vector3(0.18, 2.5, 0.18), pos + Vector3(0, 1.25, -1.5), CONCRETE_DARK, false)
    _box(Vector3(0.18, 2.5, 0.18), pos + Vector3(0, 1.25, 1.5), CONCRETE_DARK, false)
    _box(Vector3(0.18, 0.18, 3.18), pos + Vector3(0, 2.45, 0), CONCRETE_DARK, false)

func _hospital_room_props(y: float, medical: bool) -> void:
    for z in [HOSP_Z - 10.0, HOSP_Z + 14.0]:
        for x in [HOSP_X - 17.0, HOSP_X + 17.0]:
            _box(Vector3(2.4, 0.35, 5.5), Vector3(x, y + 0.35, z), Color(0.25, 0.28, 0.28), true)
            _box(Vector3(2.1, 0.15, 4.8), Vector3(x, y + 0.57, z), Color(0.42, 0.43, 0.40), false)
    if medical:
        _box(Vector3(3.0, 1.0, 1.0), Vector3(HOSP_X + 15.0, y + 0.6, HOSP_Z - 1.0), CONCRETE_DARK, true)
        _box(Vector3(0.8, 1.8, 0.8), Vector3(HOSP_X + 15.0, y + 1.5, HOSP_Z - 1.0), Color(0.65, 0.67, 0.62), true)

func _hospital_stairs() -> void:
    # Two ramps (ground->first, first->second) in the corridor, matching the floor openings.
    var body := StaticBody3D.new()
    body.name = "HospitalStairs"
    add_child(body)
    var cx: float = HOSP_X + H_STAIR_X
    for lv in range(2):
        var y_a: float = GROUND_Y + float(lv) * FLOOR_H + 0.11
        _make_ramp(body, "g_hospital", self, cx, STAIR_W, HOSP_Z + H_STAIR_Z0, HOSP_Z + H_STAIR_Z1, y_a, y_a + FLOOR_H, CONCRETE_DARK)

func _hospital_elevator_shaft() -> void:
    # Dark elevator shaft. Three solid walls + solid black floor so nothing can walk through the void.
    # Front stays open as a creepy vertical drop the player can look into.
    var y: float = GROUND_Y + FLOOR_H * 1.5
    _box(Vector3(4.5, FLOOR_H * 3.0, 0.35), Vector3(HOSP_X - 3.0, y, HOSP_Z + 4.0), CONCRETE_DARK, true)
    _box(Vector3(0.35, FLOOR_H * 3.0, 4.5), Vector3(HOSP_X - 5.25, y, HOSP_Z + 6.1), CONCRETE_DARK, true)
    _box(Vector3(0.35, FLOOR_H * 3.0, 4.5), Vector3(HOSP_X - 0.75, y, HOSP_Z + 6.1), CONCRETE_DARK, true)
    # Black floor of the shaft pit (with collision so you cannot fall through the visual)
    _box(Vector3(4.2, 0.25, 4.2), Vector3(HOSP_X - 3.0, 0.12, HOSP_Z + 6.1), Color(0.04, 0.04, 0.04), true)
    # Inner black lining (visual depth)
    _box(Vector3(3.8, FLOOR_H * 2.9, 0.08), Vector3(HOSP_X - 3.0, y, HOSP_Z + 4.25), Color(0.02, 0.02, 0.02), false)
    for floor in range(3):
        _blood_stain(Vector3(HOSP_X - 3.0, GROUND_Y + floor * FLOOR_H + 0.13, HOSP_Z + 5.8), 2.0 + floor * 0.7)

func _hospital_cross(pos: Vector3) -> void:
    # Simple low-poly red + mounted directly on the hospital facade.
    _box(Vector3(5.8, 1.0, 0.16), pos + Vector3(0, 0.0, 0), BLOOD, false)
    _box(Vector3(1.0, 5.8, 0.16), pos + Vector3(0, 0.0, -0.01), BLOOD, false)

func _hospital_entrance() -> void:
    var z: float = HOSP_Z - HOSP_D / 2.0 - 1.0
    _box(Vector3(12.0, 0.25, 5.0), Vector3(HOSP_X, GROUND_Y + 0.08, z), CONCRETE_DARK, true)
    # Broken glass / dark doorway frame.
    _box(Vector3(0.25, 3.1, 0.25), Vector3(HOSP_X - 5.7, GROUND_Y + 1.55, z), CONCRETE_DARK, false)
    _box(Vector3(0.25, 3.1, 0.25), Vector3(HOSP_X + 5.7, GROUND_Y + 1.55, z), CONCRETE_DARK, false)
    _box(Vector3(11.7, 0.25, 0.25), Vector3(HOSP_X, GROUND_Y + 3.0, z), CONCRETE_DARK, false)
    _blood_stain(Vector3(HOSP_X - 2.0, GROUND_Y + 0.16, z + 0.8), 3.0)

func _hospital_lights(y: float, lv: int) -> void:
    # Fixtures are mounted flush against the ceiling (underside of the slab above). Some are dead, some flicker.
    var ceil_y: float = y + FLOOR_H - (0.11 if lv < 2 else 0.15) - 0.04
    for x in [HOSP_X - 14.0, HOSP_X, HOSP_X + 14.0]:
        for z in [HOSP_Z - 10.0, HOSP_Z + 2.0, HOSP_Z + 14.0]:
            var dark_fixture: bool = (int(x) + int(z) + lv) % 4 == 0
            var flicker: bool = (not dark_fixture) and (int(x) + int(z) + lv * 2) % 3 == 0
            _fluorescent(Vector3(x, ceil_y, z), dark_fixture, flicker)
    # Red emergency lamp: dim, pulsing, makes every floor feel wrong.
    var rpos := Vector3(HOSP_X + 8.0, ceil_y - 0.05, HOSP_Z + 3.0)
    var lens := MeshInstance3D.new()
    var lb := BoxMesh.new()
    lb.size = Vector3(0.3, 0.18, 0.3)
    lens.mesh = lb
    lens.position = rpos
    lens.material_override = _emissive_mat(Color(0.9, 0.04, 0.03), 2.0)
    lens.visibility_range_end = VIS_RANGE
    add_child(lens)
    var red := OmniLight3D.new()
    red.position = rpos + Vector3(0, -0.3, 0)
    red.light_color = Color(1.0, 0.06, 0.04)
    red.light_energy = 0.8
    red.omni_range = 9.0
    add_child(red)
    _register_light(red, true)

func _fluorescent(pos: Vector3, broken: bool, flicker: bool = false) -> void:
    # pos is the centre of the fixture housing, which touches the ceiling.
    _box(Vector3(3.0, 0.08, 0.32), pos, Color(0.65, 0.68, 0.65) if not broken else CONCRETE_DARK, false)
    if broken:
        return
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(2.4, 0.04, 0.18)
    mesh.mesh = box
    mesh.position = pos + Vector3(0, -0.06, 0)
    mesh.material_override = _emissive_mat(FLUORESCENT, 1.2)
    mesh.visibility_range_end = VIS_RANGE
    add_child(mesh)
    var light := OmniLight3D.new()
    light.position = pos + Vector3(0, -0.25, 0)
    light.light_color = FLUORESCENT
    light.light_energy = 0.45
    light.omni_range = 7.0
    add_child(light)
    _register_light(light, flicker)

func _hospital_blood(floor: int) -> void:
    var y: float = GROUND_Y + float(floor) * FLOOR_H + 0.14
    var spots: Array[Vector3] = [
        Vector3(HOSP_X - 18, y, HOSP_Z - 12), Vector3(HOSP_X + 7, y, HOSP_Z - 3),
        Vector3(HOSP_X - 7, y, HOSP_Z + 12), Vector3(HOSP_X + 18, y, HOSP_Z + 8)
    ]
    for i in range(spots.size()):
        _blood_stain(spots[i], 1.0 + float((i + floor) % 3))
    # Vertical blood smears on selected walls.
    if floor != 1:
        _blood_smear(Vector3(HOSP_X - HOSP_W / 2.0 + 0.03, y + 1.2, HOSP_Z + 2.0), Vector3(0.04, 2.2, 0.7))
        _blood_smear(Vector3(HOSP_X + HOSP_W / 2.0 - 0.03, y + 1.0, HOSP_Z - 8.0), Vector3(0.04, 1.8, 0.55))

func _blood_stain(pos: Vector3, radius: float) -> void:
    var mesh := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = radius
    cyl.bottom_radius = radius * 1.15
    cyl.height = 0.025
    mesh.mesh = cyl
    mesh.position = pos
    mesh.material_override = _mat(BLOOD)
    add_child(mesh)
    for i in range(3):
        var drop := MeshInstance3D.new()
        var d := CylinderMesh.new()
        var r: float = radius * (0.12 + float(i) * 0.05)
        d.top_radius = r
        d.bottom_radius = r * 1.1
        d.height = 0.028
        drop.mesh = d
        drop.position = pos + Vector3((i - 1) * radius * 0.9, 0.01, ((i * 7) % 3 - 1) * radius * 0.65)
        drop.material_override = _mat(BLOOD_DARK)
        add_child(drop)

func _blood_smear(pos: Vector3, size: Vector3) -> void:
    _box(size, pos, BLOOD_DARK, false)
    _box(Vector3(size.x * 0.5, size.y * 0.35, size.z * 0.6), pos + Vector3(0, -size.y * 0.25, 0.02), BLOOD, false)

func _hospital_roof_ruins() -> void:
    var y: float = GROUND_Y + FLOOR_H * 3.0
    _box(Vector3(HOSP_W + 2.0, 0.3, HOSP_D + 2.0), Vector3(HOSP_X, y, HOSP_Z), ROOF, true)
    for x in [HOSP_X - 18.0, HOSP_X + 17.0]:
        _box(Vector3(3.0, 1.5, 3.0), Vector3(x, y + 0.8, HOSP_Z + 10), CONCRETE_DARK, true)

func _build_street_lights() -> void:
    for x in [115.0, 145.0, 175.0, 205.0, 235.0]:
        for z in [-96.0, -48.0, 48.0, 96.0]:
            _lamp(Vector3(x, ROAD_Y, z))
    for z in [-80.0, -40.0, 40.0, 80.0]:
        _lamp(Vector3(100.0, ROAD_Y, z))
        _lamp(Vector3(250.0, ROAD_Y, z))

func _lamp(pos: Vector3) -> void:
    _box(Vector3(0.22, 5.5, 0.22), pos + Vector3(0, 2.75, 0), CONCRETE_DARK, true)
    _box(Vector3(1.3, 0.18, 0.18), pos + Vector3(0.5, 5.4, 0), CONCRETE_DARK, false)
    var light_mesh := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.16
    sphere.height = 0.32
    sphere.radial_segments = 8
    sphere.rings = 4
    light_mesh.mesh = sphere
    light_mesh.position = pos + Vector3(1.0, 5.25, 0)
    light_mesh.material_override = _emissive_mat(WINDOW_LIT, 2.0)
    light_mesh.visibility_range_end = VIS_RANGE
    add_child(light_mesh)
    var light := OmniLight3D.new()
    light.position = light_mesh.position
    light.light_color = WINDOW_LIT
    light.light_energy = 0.55
    light.omni_range = 8.0
    add_child(light)
    _register_light(light)

func _build_cars() -> void:
    _car(Vector3(133, ROAD_Y + 0.5, 0), Color(0.55, 0.04, 0.03), 0)
    _car(Vector3(194, ROAD_Y + 0.5, -38), Color(0.06, 0.08, 0.1), 90)
    _car(Vector3(224, ROAD_Y + 0.5, 38), Color(0.08, 0.22, 0.55), 90)
    _car(Vector3(157, ROAD_Y + 0.5, 72), Color(0.45, 0.35, 0.08), 0)

func _car(pos: Vector3, color: Color, yaw_deg: float) -> void:
    var body := StaticBody3D.new()
    body.position = pos
    body.rotation.y = deg_to_rad(yaw_deg)
    add_child(body)
    _box_local(body, Vector3(4.4, 1.0, 2.0), Vector3.ZERO, color, true)
    _box_local(body, Vector3(2.4, 0.8, 1.7), Vector3(-0.2, 0.75, 0), CONCRETE_DARK, false)
    for x in [-1.4, 1.4]:
        for z in [-1.0, 1.0]:
            var wheel := MeshInstance3D.new()
            var cyl := CylinderMesh.new()
            cyl.top_radius = 0.38
            cyl.bottom_radius = 0.38
            cyl.height = 0.24
            wheel.mesh = cyl
            wheel.rotation.z = deg_to_rad(90)
            wheel.position = Vector3(x, -0.5, z)
            wheel.material_override = _mat(CONCRETE_DARK)
            body.add_child(wheel)

func _build_city_details() -> void:
    _build_trash_bins()
    _build_parking_lot()

func _build_trash_bins() -> void:
    var spots := [
        Vector3(126, ROAD_Y, -90), Vector3(155, ROAD_Y, -90), Vector3(208, ROAD_Y, -90),
        Vector3(246, ROAD_Y, -42), Vector3(246, ROAD_Y, 42), Vector3(126, ROAD_Y, 42),
        Vector3(190, ROAD_Y, 45), Vector3(190, ROAD_Y, -45)
    ]
    for p in spots:
        _trash_bin(p)

func _trash_bin(pos: Vector3) -> void:
    _box(Vector3(0.85, 1.15, 0.75), pos + Vector3(0, 0.58, 0), Color(0.08, 0.10, 0.09), true)
    _box(Vector3(0.95, 0.12, 0.82), pos + Vector3(0, 1.19, 0), Color(0.025, 0.03, 0.03), false)
    _box(Vector3(0.10, 0.45, 0.10), pos + Vector3(0.38, 0.45, 0.25), Color(0.16, 0.18, 0.17), false)

func _build_parking_lot() -> void:
    # Empty south-west pocket converted to a proper marked parking area.
    var center := Vector3(160.0, ROAD_Y + 0.015, -94.0)
    _box(Vector3(34.0, 0.06, 18.0), center, Color(0.045, 0.047, 0.05), false)
    var line := Color(0.82, 0.80, 0.70)
    for x in [147.5, 154.0, 160.5, 167.0, 173.5]:
        _box(Vector3(0.16, 0.025, 7.5), Vector3(x, ROAD_Y + 0.07, -94.0), line, false)
    _box(Vector3(30.0, 0.025, 0.16), Vector3(160.0, ROAD_Y + 0.07, -101.0), line, false)
    _box(Vector3(30.0, 0.025, 0.16), Vector3(160.0, ROAD_Y + 0.07, -87.0), line, false)

func _box(size: Vector3, pos: Vector3, color: Color, collision: bool) -> void:
    var key: String = "g%d_%d" % [floori(pos.x / 50.0), floori(pos.z / 50.0)]
    _vis_add(key, self, size, Transform3D(Basis.IDENTITY, pos), color)
    if collision:
        var body := StaticBody3D.new()
        body.position = pos
        add_child(body)
        var cs := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        cs.shape = shape
        body.add_child(cs)


func _add_tilted_solid(parent: Node3D, size: Vector3, pos: Vector3, rot_deg: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.position = pos
    body.rotation_degrees = rot_deg
    parent.add_child(body)
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    mesh.material_override = _mat(color)
    body.add_child(mesh)
    var cs := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    cs.shape = shape
    body.add_child(cs)

func _box_local(parent: Node3D, size: Vector3, pos: Vector3, color: Color, collision: bool) -> void:
    if parent.has_meta("batch"):
        _vis_add("b%d" % parent.get_instance_id(), parent, size, Transform3D(Basis.IDENTITY, pos), color)
    else:
        var m := MeshInstance3D.new()
        var b := BoxMesh.new()
        b.size = size
        m.mesh = b
        m.position = pos
        m.material_override = _mat(color)
        parent.add_child(m)
    if collision:
        # CollisionShape3D only works under PhysicsBody3D. Landmarks use plain Node3D roots.
        if parent is StaticBody3D or parent is AnimatableBody3D or parent is CharacterBody3D or parent is RigidBody3D:
            var cs := CollisionShape3D.new()
            var shape := BoxShape3D.new()
            shape.size = size
            cs.shape = shape
            cs.position = pos
            parent.add_child(cs)
        else:
            var body := StaticBody3D.new()
            body.position = pos
            parent.add_child(body)
            var cs2 := CollisionShape3D.new()
            var shape2 := BoxShape3D.new()
            shape2.size = size
            cs2.shape = shape2
            body.add_child(cs2)

func _mat(color: Color) -> StandardMaterial3D:
    if _mat_cache.has(color):
        return _mat_cache[color]
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.86
    _mat_cache[color] = m
    return m

func _emissive_mat(color: Color, energy: float) -> StandardMaterial3D:
    var key: String = "e%s_%s" % [str(color), str(energy)]
    if _mat_cache.has(key):
        return _mat_cache[key]
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.86
    m.emission_enabled = true
    m.emission = color
    m.emission_energy_multiplier = energy
    _mat_cache[key] = m
    return m

func _vis_add(key: String, parent: Node3D, size: Vector3, xf: Transform3D, color: Color) -> void:
    var b: VBatch = _batches.get(key)
    if b == null:
        b = VBatch.new()
        b.parent = parent
        _batches[key] = b
    var h: Vector3 = size * 0.5
    for f in FACES:
        var nrm: Vector3 = f[0]
        var u: Vector3 = f[1]
        var w: Vector3 = f[2]
        var hu: float = absf(u.x) * h.x + absf(u.y) * h.y + absf(u.z) * h.z
        var hv: float = absf(w.x) * h.x + absf(w.y) * h.y + absf(w.z) * h.z
        var ctr := Vector3(nrm.x * h.x, nrm.y * h.y, nrm.z * h.z)
        var base: int = b.v.size()
        var wn: Vector3 = xf.basis * nrm
        b.v.append(xf * (ctr - u * hu - w * hv))
        b.v.append(xf * (ctr - u * hu + w * hv))
        b.v.append(xf * (ctr + u * hu + w * hv))
        b.v.append(xf * (ctr + u * hu - w * hv))
        for k in range(4):
            b.n.append(wn)
            b.c.append(color)
        b.idx.append(base)
        b.idx.append(base + 1)
        b.idx.append(base + 2)
        b.idx.append(base)
        b.idx.append(base + 2)
        b.idx.append(base + 3)

func _flush_batches() -> void:
    for key in _batches:
        var b: VBatch = _batches[key]
        if b.v.is_empty() or not is_instance_valid(b.parent):
            continue
        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = b.v
        arrays[Mesh.ARRAY_NORMAL] = b.n
        arrays[Mesh.ARRAY_COLOR] = b.c
        arrays[Mesh.ARRAY_INDEX] = b.idx
        var mesh := ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.material_override = _vertex_material()
        mi.visibility_range_end = VIS_RANGE
        b.parent.add_child(mi)
    _batches.clear()

func _vertex_material() -> StandardMaterial3D:
    if _vertex_mat == null:
        _vertex_mat = StandardMaterial3D.new()
        _vertex_mat.vertex_color_use_as_albedo = true
        _vertex_mat.vertex_color_is_srgb = true
        _vertex_mat.roughness = 0.86
    return _vertex_mat


func _build_city_skirt() -> void:
    # The city slab is flat and raised, the hills around it are not. Where the ground is lower than the city,
    # close the gap with a retaining wall (with a top lip and support pillars) that reaches down into the ground.
    if _terrain == null or not _terrain.has_method("height"):
        return
    var x0: float = CITY_MIN_X - 1.0
    var x1: float = CITY_MAX_X + 1.0
    var z0: float = CITY_MIN_Z - 1.0
    var z1: float = CITY_MAX_Z + 1.0
    var step: float = 8.0
    var i: int = 0
    var z: float = z0 + step * 0.5
    while z < z1:
        _skirt_segment(Vector2(x0, z), Vector2(-1.0, 0.0), step, i)
        _skirt_segment(Vector2(x1, z), Vector2(1.0, 0.0), step, i)
        z += step
        i += 1
    i = 0
    var x: float = x0 + step * 0.5
    while x < x1:
        _skirt_segment(Vector2(x, z0), Vector2(0.0, -1.0), step, i)
        _skirt_segment(Vector2(x, z1), Vector2(0.0, 1.0), step, i)
        x += step
        i += 1

func _skirt_segment(edge: Vector2, out: Vector2, seg_len: float, idx: int) -> void:
    var low: float = 1.0e9
    for d in [0.0, 2.0, 4.0]:
        var p: Vector2 = edge + out * float(d)
        low = minf(low, float(_terrain.call("height", p.x, p.y)))
    var top: float = 0.04
    var bottom: float = low - global_position.y - 2.5
    if bottom > top - 0.6:
        return
    var h: float = top - bottom
    var along_x: bool = absf(out.y) > 0.5
    var wall_color := Color(0.17, 0.18, 0.19)
    var wall_size := Vector3(seg_len + 0.1, h, 1.0) if along_x else Vector3(1.0, h, seg_len + 0.1)
    var c: Vector2 = edge + out * 0.5
    _box(wall_size, Vector3(c.x, (top + bottom) * 0.5, c.y), wall_color, true)
    # Concrete lip on top so the edge looks finished.
    var lip_size := Vector3(seg_len + 0.1, 0.2, 1.3) if along_x else Vector3(1.3, 0.2, seg_len + 0.1)
    var lc: Vector2 = edge + out * 0.65
    _box(lip_size, Vector3(lc.x, top + 0.1, lc.y), Color(0.26, 0.27, 0.28), false)
    # Support pillar every third segment.
    if idx % 3 == 0:
        var ph: float = h - 0.5
        var psize := Vector3(1.8, ph, 2.0) if along_x else Vector3(2.0, ph, 1.8)
        var pc: Vector2 = edge + out * 1.9
        _box(psize, Vector3(pc.x, bottom + ph * 0.5, pc.y), Color(0.13, 0.14, 0.15), true)
func _hospital_horror(lv: int) -> void:
    # Extra dressing: blood drag trails ending in body bags, tipped gurney, fallen IV stands,
    # bloody handprints and drips on the corridor walls, scattered papers and fallen ceiling tiles.
    # Everything is merged into the hospital mesh and has no collision (cheap, never blocks the player).
    var y: float = GROUND_Y + float(lv) * FLOOR_H + 0.11
    var rng := RandomNumberGenerator.new()
    rng.seed = 7700 + lv * 31
    var key: String = "g_hospital"
    for t in range(3):
        var pos: Vector2 = _horror_spot(rng)
        var dir: float = rng.randf() * TAU
        var step_v := Vector2(sin(dir), cos(dir))
        var last_ok: Vector2 = pos
        for s in range(6):
            var c: Vector2 = pos + step_v * 0.75
            if not _horror_ok(c):
                break
            var w: float = 0.55 - float(s) * 0.05
            var xf := Transform3D(Basis(Vector3.UP, dir), Vector3(HOSP_X + c.x, y + 0.012, HOSP_Z + c.y))
            _vis_add(key, self, Vector3(w, 0.02, 1.5), xf, BLOOD_DARK if s % 2 == 0 else BLOOD)
            pos += step_v * 1.4
            last_ok = pos
        var bag_pos: Vector2 = last_ok + step_v * 1.0
        if _horror_ok(bag_pos):
            _body_bag(key, Vector3(HOSP_X + bag_pos.x, y, HOSP_Z + bag_pos.y), dir)
    for t in range(2):
        var p: Vector2 = _horror_spot(rng)
        _iv_stand(key, Vector3(HOSP_X + p.x, y, HOSP_Z + p.y), t == 1, rng.randf() * TAU)
    var g: Vector2 = _horror_spot(rng)
    _tipped_gurney(key, Vector3(HOSP_X + g.x, y, HOSP_Z + g.y), rng.randf() * TAU)
    for t in range(14):
        var pp: Vector2 = _horror_spot(rng)
        var pxf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(HOSP_X + pp.x, y + 0.006, HOSP_Z + pp.y))
        _vis_add(key, self, Vector3(0.3, 0.012, 0.4), pxf, Color(0.55, 0.55, 0.50))
    for t in range(3):
        var tp: Vector2 = _horror_spot(rng)
        var tb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, 0.12)
        _vis_add(key, self, Vector3(1.2, 0.04, 1.2), Transform3D(tb, Vector3(HOSP_X + tp.x, y + 0.04, HOSP_Z + tp.y)), Color(0.30, 0.31, 0.30))
    _hospital_wall_marks(lv, rng, y, key)

func _horror_ok(p: Vector2) -> bool:
    # Keep clear of the stair opening, the elevator shaft and the outer edge of the corridor.
    if p.x < -9.0 or p.x > 9.0 or p.y < -18.0 or p.y > 18.0:
        return false
    if p.x > 2.0 and p.x < 8.0 and p.y > -16.0 and p.y < -5.5:
        return false
    if p.x > -7.0 and p.x < 1.0 and p.y > 2.5 and p.y < 10.0:
        return false
    return true

func _horror_spot(rng: RandomNumberGenerator) -> Vector2:
    for i in range(30):
        var p := Vector2(rng.randf_range(-8.5, 8.5), rng.randf_range(-17.0, 17.0))
        if _horror_ok(p):
            return p
    return Vector2(-8.0, 12.0)

func _part(root: Transform3D, key: String, size: Vector3, local: Vector3, color: Color) -> void:
    _vis_add(key, self, size, Transform3D(root.basis, root.origin + root.basis * local), color)

func _body_bag(key: String, pos: Vector3, yaw: float) -> void:
    var root := Transform3D(Basis(Vector3.UP, yaw), pos)
    _part(root, key, Vector3(0.8, 0.3, 1.95), Vector3(0, 0.15, 0), Color(0.09, 0.10, 0.095))
    _part(root, key, Vector3(0.05, 0.02, 1.7), Vector3(0, 0.31, 0), Color(0.30, 0.30, 0.28))
    _part(root, key, Vector3(0.55, 0.02, 0.5), Vector3(0.25, 0.32, -0.3), BLOOD_DARK)
    _blood_stain(pos + Vector3(0.5, 0.03, 0.2), 1.1)

func _iv_stand(key: String, pos: Vector3, tipped: bool, yaw: float) -> void:
    var b := Basis(Vector3.UP, yaw)
    var origin: Vector3 = pos
    if tipped:
        b = b * Basis(Vector3(0, 0, 1), 1.5)
        origin = pos + Vector3(0, 0.05, 0)
    var root := Transform3D(b, origin)
    _part(root, key, Vector3(0.04, 2.0, 0.04), Vector3(0, 1.0, 0), Color(0.55, 0.57, 0.56))
    _part(root, key, Vector3(0.5, 0.04, 0.05), Vector3(0, 0.02, 0), Color(0.40, 0.42, 0.41))
    _part(root, key, Vector3(0.05, 0.04, 0.5), Vector3(0, 0.02, 0), Color(0.40, 0.42, 0.41))
    _part(root, key, Vector3(0.16, 0.28, 0.06), Vector3(0.1, 1.82, 0), Color(0.55, 0.60, 0.55))
    _part(root, key, Vector3(0.05, 0.3, 0.05), Vector3(0.1, 1.5, 0), BLOOD)

func _tipped_gurney(key: String, pos: Vector3, yaw: float) -> void:
    var b := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), 1.35)
    var root := Transform3D(b, pos + Vector3(0, 0.1, 0))
    _part(root, key, Vector3(0.9, 0.12, 2.0), Vector3(0, 0.95, 0), Color(0.42, 0.43, 0.40))
    _part(root, key, Vector3(0.8, 0.06, 1.9), Vector3(0, 0.84, 0), Color(0.45, 0.47, 0.46))
    _part(root, key, Vector3(0.5, 0.02, 0.9), Vector3(0.1, 1.02, 0.2), BLOOD_DARK)
    for lx in [-0.38, 0.38]:
        for lz in [-0.9, 0.9]:
            _part(root, key, Vector3(0.05, 0.8, 0.05), Vector3(float(lx), 0.4, float(lz)), Color(0.55, 0.57, 0.56))

func _hospital_wall_marks(lv: int, rng: RandomNumberGenerator, y: float, key: String) -> void:
    # Corridor walls are at HOSP_X +/- 10 (wall segments cover these z ranges).
    var ranges := [Vector2(-14.5, -8.5), Vector2(-2.5, 3.0), Vector2(9.5, 15.5)]
    for t in range(6):
        var side: float = -1.0 if t % 2 == 0 else 1.0
        var rg: Vector2 = ranges[t % 3]
        var wx: float = HOSP_X + side * 9.82
        var wz: float = HOSP_Z + rng.randf_range(rg.x, rg.y)
        var kind: int = (t + lv) % 3
        if kind == 0:
            # Dripping blood from high on the wall.
            for d in range(4):
                var hgt: float = rng.randf_range(0.4, 1.7)
                _vis_add(key, self, Vector3(0.03, hgt, 0.05), Transform3D(Basis.IDENTITY, Vector3(wx, y + 2.3 - hgt * 0.5, wz + float(d) * 0.16)), BLOOD)
            _vis_add(key, self, Vector3(0.03, 0.12, 0.8), Transform3D(Basis.IDENTITY, Vector3(wx, y + 2.34, wz + 0.24)), BLOOD_DARK)
        elif kind == 1:
            # A line of bloody handprints sliding down the wall.
            for d in range(4):
                var hy: float = y + 1.7 - float(d) * 0.22
                var hz: float = wz + float(d) * 0.38
                _vis_add(key, self, Vector3(0.03, 0.16, 0.14), Transform3D(Basis.IDENTITY, Vector3(wx, hy, hz)), BLOOD)
                for f in range(4):
                    _vis_add(key, self, Vector3(0.03, 0.10, 0.025), Transform3D(Basis.IDENTITY, Vector3(wx, hy + 0.12, hz - 0.055 + float(f) * 0.037)), BLOOD)
        else:
            # Long smear down to the floor with a pool at its foot.
            _vis_add(key, self, Vector3(0.03, 2.1, 0.45), Transform3D(Basis.IDENTITY, Vector3(wx, y + 1.1, wz)), BLOOD_DARK)
            _vis_add(key, self, Vector3(0.03, 1.2, 0.18), Transform3D(Basis.IDENTITY, Vector3(wx, y + 0.7, wz + 0.1)), BLOOD)
            _blood_stain(Vector3(wx - side * 0.5, y + 0.03, wz), 0.9)

