extends Node
## Keeps cabins, fences and fires identical for every player.
## Clients ask the server; the server creates/updates and tells everybody.

const KINDS := ["cabin", "fence", "fire"]
const SCRIPTS := {
	"cabin": "res://buildable_cabin.gd",
	"fence": "res://buildable_fence.gd",
	"fire": "res://buildable_fire.gd",
}
const NAMES := {
	"cabin": "CabinConstructionSite",
	"fence": "FenceConstructionSite",
	"fire": "FireConstructionSite",
}

var sites: Dictionary = {}
var next_id := 1

func _ready() -> void:
	if Network.is_client():
		_rpc_req_state.rpc_id(1)

func _spawn_site(id: String, kind: String, pos: Vector3, yaw: float) -> Node:
	if sites.has(id) and is_instance_valid(sites[id]):
		return sites[id]
	var site = Node3D.new()
	site.name = "%s_%s" % [NAMES[kind], id]
	site.set_script(load(SCRIPTS[kind]))
	site.net_id = id
	site.set_meta("kind", kind)
	site.position = pos
	site.rotation.y = yaw
	get_parent().add_child(site)
	sites[id] = site
	return site

# ---------- place a blueprint ----------
func request_place(kind: String, pos: Vector3, yaw: float) -> void:
	if multiplayer.is_server():
		_server_place(kind, pos, yaw)
	else:
		_rpc_place_req.rpc_id(1, kind, pos, yaw)

@rpc("any_peer", "reliable")
func _rpc_place_req(kind: String, pos: Vector3, yaw: float) -> void:
	if multiplayer.is_server():
		_server_place(kind, pos, yaw)

func _server_place(kind: String, pos: Vector3, yaw: float) -> void:
	if not (kind in KINDS):
		return
	if absf(pos.x) > 320.0 or absf(pos.z) > 320.0:
		return
	var id := "B%d" % next_id
	next_id += 1
	_spawn_site(id, kind, pos, yaw)
	_rpc_place.rpc(id, kind, pos, yaw)

@rpc("authority", "reliable")
func _rpc_place(id: String, kind: String, pos: Vector3, yaw: float) -> void:
	_spawn_site(id, kind, pos, yaw)

# ---------- add a log ----------
func request_log(id: String) -> void:
	if multiplayer.is_server():
		_server_log(id)
	else:
		_rpc_log_req.rpc_id(1, id)

@rpc("any_peer", "reliable")
func _rpc_log_req(id: String) -> void:
	if multiplayer.is_server():
		_server_log(id)

func _server_log(id: String) -> void:
	var s = sites.get(id)
	if s == null or not is_instance_valid(s) or s.is_built:
		return
	var n: int = s.logs_added + 1
	s.net_set_logs(n)
	_rpc_logs.rpc(id, n)

@rpc("authority", "reliable")
func _rpc_logs(id: String, n: int) -> void:
	var s = sites.get(id)
	if s != null and is_instance_valid(s):
		s.net_set_logs(n)

# ---------- cabin door ----------
func request_door(id: String, open: bool) -> void:
	if multiplayer.is_server():
		_server_door(id, open)
	else:
		_rpc_door_req.rpc_id(1, id, open)

@rpc("any_peer", "reliable")
func _rpc_door_req(id: String, open: bool) -> void:
	if multiplayer.is_server():
		_server_door(id, open)

func _server_door(id: String, open: bool) -> void:
	var s = sites.get(id)
	if s == null or not is_instance_valid(s) or not s.is_built:
		return
	s.net_set_door(open)
	_rpc_door.rpc(id, open)

@rpc("authority", "reliable")
func _rpc_door(id: String, open: bool) -> void:
	var s = sites.get(id)
	if s != null and is_instance_valid(s):
		s.net_set_door(open)

# ---------- late joiners ----------
@rpc("any_peer", "reliable")
func _rpc_req_state() -> void:
	if not multiplayer.is_server():
		return
	var list: Array = []
	for id in sites.keys():
		var s = sites[id]
		if not is_instance_valid(s):
			continue
		var door: bool = bool(s.get("door_open")) if s.get("door_open") != null else false
		list.append([id, str(s.get_meta("kind")), s.position, s.rotation.y, s.logs_added, door])
	_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), list)

@rpc("authority", "reliable")
func _rpc_state(list: Array) -> void:
	for e in list:
		var s = _spawn_site(str(e[0]), str(e[1]), e[2], float(e[3]))
		s.net_set_logs(int(e[4]))
		if bool(e[5]):
			s.net_set_door(true)
