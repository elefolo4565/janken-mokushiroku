extends HBoxContainer

## 画面下部の手札枚数表示バー

@onready var rock_label: Label = %RockLabel
@onready var scissors_label: Label = %ScissorsLabel
@onready var paper_label: Label = %PaperLabel

func _process(_delta: float) -> void:
	if not GameState.in_game:
		return
	var mc: Dictionary = GameState.my_cards
	rock_label.text = "✊\n×%d" % mc.get("rock", 0)
	scissors_label.text = "✌\n×%d" % mc.get("scissors", 0)
	paper_label.text = "✋\n×%d" % mc.get("paper", 0)
