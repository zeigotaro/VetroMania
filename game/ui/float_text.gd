class_name FloatText
extends Label
## Damage numbers and pickup text that drift up and fade out.

var _age := 0
var _life := 40
var _rise := 0.5


static func spawn(parent: Node, at: Vector2, text: String, color: Color = Color.WHITE, scale: int = 1, life: int = 40) -> FloatText:
	var node := FloatText.new()
	node.text = text
	node._life = life
	UIKit.style(node, color, scale)
	node.z_index = 100
	node.position = at - Vector2(UIKit.text_width(text, scale) / 2.0, 0)
	parent.add_child(node)
	return node


func _physics_process(_delta: float) -> void:
	_age += 1
	position.y -= _rise
	_rise = maxf(0.1, _rise * 0.97)
	modulate.a = clampf(1.0 - float(_age - _life * 0.5) / (_life * 0.5), 0.0, 1.0) if _age > _life * 0.5 else 1.0
	if _age >= _life:
		queue_free()
