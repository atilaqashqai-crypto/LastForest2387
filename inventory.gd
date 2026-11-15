extends Node
const PACK = {"pistol": 10, "shotgun": 4, "ak": 30}
var food = 0
var water = 0
var medkits = 0
var guns = []
var ammo = {"pistol": 0, "shotgun": 0, "ak": 0}
var sel = 0
var label = null
func _ready(): label = Label.new(); var cl = CanvasLayer.new(); add_child(cl); cl.add_child(label); label.position = Vector2(30, 165); label.add_theme_font_size_override("font_size", 22)
func _process(_d): label.text = _head() + _stock_line() + _ammo_line()
func _head(): return "Item: " + current() + "\n"
func _stock_line(): return "Food " + str(food) + "  Water " + str(water) + "  Med " + str(medkits) + "  Wood " + str(1 if get_parent().get("carried_log") else 0) + "\n"
func _ammo_line(): return "Ammo  P " + str(ammo["pistol"]) + "  S " + str(ammo["shotgun"]) + "  AK " + str(ammo["ak"])
func add(k): _stock(k); _gun(k); _mag(k)
func _stock(k): if k in ["food", "water", "medkits"]: set(k, get(k) + 1)
func _gun(k): if k in ["pistol", "shotgun", "ak"] and not guns.has(k): guns.append(k)
func _mag(k): if k.begins_with("ammo_"): ammo[k.substr(5)] += PACK[k.substr(5)]
func slots(): var s = ["knife"] + guns; _has(s, "food", food); _has(s, "water", water); _has(s, "medkits", medkits); return s
func _has(s, k, n): if n > 0: s.append(k)
func current(): var s = slots(); sel = mini(sel, s.size() - 1); return s[sel]
func next(): sel = (sel + 1) % slots().size()
func _st(): return get_node("../Stats")
func use(): var c = current(); _eat(c); _drink(c); _heal(c)
func _eat(c): if c == "food" and _st().food < _st().max_food: food -= 1; _st().eat()
func _drink(c): if c == "water" and _st().water < _st().max_water: water -= 1; _st().drink()
func _hurt(): return _st().health < _st().max_health
func _heal(c): if c == "medkits" and _hurt(): medkits -= 1; _st().medkit()

func clear_all():
	food = 0
	water = 0
	medkits = 0
	guns.clear()
	ammo = {"pistol": 0, "shotgun": 0, "ak": 0}
	sel = 0
