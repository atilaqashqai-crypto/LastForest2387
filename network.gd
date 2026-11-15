extends Node

const MAX_PLAYERS := 8
const PORT := 7777
## Same seed on server and every client => same trees, rocks and loot.
const WORLD_SEED := 20261115
## Put your VPS IP here BEFORE exporting the Android app, so players don't have to type it.
## (They can still change it in the lobby.)
const DEFAULT_SERVER_IP := "127.0.0.1"
const SERVER_CFG := "user://server.cfg"
const GAME_SCENE := "res://main.tscn"
const LOBBY_SCENE := "res://lobby.tscn"

## peer_id -> { name: String, color: Array [r,g,b] }
var players: Dictionary = {}
var local_color: Color = Color.WHITE
var display_name: String = "Player"
var is_online: bool = false
var external_ip: String = ""
var local_ip: String = ""
var upnp_status: String = ""
var is_dedicated: bool = false
var game_started: bool = false
var server_ip: String = DEFAULT_SERVER_IP

# ---------- PvP ----------
## Players can hurt each other. Server option:  --no-pvp  turns it off.
var pvp_enabled: bool = true
## PvP damage = weapon damage * this (player health is 5, zombies only have 2).
const PVP_DAMAGE_MULT := 0.5
const PVP_SPAWN_PROTECT_SEC := 3.0
const PVP_DMG := {"knife": 1.0, "pistol": 1.5, "shotgun": 3.0, "ak": 3.0}
const PVP_RATE := {"knife": 0.5, "pistol": 0.4, "shotgun": 1.0, "ak": 0.15}
const PVP_REACH := {"knife": 2.6, "pistol": 45.0, "shotgun": 20.0, "ak": 70.0}
var spawn_protect_until: int = 0
var last_attacker: int = 0
var last_attacker_msec: int = 0
var _last_shot: Dictionary = {}      # server: "shooter:weapon" -> msec
var _feed_box: VBoxContainer = null
var _flash_rect: ColorRect = null

signal players_changed
signal connection_failed(msg: String)
signal server_disconnected

func _ready() -> void:
	is_dedicated = _detect_dedicated()
	if "--no-pvp" in (OS.get_cmdline_args() + OS.get_cmdline_user_args()):
		pvp_enabled = false
	_load_server_ip()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	_register_local()
	call_deferred("_detect_ips")
	call_deferred("_try_upnp")
	return OK

func join_game(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	return OK

func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_online = false
	game_started = false
	external_ip = ""
	upnp_status = ""
	players_changed.emit()

func _register_local() -> void:
	var id := multiplayer.get_unique_id()
	local_color = _color_for_id(id)
	var n := display_name.strip_edges()
	if n.is_empty():
		n = "Player %d" % id
	players[id] = {
		"name": n,
		"color": [local_color.r, local_color.g, local_color.b]
	}
	players_changed.emit()

func set_display_name(n: String) -> void:
	display_name = n.strip_edges()
	if display_name.is_empty():
		display_name = "Player"

func color_from_info(info: Dictionary) -> Color:
	var c = info.get("color", [0.8, 0.8, 0.8])
	if c is Color:
		return c
	if c is Array and c.size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return Color(0.8, 0.8, 0.8)

func _color_for_id(id: int) -> Color:
	var palette := [
		Color(0.75, 0.2, 0.18),
		Color(0.2, 0.45, 0.85),
		Color(0.2, 0.7, 0.35),
		Color(0.85, 0.65, 0.15),
		Color(0.7, 0.3, 0.75),
	]
	return palette[abs(id) % palette.size()]

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_rpc_send_roster.rpc_id(id, players)
		_rpc_pvp_flag.rpc_id(id, pvp_enabled)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	players_changed.emit()
	var node := get_tree().get_first_node_in_group("player_%d" % id)
	if node:
		node.queue_free()

func _on_connected_ok() -> void:
	_register_local()
	_rpc_announce.rpc_id(1, players[multiplayer.get_unique_id()])

func _on_connection_failed() -> void:
	disconnect_game()
	connection_failed.emit("Connection failed")

func _on_server_disconnected() -> void:
	disconnect_game()
	server_disconnected.emit()
	get_tree().change_scene_to_file(LOBBY_SCENE)

@rpc("any_peer", "reliable")
func _rpc_announce(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	players[id] = info
	players_changed.emit()
	if multiplayer.is_server():
		for peer in multiplayer.get_peers():
			if peer != id:
				_rpc_player_joined.rpc_id(peer, id, info)
		# Match already running: send the newcomer straight into the game.
		if game_started and id != 1:
			_rpc_start_game.rpc_id(id)

@rpc("authority", "reliable")
func _rpc_player_joined(id: int, info: Dictionary) -> void:
	players[id] = info
	players_changed.emit()

@rpc("authority", "reliable")
func _rpc_send_roster(roster: Dictionary) -> void:
	for k in roster:
		players[int(k)] = roster[k]
	players_changed.emit()

func start_game() -> void:
	if not multiplayer.is_server():
		return
	_rpc_start_game.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_start_game() -> void:
	_begin_game()

func _begin_game() -> void:
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == GAME_SCENE:
		return
	game_started = true
	get_tree().change_scene_to_file(GAME_SCENE)

# ---------- dedicated server (VPS, no screen) ----------
func _detect_dedicated() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	return "--server" in args

func start_dedicated() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("Server start failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	is_online = true
	print("LastForest dedicated server running on UDP port %d (max %d players)" % [PORT, MAX_PLAYERS])
	_begin_game()

# ---------- saved server ip ----------
func _load_server_ip() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SERVER_CFG) == OK:
		server_ip = str(cfg.get_value("server", "ip", DEFAULT_SERVER_IP))

func save_server_ip(ip: String) -> void:
	server_ip = ip.strip_edges()
	var cfg := ConfigFile.new()
	cfg.set_value("server", "ip", server_ip)
	cfg.save(SERVER_CFG)

func _detect_ips() -> void:
	local_ip = ""
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			local_ip = addr
			break
	if local_ip.is_empty():
		for addr in IP.get_local_addresses():
			if ":" not in addr and addr != "127.0.0.1":
				local_ip = addr
				break

func _try_upnp() -> void:
	upnp_status = "Trying UPnP..."
	external_ip = ""
	var upnp := UPNP.new()
	var disc := upnp.discover(1500)
	if disc != UPNP.UPNP_RESULT_SUCCESS:
		upnp_status = "UPnP unavailable. Forward UDP %d or use LAN IP." % PORT
		return
	var map_err := upnp.add_port_mapping(PORT, PORT, "LastForest", "UDP")
	external_ip = str(upnp.query_external_address())
	if map_err == UPNP.UPNP_RESULT_SUCCESS and not external_ip.is_empty():
		upnp_status = "Internet ready — friends join: %s" % external_ip
	elif not external_ip.is_empty():
		upnp_status = "Public IP %s (port map may have failed)" % external_ip
	else:
		upnp_status = "UPnP failed — try LAN IP or port-forward UDP %d" % PORT

func get_join_hint() -> String:
	var lines: PackedStringArray = []
	if not external_ip.is_empty():
		lines.append("Internet IP: %s" % external_ip)
	if not local_ip.is_empty():
		lines.append("LAN IP: %s" % local_ip)
	if not upnp_status.is_empty():
		lines.append(upnp_status)
	lines.append("Port: %d (UDP)" % PORT)
	return "\n".join(lines)

func player_count() -> int:
	return players.size()

# ---------- helpers used by zombies / loot / voice ----------
func is_client() -> bool:
	return is_online and multiplayer.multiplayer_peer != null and not multiplayer.is_server()

func get_local_player() -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p.has_method("is_local") and p.is_local():
			return p
	return null

## Server tells one player's own game that something hurt them.
## attacker = peer id of the player who shot them (0 = zombie / hunger / etc.)
func hurt_peer(pid: int, amount: float, attacker: int = 0) -> void:
	if pid == multiplayer.get_unique_id():
		_apply_hurt(amount, attacker)
	else:
		_rpc_hurt.rpc_id(pid, amount, attacker)

@rpc("authority", "reliable")
func _rpc_hurt(amount: float, attacker: int) -> void:
	_apply_hurt(amount, attacker)

func _apply_hurt(amount: float, attacker: int = 0) -> void:
	var p := get_local_player()
	if p == null:
		return
	if attacker != 0:
		# Freshly respawned players cannot be shot for a few seconds.
		if Time.get_ticks_msec() < spawn_protect_until:
			return
		last_attacker = attacker
		last_attacker_msec = Time.get_ticks_msec()
		_flash_hit()
	var st = p.get_node_or_null("Stats")
	if st != null:
		st.hurt(amount)

# ---------- PvP: shooter's client asks, server checks and applies ----------
@rpc("authority", "reliable")
func _rpc_pvp_flag(on: bool) -> void:
	pvp_enabled = on

## Called by combat.gd when the local player's shot hits another player.
func pvp_hit(target_id: int, weapon: String) -> void:
	if multiplayer.multiplayer_peer == null or not pvp_enabled:
		return
	if multiplayer.is_server():
		_server_pvp(multiplayer.get_unique_id(), target_id, weapon)
	else:
		_rpc_pvp_hit.rpc_id(1, target_id, weapon)

@rpc("any_peer", "reliable")
func _rpc_pvp_hit(target_id: int, weapon: String) -> void:
	if multiplayer.is_server():
		_server_pvp(multiplayer.get_remote_sender_id(), target_id, weapon)

func _server_pvp(shooter_id: int, target_id: int, weapon: String) -> void:
	if not pvp_enabled or shooter_id == target_id:
		return
	if not PVP_DMG.has(weapon):
		return
	var s_av = get_tree().get_first_node_in_group("player_%d" % shooter_id)
	var t_av = get_tree().get_first_node_in_group("player_%d" % target_id)
	if s_av == null or t_av == null:
		return
	# Anti-cheat: must be roughly in range (a little slack for lag) and not faster than the weapon allows.
	if s_av.global_position.distance_to(t_av.global_position) > float(PVP_REACH[weapon]) + 8.0:
		return
	var key := "%d:%s" % [shooter_id, weapon]
	var now := Time.get_ticks_msec()
	if now - int(_last_shot.get(key, -100000)) < int(float(PVP_RATE[weapon]) * 600.0):
		return
	_last_shot[key] = now
	hurt_peer(target_id, float(PVP_DMG[weapon]) * PVP_DAMAGE_MULT, shooter_id)

# ---------- death / kill feed ----------
## The local player just died (called from stats.gd).
func local_died() -> void:
	spawn_protect_until = Time.get_ticks_msec() + int(PVP_SPAWN_PROTECT_SEC * 1000.0)
	var killer := 0
	if last_attacker != 0 and Time.get_ticks_msec() - last_attacker_msec < 8000:
		killer = last_attacker
	last_attacker = 0
	if not is_online or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_server_announce_death(multiplayer.get_unique_id(), killer)
	else:
		_rpc_report_death.rpc_id(1, killer)

@rpc("any_peer", "reliable")
func _rpc_report_death(killer: int) -> void:
	if multiplayer.is_server():
		_server_announce_death(multiplayer.get_remote_sender_id(), killer)

func _server_announce_death(victim: int, killer: int) -> void:
	var vn := str(players.get(victim, {}).get("name", "Player"))
	var text := "%s died" % vn
	if killer != 0 and players.has(killer):
		text = "%s killed %s" % [str(players[killer].get("name", "Player")), vn]
	_rpc_feed.rpc(text)

@rpc("authority", "call_local", "reliable")
func _rpc_feed(text: String) -> void:
	if is_dedicated:
		print(text)
		return
	_show_feed(text)

func _overlay_layer() -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = 60
	add_child(cl)
	return cl

func _show_feed(text: String) -> void:
	if _feed_box == null or not is_instance_valid(_feed_box):
		var cl := _overlay_layer()
		_feed_box = VBoxContainer.new()
		_feed_box.position = Vector2(30, 300)
		_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(_feed_box)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_box.add_child(l)
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free()
	)

func _flash_hit() -> void:
	if is_dedicated:
		return
	if _flash_rect == null or not is_instance_valid(_flash_rect):
		var cl := _overlay_layer()
		_flash_rect = ColorRect.new()
		_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(_flash_rect)
	_flash_rect.color = Color(0.8, 0.0, 0.0, 0.28)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.35)
