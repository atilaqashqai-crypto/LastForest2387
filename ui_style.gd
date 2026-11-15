extends RefCounted
class_name UIStyle
## Shared dark survival-style button / panel look for Last Forest.

static func make_button_style(bg: Color, border: Color, hover_bg: Color = Color()) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(14)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	return s

static func apply_button(b: Button, kind: String = "default") -> void:
	if b == null:
		return
	var bg: Color
	var border: Color
	var hover: Color
	var pressed: Color
	match kind:
		"shoot":
			bg = Color(0.28, 0.08, 0.08, 0.82)
			border = Color(0.85, 0.25, 0.22, 0.9)
			hover = Color(0.40, 0.12, 0.12, 0.9)
			pressed = Color(0.18, 0.05, 0.05, 0.9)
		"sprint":
			bg = Color(0.08, 0.22, 0.12, 0.82)
			border = Color(0.25, 0.75, 0.40, 0.9)
			hover = Color(0.12, 0.32, 0.18, 0.9)
			pressed = Color(0.05, 0.15, 0.08, 0.9)
		"build":
			bg = Color(0.28, 0.18, 0.06, 0.85)
			border = Color(0.95, 0.65, 0.20, 0.95)
			hover = Color(0.38, 0.25, 0.10, 0.92)
			pressed = Color(0.18, 0.12, 0.04, 0.9)
		"action":
			bg = Color(0.10, 0.14, 0.18, 0.85)
			border = Color(0.40, 0.55, 0.70, 0.9)
			hover = Color(0.16, 0.22, 0.28, 0.92)
			pressed = Color(0.06, 0.09, 0.12, 0.9)
		"danger":
			bg = Color(0.25, 0.08, 0.08, 0.88)
			border = Color(0.9, 0.3, 0.25, 0.95)
			hover = Color(0.35, 0.12, 0.12, 0.92)
			pressed = Color(0.15, 0.05, 0.05, 0.9)
		_:
			bg = Color(0.10, 0.12, 0.14, 0.82)
			border = Color(0.45, 0.55, 0.50, 0.85)
			hover = Color(0.16, 0.20, 0.22, 0.9)
			pressed = Color(0.06, 0.08, 0.09, 0.9)

	var normal := make_button_style(bg, border)
	var hov := make_button_style(hover, border.lightened(0.15))
	var pre := make_button_style(pressed, border.darkened(0.2))
	var dis := make_button_style(Color(bg.r, bg.g, bg.b, 0.4), Color(border.r, border.g, border.b, 0.35))

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", pre)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", Color(0.95, 0.96, 0.94))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.88, 0.85))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.55))
	b.add_theme_font_size_override("font_size", 18)

static func apply_panel(p: Panel) -> void:
	if p == null:
		return
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.09, 0.92)
	s.border_color = Color(0.35, 0.45, 0.38, 0.8)
	s.set_border_width_all(2)
	s.set_corner_radius_all(16)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	p.add_theme_stylebox_override("panel", s)
