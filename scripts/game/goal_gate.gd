extends Node2D

## ゴールゲート表示

@onready var gate_visual: ColorRect = $GateVisual
@onready var gate_label: Label = $GateLabel

func _ready() -> void:
	var radius: float = GameState.goal_gate.get("radius", 40.0)
	gate_visual.size = Vector2(radius * 2, radius * 2)
	gate_visual.position = Vector2(-radius, -radius)
	gate_visual.color = Color(1, 0.85, 0, 0.5) # 金色半透明

func _process(_delta: float) -> void:
	# ゴール可能かどうかで色を変える
	if GameState.can_goal():
		gate_visual.color = Color(0, 1, 0, 0.7) # 緑 = 入れる
		gate_label.text = "GOAL!"
	else:
		gate_visual.color = Color(1, 0.85, 0, 0.3) # 金色半透明 = まだ入れない
		gate_label.text = "GOAL"
