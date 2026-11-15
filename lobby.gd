extends Control

var status_label: Label
var ip_edit: LineEdit
var list_label: Label
var start_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	Network.players_changed.connect(_refresh_list)
	Network.connection_failed.connect(_on_fail)
	Network.server_disconnected.connect(_on_disconnected)
	_refresh_list()

func _on_disconnected() -> void:
	status_label.text = "Disconnected from server"

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position = Vector2(-200, -240)
	box.size = Vector2(400, 500)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title = Label.new()
	title.text = "ONLINE LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var sub = Label.new()
	sub.text = "Max %d players" % Network.MAX_PLAYERS
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65))
	box.add_child(sub)

	status_label = Label.new()
	status_label.text = "Not connected"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.custom_minimum_size = Vector2(0, 80)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.4))
	box.add_child(status_label)

	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Host IP"
	ip_edit.text = Network.server_ip
	ip_edit.custom_minimum_size = Vector2(0, 40)
	box.add_child(ip_edit)

	var host_btn = Button.new()
	host_btn.text = "Host Game"
	host_btn.custom_minimum_size = Vector2(0, 52)
	host_btn.pressed.connect(_on_host)
	box.add_child(host_btn)

	var join_btn = Button.new()
	join_btn.text = "Join Server"
	join_btn.custom_minimum_size = Vector2(0, 52)
	join_btn.pressed.connect(_on_join)
	box.add_child(join_btn)

	start_btn = Button.new()
	start_btn.text = "Start Match"
	start_btn.custom_minimum_size = Vector2(0, 52)
	start_btn.disabled = true
	start_btn.pressed.connect(_on_start)
	box.add_child(start_btn)

	list_label = Label.new()
	list_label.text = "Players: -"
	list_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(list_label)

	var back = Button.new()
	back.text = "Back to Menu"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_on_back)
	box.add_child(back)

func _on_host() -> void:
	if Network.display_name.strip_edges().is_empty():
		Network.set_display_name("Player")
	var err = Network.host_game()
	if err != OK:
		status_label.text = "Host failed: %s" % error_string(err)
		return
	start_btn.disabled = false
	status_label.text = "Hosting... detecting IP"
	_refresh_list()
	# delay hint after UPnP deferred
	get_tree().create_timer(1.8).timeout.connect(_show_join_hint)

func _show_join_hint() -> void:
	if status_label and Network.is_online:
		status_label.text = Network.get_join_hint()

func _on_join() -> void:
	var ip = ip_edit.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Enter host IP"
		return
	Network.save_server_ip(ip)
	status_label.text = "Connecting to %s..." % ip
	var err = Network.join_game(ip)
	if err != OK:
		status_label.text = "Join failed: %s" % error_string(err)

func _on_start() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		status_label.text = "Only host can start"
		return
	Network.start_game()

func _on_back() -> void:
	Network.disconnect_game()
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_fail(msg: String) -> void:
	status_label.text = msg

func _refresh_list() -> void:
	var lines = PackedStringArray()
	for id in Network.players:
		var info = Network.players[id]
		var you = " (you)" if int(id) == multiplayer.get_unique_id() else ""
		lines.append("- %s%s" % [info.get("name", str(id)), you])
	list_label.text = "Players (%d/%d):\n%s" % [
		Network.player_count(), Network.MAX_PLAYERS,
		"\n".join(lines) if lines.size() > 0 else "-"
	]
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		start_btn.disabled = false
