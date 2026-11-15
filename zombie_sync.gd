extends Node
## Server -> clients zombie sync.
## Server runs the real zombies and sends snapshots; clients show puppet copies.

const SEND_INTERVAL := 0.1
const STRIDE := 7          # id, x, y, z, yaw, hp, flags
const MAX_SEND := 60
const SEND_RADIUS := 120.0

var t := 0.0
var puppets: Dictionary = {}

func _physics_process(d: float) -> void:
	if not multiplayer.is_server():
		return
	t += d
	if t < SEND_INTERVAL:
		return
	t = 0.0
	var zs := get_tree().get_nodes_in_group("zombie")
	for pid in multiplayer.get_peers():
		var av = get_parent().get_node_or_null("Player_%d" % pid)
		if av == null:
			continue
		var center: Vector3 = av.global_position
		var list: Array = []
		for z in zs:
			if not is_instance_valid(z) or z.is_queued_for_deletion():
				continue
			var dd: float = z.global_position.distance_squared_to(center)
			if dd < SEND_RADIUS * SEND_RADIUS:
				list.append([dd, z])
		list.sort_custom(func(a, b): return a[0] < b[0])
		var data := PackedFloat32Array()
		var n := mini(list.size(), MAX_SEND)
		for i in n:
			var zz = list[i][1]
			var flags := 0
			if zz.is_gray_runner:
				flags |= 1
			if zz.attack_time > 0.0:
				flags |= 2
			data.append(float(zz.net_id))
			data.append(zz.global_position.x)
			data.append(zz.global_position.y)
			data.append(zz.global_position.z)
			data.append(zz.rotation.y)
			data.append(zz.hp)
			data.append(float(flags))
		_rpc_snapshot.rpc_id(pid, data)

@rpc("authority", "unreliable_ordered")
func _rpc_snapshot(data: PackedFloat32Array) -> void:
	if multiplayer.is_server():
		return
	var seen := {}
	var count: int = data.size() / STRIDE
	for i in count:
		var o: int = i * STRIDE
		var id := int(data[o])
		var pos := Vector3(data[o + 1], data[o + 2], data[o + 3])
		var yaw := data[o + 4]
		var hp := data[o + 5]
		var flags := int(data[o + 6])
		seen[id] = true
		var z = puppets.get(id)
		if z == null or not is_instance_valid(z):
			z = _make_puppet(id, pos, (flags & 1) != 0)
			puppets[id] = z
		z.apply_snapshot(pos, yaw, hp, flags)
	for id2 in puppets.keys():
		if not seen.has(id2):
			var old = puppets[id2]
			if is_instance_valid(old):
				old.queue_free()
			puppets.erase(id2)

func _make_puppet(id: int, pos: Vector3, gray: bool) -> Node:
	var z = CharacterBody3D.new()
	z.set_script(load("res://zombie.gd"))
	z.is_puppet = true
	z.is_gray_runner = gray
	z.net_id = id
	z.name = "Zombie_%d" % id
	z.add_to_group("zombie")
	if gray:
		z.add_to_group("gray_zombie")
	z.position = pos
	get_parent().add_child(z)
	return z

# ---------- hits: client asks, server decides ----------
func send_hit(id: int, amount: float) -> void:
	if multiplayer.is_server():
		_do_hit(id, amount, multiplayer.get_unique_id())
	else:
		_rpc_hit.rpc_id(1, id, amount)

@rpc("any_peer", "reliable")
func _rpc_hit(id: int, amount: float) -> void:
	if multiplayer.is_server():
		_do_hit(id, amount, multiplayer.get_remote_sender_id())

func _do_hit(id: int, amount: float, sender: int) -> void:
	var shooter = get_parent().get_node_or_null("Player_%d" % sender)
	if shooter == null:
		return
	for z in get_tree().get_nodes_in_group("zombie"):
		if is_instance_valid(z) and z.net_id == id and not z.is_queued_for_deletion():
			if z.global_position.distance_to(shooter.global_position) <= 85.0:
				z.take_damage(clampf(amount, 0.0, 3.5))
			return
