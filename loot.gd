extends Node3D
const COUNT = {"food": 12, "water": 40, "medkits": 8, "pistol": 8, "shotgun": 5, "ak": 3, "ammo_pistol": 20, "ammo_shotgun": 12, "ammo_ak": 10}
var _rng := RandomNumberGenerator.new()
func _ready(): _rng.seed = Network.WORLD_SEED + 3; _all(); _near(); _request_state()
func _all(): for k in COUNT: _many(k, COUNT[k])
func _many(k, n): for i in n: _drop(k)
func _drop(k): var p = Vector2(_rng.randf_range(-270, 270), _rng.randf_range(-270, 270)); if p.length() > 6: _make(k, p)
func _near(): for k in ["food", "water", "medkits", "pistol", "ammo_pistol"]: _make(k, _ring())
func _ring(): var g = _rng.randf() * TAU; return Vector2(cos(g), sin(g)) * _rng.randf_range(8.0, 16.0)
func _make(k, p):
	var a = Area3D.new()
	add_child(a)
	a.position = Vector3(p.x, _h(p) + 0.6, p.y)
	_shape(a)
	_look(a, k)
	var key = "L%d" % _n
	_n += 1
	register(key, a)
	a.body_entered.connect(_got.bind(a, k, key))
func _h(p): return get_node("../Terrain").height(p.x, p.y)
func _shape(a): var c = CollisionShape3D.new(); var s = SphereShape3D.new(); s.radius = 1.6; c.shape = s; a.add_child(c)
func _got(body, a, k, key): try_pickup(body, a, k, key)
const COL = {"food": Color(0.9, 0.5, 0.1), "water": Color(0.2, 0.55, 0.95), "medkits": Color(0.95, 0.95, 0.95),
"pistol": Color(0.6, 0.6, 0.8), "shotgun": Color(0.8, 0.45, 0.15), "ak": Color(0.3, 0.7, 0.3),
"ammo_pistol": Color(0.95, 0.85, 0.2), "ammo_shotgun": Color(0.95, 0.3, 0.2), "ammo_ak": Color(0.5, 0.85, 0.3)}
const SIZE = {"food": Vector3(0.3, 0.35, 0.3), "water": Vector3(0.25, 0.5, 0.25), "medkits": Vector3(0.5, 0.35, 0.35),
"pistol": Vector3(0.15, 0.25, 0.5), "shotgun": Vector3(0.15, 0.15, 1.1), "ak": Vector3(0.15, 0.25, 1.0),
"ammo_pistol": Vector3(0.3, 0.2, 0.3), "ammo_shotgun": Vector3(0.3, 0.2, 0.3), "ammo_ak": Vector3(0.3, 0.2, 0.3)}
func _look(a,k):
	if k=="pistol": _pistol(a)
	elif k=="ak": _ak(a)
	elif k=="shotgun": _shotgun(a)
	elif k=="water": _water(a)
	elif k=="food": _food(a)
	elif k=="medkits": _medkit(a)
	else: _simple(a,k)
func _pistol(a): _blk(a,Vector3(0.16,0.18,0.42),Vector3(0,0,0),Color(0.12,0.12,0.14)); _blk(a,Vector3(0.14,0.3,0.16),Vector3(0,-0.2,0.08),Color(0.08,0.08,0.09)); _blk(a,Vector3(0.1,0.08,0.22),Vector3(0,0.1,-0.12),Color(0.3,0.3,0.32))
func _ak(a): _blk(a,Vector3(0.12,0.14,0.85),Vector3(0,0,0),Color(0.12,0.13,0.11)); _blk(a,Vector3(0.1,0.12,0.35),Vector3(0,-0.12,-0.25),Color(0.35,0.2,0.1)); _blk(a,Vector3(0.13,0.28,0.16),Vector3(0,-0.2,0.05),Color(0.35,0.2,0.1)); _blk(a,Vector3(0.06,0.07,0.45),Vector3(0,0.08,-0.58),Color(0.1,0.1,0.1))
func _shotgun(a): _blk(a,Vector3(0.12,0.14,1.0),Vector3(0,0,0),Color(0.12,0.12,0.13)); _blk(a,Vector3(0.1,0.12,0.35),Vector3(0,-0.12,0.25),Color(0.38,0.22,0.12)); _blk(a,Vector3(0.09,0.09,0.75),Vector3(0,0.02,-0.65),Color(0.2,0.2,0.21))
func _water(a): _part(a,Vector3(0.24,0.38,0.24),Vector3(0,0.2,0),Color(0.12,0.35,0.55)); _part(a,Vector3(0.13,0.09,0.13),Vector3(0,0.43,0),Color(0.08,0.08,0.07)); _part(a,Vector3(0.19,0.1,0.245),Vector3(0,0.19,-0.005),Color(0.8,0.85,0.78))
func _food(a): _cylinder(a,0.28,0.28,0.34,Vector3(0,0.17,0),Color(0.65,0.65,0.6)); _cylinder(a,0.29,0.29,0.035,Vector3(0,0.35,0),Color(0.35,0.35,0.32)); _part(a,Vector3(0.2,0.13,0.015),Vector3(0,0.18,-0.145),Color(0.65,0.12,0.08))
func _medkit(a): _part(a,Vector3(0.48,0.3,0.34),Vector3(0,0.16,0),Color(0.85,0.84,0.76)); _part(a,Vector3(0.12,0.24,0.035),Vector3(0,0.17,-0.19),Color(0.75,0.04,0.04)); _part(a,Vector3(0.26,0.09,0.04),Vector3(0,0.17,-0.2),Color(0.75,0.04,0.04))
func _simple(a,k): _blk(a,SIZE[k],Vector3.ZERO,COL[k])
func _part(a,s,p,c): var m=MeshInstance3D.new(); var b=BoxMesh.new(); b.size=s; m.mesh=b; m.position=p; m.material_override=_mat(c); a.add_child(m)
func _cylinder(a,t,b,h,p,c): var m=MeshInstance3D.new(); var mesh=CylinderMesh.new(); mesh.top_radius=t; mesh.bottom_radius=b; mesh.height=h; m.mesh=mesh; m.position=p; m.material_override=_mat(c); a.add_child(m)
func _blk(a,s,o,c): var m=MeshInstance3D.new(); var b=BoxMesh.new(); b.size=s; m.mesh=b; m.position=o; m.material_override=_mat(c); a.add_child(m)
func _mat(c): var m=StandardMaterial3D.new(); m.albedo_color=c; m.roughness=0.85; return m

# ---------------- pickup (server decides who gets an item) ----------------
var _n := 0
var areas := {}
var taken := {}

func register(key: String, area: Node) -> void:
	if taken.has(key):
		area.queue_free()
		return
	areas[key] = area

func try_pickup(body, area, kind, key) -> void:
	if not (body.is_in_group("player") or body.name == "Player"):
		return
	if not body.has_method("is_local") or not body.is_local():
		return
	var inv = body.get_node_or_null("Inventory")
	if inv == null or not is_instance_valid(area):
		return
	if not Network.is_online or multiplayer.multiplayer_peer == null:
		inv.add(kind)
		area.queue_free()
		return
	if area.has_meta("pending"):
		return
	area.set_meta("pending", true)
	area.set_meta("loot_kind", kind)
	areas[key] = area
	if multiplayer.is_server():
		_server_claim(key, multiplayer.get_unique_id())
	else:
		_rpc_claim.rpc_id(1, key)

@rpc("any_peer", "reliable")
func _rpc_claim(key: String) -> void:
	if multiplayer.is_server():
		_server_claim(key, multiplayer.get_remote_sender_id())

func _server_claim(key: String, who: int) -> void:
	if taken.has(key):
		# Somebody was faster: just remove it for the late one.
		if who == multiplayer.get_unique_id():
			_apply_taken(key, 0)
		else:
			_rpc_taken.rpc_id(who, key, 0)
		return
	taken[key] = true
	_rpc_taken.rpc(key, who)
	_apply_taken(key, who)

@rpc("authority", "reliable")
func _rpc_taken(key: String, who: int) -> void:
	_apply_taken(key, who)

func _apply_taken(key: String, who: int) -> void:
	taken[key] = true
	var a = areas.get(key)
	areas.erase(key)
	if a == null or not is_instance_valid(a):
		return
	if who != 0 and who == multiplayer.get_unique_id() and not Network.is_dedicated:
		var p = Network.get_local_player()
		var inv = p.get_node_or_null("Inventory") if p != null else null
		if inv != null and a.has_meta("loot_kind"):
			inv.add(a.get_meta("loot_kind"))
	a.queue_free()

func _request_state() -> void:
	if Network.is_client():
		_rpc_req_state.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_req_state() -> void:
	if multiplayer.is_server():
		_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), taken.keys())

@rpc("authority", "reliable")
func _rpc_state(keys: Array) -> void:
	for k in keys:
		_apply_taken(str(k), 0)
