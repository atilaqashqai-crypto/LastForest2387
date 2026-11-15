extends Node3D
## Simple 3D health bar that always faces the camera.
## Call set_health(current, maximum) to update.

var _bg: MeshInstance3D
var _fg: MeshInstance3D
var _max_hp: float = 1.0
var _cur_hp: float = 1.0
var bar_width: float = 0.9
var bar_height: float = 0.08

func _ready() -> void:
	_build()
	visible = false  # hide until first damage or explicit show

func _build() -> void:
	# Background
	_bg = MeshInstance3D.new()
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(bar_width, bar_height, 0.02)
	_bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.08, 0.06, 0.06, 0.85)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	_bg.material_override = bg_mat
	add_child(_bg)

	# Foreground (scales on X)
	_fg = MeshInstance3D.new()
	var fg_mesh := BoxMesh.new()
	fg_mesh.size = Vector3(bar_width, bar_height * 0.7, 0.025)
	_fg.mesh = fg_mesh
	var fg_mat := StandardMaterial3D.new()
	fg_mat.albedo_color = Color(0.85, 0.15, 0.12, 0.95)
	fg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fg_mat.no_depth_test = true
	fg_mat.emission_enabled = true
	fg_mat.emission = Color(0.7, 0.1, 0.08)
	fg_mat.emission_energy_multiplier = 0.6
	_fg.material_override = fg_mat
	_fg.position.z = 0.01
	add_child(_fg)

func set_health(current: float, maximum: float) -> void:
	_max_hp = maxf(maximum, 0.001)
	_cur_hp = clampf(current, 0.0, _max_hp)
	var ratio := _cur_hp / _max_hp
	visible = _cur_hp > 0.0 and _cur_hp < _max_hp  # show only when damaged but alive
	# Always show if you prefer: visible = _cur_hp > 0.0
	if _fg:
		_fg.scale.x = maxf(ratio, 0.02)
		# shift so it shrinks from the right (left-aligned)
		_fg.position.x = -bar_width * 0.5 * (1.0 - ratio)
		# color from green-ish to red as HP drops
		var mat := _fg.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.9 - ratio * 0.3, 0.12 + ratio * 0.45, 0.1, 0.95)

func show_full() -> void:
	# Force visible even at full HP (optional)
	visible = true
	set_health(_cur_hp, _max_hp)
	visible = true
