extends Node3D

const REQUIRED_LOGS := 5
const WOOD := Color(0.34, 0.21, 0.11)
const WOOD_LIGHT := Color(0.49, 0.32, 0.17)
const WOOD_DARK := Color(0.20, 0.12, 0.07)
const ROOF := Color(0.16, 0.14, 0.12)

var logs_added := 0
var is_built := false
var progress_label: Label3D
var door_pivot: Node3D
var door_open := false

func _ready() -> void:
	add_to_group("interactable")
	_build_foundation()
	_create_progress_label()
	_update_progress()

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material

func _add_box(size: Vector3, pos: Vector3, color: Color, solid: bool = true, rot: Vector3 = Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	mesh_instance.rotation = rot
	mesh_instance.material_override = _mat(color)
	add_child(mesh_instance)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation = rot
		add_child(body)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)

func _build_foundation() -> void:
	_add_box(Vector3(9.0, 0.12, 7.0), Vector3(0.0, 0.06, 0.0), Color(0.29, 0.22, 0.14), true)
	for x in [-4.35, 4.35]:
		for z in [-3.35, 3.35]:
			_add_box(Vector3(0.18, 0.45, 0.18), Vector3(x, 0.28, z), WOOD_DARK, false)

func _create_progress_label() -> void:
	progress_label = Label3D.new()
	progress_label.position = Vector3(0.0, 3.4, 0.0)
	progress_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	progress_label.font_size = 44
	progress_label.pixel_size = 0.009
	progress_label.modulate = Color(1.0, 0.88, 0.62)
	progress_label.outline_size = 8
	progress_label.outline_modulate = Color(0.04, 0.03, 0.02)
	progress_label.no_depth_test = true
	add_child(progress_label)

func _update_progress() -> void:
	if progress_label == null:
		return
	# Show the wood count only while the cabin is under construction.
	progress_label.visible = not is_built
	if not is_built:
		progress_label.text = "CABIN %d/%d LOGS" % [logs_added, REQUIRED_LOGS]

func interact(player: Node) -> void:
	if player == null:
		return
	if not is_built:
		if bool(player.get("carried_log")):
			if player.has_method("set_carried_log"):
				player.call("set_carried_log", false)
			_add_log_request()
		return
	_toggle_door()

func _complete_cabin() -> void:
	is_built = true
	_build_walls_and_roof()
	_update_progress()

func _build_walls_and_roof() -> void:
	# Full cabin timber siding: a dark structural backing plus evenly spaced horizontal boards.
	# The same striped timber language used on the new gable ends now covers every wall.
	_build_horizontal_wall(Vector3(8.8, 3.4, 0.24), Vector3(0.0, 1.8, -3.4), false)
	_build_horizontal_wall(Vector3(0.24, 3.4, 6.8), Vector3(-4.4, 1.8, 0.0), true)
	_build_horizontal_wall(Vector3(0.24, 3.4, 6.8), Vector3(4.4, 1.8, 0.0), true)
	# Rear wall keeps the centered doorway opening.
	_build_horizontal_wall(Vector3(3.3, 3.4, 0.24), Vector3(-2.75, 1.8, 3.4), false)
	_build_horizontal_wall(Vector3(3.3, 3.4, 0.24), Vector3(2.75, 1.8, 3.4), false)
	# Doorway is intentionally open (no solid wall behind the swinging door).
	# Corner posts and a heavy sill give the cabin a hand-built timber-frame character.
	for x in [-4.22, 4.22]:
		for z in [-3.22, 3.22]:
			_add_box(Vector3(0.22, 3.6, 0.22), Vector3(x, 1.85, z), WOOD_DARK, false)
	# Correctly pitched roof: both panels rise toward the center ridge.
	_add_box(Vector3(4.65, 0.22, 7.35), Vector3(-2.12, 4.22, 0.0), ROOF, true, Vector3(0.0, 0.0, 0.32))
	_add_box(Vector3(4.65, 0.22, 7.35), Vector3(2.12, 4.22, 0.0), ROOF, true, Vector3(0.0, 0.0, -0.32))
	# Close the triangular gable openings at both ends of the pitched roof.
	_build_gable_end(3.43)
	_build_gable_end(-3.43)
	# Timber trim around the doorway.
	_add_box(Vector3(0.18, 3.4, 0.2), Vector3(-1.12, 1.8, 3.53), WOOD_LIGHT, false)
	_add_box(Vector3(0.18, 3.4, 0.2), Vector3(1.12, 1.8, 3.53), WOOD_LIGHT, false)
	_build_door()

func _build_horizontal_wall(size: Vector3, pos: Vector3, side_wall: bool) -> void:
	# Structural backing prevents daylight from leaking through the narrow decorative gaps.
	_add_box(size, pos, WOOD_DARK, true)
	var board_h := 0.27
	var gap := 0.035
	var rows := 11
	var start_y := 0.30
	for i in range(rows):
		var y := start_y + i * (board_h + gap)
		if side_wall:
			# Side boards run along the cabin length.
			_add_box(Vector3(0.055, board_h, size.z + 0.04), Vector3(pos.x + (0.135 if pos.x < 0.0 else -0.135), y, pos.z), WOOD_LIGHT, false)
		else:
			# End boards run horizontally and create the same lined pattern as the gables.
			_add_box(Vector3(size.x + 0.04, board_h, 0.055), Vector3(pos.x, y, pos.z + (0.135 if pos.z < 0.0 else -0.135)), WOOD_LIGHT, false)


func _build_gable_end(z_face: float) -> void:
	# A thin solid timber infill follows the roof pitch, closing the front/rear attic triangles.
	var z_front := z_face - 0.09
	var z_back := z_face + 0.09
	var left_bottom := Vector3(-4.38, 3.48, z_front)
	var right_bottom := Vector3(4.38, 3.48, z_front)
	var peak_front := Vector3(0.0, 4.96, z_front)
	var left_back := Vector3(-4.38, 3.48, z_back)
	var right_back := Vector3(4.38, 3.48, z_back)
	var peak_back := Vector3(0.0, 4.96, z_back)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_triangle(st, left_bottom, right_bottom, peak_front)
	_add_triangle(st, right_back, left_back, peak_back)
	_add_triangle(st, left_back, left_bottom, peak_front)
	_add_triangle(st, left_back, peak_front, peak_back)
	_add_triangle(st, right_bottom, right_back, peak_back)
	_add_triangle(st, right_bottom, peak_back, peak_front)
	_add_triangle(st, left_bottom, left_back, right_back)
	_add_triangle(st, left_bottom, right_back, right_bottom)
	_add_triangle(st, peak_front, peak_back, left_back)
	_add_triangle(st, peak_front, left_back, left_bottom)
	_add_triangle(st, peak_back, peak_front, right_bottom)
	_add_triangle(st, peak_back, right_bottom, right_back)
	st.generate_normals()
	var gable_mesh := MeshInstance3D.new()
	gable_mesh.mesh = st.commit()
	gable_mesh.material_override = _mat(WOOD)
	add_child(gable_mesh)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array([left_bottom, right_bottom, peak_front, left_back, right_back, peak_back])
	collision.shape = hull
	body.add_child(collision)
	add_child(body)
	# Horizontal timber siding on the gable face; each board narrows toward the ridge.
	var face_z := z_face + (0.105 if z_face > 0.0 else -0.105)
	for y in [3.72, 3.98, 4.24, 4.50, 4.76]:
		var half_width: float = 4.38 * (1.0 - (y - 3.48) / (4.96 - 3.48))
		var board_width: float = max(0.25, half_width * 2.0 - 0.12)
		_add_box(Vector3(board_width, 0.055, 0.045), Vector3(0.0, y, face_z), WOOD_LIGHT, false)
	# Exposed rafters and fascia emphasize the triangular roof silhouette.
	var trim_z := face_z + (0.035 if z_face > 0.0 else -0.035)
	_add_box(Vector3(4.72, 0.16, 0.16), Vector3(-2.20, 4.22, trim_z), WOOD_DARK, false, Vector3(0.0, 0.0, 0.325))
	_add_box(Vector3(4.72, 0.16, 0.16), Vector3(2.20, 4.22, trim_z), WOOD_DARK, false, Vector3(0.0, 0.0, -0.325))
	_add_box(Vector3(0.18, 0.18, 0.18), Vector3(0.0, 4.96, trim_z), WOOD_LIGHT, false)

func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _build_door() -> void:
	door_pivot = Node3D.new()
	door_pivot.position = Vector3(-1.1, 0.0, 3.48)
	add_child(door_pivot)
	var door := StaticBody3D.new()
	door.position = Vector3(1.1, 1.55, 0.0)
	door_pivot.add_child(door)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.2, 3.1, 0.14)
	mesh.mesh = box
	mesh.material_override = _mat(WOOD_DARK)
	door.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 3.1, 0.14)
	collision.shape = shape
	door.add_child(collision)

func _toggle_door() -> void:
	if door_pivot == null:
		return
	if net_id != "" and Network.is_online:
		var bs = get_tree().current_scene.get_node_or_null("BuildSync")
		if bs != null:
			bs.request_door(net_id, not door_open)
			return
	net_set_door(not door_open)

func net_set_door(open: bool) -> void:
	if door_pivot == null:
		return
	door_open = open
	var target := -1.35 if door_open else 0.0
	var tween := create_tween()
	tween.tween_property(door_pivot, "rotation:y", target, 0.35)

# ---------- multiplayer: BuildSync keeps every player's copy identical ----------
var net_id := ""

func _add_log_request() -> void:
	if net_id != "" and Network.is_online:
		var bs = get_tree().current_scene.get_node_or_null("BuildSync")
		if bs != null:
			bs.request_log(net_id)
			return
	net_set_logs(logs_added + 1)

func net_set_logs(n: int) -> void:
	if is_built:
		return
	logs_added = n
	_update_progress()
	if logs_added >= REQUIRED_LOGS:
		_complete_cabin()
