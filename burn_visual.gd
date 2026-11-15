extends Node3D
## Attaches small flame particles to a character while burning.
## Call start(duration) / refresh from outside.

var _particles: GPUParticles3D
var _time_left: float = 0.0

func _ready() -> void:
	_build()
	visible = false
	set_process(false)

func start(duration: float = 2.5) -> void:
	_time_left = maxf(_time_left, duration)
	visible = true
	set_process(true)
	if _particles:
		_particles.emitting = true

func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		visible = false
		set_process(false)
		if _particles:
			_particles.emitting = false

func _build() -> void:
	_particles = GPUParticles3D.new()
	_particles.position = Vector3(0, 0.9, 0)
	_particles.amount = 12
	_particles.lifetime = 0.7
	_particles.explosiveness = 0.05
	_particles.randomness = 0.5
	_particles.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 2.5, 2))
	_particles.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 40.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 1.2
	mat.gravity = Vector3(0, 0.5, 0)
	mat.scale_min = 0.15
	mat.scale_max = 0.4
	mat.color = Color(1.0, 0.5, 0.1, 0.9)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.9, 0.3, 0.95),
		Color(1.0, 0.4, 0.05, 0.7),
		Color(0.4, 0.05, 0.0, 0.0)
	])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	_particles.process_material = mat

	var draw := QuadMesh.new()
	draw.size = Vector2(0.2, 0.28)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(1.0, 0.45, 0.08)
	draw_mat.emission_energy_multiplier = 2.2
	draw.material = draw_mat
	_particles.draw_pass_1 = draw
	add_child(_particles)
