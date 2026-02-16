extends PanelContainer

## 上部情報バー: カード総数、残り時間、自分の星・ゴールド

@onready var rock_label: Label = %RockTotalLabel
@onready var scissors_label: Label = %ScissorsTotalLabel
@onready var paper_label: Label = %PaperTotalLabel
@onready var time_label: Label = %TimeLabel
@onready var stars_label: Label = %StarsLabel
@onready var gold_label: Label = %GoldLabel

func _process(_delta: float) -> void:
	if not GameState.in_game:
		return

	# カード総数
	var totals: Dictionary = GameState.card_totals
	rock_label.text = "✊ %d" % totals.get("rock", 0)
	scissors_label.text = "✌ %d" % totals.get("scissors", 0)
	paper_label.text = "✋ %d" % totals.get("paper", 0)

	# 残り時間
	var t: int = GameState.time_left
	var minutes := t / 60
	var seconds := t % 60
	time_label.text = "%d:%02d" % [minutes, seconds]

	# 自分の星
	stars_label.text = "⭐×%d" % GameState.my_stars

	# 自分のゴールド
	gold_label.text = "💰 %d" % GameState.my_gold
