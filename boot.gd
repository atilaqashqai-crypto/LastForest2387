extends Control

const MENU_SCENE := "res://main_menu.tscn"
const INTRO_OGV := "res://studio_intro.ogv"
const INTRO_DURATION := 6.8

var _skipped := false
var _video: VideoStreamPlayer = null

func _ready() -> void:
	if Network.is_dedicated:
		Network.start_dedicated.call_deferred()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	if ResourceLoader.exists(INTRO_OGV):
		_play_video()
	else:
		_play_splash()

func _play_video() -> void:
	_video = VideoStreamPlayer.new()
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video)
	var stream = load(INTRO_OGV)
	if stream == null:
		_play_splash()
		return
	_video.stream = stream
	_video.finished.connect(_go_menu)
	_video.play()
	_add_skip_hint()
	# Safety timeout in case finished signal misses
	get_tree().create_timer(INTRO_DURATION + 1.0).timeout.connect(func():
		if not _skipped:
			_go_menu()
	)

func _play_splash() -> void:
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.position = Vector2(-220, -60)
	center.size = Vector2(440, 120)
	center.add_theme_constant_override("separation", 10)
	add_child(center)

	var studio := Label.new()
	studio.text = "ATILA GAMES"
	studio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	studio.add_theme_font_size_override("font_size", 42)
	studio.add_theme_color_override("font_color", Color(0.85, 0.88, 0.9))
	center.add_child(studio)

	var sub := Label.new()
	sub.text = "presents  ·  PROJECT: LAST FOREST"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))
	center.add_child(sub)

	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.7)
	tw.tween_interval(2.2)
	tw.tween_property(self, "modulate:a", 0.0, 0.7)
	tw.tween_callback(_go_menu)
	_add_skip_hint()

func _add_skip_hint() -> void:
	var hint := Label.new()
	hint.text = "Tap / click to skip"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -120
	hint.offset_right = 120
	hint.offset_top = -48
	hint.offset_bottom = -18
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62, 0.85))
	add_child(hint)

func _input(event: InputEvent) -> void:
	if _skipped:
		return
	if event is InputEventScreenTouch and event.pressed:
		_skip()
	elif event is InputEventMouseButton and event.pressed:
		_skip()
	elif event is InputEventKey and event.pressed:
		_skip()

func _skip() -> void:
	if _skipped:
		return
	_skipped = true
	if _video and _video.is_playing():
		_video.stop()
	_go_menu()

func _go_menu() -> void:
	if _skipped and not is_inside_tree():
		return
	_skipped = true
	if is_inside_tree():
		get_tree().change_scene_to_file(MENU_SCENE)
