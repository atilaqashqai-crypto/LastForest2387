extends Node3D

var door_open: bool = false
var _door_tween: Tween = null

func _ready() -> void:
	add_to_group("interactable")

func interact(_player: Node = null) -> void:
	door_open = not door_open
	if _door_tween != null and _door_tween.is_running():
		_door_tween.kill()
	_door_tween = create_tween()
	var target_angle: float = -1.45 if door_open else 0.0
	_door_tween.tween_property(self, "rotation:y", target_angle, 0.35)
