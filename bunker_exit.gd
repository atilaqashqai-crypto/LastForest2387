extends Node3D

var bunker: Node3D = null

func interact(player: Node3D = null) -> void:
	if bunker != null and player != null and bunker.has_method("exit_bunker"):
		bunker.call("exit_bunker", player)
