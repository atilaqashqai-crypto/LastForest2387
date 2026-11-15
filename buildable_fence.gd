extends Node3D

const REQUIRED_LOGS := 1
const FENCE_LENGTH := 4.0
const POST_COLOR := Color(0.30, 0.18, 0.09)
const RAIL_COLOR := Color(0.43, 0.28, 0.14)

var logs_added := 0
var is_built := false
var progress_label: Label3D

func _ready() -> void:
	add_to_group("interactable")
	_create_progress_label()
	_update_progress()

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	return material

func _add_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	mesh_instance.material_override = _mat(color)
	add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func _create_progress_label() -> void:
	progress_label = Label3D.new()
	progress_label.position = Vector3(0.0, 1.8, 0.0)
	progress_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	progress_label.font_size = 38
	progress_label.pixel_size = 0.009
	progress_label.modulate = Color(1.0, 0.88, 0.62)
	progress_label.outline_size = 8
	progress_label.outline_modulate = Color(0.04, 0.03, 0.02)
	progress_label.no_depth_test = true
	add_child(progress_label)

func _update_progress() -> void:
	if progress_label == null:
		return
	# Keep the wood counter visible only while the fence is being built.
	progress_label.visible = not is_built
	if not is_built:
		progress_label.text = "FENCE %d/%d LOGS" % [logs_added, REQUIRED_LOGS]

func interact(player: Node) -> void:
	if player == null or is_built or not bool(player.get("carried_log")):
		return
	if player.has_method("set_carried_log"):
		player.call("set_carried_log", false)
	_add_log_request()

func _complete_fence() -> void:
	is_built = true
	# Farm fence: two horizontal rails and two end posts.
	for x in [-FENCE_LENGTH * 0.5, FENCE_LENGTH * 0.5]:
		_add_box(Vector3(0.16, 1.2, 0.16), Vector3(x, 0.6, 0.0), POST_COLOR)
	for y in [0.4, 0.88]:
		_add_box(Vector3(FENCE_LENGTH, 0.13, 0.13), Vector3(0.0, y, 0.0), RAIL_COLOR)
	add_to_group("farm_fence")
	_update_progress()

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
		_complete_fence()
