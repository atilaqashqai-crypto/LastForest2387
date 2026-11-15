extends Node

const SAVE_PATH := "user://settings.cfg"

var master_volume: float = 0.8
var graphics_quality: String = "high"  # "medium" | "high"

func _ready() -> void:
	load_settings()
	apply_all()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	master_volume = float(cfg.get_value("audio", "master", 0.8))
	graphics_quality = str(cfg.get_value("graphics", "quality", "high"))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("graphics", "quality", graphics_quality)
	cfg.save(SAVE_PATH)

func apply_all() -> void:
	apply_volume()
	apply_graphics()

func apply_volume() -> void:
	var db := linear_to_db(clampf(master_volume, 0.0001, 1.0))
	if master_volume <= 0.001:
		db = -80.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

func apply_graphics() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if graphics_quality == "high":
		vp.scaling_3d_scale = 1.0
		ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 2)  # 2x
		ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)
	else:
		# medium
		vp.scaling_3d_scale = 0.75
		ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
		ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", 2048)

func set_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	apply_volume()
	save_settings()

func set_graphics(q: String) -> void:
	if q != "medium" and q != "high":
		return
	graphics_quality = q
	apply_graphics()
	save_settings()
