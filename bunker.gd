extends Node3D

const ENTRANCE_X := -252.0
const ENTRANCE_Z := 0.0
const INTERIOR_POSITION := Vector3(0.0, -100.0, 0.0)

const CONCRETE := Color(0.24, 0.26, 0.27)
const CONCRETE_DARK := Color(0.13, 0.15, 0.16)
const STEEL := Color(0.12, 0.15, 0.17)
const STEEL_EDGE := Color(0.34, 0.38, 0.4)
const YELLOW := Color(1.0, 0.78, 0.02)
const BLACK := Color(0.025, 0.025, 0.025)

var door_open := false
var door_pivot: Node3D = null
var door_collision: StaticBody3D = null
var interior: Node3D = null
var _door_tween: Tween = null
var _terrain: Node = null

func _ready() -> void:
	call_deferred("_build")

func _build() -> void:
	_terrain = get_node_or_null("../Terrain")
	var ground_y := 0.0
	if _terrain != null and _terrain.has_method("height"):
		ground_y = float(_terrain.call("height", ENTRANCE_X, ENTRANCE_Z))
	# Sit the door sill on the local terrain so the player can walk straight in.
	global_position = Vector3(ENTRANCE_X, ground_y - 0.15, ENTRANCE_Z)
	rotation.y = -PI * 0.5
	_clear_nearby_obstacles()
	_build_entrance()
	_build_entry_pad()
	_build_interior()
	add_to_group("interactable")

func _clear_nearby_obstacles() -> void:
	for path in ["../Forest", "../Props"]:
		var holder := get_node_or_null(path)
		if holder == null:
			continue
		for item in holder.get_children():
			if item is Node3D and item.global_position.distance_to(global_position) < 13.0:
				item.queue_free()

func _material(color: Color, metal: float = 0.0, rough: float = 0.85) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = rough
	return material

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, solid: bool = false, metal: float = 0.0) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.position = pos
	mesh_instance.material_override = _material(color, metal)
	parent.add_child(mesh_instance)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		parent.add_child(body)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
	return mesh_instance

func _label(parent: Node3D, value: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.position = pos
	label.font_size = size
	label.modulate = color
	label.outline_size = 6
	label.outline_modulate = BLACK
	label.pixel_size = 0.012
	parent.add_child(label)
	return label

func _build_entrance() -> void:
	# Massive concrete frame set into the mountain face.
	_box(self, Vector3(1.1, 6.4, 1.3), Vector3(-5.25, 3.15, 0.0), CONCRETE, true)
	_box(self, Vector3(1.1, 6.4, 1.3), Vector3(5.25, 3.15, 0.0), CONCRETE, true)
	_box(self, Vector3(11.6, 1.25, 1.4), Vector3(0.0, 6.0, 0.0), CONCRETE, true)
	_box(self, Vector3(10.2, 0.35, 2.0), Vector3(0.0, 0.12, 0.2), CONCRETE_DARK, true)
	_box(self, Vector3(0.28, 5.2, 0.18), Vector3(-2.55, 2.75, -0.72), STEEL_EDGE, false, 0.5)
	_box(self, Vector3(0.28, 5.2, 0.18), Vector3(2.55, 2.75, -0.72), STEEL_EDGE, false, 0.5)
	# Dark portal surface behind the blast door makes the open entrance read as a tunnel.
	_box(self, Vector3(4.65, 5.2, 0.1), Vector3(0.0, 2.65, -0.38), Color(0.008, 0.012, 0.016), false)

	# Yellow radiation-warning plate and black symbol, facing the forest.
	_box(self, Vector3(5.4, 1.65, 0.28), Vector3(0.0, 7.15, -0.62), YELLOW, false, 0.15)
	_label(self, "☢", Vector3(0.0, 6.48, -0.82), 112, BLACK)
	
	# Heavy blast door with a side hinge.
	door_pivot = Node3D.new()
	door_pivot.position = Vector3(-2.35, 0.0, -0.72)
	add_child(door_pivot)
	door_collision = StaticBody3D.new()
	door_collision.position = Vector3(2.35, 2.65, 0.0)
	door_pivot.add_child(door_collision)
	_box(door_collision, Vector3(4.7, 5.3, 0.42), Vector3.ZERO, STEEL, false, 0.65)
	var door_shape := CollisionShape3D.new()
	var door_box := BoxShape3D.new()
	door_box.size = Vector3(4.7, 5.3, 0.42)
	door_shape.shape = door_box
	door_collision.add_child(door_shape)
	_box(door_collision, Vector3(4.25, 4.85, 0.12), Vector3(0.0, 0.0, -0.28), CONCRETE_DARK, false, 0.25)
	for x in [-1.85, 1.85]:
		for y in [-2.15, 2.15]:
			_box(door_collision, Vector3(0.18, 0.18, 0.12), Vector3(x, y, -0.37), STEEL_EDGE, false, 0.7)
	_box(door_collision, Vector3(0.18, 1.3, 0.18), Vector3(1.85, 0.0, -0.4), YELLOW, false, 0.2)
	_box(door_collision, Vector3(0.12, 0.75, 0.16), Vector3(1.48, 0.0, -0.42), STEEL_EDGE, false, 0.8)

	# Hazard stripes along the threshold.
	for i in 10:
		var stripe_color := YELLOW if i % 2 == 0 else BLACK
		_box(self, Vector3(0.52, 0.08, 0.34), Vector3(-2.34 + float(i) * 0.52, 0.24, -1.02), stripe_color, false)

	# Status lamps.
	_add_lamp(Vector3(-5.9, 4.8, -0.85), Color(0.1, 0.85, 0.2))
	_add_lamp(Vector3(5.9, 4.8, -0.85), Color(0.95, 0.12, 0.06))

func _add_lamp(pos: Vector3, color: Color) -> void:
	var lamp := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	lamp.mesh = sphere
	lamp.position = pos
	var mat := _material(color, 0.15, 0.25)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.4
	lamp.material_override = mat
	add_child(lamp)

func interact(player: Node3D = null) -> void:
	if not door_open:
		_set_door_open(true)
		return
	if player != null:
		_enter_bunker(player)
	else:
		_set_door_open(false)

func _set_door_open(open: bool) -> void:
	if door_pivot == null:
		return
	door_open = open
	if _door_tween != null and _door_tween.is_running():
		_door_tween.kill()
	_door_tween = create_tween()
	var target := -1.48 if door_open else 0.0
	_door_tween.tween_property(door_pivot, "rotation:y", target, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)



func _build_entry_pad() -> void:
	# Flat concrete apron in front of the door, flush with the mountain base.
	_box(self, Vector3(10.0, 0.35, 6.0), Vector3(0.0, 0.05, -3.2), CONCRETE, true)
	_box(self, Vector3(8.0, 0.25, 4.0), Vector3(0.0, 0.02, -6.5), CONCRETE_DARK, true)


func _build_interior() -> void:
	interior = Node3D.new()
	interior.name = "BunkerInterior"
	add_child(interior)
	interior.global_position = INTERIOR_POSITION
	interior.global_rotation = Vector3.ZERO

	# Sealed underground room: 18 m wide, 16 m deep, 6 m high.
	_box(interior, Vector3(18.0, 0.45, 16.0), Vector3(0.0, -0.25, 0.0), Color(0.19, 0.2, 0.21), true)
	_box(interior, Vector3(18.0, 6.4, 0.45), Vector3(0.0, 2.95, 8.0), CONCRETE, true)
	_box(interior, Vector3(0.45, 6.4, 16.0), Vector3(-9.0, 2.95, 0.0), CONCRETE, true)
	_box(interior, Vector3(0.45, 6.4, 16.0), Vector3(9.0, 2.95, 0.0), CONCRETE, true)
	_box(interior, Vector3(18.0, 0.55, 16.0), Vector3(0.0, 6.15, 0.0), CONCRETE_DARK, true)

	# Reinforced ceiling beams and wall markings.
	for x in [-7.0, -3.5, 0.0, 3.5, 7.0]:
		_box(interior, Vector3(0.22, 0.35, 15.0), Vector3(x, 5.72, 0.0), STEEL_EDGE, false, 0.65)
	_box(interior, Vector3(8.0, 0.12, 0.12), Vector3(0.0, 4.8, -7.72), YELLOW, false)
	_label(interior, "AUTHORIZED PERSONNEL ONLY", Vector3(0.0, 4.95, -7.68), 22, YELLOW)
	_label(interior, "LAST FOREST  /  SHELTER 01", Vector3(0.0, 5.55, 7.72), 24, YELLOW)

	# Interior lighting.
	for x in [-5.5, 0.0, 5.5]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 4.9, 0.0)
		light.light_color = Color(0.72, 0.82, 0.88)
		light.light_energy = 1.5
		light.omni_range = 13.0
		interior.add_child(light)

	_build_storage_racks()
	_build_exit_door()
	_build_bunker_loot()

func _build_storage_racks() -> void:
	# Food and water shelves on the left.
	for z in [-4.8, -1.8, 1.2, 4.2]:
		_box(interior, Vector3(3.8, 0.18, 1.0), Vector3(-6.7, 1.45, z), STEEL_EDGE, true, 0.55)
		_box(interior, Vector3(3.8, 0.18, 1.0), Vector3(-6.7, 3.0, z), STEEL_EDGE, true, 0.55)
		_box(interior, Vector3(0.12, 3.2, 0.12), Vector3(-8.45, 1.9, z), STEEL, true, 0.55)
		_box(interior, Vector3(0.12, 3.2, 0.12), Vector3(-4.95, 1.9, z), STEEL, true, 0.55)

	# Weapons rack on the right.
	for z in [-4.0, 0.0, 4.0]:
		_box(interior, Vector3(4.0, 0.2, 1.0), Vector3(6.5, 1.2, z), STEEL_EDGE, true, 0.6)
		_box(interior, Vector3(4.0, 0.2, 1.0), Vector3(6.5, 3.0, z), STEEL_EDGE, true, 0.6)
		_box(interior, Vector3(0.12, 3.5, 0.12), Vector3(4.65, 1.9, z), STEEL, true, 0.6)
		_box(interior, Vector3(0.12, 3.5, 0.12), Vector3(8.35, 1.9, z), STEEL, true, 0.6)

	# Central supply crates.
	_box(interior, Vector3(2.0, 1.25, 1.5), Vector3(-1.8, 0.62, 3.2), Color(0.25, 0.29, 0.23), true)
	_box(interior, Vector3(2.0, 1.25, 1.5), Vector3(1.8, 0.62, 3.2), Color(0.25, 0.29, 0.23), true)
	_box(interior, Vector3(0.12, 1.3, 1.55), Vector3(-1.8, 0.62, 3.2), YELLOW, false)
	_box(interior, Vector3(0.12, 1.3, 1.55), Vector3(1.8, 0.62, 3.2), YELLOW, false)

func _build_exit_door() -> void:
	_box(interior, Vector3(4.8, 5.5, 0.35), Vector3(0.0, 2.75, -7.72), STEEL, true, 0.6)
	_box(interior, Vector3(3.8, 4.5, 0.12), Vector3(0.0, 2.75, -7.96), CONCRETE_DARK, false)
	_label(interior, "EXIT", Vector3(0.0, 4.2, -8.05), 46, YELLOW)
	var exit_node := Node3D.new()
	exit_node.name = "BunkerExitInteractable"
	exit_node.position = Vector3(0.0, 1.4, -6.5)
	exit_node.set_script(load("res://bunker_exit.gd"))
	exit_node.set("bunker", self)
	interior.add_child(exit_node)
	exit_node.add_to_group("interactable")

func _build_bunker_loot() -> void:
	# Canned food and water on the storage racks.
	var food_positions: Array[Vector3] = [
		Vector3(-6.8, 1.95, -5.1), Vector3(-6.0, 1.95, -4.4),
		Vector3(-7.2, 1.95, -2.0), Vector3(-6.2, 1.95, -1.4),
		Vector3(-7.0, 3.5, 1.0), Vector3(-6.0, 3.5, 1.7),
		Vector3(-7.0, 3.5, 4.0), Vector3(-6.0, 3.5, 4.7),
		Vector3(-2.0, 1.4, 4.4), Vector3(2.0, 1.4, 4.4),
		Vector3(-2.0, 1.4, 2.0), Vector3(2.0, 1.4, 2.0)
	]
	for pos in food_positions:
		_add_pickup("food", pos)

	var water_positions: Array[Vector3] = [
		Vector3(-7.4, 3.5, -5.0), Vector3(-5.8, 3.5, -5.0),
		Vector3(-7.4, 1.95, 1.0), Vector3(-5.8, 1.95, 1.0),
		Vector3(-7.4, 1.95, 4.0), Vector3(-5.8, 1.95, 4.0),
		Vector3(-1.8, 1.45, 3.1), Vector3(1.8, 1.45, 3.1)
	]
	for pos in water_positions:
		_add_pickup("water", pos)

	# Multiple weapons and ammunition caches.
	_add_pickup("pistol", Vector3(6.0, 1.75, -4.0))
	_add_pickup("pistol", Vector3(7.0, 3.55, -4.0))
	_add_pickup("shotgun", Vector3(6.0, 1.75, 0.0))
	_add_pickup("shotgun", Vector3(7.0, 3.55, 0.0))
	_add_pickup("ak", Vector3(6.0, 1.75, 4.0))
	_add_pickup("ak", Vector3(7.0, 3.55, 4.0))
	_add_pickup("ammo_pistol", Vector3(4.8, 1.75, -2.0))
	_add_pickup("ammo_pistol", Vector3(8.0, 1.75, -2.0))
	_add_pickup("ammo_shotgun", Vector3(4.8, 1.75, 2.0))
	_add_pickup("ammo_ak", Vector3(8.0, 1.75, 2.0))
	_add_pickup("medkits", Vector3(0.0, 1.25, 5.4))
	_add_pickup("medkits", Vector3(2.2, 1.25, 5.4))

func _add_pickup(kind: String, pos: Vector3) -> void:
	var area := Area3D.new()
	area.name = "BunkerLoot_" + kind
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1
	interior.add_child(area)
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	collision.shape = sphere
	area.add_child(collision)

	var item_color := Color(0.75, 0.5, 0.16)
	var item_size := Vector3(0.55, 0.55, 0.55)
	if kind == "water":
		item_color = Color(0.1, 0.4, 0.8)
		item_size = Vector3(0.32, 0.65, 0.32)
	elif kind == "medkits":
		item_color = Color(0.9, 0.9, 0.82)
		item_size = Vector3(0.65, 0.4, 0.48)
	elif kind.begins_with("ammo_"):
		item_color = YELLOW
		item_size = Vector3(0.42, 0.28, 0.42)
	elif kind in ["pistol", "shotgun", "ak"]:
		item_color = STEEL_EDGE
		item_size = Vector3(0.2, 0.2, 1.0 if kind != "pistol" else 0.45)
	var visual := MeshInstance3D.new()
	var item_mesh := BoxMesh.new()
	item_mesh.size = item_size
	visual.mesh = item_mesh
	visual.position = Vector3(0.0, 0.0, 0.0)
	visual.material_override = _material(item_color, 0.25, 0.55)
	area.add_child(visual)
	area.body_entered.connect(_on_pickup.bind(area, kind))

func _on_pickup(body: Node3D, area: Area3D, kind: String) -> void:
	if not is_instance_valid(area) or not is_instance_valid(body):
		return
	if not body.is_in_group("player") and body.name != "Player":
		return
	var inventory := body.get_node_or_null("Inventory")
	if inventory == null or not inventory.has_method("add"):
		return
	inventory.call("add", kind)
	area.queue_free()

func _enter_bunker(player: Node3D) -> void:
	if interior == null or not is_instance_valid(player):
		return
	player.global_position = interior.global_position + Vector3(0.0, 1.1, -5.2)
	player.global_rotation = Vector3.ZERO
	_reset_player_motion(player)

func exit_bunker(player: Node3D) -> void:
	if not is_instance_valid(player):
		return
	var outside_x := ENTRANCE_X - 4.5
	var outside_y := 1.0
	if _terrain != null and _terrain.has_method("height"):
		outside_y = float(_terrain.call("height", outside_x, ENTRANCE_Z)) + 1.0
	player.global_position = Vector3(outside_x, outside_y, ENTRANCE_Z)
	player.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)
	_reset_player_motion(player)

func _reset_player_motion(player: Node3D) -> void:
	if player is CharacterBody3D:
		player.velocity = Vector3.ZERO
	if "move_input" in player:
		player.move_input = Vector2.ZERO
	if "sprinting" in player:
		player.sprinting = false
	var camera_pivot := player.get_node_or_null("CameraPivot") as Node3D
	if camera_pivot != null:
		camera_pivot.rotation.y = 0.0
		camera_pivot.rotation.z = 0.0
		camera_pivot.rotation.x = 0.0
