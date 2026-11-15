extends Control

const UIStyleScript := preload("res://ui_style.gd")

const GAME_SCENE := "res://main.tscn"

var settings_panel: Panel = null
var name_edit: LineEdit = null
var volume_slider: HSlider = null
var gfx_label: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_main_buttons()
	_build_settings_panel()

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# subtle top accent
	var accent := ColorRect.new()
	accent.color = Color(0.55, 0.08, 0.06)
	accent.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	accent.offset_bottom = 6
	add_child(accent)

func _build_main_buttons() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position = Vector2(-170, -200)
	box.size = Vector2(340, 420)
	box.add_theme_constant_override("separation", 16)
	add_child(box)

	var title := Label.new()
	title.text = "LAST FOREST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	box.add_child(title)

	var credit := Label.new()
	credit.text = "ATILA GAMES"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.add_theme_font_size_override("font_size", 14)
	credit.add_theme_color_override("font_color", Color(0.45, 0.48, 0.52))
	box.add_child(credit)

	var sub := Label.new()
	sub.text = "Survive the woods"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65))
	box.add_child(sub)

	# Player name (used in online)
	var name_lbl := Label.new()
	name_lbl.text = "Your Name"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
	box.add_child(name_lbl)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Enter name..."
	name_edit.text = Network.display_name if Network.display_name != "Player" else ""
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(0, 42)
	name_edit.max_length = 16
	name_edit.text_changed.connect(_on_name_changed)
	box.add_child(name_edit)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(spacer)

	_add_menu_button(box, "Play Offline", _on_play_offline)
	_add_menu_button(box, "Play Online", _on_play_online)
	_add_menu_button(box, "Settings", _on_settings)
	_add_menu_button(box, "Quit", _on_quit)

func _add_menu_button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 56)
	b.pressed.connect(cb)
	var kind := "default"
	if text == "Quit":
		kind = "danger"
	elif text == "Play Offline" or text == "Play Online":
		kind = "build"
	elif text == "Settings":
		kind = "action"
	UIStyleScript.apply_button(b, kind)
	b.add_theme_font_size_override("font_size", 20)
	parent.add_child(b)

func _build_settings_panel() -> void:
	settings_panel = Panel.new()
	settings_panel.visible = false
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	settings_panel.position = Vector2(-200, -180)
	settings_panel.size = Vector2(400, 360)
	add_child(settings_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	settings_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var h := Label.new()
	h.text = "Settings"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 26)
	vbox.add_child(h)

	# Volume
	var vol_row := Label.new()
	vol_row.text = "Master Volume"
	vbox.add_child(vol_row)

	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = GameSettings.master_volume
	volume_slider.custom_minimum_size = Vector2(0, 28)
	volume_slider.value_changed.connect(_on_volume_changed)
	vbox.add_child(volume_slider)

	var vol_val := Label.new()
	vol_val.name = "VolValue"
	vol_val.text = "%d%%" % int(GameSettings.master_volume * 100)
	vol_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(vol_val)

	# Graphics
	var gfx_row := Label.new()
	gfx_row.text = "Graphics Quality"
	vbox.add_child(gfx_row)

	var gfx_btns := HBoxContainer.new()
	gfx_btns.add_theme_constant_override("separation", 12)
	vbox.add_child(gfx_btns)

	var med := Button.new()
	med.text = "Medium"
	med.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	med.pressed.connect(func(): _set_gfx("medium"))
	gfx_btns.add_child(med)

	var high := Button.new()
	high.text = "High"
	high.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	high.pressed.connect(func(): _set_gfx("high"))
	gfx_btns.add_child(high)

	gfx_label = Label.new()
	gfx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gfx_label.text = "Current: %s" % GameSettings.graphics_quality.capitalize()
	vbox.add_child(gfx_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_hide_settings)
	vbox.add_child(back)

func _on_volume_changed(v: float) -> void:
	GameSettings.set_volume(v)
	var lbl := settings_panel.find_child("VolValue", true, false) as Label
	if lbl:
		lbl.text = "%d%%" % int(v * 100)

func _set_gfx(q: String) -> void:
	GameSettings.set_graphics(q)
	if gfx_label:
		gfx_label.text = "Current: %s" % q.capitalize()

func _on_play_offline() -> void:
	_commit_name()
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_play_online() -> void:
	_commit_name()
	get_tree().change_scene_to_file("res://lobby.tscn")

func _on_settings() -> void:
	if settings_panel:
		settings_panel.visible = true
		if volume_slider:
			volume_slider.value = GameSettings.master_volume

func _hide_settings() -> void:
	if settings_panel:
		settings_panel.visible = false

func _on_quit() -> void:
	get_tree().quit()

func _on_name_changed(txt: String) -> void:
	Network.set_display_name(txt)

func _commit_name() -> void:
	if name_edit:
		Network.set_display_name(name_edit.text)

