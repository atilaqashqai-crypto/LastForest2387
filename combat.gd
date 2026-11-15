extends Node
const DMG = {"knife": 1.0, "pistol": 1.5, "shotgun": 3.0, "ak": 3.0}
const RATE = {"knife": 0.5, "pistol": 0.4, "shotgun": 1.0, "ak": 0.15}
const REACH = {"knife": 2.6, "pistol": 45.0, "shotgun": 20.0, "ak": 70.0}
const CAP = {"pistol": 10, "shotgun": 4, "ak": 30}
const KICK = {"knife": 1.2, "pistol": 0.4, "shotgun": 0.7, "ak": 0.2}
const LEN = {"knife": 0.4, "pistol": 0.42, "shotgun": 1.42, "ak": 1.38}
const COLS = {"knife": Color(0.8, 0.8, 0.85), "pistol": Color(0.15, 0.15, 0.18), "shotgun": Color(0.35, 0.22, 0.1), "ak": Color(0.18, 0.2, 0.15)}
const RELOAD = 1.3
var mag = {"pistol": 0, "shotgun": 0, "ak": 0}; var cd = 0.0; var shown = ""; var label = null; var xh = null; var sb = null
var tgt = null; var tb = 0.0; var ao = Vector3.ZERO; var ad = Vector3.ZERO; var flash = null
func _ready(): label = Label.new(); var cl = CanvasLayer.new(); add_child(cl); cl.add_child(label); _ui(cl)
func _ui(cl): label.position = Vector2(30, 255); label.add_theme_font_size_override("font_size", 22); _cross(cl)
func _process(d): cd = maxf(cd - d, 0.0); _sync(); _grab(); _fire_held(); _text(); _fade(d)
func _text(): label.text = "Mag " + str(mag.get(shown, "-")) + " / " + str(CAP.get(shown, "-"))
func fire(): var w = _inv().current(); if cd <= 0.0 and DMG.has(w): _use(w)
func _use(w): _stab(w); _gun(w)
func _stab(w): if w == "knife": cd = RATE[w]; _strike(w, _chest(), _fwd(), 0.6)
func _gun(w): if w != "knife": _empty(w); _bang(w)
func _empty(w): if mag[w] <= 0: _reload(w)
func _bang(w): if mag[w] > 0 and cd <= 0.0: mag[w] -= 1; cd = RATE[w]; _strike(w, _cam().global_position, -_cam().global_transform.basis.z, 0.09)
func _reload(w): var n = mini(CAP[w] - mag[w], _inv().ammo[w]); _inv().ammo[w] -= n; mag[w] += n; cd = RELOAD if n > 0 else 0.0
func _strike(w, o, dv, cone): _aim(o, dv, cone, REACH[w]); _hurt(w); _anim(w)
func _aim(o, dv, cone, rng): ao = o; ad = dv; tgt = null; tb = cone; _scan(rng)
func _scan(rng):
	for z in get_tree().get_nodes_in_group("zombie"): _cand(z, rng)
	_scan_players(rng)
func _scan_players(rng):
	# PvP: other players are valid targets too (the server decides if PvP is on).
	if not Network.is_online or not Network.pvp_enabled: return
	for p in get_tree().get_nodes_in_group("player"):
		if p == get_parent() or not is_instance_valid(p): continue
		if int(p.peer_id) == 0: continue
		_cand(p, rng)
func _cand(z, rng):
	var to = z.global_position + Vector3(0, 0.3, 0) - ao
	var a = to.normalized().distance_to(ad)
	if to.length() < rng and a < tb and _los_clear(z):
		tgt = z
		tb = a
func _los_clear(z):
	# Walls, floors and doors block hits. Other zombies do not.
	var space = get_viewport().find_world_3d().direct_space_state
	var from = get_parent().global_position + Vector3(0, 0.4, 0)
	var to = z.global_position + Vector3(0, 0.3, 0)
	var skip = [get_parent().get_rid(), z.get_rid()]
	for i in 4:
		var q = PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.collide_with_areas = false
		q.exclude = skip
		var hit = space.intersect_ray(q)
		if hit.is_empty():
			return true
		var col = hit.get("collider")
		if col is Node and col.is_in_group("zombie"):
			skip.append(col.get_rid())
		else:
			return false
	return true
func _hurt(w):
	if tgt == null: return
	if tgt.is_in_group("player"):
		Network.pvp_hit(int(tgt.peer_id), w)
	else:
		tgt.take_damage(DMG[w])
	xh.modulate = Color(1.0, 0.2, 0.2)
func _anim(w):
	_vis().kick = KICK[w]
	if w == "knife":
		_vis().play_knife_attack()
	_flash()
func _inv(): return get_node("../Inventory")
func _vis(): return get_node("../CharacterVisual")
func _cam(): return get_viewport().get_camera_3d()
func _sync(): var c = _inv().current(); if c != shown: _equip(c)
func _equip(c):
	shown = c
	_vis().raise = 1.45 if CAP.has(c) else 0.0
	_vis().two_hand = c in ["shotgun", "ak"]
	_vis().knife_equipped = c == "knife"
	_clear()
	_model(c)

func reset_on_death():
	mag = {"pistol": 0, "shotgun": 0, "ak": 0}
	cd = 0.0
	shown = ""
	if is_instance_valid(_vis()):
		_sync()
func _clear():
	flash = null
	for holder in [_vis().weapon_holder, _vis().knife_holder, _vis().pistol_holder]:
		if holder == null:
			continue
		for n in holder.get_children():
			n.queue_free()
func _model(c):
	if c == "knife":
		_knife_model()
		return
	if c == "pistol":
		_pistol_model()
		return
	if c == "shotgun":
		_shotgun_model()
		return
	if c == "ak":
		_ak_model()
		return

func _pistol_model():
	# Compact block-built sidearm, mounted directly to the right palm.
	_part(0.105, 0.105, 0.38, 0.0, 0.025, -0.18, Color(0.12, 0.13, 0.15)) # slide
	_part(0.085, 0.075, 0.30, 0.0, -0.035, -0.18, Color(0.25, 0.26, 0.28)) # frame
	_part(0.085, 0.22, 0.105, 0.0, -0.13, -0.015, Color(0.12, 0.12, 0.13)) # grip
	_part(0.095, 0.025, 0.16, 0.0, -0.235, -0.02, Color(0.20, 0.18, 0.16)) # grip base
	_part(0.035, 0.075, 0.035, 0.0, -0.065, -0.10, Color(0.07, 0.07, 0.08)) # trigger guard
	_part(0.035, 0.045, 0.045, 0.0, 0.095, -0.12, Color(0.32, 0.33, 0.34)) # rear sight
	_part(0.035, 0.035, 0.045, 0.0, 0.095, -0.34, Color(0.32, 0.33, 0.34)) # front sight
	flash = _part(0.075, 0.075, 0.06, 0.0, 0.025, -0.39, Color(1.0, 0.78, 0.22))
	flash.visible = false

func _shotgun_model():
	# Long pump-action silhouette: stock, receiver, wooden pump and barrel.
	_part(0.16, 0.17, 0.38, 0.0, -0.015, 0.16, Color(0.24, 0.14, 0.075)) # stock
	_part(0.19, 0.17, 0.42, 0.0, 0.0, -0.19, Color(0.12, 0.13, 0.14)) # receiver
	_part(0.085, 0.085, 0.88, 0.0, 0.035, -0.82, Color(0.09, 0.10, 0.11)) # barrel
	_part(0.13, 0.12, 0.48, 0.0, -0.07, -0.69, Color(0.34, 0.21, 0.11)) # wooden pump
	_part(0.10, 0.10, 0.26, 0.0, -0.14, 0.02, Color(0.13, 0.13, 0.14)) # pistol grip
	_part(0.12, 0.035, 0.30, 0.0, -0.12, -0.35, Color(0.08, 0.09, 0.10)) # magazine tube
	_part(0.12, 0.055, 0.12, 0.0, 0.105, -0.82, Color(0.18, 0.19, 0.20)) # front sight block
	_part(0.045, 0.07, 0.06, 0.0, 0.13, -0.20, Color(0.07, 0.08, 0.09)) # rear sight
	_part(0.13, 0.04, 0.13, 0.0, -0.11, -0.18, Color(0.06, 0.06, 0.07)) # trigger guard
	flash = _part(0.13, 0.13, 0.09, 0.0, 0.035, -1.28, Color(1.0, 0.78, 0.22))
	flash.visible = false

func _ak_model():
	# AK-inspired rifle with distinct wooden furniture, curved magazine and sights.
	_part(0.16, 0.18, 0.43, 0.0, 0.015, 0.20, Color(0.34, 0.20, 0.10)) # wooden stock
	_part(0.19, 0.19, 0.43, 0.0, 0.0, -0.20, Color(0.16, 0.18, 0.16)) # receiver
	_part(0.085, 0.085, 0.92, 0.0, 0.035, -0.88, Color(0.10, 0.11, 0.10)) # barrel
	_part(0.13, 0.12, 0.50, 0.0, -0.07, -0.72, Color(0.35, 0.22, 0.11)) # wooden handguard
	_part(0.13, 0.24, 0.22, 0.0, -0.22, -0.31, Color(0.13, 0.15, 0.13)) # magazine upper
	_part(0.12, 0.20, 0.18, 0.0, -0.40, -0.37, Color(0.12, 0.14, 0.12)) # curved magazine lower
	_part(0.11, 0.20, 0.10, 0.0, -0.15, 0.02, Color(0.28, 0.17, 0.09)) # pistol grip
	_part(0.055, 0.11, 0.10, 0.0, 0.14, -0.18, Color(0.07, 0.08, 0.07)) # rear sight
	_part(0.10, 0.08, 0.12, 0.0, 0.12, -1.18, Color(0.12, 0.13, 0.12)) # front sight
	_part(0.12, 0.06, 0.10, 0.0, 0.035, -1.34, Color(0.07, 0.08, 0.08)) # muzzle brake
	_part(0.14, 0.035, 0.16, 0.0, -0.12, -0.20, Color(0.06, 0.07, 0.06)) # trigger guard
	flash = _part(0.14, 0.14, 0.10, 0.0, 0.035, -1.40, Color(1.0, 0.78, 0.22))
	flash.visible = false
func _knife_model():
	# Handle sits inside the palm; the blade points forward from the fist.
	_part(0.075, 0.16, 0.075, 0.0, -0.015, 0.015, Color(0.22, 0.16, 0.1))
	_part(0.11, 0.035, 0.055, 0.0, 0.075, -0.015, Color(0.35, 0.3, 0.22))
	_part(0.055, 0.055, 0.27, 0.0, 0.085, -0.17, Color(0.78, 0.8, 0.83))
func _body_part(c): if LEN.has(c): _part(0.07, 0.09, LEN[c], 0, 0, -LEN[c] / 2, COLS[c])
func _grip(c):
	if CAP.has(c):
		_part(0.07, 0.2, 0.08, 0, -0.1, -0.05, COLS[c])
		if c in ["shotgun", "ak"]:
			# Forward grip/pump where the supporting hand meets the weapon.
			_part(0.1, 0.18, 0.14, -0.05, -0.1, -0.22, COLS[c])
		_tip(c)
func _tip(c): flash = _part(0.12, 0.12, 0.12, 0, 0, -LEN[c], Color(1.0, 0.9, 0.3)); flash.visible = false
func _flash(): if flash != null and is_instance_valid(flash): flash.visible = true; get_tree().create_timer(0.06).timeout.connect(_off)
func _off(): if flash != null and is_instance_valid(flash): flash.visible = false
func _part(sx, sy, sz, x, y, z, c):
	var m = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	m.mesh = b
	m.position = Vector3(x, y, z)
	m.material_override = _mat(c)
	var holder: Node3D
	if shown == "knife":
		holder = _vis().knife_holder
	elif shown == "pistol":
		holder = _vis().pistol_holder
	else:
		holder = _vis().weapon_holder
	holder.add_child(m)
	return m
func _mat(c): var m = StandardMaterial3D.new(); m.albedo_color = c; return m
func _cross(cl): xh = Control.new(); cl.add_child(xh); _bar(Vector2(18, 3), Vector2(-9, -1.5)); _bar(Vector2(3, 18), Vector2(-1.5, -9))
func _btn(): var l = get_tree().current_scene.get_node("CanvasLayer").get_children().filter(func(b): return b is Button and b.text == "Shoot"); return l[0] if l.size() > 0 else null
func _grab(): if sb == null: sb = _btn()
func _fire_held(): if sb != null and sb.button_pressed: fire()
func _chest(): return get_parent().global_position + Vector3(0, 0.4, 0)
func _fwd(): return -get_parent().global_transform.basis.z
func _bar(s, o): var r = ColorRect.new(); r.size = s; r.position = o; r.color = Color(1, 1, 1, 0.85); xh.add_child(r)
func _mid(): return get_viewport().get_visible_rect().size / 2
func _fade(d): xh.position = _mid(); xh.modulate = xh.modulate.lerp(Color.WHITE, d * 8.0)
# end of file
