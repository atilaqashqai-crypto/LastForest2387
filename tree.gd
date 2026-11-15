extends StaticBody3D

const LOG_SCENE := preload("res://wood_log.tscn")
const CHOPS_TO_FELL := 4
var chops := 0
var progress_label: Label3D

func _ready() -> void:
	add_to_group("interactable")
	progress_label = Label3D.new()
	progress_label.position = Vector3(0.0, 2.8, 0.0)
	progress_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	progress_label.font_size = 42
	progress_label.pixel_size = 0.008
	progress_label.modulate = Color(1.0, 0.86, 0.55)
	progress_label.outline_size = 8
	progress_label.outline_modulate = Color(0.08, 0.05, 0.025)
	progress_label.visible = false
	add_child(progress_label)

func interact(player: Node) -> void:
	if player == null or player.get("current_vehicle") != null:
		return
	chops += 1
	progress_label.visible = true
	progress_label.text = "CUTTING %d/%d" % [chops, CHOPS_TO_FELL]
	if chops < CHOPS_TO_FELL:
		return
	_fell_tree()

func _fell_tree() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in 3:
		var log := LOG_SCENE.instantiate()
		parent.add_child(log)
		var angle := float(i) * TAU / 3.0 + randf_range(-0.25, 0.25)
		log.global_position = global_position + Vector3(cos(angle) * 1.2, 0.75, sin(angle) * 1.2)
		log.rotation.y = randf() * TAU
		log.linear_velocity = Vector3(cos(angle) * randf_range(1.0, 2.0), 1.8, sin(angle) * randf_range(1.0, 2.0))
	queue_free()
