extends Node3D
## Attractive fire: particle flames + embers + soft flickering yellow light.

@export var light_energy_base: float = 1.4
@export var light_range: float = 8.0
@export var flicker_amount: float = 0.3
@export var ember_count: int = 22
@export var flame_count: int = 14

var _light: OmniLight3D
var _time: float = 0.0
var _base_energy: float = 1.4

func _ready() -> void:
	_build_fire()
	_base_energy = light_energy_base

func _process(delta: float) -> void:
	_time += delta
	if _light == null:
		return
	var f1 = sin(_time * 7.3) * 0.5 + 0.5
	var f2 = sin(_time * 13.1 + 1.7) * 0.5 + 0.5
	var f3 = sin(_time * 4.2 + 0.4) * 0.5 + 0.5
	var flicker = f1 * 0.45 + f2 * 0.35 + f3 * 0.20
	_light.light_energy = _base_energy * (1.0 - flicker_amount * 0.5 + flicker * flicker_amount)
	var t = 0.55 + 0.45 * sin(_time * 2.8)
	_light.light_color = Color(1.0, 0.62 + 0.18 * t, 0.22 + 0.12 * t)

func _build_fire() -> void:
	# Glowing core
	var core = MeshInstance3D.new()
	var core_mesh = SphereMesh.new()
	core_mesh.radius = 0.15
	core_mesh.height = 0.26
	core.mesh = core_mesh
	core.position = Vector3(0, 0.14, 0)
	var core_mat = StandardMaterial3D.new()
	core_mat.albedo_color = Color(1.0, 0.55, 0.15)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.5, 0.1)
	core_mat.emission_energy_multiplier = 4.0
	core_mat.roughness = 1.0
	core.material_override = core_mat
	add_child(core)

	# Flames
	var flames = GPUParticles3D.new()
	flames.position = Vector3(0, 0.08, 0)
	flames.amount = flame_count
	flames.lifetime = 0.9
	flames.explosiveness = 0.04
	flames.randomness = 0.4
	flames.visibility_aabb = AABB(Vector3(-1.5, -0.3, -1.5), Vector3(3, 3, 3))
	flames.emitting = true

	var flame_mat = ParticleProcessMaterial.new()
	flame_mat.direction = Vector3(0, 1, 0)
	flame_mat.spread = 20.0
	flame_mat.initial_velocity_min = 0.5
	flame_mat.initial_velocity_max = 1.35
	flame_mat.gravity = Vector3(0, 0.2, 0)
	flame_mat.damping_min = 0.3
	flame_mat.damping_max = 1.0
	flame_mat.scale_min = 0.28
	flame_mat.scale_max = 0.7
	flame_mat.color = Color(1.0, 0.55, 0.12, 0.9)

	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.88, 0.4, 0.95),
		Color(1.0, 0.45, 0.08, 0.7),
		Color(0.5, 0.1, 0.0, 0.0)
	])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	flame_mat.color_ramp = ramp
	flames.process_material = flame_mat

	var flame_draw = QuadMesh.new()
	flame_draw.size = Vector2(0.24, 0.34)
	var flame_draw_mat = StandardMaterial3D.new()
	flame_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_draw_mat.vertex_color_use_as_albedo = true
	flame_draw_mat.albedo_color = Color(1, 1, 1, 0.9)
	flame_draw_mat.emission_enabled = true
	flame_draw_mat.emission = Color(1.0, 0.5, 0.1)
	flame_draw_mat.emission_energy_multiplier = 2.5
	flame_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_draw.material = flame_draw_mat
	flames.draw_pass_1 = flame_draw
	add_child(flames)

	# Embers
	var embers = GPUParticles3D.new()
	embers.position = Vector3(0, 0.2, 0)
	embers.amount = ember_count
	embers.lifetime = 1.5
	embers.randomness = 0.65
	embers.visibility_aabb = AABB(Vector3(-1.8, -0.4, -1.8), Vector3(3.6, 3.8, 3.6))
	embers.emitting = true

	var ember_mat = ParticleProcessMaterial.new()
	ember_mat.direction = Vector3(0, 1, 0)
	ember_mat.spread = 38.0
	ember_mat.initial_velocity_min = 0.35
	ember_mat.initial_velocity_max = 1.6
	ember_mat.gravity = Vector3(0, -0.3, 0)
	ember_mat.damping_min = 0.1
	ember_mat.damping_max = 0.55
	ember_mat.scale_min = 0.05
	ember_mat.scale_max = 0.13
	ember_mat.color = Color(1.0, 0.6, 0.15, 1.0)

	var egrad = Gradient.new()
	egrad.colors = PackedColorArray([
		Color(1.0, 0.9, 0.4, 1.0),
		Color(1.0, 0.35, 0.05, 0.75),
		Color(0.25, 0.04, 0.0, 0.0)
	])
	egrad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var eramp = GradientTexture1D.new()
	eramp.gradient = egrad
	ember_mat.color_ramp = eramp
	embers.process_material = ember_mat

	var ember_draw = SphereMesh.new()
	ember_draw.radius = 0.032
	ember_draw.height = 0.064
	var ember_draw_mat = StandardMaterial3D.new()
	ember_draw_mat.vertex_color_use_as_albedo = true
	ember_draw_mat.emission_enabled = true
	ember_draw_mat.emission = Color(1.0, 0.55, 0.1)
	ember_draw_mat.emission_energy_multiplier = 4.5
	ember_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_draw.material = ember_draw_mat
	embers.draw_pass_1 = ember_draw
	add_child(embers)

	# Main soft yellow light
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.48, 0.1)
	_light.light_color = Color(1.0, 0.72, 0.32)
	_light.light_energy = light_energy_base
	_light.omni_range = light_range
	_light.omni_attenuation = 1.3
	_light.shadow_enabled = false
	add_child(_light)

	# Soft fill light
	var fill = OmniLight3D.new()
	fill.position = Vector3(0, 0.8, 0.3)
	fill.light_color = Color(1.0, 0.78, 0.45)
	fill.light_energy = 0.3
	fill.omni_range = light_range * 1.3
	fill.omni_attenuation = 1.5
	fill.shadow_enabled = false
	add_child(fill)
