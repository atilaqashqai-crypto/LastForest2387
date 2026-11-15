extends Node

const DECAY_SECONDS = 60.0
const STARVE_SECONDS = 5.0
const STARVE_DAMAGE = 1.0
const RESPAWN_POS = Vector3(0, 3, 0)

var max_health = 5.0
var max_food = 4.0
var max_water = 4.0
var health = 5.0
var food = 4.0
var water = 4.0
var t1 = 0.0
var t2 = 0.0

func _process(d):
	var par = get_parent()
	if par != null and par.has_method("is_local") and not par.is_local():
		return
	_decay(d)
	_starve(d)

func _decay(d):
	t1 += d
	if t1 >= DECAY_SECONDS:
		t1 = 0.0
		food = maxf(food - 1.0, 0.0)
		water = maxf(water - 1.0, 0.0)

func _starve(d):
	# Even a tiny amount left in either meter prevents starvation damage.
	if food > 0.0 or water > 0.0:
		t2 = 0.0
		return
	# Damage timer runs only while BOTH meters are exactly empty.
	_hungry(d)

func _hungry(d):
	t2 += d
	while t2 >= STARVE_SECONDS:
		t2 -= STARVE_SECONDS
		hurt(STARVE_DAMAGE)
		# Death/respawn restores food and water and resets the timer.
		if food > 0.0 or water > 0.0:
			t2 = 0.0
			break

func hurt(a):
	health = maxf(health - a, 0.0)
	_check()

func heal(a):
	health = minf(health + a, max_health)

func eat():
	food = minf(food + 1.0, max_food)

func drink():
	water = minf(water + 1.0, max_water)

func medkit():
	health = max_health

func _check():
	if health <= 0.0:
		_respawn_player()

func _respawn_player() -> void:
	var player = get_parent()
	if player == null:
		return
	Network.local_died()
	# Preserve the camera mode active at the moment of death.
	var respawn_first_person: bool = bool(player.get("is_first_person")) if "is_first_person" in player else false
	# Leave vehicle if inside — do NOT touch/move/destroy vehicles
	if "current_vehicle" in player and player.current_vehicle != null:
		if player.current_vehicle.has_method("exit_player"):
			player.current_vehicle.call("exit_player", player)
	# Remove every item collected before death. The player respawns empty-handed.
	var inventory = player.get_node_or_null("Inventory")
	if inventory != null and inventory.has_method("clear_all"):
		inventory.call("clear_all")
	var combat = player.get_node_or_null("Combat")
	if combat != null and combat.has_method("reset_on_death"):
		combat.call("reset_on_death")
	# Reset vitals only after clearing carried items.
	health = max_health
	food = max_food
	water = max_water
	t1 = 0.0
	t2 = 0.0
	# Move only the player back to spawn
	if player is Node3D:
		# Ensure player is under the main scene (not stuck under a seat)
		var scene = get_tree().current_scene
		if player.get_parent() != scene and scene != null:
			player.reparent(scene, true)
		player.global_position = RESPAWN_POS
		player.rotation = Vector3.ZERO
		if "velocity" in player:
			player.velocity = Vector3.ZERO
		if "move_input" in player:
			player.move_input = Vector2.ZERO
		if "sprinting" in player:
			player.sprinting = false
		player.set_physics_process(true)
		var col = player.get_node_or_null("CollisionShape3D")
		if col:
			col.disabled = false
		if player.has_method("set_camera_mode"):
			player.call("set_camera_mode", respawn_first_person)
		else:
			var arm = player.get_node_or_null("CameraPivot/SpringArm3D")
			if arm:
				arm.spring_length = 0.05 if respawn_first_person else 4.0
