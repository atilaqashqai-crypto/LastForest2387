extends RigidBody3D

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 4
	collision_mask = 1
	mass = 18.0
	linear_damp = 1.4
	angular_damp = 2.0
	contact_monitor = true
	max_contacts_reported = 4

func interact(player: Node) -> void:
	if player == null or player.get("current_vehicle") != null:
		return
	if bool(player.get("carried_log")):
		return
	if player.has_method("set_carried_log"):
		player.call("set_carried_log", true)
		queue_free()
