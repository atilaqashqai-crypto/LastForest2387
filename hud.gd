extends CanvasLayer

var bars = {}
var stats = null

func _ready():
	_bar("health", "HP", Color(0.8, 0.15, 0.15), 40)
	_bar("food", "FOOD", Color(0.85, 0.6, 0.15), 80)
	_bar("water", "WATER", Color(0.2, 0.5, 0.9), 120)
	# Cache stats reference once (survives player reparenting into vehicle)
	var p = get_node_or_null("../Player")
	if p:
		stats = p.get_node_or_null("Stats")

func _bar(k, n, c, y):
	var b = ProgressBar.new()
	add_child(b)
	b.position = Vector2(30, y)
	b.size = Vector2(300, 28)
	b.show_percentage = false
	b.add_theme_stylebox_override("fill", _sb(c))
	bars[k] = b
	_lbl(b, n)

func _sb(c):
	var s = StyleBoxFlat.new()
	s.bg_color = c
	return s

func _lbl(b, n):
	var l = Label.new()
	l.text = n
	l.position = Vector2(8, 0)
	b.add_child(l)

func _process(_d):
	if stats == null or not is_instance_valid(stats):
		# try to find again if lost
		# Online there are several players: always show OUR stats, not someone else's.
		var p = Network.get_local_player() if get_tree() else null
		if p == null:
			var main = get_parent()
			if main:
				p = main.get_node_or_null("Player")
		if p:
			stats = p.get_node_or_null("Stats")
		if stats == null:
			return
	_update("health", stats.health, stats.max_health)
	_update("food", stats.food, stats.max_food)
	_update("water", stats.water, stats.max_water)

func _update(k, v, m):
	bars[k].max_value = m
	bars[k].value = v
