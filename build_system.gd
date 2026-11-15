extends Node

var is_placing := false
var placement_kind := "cabin"
var preview_root: Node3D = null
var _last_player: Node3D = null

const FENCE_LENGTH := 4.0
const FENCE_POST_COLOR := Color(0.65, 0.9, 0.68, 0.75)
const FENCE_RAIL_COLOR := Color(0.3, 0.8, 0.42, 0.38)

func toggle_placement(player: Node3D, kind: String = "cabin") -> void:
	if is_placing:
		cancel_placement()
		return
	if player == null or player.get("current_vehicle") != null or bool(player.get("carried_log")):
		return
	if kind not in ["cabin", "fence", "fire"]:
		return
	_last_player = player
	placement_kind = kind
	is_placing = true
	_create_preview()
	_update_preview()

func _ghost_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _create_preview() -> void:
	preview_root = Node3D.new()
	if placement_kind == "fence":
		preview_root.name = "FencePlacementPreview"
	elif placement_kind == "fire":
		preview_root.name = "FirePlacementPreview"
	else:
		preview_root.name = "CabinPlacementPreview"
	get_tree().current_scene.add_child(preview_root)

	if placement_kind == "fence":
		_make_fence_preview()
		return
	if placement_kind == "fire":
		_make_fire_preview()
		return

	# Keep the original cabin's translucent placement blueprint unchanged.
	var ghost_mat := _ghost_material(Color(0.3, 0.8, 0.42, 0.28))
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(9.0, 0.08, 7.0)
	floor_mesh.mesh = floor_box
	floor_mesh.position.y = 0.08
	floor_mesh.material_override = ghost_mat
	preview_root.add_child(floor_mesh)

	var frame_mat := _ghost_material(Color(0.65, 0.9, 0.68, 0.75))
	for x in [-4.35, 4.35]:
		for z in [-3.35, 3.35]:
			var post := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.16, 3.4, 0.16)
			post.mesh = box
			post.position = Vector3(x, 1.75, z)
			post.material_override = frame_mat
			preview_root.add_child(post)

func _make_fence_preview() -> void:
	var rail_mat := _ghost_material(FENCE_RAIL_COLOR)
	var post_mat := _ghost_material(FENCE_POST_COLOR)
	for x in [-FENCE_LENGTH * 0.5, FENCE_LENGTH * 0.5]:
		var post := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.16, 1.2, 0.16)
		post.mesh = mesh
		post.position = Vector3(x, 0.6, 0.0)
		post.material_override = post_mat
		preview_root.add_child(post)
	for y in [0.4, 0.88]:
		var rail := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(FENCE_LENGTH, 0.13, 0.13)
		rail.mesh = mesh
		rail.position = Vector3(0.0, y, 0.0)
		rail.material_override = rail_mat
		preview_root.add_child(rail)

func _process(_delta: float) -> void:
	if is_placing:
		_update_preview()

func _terrain_height(x: float, z: float) -> float:
	var terrain := get_tree().current_scene.get_node_or_null("Terrain")
	if terrain != null and terrain.has_method("height"):
		return float(terrain.call("height", x, z))
	return 0.0

func _update_preview() -> void:
	if not is_instance_valid(preview_root) or not is_instance_valid(_last_player):
		return
	var forward: Vector3 = -_last_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var distance := 7.0 if placement_kind == "cabin" else 3.2
	var target := _last_player.global_position + forward * distance

	# For fences, snap an endpoint to a nearby existing fence endpoint.
	if placement_kind == "fence":
		var snapped := _find_fence_snap(target, _last_player.global_rotation.y)
		target = snapped["position"]
		preview_root.global_rotation.y = float(snapped["rotation"])
	else:
		preview_root.global_rotation.y = _last_player.global_rotation.y

	var y := _terrain_height(target.x, target.z)
	preview_root.global_position = Vector3(target.x, y, target.z)

func _find_fence_snap(target: Vector3, yaw: float) -> Dictionary:
	var best_distance := 1.25
	var best_position := target
	var best_rotation := yaw
	var found := false
	for fence in get_tree().get_nodes_in_group("farm_fence"):
		if not is_instance_valid(fence) or not fence is Node3D:
			continue
		var fence_node := fence as Node3D
		var axis := Vector3(cos(fence_node.global_rotation.y), 0.0, -sin(fence_node.global_rotation.y))
		for sign_value in [-1.0, 1.0]:
			var endpoint: Vector3 = fence_node.global_position + axis * (FENCE_LENGTH * 0.5 * float(sign_value))
			var candidate: Vector3 = endpoint + axis * (FENCE_LENGTH * 0.5 * float(sign_value))
			var d := Vector2(target.x - candidate.x, target.z - candidate.z).length()
			if d < best_distance:
				best_distance = d
				best_position = candidate
				best_rotation = fence_node.global_rotation.y
				found = true
	if found:
		return {"position": best_position, "rotation": best_rotation}
	return {"position": target, "rotation": yaw}


func _make_fire_preview() -> void:
	var mat := _ghost_material(Color(0.75, 0.55, 0.25, 0.55))
	var ring := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 0.2, 1.3)
	ring.mesh = box
	ring.position = Vector3(0, 0.12, 0)
	ring.material_override = mat
	preview_root.add_child(ring)
	var inner := MeshInstance3D.new()
	var ibox := BoxMesh.new()
	ibox.size = Vector3(0.7, 0.08, 0.7)
	inner.mesh = ibox
	inner.position = Vector3(0, 0.18, 0)
	inner.material_override = _ghost_material(Color(0.9, 0.4, 0.15, 0.4))
	preview_root.add_child(inner)

func confirm_placement(player: Node3D) -> void:
	if not is_placing or not is_instance_valid(player) or bool(player.get("carried_log")):
		return
	_update_preview()
	if not is_instance_valid(preview_root):
		cancel_placement()
		return

	if Network.is_online and multiplayer.multiplayer_peer != null:
		# Online: the server creates the site for everyone.
		var bs = get_tree().current_scene.get_node_or_null("BuildSync")
		if bs != null:
			bs.request_place(placement_kind, preview_root.global_position, preview_root.global_rotation.y)
			cancel_placement()
			return
	var site := Node3D.new()
	if placement_kind == "fence":
		site.name = "FenceConstructionSite"
		site.set_script(load("res://buildable_fence.gd"))
	elif placement_kind == "fire":
		site.name = "FireConstructionSite"
		site.set_script(load("res://buildable_fire.gd"))
	else:
		site.name = "CabinConstructionSite"
		site.set_script(load("res://buildable_cabin.gd"))
	site.global_transform = preview_root.global_transform
	get_tree().current_scene.add_child(site)
	cancel_placement()

func cancel_placement() -> void:
	is_placing = false
	if is_instance_valid(preview_root):
		preview_root.queue_free()
	preview_root = null
	_last_player = null
	placement_kind = "cabin"
