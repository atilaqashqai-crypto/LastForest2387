extends Node3D

const SK = Color(0.8, 0.62, 0.48)
const HR = Color(0.1, 0.07, 0.05)
var JK = Color(0.25, 0.3, 0.22)
const VS = Color(0.14, 0.14, 0.16)
var PT = Color(0.22, 0.22, 0.26)
const BT = Color(0.1, 0.08, 0.07)
var SC = Color(0.5, 0.12, 0.1)
const BR = Color(0.3, 0.22, 0.12)
var ph = 0.0
var al
var ar
var weapon_holder: Node3D
var knife_holder: Node3D
var pistol_holder: Node3D
var knife_attack_time: float = 0.0
var first_person_view: bool = false
var ll
var lr
var _built := false

func _ready():
	if not _built:
		_build()

func _build():
	_built = true
	_arms()
	_legs()
	_torso()
	_head()
	_pack()
	_setup_weapon_holder()

func set_first_person_view(enabled: bool) -> void:
	first_person_view = enabled
	# Hide the head/body to prevent clipping, while bringing arms and weapons
	# into the lower part of the first-person view.
	for child in get_children():
		if child == al or child == ar or child == weapon_holder:
			child.visible = true
		else:
			child.visible = not enabled
	if al != null:
		al.position.y = 1.80 if enabled else 0.6
	if ar != null:
		ar.position.y = 1.80 if enabled else 0.6
	if weapon_holder != null:
		weapon_holder.position = Vector3(0.0, 1.42, -0.52) if enabled else Vector3(0.0, 0.42, -0.35)
		weapon_holder.scale = Vector3.ONE * (1.18 if enabled else 1.0)

func set_outfit_color(c: Color) -> void:
	JK = c
	PT = c.darkened(0.25)
	SC = c.lightened(0.15)
	# rebuild meshes with new colors
	for child in get_children():
		child.queue_free()
	al = null
	ar = null
	ll = null
	lr = null
	weapon_holder = null
	knife_holder = null
	pistol_holder = null
	_built = false
	call_deferred("_build")

func _setup_weapon_holder():
	# Long guns stay centered between both hands.
	weapon_holder = Node3D.new()
	add_child(weapon_holder)
	weapon_holder.position = Vector3(0.0, 0.42, -0.35)

	# The knife is attached directly to the right hand, not to the torso.
	knife_holder = Node3D.new()
	ar.add_child(knife_holder)
	knife_holder.position = Vector3(0.0, -0.72, -0.025)

	# Keep the pistol rigidly attached to the right hand so it cannot float
	# beside the torso. Counter-rotate the hand pitch to keep the barrel level.
	pistol_holder = Node3D.new()
	ar.add_child(pistol_holder)
	pistol_holder.position = Vector3(0.0, -0.69, -0.015)
	pistol_holder.rotation.x = -1.45

func _arms():
	al = _arm(-0.49)
	ar = _arm(0.49)

func _arm(x):
	var p = _pivot(x, 0.6)
	_pp(p, 0.26, 0.6, 0.26, -0.3, 0.0, JK)
	_pp(p, 0.24, 0.2, 0.24, -0.7, 0.0, BT)
	return p

func _legs():
	ll = _leg(-0.2)
	lr = _leg(0.2)

func _leg(x):
	var p = _pivot(x, -0.2)
	_pp(p, 0.3, 0.55, 0.3, -0.275, 0.0, PT)
	_pp(p, 0.34, 0.25, 0.38, -0.675, -0.03, BT)
	return p

func _torso():
	_b(0.72, 0.8, 0.38, 0, 0.2, 0, JK)
	_b(0.74, 0.45, 0.4, 0, 0.3, 0, VS)
	_b(0.5, 0.14, 0.45, 0, 0.6, 0, SC)
	_belt()

func _belt():
	_b(0.74, 0.1, 0.4, 0, -0.15, 0, BT)
	_b(0.12, 0.1, 0.02, 0, -0.15, -0.21, Color(0.65, 0.55, 0.25))
	_pouch(-0.2)
	_pouch(0.2)

func _pouch(x):
	_b(0.15, 0.15, 0.08, x, 0.2, -0.24, Color(0.25, 0.25, 0.28))

func _head():
	_b(0.45, 0.45, 0.45, 0, 0.825, 0, SK)
	_hair()
	_eyes(-0.1)
	_eyes(0.1)
	_face()

func _hair():
	_b(0.49, 0.12, 0.49, 0, 1.03, 0, HR)
	_b(0.49, 0.35, 0.1, 0, 0.88, 0.2, HR)
	_b(0.49, 0.1, 0.1, 0, 0.97, -0.2, HR)
	_b(0.06, 0.25, 0.4, -0.235, 0.93, 0, HR)
	_b(0.06, 0.25, 0.4, 0.235, 0.93, 0, HR)

func _eyes(x):
	_b(0.1, 0.07, 0.03, x, 0.83, -0.23, Color.WHITE)
	_b(0.05, 0.07, 0.03, x, 0.83, -0.25, Color.BLACK)
	_b(0.11, 0.03, 0.03, x, 0.9, -0.23, HR)

func _face():
	_b(0.06, 0.08, 0.05, 0, 0.77, -0.25, Color(0.72, 0.56, 0.43))
	_b(0.14, 0.025, 0.02, 0, 0.7, -0.23, Color(0.4, 0.2, 0.18))
	_b(0.03, 0.12, 0.02, 0.14, 0.78, -0.23, Color(0.65, 0.4, 0.35))

func _pack():
	_b(0.5, 0.6, 0.25, 0, 0.25, 0.32, BR)
	_b(0.5, 0.15, 0.28, 0, 0.5, 0.33, Color(0.22, 0.16, 0.09))
	_b(0.6, 0.18, 0.18, 0, 0.72, 0.33, Color(0.15, 0.2, 0.18))

func _pivot(x, top):
	var p = Node3D.new()
	add_child(p)
	p.position = Vector3(x, top, 0)
	return p

func _b(sx, sy, sz, x, y, z, c):
	_put(self, Vector3(sx, sy, sz), Vector3(x, y, z), c)

func _pp(p, sx, sy, sz, y, z, c):
	_put(p, Vector3(sx, sy, sz), Vector3(0, y, z), c)

func _put(p, s, o, c):
	var m = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = s
	m.mesh = b
	m.position = o
	m.material_override = _mat(c)
	p.add_child(m)

func _mat(c):
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	return m

func _process(d):
	if al == null:
		return
	knife_attack_time = maxf(knife_attack_time - d, 0.0)
	var parent = get_parent()
	if parent == null or not ("velocity" in parent):
		return
	var v = parent.velocity
	var sp = Vector2(v.x, v.z).length()
	ph += d * sp * 1.6
	_swing(sin(ph) * 0.7 * clampf(sp / 5.0, 0.0, 1.0), d)

var raise = 0.0
var two_hand = false
var knife_equipped = true
var kick = 0.0

func play_knife_attack() -> void:
	knife_attack_time = 0.28

func _swing(a, d):
	kick = maxf(kick - d * 3.0, 0.0)
	if two_hand:
		# Shotgun and AK stance: both arms reach forward and inward to hold
		# the receiver and fore-end, with the left hand supporting the barrel.
		_rot(al, 1.18, d)
		_rot(ar, 1.08 + kick, d)
		_rot_z(al, 0.82, d)
		_rot_z(ar, -0.82, d)
		if weapon_holder:
			weapon_holder.position = weapon_holder.position.lerp(Vector3(0.0, 1.42 if first_person_view else 0.42, -0.52 if first_person_view else -0.35), 12.0 * d)
	elif knife_equipped:
		# The knife follows the right hand and performs a short forward stab.
		var attack_weight = 0.0
		if knife_attack_time > 0.0:
			attack_weight = sin((1.0 - knife_attack_time / 0.28) * PI)
		var idle_right = a
		var stab_pose = 1.45 * attack_weight
		_rot(al, -a * 0.35, d)
		_rot(ar, idle_right + stab_pose, d)
		_rot_z(al, 0.0, d)
		_rot_z(ar, -0.08 * attack_weight, d)
		if weapon_holder:
			weapon_holder.position = weapon_holder.position.lerp(Vector3(0.49, 0.72 if first_person_view else -0.12, -0.28), 12.0 * d)
	elif raise > 0.0:
		# One-handed pistol pose.
		_rot(al, 0.0, d)
		_rot(ar, 1.45 + kick, d)
		_rot_z(al, 0.0, d)
		_rot_z(ar, 0.0, d)
		if weapon_holder:
			weapon_holder.position = weapon_holder.position.lerp(Vector3(0.49, 0.72 if first_person_view else -0.12, -0.28), 12.0 * d)
	else:
		_rot(al, -a, d)
		_rot(ar, a, d)
		_rot_z(al, 0.0, d)
		_rot_z(ar, 0.0, d)
	_rot(ll, a, d)
	_rot(lr, -a, d)
	_level()

func _level():
	if weapon_holder:
		# The holder is now parented to the character root, so it no longer
		# needs to counter-rotate against the right arm.
		weapon_holder.rotation.x = kick * 0.5 if raise > 0.0 else 0.0

func _rot(n, t, d):
	if n:
		n.rotation.x = lerpf(n.rotation.x, t, 12.0 * d)

func _rot_z(n, t, d):
	if n:
		n.rotation.z = lerpf(n.rotation.z, t, 12.0 * d)
