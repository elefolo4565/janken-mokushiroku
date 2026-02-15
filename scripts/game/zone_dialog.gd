extends Control

## ゾーン内対戦ダイアログ
## ゾーンで2名マッチした際に表示される

@onready var opponent_name_label: Label = %OpponentNameLabel
@onready var opponent_info_label: Label = %OpponentInfoLabel
@onready var choice_panel: Control = %ChoicePanel
@onready var fight_button: Button = %FightButton
@onready var leave_button: Button = %LeaveButton

# 勝負選択パネル（fight_button押下後に表示）
@onready var fight_panel: Control = %FightPanel
@onready var hand_rock_btn: Button = %HandRockBtn
@onready var hand_scissors_btn: Button = %HandScissorsBtn
@onready var hand_paper_btn: Button = %HandPaperBtn
@onready var bet_spin: SpinBox = %BetSpin
@onready var confirm_fight_btn: Button = %ConfirmFightBtn

@onready var waiting_label: Label = %WaitingLabel

var _selected_hand := ""
var _zone_id := ""

func _ready() -> void:
	visible = false
	fight_panel.visible = false
	waiting_label.visible = false
	fight_button.pressed.connect(_on_fight)
	leave_button.pressed.connect(_on_leave)
	hand_rock_btn.pressed.connect(func() -> void: _select_hand("rock"))
	hand_scissors_btn.pressed.connect(func() -> void: _select_hand("scissors"))
	hand_paper_btn.pressed.connect(func() -> void: _select_hand("paper"))
	confirm_fight_btn.pressed.connect(_on_confirm_fight)

func show_match(data: Dictionary) -> void:
	_zone_id = data.get("zoneId", "")
	var opp: Dictionary = data.get("opponent", {})
	opponent_name_label.text = opp.get("name", "???")
	opponent_info_label.text = "⭐ %d  💰 %d  カード残: %d枚" % [
		opp.get("stars", 0),
		opp.get("gold", 0),
		opp.get("cardsLeft", 0),
	]

	# パネル状態をリセット
	choice_panel.visible = true
	fight_panel.visible = false
	waiting_label.visible = false
	fight_button.visible = true
	fight_button.disabled = false
	leave_button.disabled = false
	_selected_hand = ""

	# カードのない手は選択不可
	var mc: Dictionary = GameState.my_cards
	hand_rock_btn.disabled = mc.get("rock", 0) <= 0
	hand_scissors_btn.disabled = mc.get("scissors", 0) <= 0
	hand_paper_btn.disabled = mc.get("paper", 0) <= 0
	hand_rock_btn.button_pressed = false
	hand_scissors_btn.button_pressed = false
	hand_paper_btn.button_pressed = false

	# 賭け金の最大値
	bet_spin.max_value = GameState.my_gold
	bet_spin.value = 0

	visible = true

func hide_dialog() -> void:
	visible = false
	fight_panel.visible = false
	waiting_label.visible = false
	_selected_hand = ""

func _on_fight() -> void:
	fight_panel.visible = true
	fight_button.visible = false

func _on_leave() -> void:
	NetworkManager.send_zone_leave()
	hide_dialog()
	GameState.in_zone_match = false
	GameState.zone_opponent = {}

func _select_hand(hand: String) -> void:
	_selected_hand = hand
	hand_rock_btn.button_pressed = (hand == "rock")
	hand_scissors_btn.button_pressed = (hand == "scissors")
	hand_paper_btn.button_pressed = (hand == "paper")

func _on_confirm_fight() -> void:
	if _selected_hand == "":
		return
	NetworkManager.send_zone_fight(_selected_hand, int(bet_spin.value))
	# 「待機中...」表示に切り替え
	choice_panel.visible = false
	fight_panel.visible = false
	waiting_label.visible = true
	waiting_label.text = "相手の選択を待っています..."
