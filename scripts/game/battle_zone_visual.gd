extends Node2D

## 勝負ゾーンの視覚的表現（円形の光るエリア）

var radius := 60.0
var zone_id := ""
var _state := "empty"

func _process(_delta: float) -> void:
	for z: Dictionary in GameState.battle_zones:
		if z.get("id", "") == zone_id:
			_state = z.get("state", "empty")
			break
	queue_redraw()

func _draw() -> void:
	var color: Color
	match _state:
		"empty":
			color = Color(0.3, 0.6, 1.0, 0.15)
		"waiting":
			color = Color(1.0, 0.8, 0.2, 0.25)
		"matched":
			color = Color(1.0, 0.3, 0.3, 0.3)
		_:
			color = Color(0.5, 0.5, 0.5, 0.15)

	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, color * 1.8, 2.0)

	# ゾーンラベル
	var label_color := Color(1, 1, 1, 0.4)
	match _state:
		"empty":
			pass
		"waiting":
			label_color = Color(1, 0.9, 0.3, 0.6)
		"matched":
			label_color = Color(1, 0.4, 0.4, 0.6)
