extends Control

## ゾーン内対戦ダイアログ
## ゾーンで2名マッチした際に表示される

const HAND_ICONS := {
	"rock": "✊",
	"scissors": "✌",
	"paper": "✋",
}

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
@onready var _panel_vbox: VBoxContainer = %VBox

var _selected_hand := ""
var _zone_id := ""
var _result_container: VBoxContainer = null
var _cancel_tween: Tween = null

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
	_kill_cancel_tween()
	_zone_id = data.get("zoneId", "")
	var opp: Dictionary = data.get("opponent", {})
	opponent_name_label.text = opp.get("name", "???")
	opponent_info_label.text = "⭐ %d  💰 %d  カード残: %d枚" % [
		opp.get("stars", 0),
		opp.get("gold", 0),
		opp.get("cardsLeft", 0),
	]

	# パネル状態をリセット（即座に手選択へ）
	choice_panel.visible = false
	fight_panel.visible = true
	waiting_label.visible = false
	_selected_hand = ""

	# カード枚数表示 + 0枚の手は選択不可
	var mc: Dictionary = GameState.my_cards
	hand_rock_btn.text = "✊\nグー ×%d" % mc.get("rock", 0)
	hand_scissors_btn.text = "✌\nチョキ ×%d" % mc.get("scissors", 0)
	hand_paper_btn.text = "✋\nパー ×%d" % mc.get("paper", 0)
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

func show_result(data: Dictionary) -> void:
	# 既存パネルを全て非表示
	choice_panel.visible = false
	fight_panel.visible = false
	waiting_label.visible = false

	# 前回の結果コンテナがあれば削除
	_clear_result_container()

	# 自分がどちらのプレイヤーか判定
	var p1: Dictionary = data.get("player1", {})
	var p2: Dictionary = data.get("player2", {})
	var winner_id: Variant = data.get("winner")
	var bet: int = data.get("bet", 0)
	var is_p1: bool = (p1.get("id", "") == GameState.player_id)
	var my_hand_key: String = p1.get("hand", "") if is_p1 else p2.get("hand", "")
	var opp_hand_key: String = p2.get("hand", "") if is_p1 else p1.get("hand", "")
	var my_icon: String = HAND_ICONS.get(my_hand_key, "?")
	var opp_icon: String = HAND_ICONS.get(opp_hand_key, "?")

	# 結果コンテナ作成
	_result_container = VBoxContainer.new()
	_result_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_container.add_theme_constant_override("separation", 12)
	_panel_vbox.add_child(_result_container)

	# --- 手の表示 (左右からスライドイン) ---
	var hands_row := HBoxContainer.new()
	hands_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hands_row.add_theme_constant_override("separation", 20)
	_result_container.add_child(hands_row)

	var my_hand_label := Label.new()
	my_hand_label.text = my_icon
	my_hand_label.add_theme_font_size_override("font_size", 48)
	my_hand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	my_hand_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hands_row.add_child(my_hand_label)

	var vs_label := Label.new()
	vs_label.text = "VS"
	vs_label.add_theme_font_size_override("font_size", 24)
	vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs_label.modulate = Color(0.7, 0.7, 0.7)
	hands_row.add_child(vs_label)

	var opp_hand_label := Label.new()
	opp_hand_label.text = opp_icon
	opp_hand_label.add_theme_font_size_override("font_size", 48)
	opp_hand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opp_hand_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hands_row.add_child(opp_hand_label)

	# --- 勝敗テキスト ---
	var result_label := Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 40)
	_result_container.add_child(result_label)

	var i_won: bool = (winner_id == GameState.player_id)
	var is_draw: bool = data.get("result", "") == "draw"

	if is_draw:
		result_label.text = "DRAW"
		result_label.add_theme_color_override("font_color", Color.YELLOW)
	elif i_won:
		result_label.text = "WIN!"
		result_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		result_label.text = "LOSE..."
		result_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	# --- 星・ゴールド変動 ---
	var detail_label := Label.new()
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.add_theme_font_size_override("font_size", 22)
	_result_container.add_child(detail_label)

	if is_draw:
		detail_label.text = "カード消費のみ"
		detail_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	elif i_won:
		detail_label.text = "⭐+1  💰+%d" % bet
		detail_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		detail_label.text = "⭐-1  💰-%d" % bet
		detail_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

	# --- アニメーション ---
	# 手アイコン: 左右からスライドイン
	my_hand_label.position.x = -200.0
	my_hand_label.modulate.a = 0.0
	opp_hand_label.position.x = 200.0
	opp_hand_label.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(my_hand_label, "position:x", 0.0, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(my_hand_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(opp_hand_label, "position:x", 0.0, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(opp_hand_label, "modulate:a", 1.0, 0.3)

	# 勝敗テキスト: スケールアップで出現（0.5秒後）
	result_label.pivot_offset = result_label.size / 2
	result_label.scale = Vector2(0.0, 0.0)
	result_label.modulate.a = 0.0
	tween.tween_property(result_label, "scale", Vector2(1.0, 1.0), 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.5)
	tween.tween_property(result_label, "modulate:a", 1.0, 0.2).set_delay(0.5)

	# 変動テキスト: フェードイン（0.8秒後）
	detail_label.modulate.a = 0.0
	tween.tween_property(detail_label, "modulate:a", 1.0, 0.3).set_delay(0.8)

	# 3秒後に自動クローズ
	tween.set_parallel(false)
	tween.tween_interval(3.0)
	tween.tween_callback(_on_result_finished)

	# ダイアログ表示を保証
	visible = true

func _on_result_finished() -> void:
	hide_dialog()
	GameState.in_zone_match = false
	GameState.zone_opponent = {}

func show_cancelled(reason: String) -> void:
	# 既存パネルを全て非表示
	choice_panel.visible = false
	fight_panel.visible = false
	waiting_label.visible = false
	_clear_result_container()

	# キャンセル理由テキスト
	var reason_text := ""
	match reason:
		"timeout":
			reason_text = "タイムアウトしました"
		"opponent_left":
			reason_text = "相手がゾーンを離れました"
		"opponent_eliminated":
			reason_text = "相手が退場しました"
		_:
			reason_text = "対戦がキャンセルされました"

	waiting_label.text = reason_text
	waiting_label.visible = true
	visible = true

	# 2秒後に自動クローズ
	_kill_cancel_tween()
	_cancel_tween = create_tween()
	_cancel_tween.tween_interval(2.0)
	_cancel_tween.tween_callback(func() -> void:
		hide_dialog()
		GameState.in_zone_match = false
		GameState.zone_opponent = {}
	)

func _kill_cancel_tween() -> void:
	if _cancel_tween and _cancel_tween.is_valid():
		_cancel_tween.kill()
		_cancel_tween = null

func _clear_result_container() -> void:
	if _result_container and is_instance_valid(_result_container):
		_result_container.queue_free()
		_result_container = null

func hide_dialog() -> void:
	_kill_cancel_tween()
	visible = false
	fight_panel.visible = false
	waiting_label.visible = false
	_clear_result_container()
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
