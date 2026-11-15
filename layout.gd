extends Node
func _ready(): _arrange.call_deferred()
func _fix(b): if b is Button: _put(b, get_viewport().get_visible_rect().size)
func _put(b, s): b.size = Vector2(170, 85); b.position = _spot(b.text, s)
func _spot(t, s): return {"Jump": Vector2(s.x - 182, s.y - 100), "Sprint": Vector2(s.x - 182, s.y - 200), "Shoot": Vector2(s.x - 182, s.y - 300), "Switch": Vector2(12, s.y - 200), "Use": Vector2(12, s.y - 100)}.get(t, Vector2(20, 20))
func _arrange(): for b in get_tree().current_scene.get_node("CanvasLayer").get_children(): _fix(b)
# end of file
