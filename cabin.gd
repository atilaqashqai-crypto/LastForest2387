extends Node3D

const WOOD = Color(0.42, 0.28, 0.16)
const WOOD_DARK = Color(0.28, 0.17, 0.10)
const WOOD_LIGHT = Color(0.55, 0.38, 0.22)
const ROOF_COL = Color(0.25, 0.14, 0.08)
const FLOOR_COL = Color(0.36, 0.24, 0.14)
const STONE = Color(0.35, 0.34, 0.32)
const FABRIC = Color(0.45, 0.18, 0.14)
const FIRE = Color(1.0, 0.45, 0.12)

var door_open = false
var door_pivot: Node3D
var _tween: Tween

func _ready() -> void:
	# Defer so Terrain/Forest exist
	call_deferred("_setup")

func _setup() -> void:
	var y = 0.0
	var terrain = get_node_or_null("../Terrain")
	if terrain and terrain.has_method("height"):
		y = terrain.height(12.0, 12.0)
	position = Vector3(12.0, y, 12.0)
	_clear_trees()
	_build_structure()
	_build_roof()
	_build_door()
	_build_interior()
	add_to_group("interactable")

func _clear_trees() -> void:
	var forest = get_node_or_null("../Forest")
	if forest == null:
		return
	var to_remove = []
	for t in forest.get_children():
		if t is Node3D and t.global_position.distance_to(global_position) < 12.0:
			to_remove.append(t)
	for t in to_remove:
		t.queue_free()

func _mat(c: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _box(size: Vector3, pos: Vector3, color: Color, col: bool = true) -> void:
	var mi = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	add_child(mi)
	if col:
		var body = StaticBody3D.new()
		body.position = pos
		add_child(body)
		var cs = CollisionShape3D.new()
		var sh = BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)

func _box_r(size: Vector3, pos: Vector3, rot: Vector3, color: Color) -> void:
	var mi = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat(color)
	add_child(mi)
	var body = StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	add_child(body)
	var cs = CollisionShape3D.new()
	var sh = BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)

func _build_structure() -> void:
	_box(Vector3(10, 0.25, 8), Vector3(0, 0.12, 0), FLOOR_COL)
	_box(Vector3(10, 3.4, 0.35), Vector3(0, 1.85, -3.9), WOOD)
	_box(Vector3(0.35, 3.4, 8), Vector3(-4.85, 1.85, 0), WOOD)
	_box(Vector3(0.35, 3.4, 8), Vector3(4.85, 1.85, 0), WOOD)
	_box(Vector3(3.9, 3.4, 0.35), Vector3(-2.95, 1.85, 3.9), WOOD)
	_box(Vector3(3.9, 3.4, 0.35), Vector3(2.95, 1.85, 3.9), WOOD)
	_box(Vector3(2.0, 0.7, 0.35), Vector3(0, 3.15, 3.9), WOOD_DARK)
	_box(Vector3(2.4, 0.2, 1.0), Vector3(0, 0.15, 4.6), WOOD_LIGHT)
	for x in [-4.7, 4.7]:
		for z in [-3.7, 3.7]:
			_box(Vector3(0.28, 3.5, 0.28), Vector3(x, 1.85, z), WOOD_DARK)

func _build_roof() -> void:
	var a = deg_to_rad(32.0)
	_box_r(Vector3(6.2, 0.22, 9.2), Vector3(-2.6, 4.35, 0), Vector3(0, 0, a), ROOF_COL)
	_box_r(Vector3(6.2, 0.22, 9.2), Vector3(2.6, 4.35, 0), Vector3(0, 0, -a), ROOF_COL)
	_box(Vector3(0.25, 0.25, 9.0), Vector3(0, 5.05, 0), WOOD_DARK)
	for i in range(4):
		var w = 9.2 - float(i) * 2.2
		var y = 3.7 + float(i) * 0.38
		_box(Vector3(w, 0.4, 0.3), Vector3(0, y, -3.9), WOOD_LIGHT, false)
		_box(Vector3(w, 0.4, 0.3), Vector3(0, y, 3.9), WOOD_LIGHT, false)

func _build_door() -> void:
	door_pivot = Node3D.new()
	door_pivot.position = Vector3(-0.85, 0, 3.9)
	add_child(door_pivot)

	var door_body = StaticBody3D.new()
	door_body.position = Vector3(0.85, 1.45, 0)
	door_pivot.add_child(door_body)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.7, 2.7, 0.12)
	mesh.mesh = box
	mesh.material_override = _mat(WOOD_DARK)
	door_body.add_child(mesh)

	var cs = CollisionShape3D.new()
	var sh = BoxShape3D.new()
	sh.size = Vector3(1.7, 2.7, 0.12)
	cs.shape = sh
	door_body.add_child(cs)

	var handle = MeshInstance3D.new()
	var hb = BoxMesh.new()
	hb.size = Vector3(0.08, 0.28, 0.14)
	handle.mesh = hb
	handle.position = Vector3(0.65, 0.0, 0.1)
	handle.material_override = _mat(Color(0.55, 0.45, 0.2))
	door_body.add_child(handle)

func _build_interior() -> void:
	_box(Vector3(3.5, 0.05, 2.5), Vector3(0, 0.28, 0.2), Color(0.4, 0.12, 0.1), false)
	# table
	_box(Vector3(1.8, 0.12, 1.0), Vector3(0, 0.95, 0.3), WOOD_LIGHT)
	_box(Vector3(0.12, 0.75, 0.12), Vector3(-0.7, 0.55, 0.0), WOOD_DARK)
	_box(Vector3(0.12, 0.75, 0.12), Vector3(0.7, 0.55, 0.0), WOOD_DARK)
	_box(Vector3(0.12, 0.75, 0.12), Vector3(-0.7, 0.55, 0.6), WOOD_DARK)
	_box(Vector3(0.12, 0.75, 0.12), Vector3(0.7, 0.55, 0.6), WOOD_DARK)
	# stools
	_box(Vector3(0.55, 0.1, 0.55), Vector3(-1.4, 0.55, 0.3), WOOD_LIGHT)
	_box(Vector3(0.1, 0.5, 0.1), Vector3(-1.4, 0.28, 0.3), WOOD_DARK)
	_box(Vector3(0.55, 0.1, 0.55), Vector3(1.4, 0.55, 0.3), WOOD_LIGHT)
	_box(Vector3(0.1, 0.5, 0.1), Vector3(1.4, 0.28, 0.3), WOOD_DARK)
	# bed
	_box(Vector3(2.2, 0.35, 1.3), Vector3(-2.8, 0.45, -2.2), WOOD)
	_box(Vector3(2.0, 0.2, 1.15), Vector3(-2.8, 0.7, -2.2), FABRIC, false)
	_box(Vector3(0.6, 0.18, 0.9), Vector3(-3.3, 0.85, -2.2), Color(0.75, 0.72, 0.65), false)
	_box(Vector3(0.12, 1.0, 1.3), Vector3(-3.9, 0.9, -2.2), WOOD_DARK)
	# shelf
	_box(Vector3(2.5, 0.1, 0.4), Vector3(2.2, 2.0, -3.55), WOOD_LIGHT, false)
	# fireplace
	_box(Vector3(1.6, 1.8, 0.9), Vector3(3.2, 1.05, -3.0), STONE)
	_box(Vector3(1.0, 0.7, 0.5), Vector3(3.2, 0.7, -2.7), Color(0.12, 0.1, 0.08), false)
	_box(Vector3(0.7, 2.5, 0.7), Vector3(3.2, 3.2, -3.2), STONE)
	var glow = MeshInstance3D.new()
	var gm = BoxMesh.new()
	gm.size = Vector3(0.7, 0.45, 0.3)
	glow.mesh = gm
	glow.position = Vector3(3.2, 0.65, -2.55)
	var fm = _mat(FIRE)
	fm.emission_enabled = true
	fm.emission = FIRE
	fm.emission_energy_multiplier = 2.5
	glow.material_override = fm
	add_child(glow)
	var light = OmniLight3D.new()
	light.position = Vector3(0.2, 1.5, 0.3)
	light.light_color = Color(1.0, 0.75, 0.45)
	light.light_energy = 1.1
	light.omni_range = 6.0
	add_child(light)

func interact(_player = null) -> void:
	toggle_door()

func toggle_door() -> void:
	if door_pivot == null:
		return
	door_open = not door_open
	var target = -1.4 if door_open else 0.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(door_pivot, "rotation:y", target, 0.45)

func can_accept_player() -> bool:
	return true
