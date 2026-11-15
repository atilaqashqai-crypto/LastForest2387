extends WorldEnvironment
func _ready(): var e = Environment.new(); _sky(e); _fog(e); _amb(e); environment = e
func _sky(e): e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.05, 0.07, 0.08)
func _fog(e): e.fog_enabled = true; e.fog_light_color = Color(0.08, 0.1, 0.11); e.fog_density = 0.03
func _amb(e): e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.5, 0.55, 0.65); e.ambient_light_energy = 1.6
# end of file
