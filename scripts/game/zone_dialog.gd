extends Control

## ゾーン内対戦ダイアログ（格闘ゲーム風VS画面）
## ゾーンで2名マッチした際に全画面黒背景でフェードイン表示

const HAND_ICONS := {
	"rock": "グー",
	"scissors": "チョキ",
	"paper": "パー",
}

const PlayerCharacter = preload("res://scripts/game/player_character.gd")

@onready var bg: ColorRect = %BG
@onready var my_avatar: TextureRect = %MyAvatar
@onready var my_name_label: Label = %MyNameLabel
@onready var opp_avatar: TextureRect = %OppAvatar
@onready var opp_name_label: Label = %OppNameLabel
@onready var opponent_info_label: Label = %OpponentInfoLabel
@onready var card_totals_label: Label = %CardTotalsLabel

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
var _fade_tween: Tween = null

func _ready() -> void:
	visible = false
	fight_panel.visible = false
	waiting_label.visible = false
	hand_rock_btn.pressed.connect(func() -> void: _select_hand("rock"))
	hand_scissors_btn.pressed.connect(func() -> void: _select_hand("scissors"))
	hand_paper_btn.pressed.connect(func() -> void: _select_hand("paper"))
	confirm_fight_btn.pressed.connect(_on_confirm_fight)

func _process(_delta: float) -> void:
	if not visible:
		return
	var totals: Dictionary = GameState.card_totals
	card_totals_label.text = "場: グー%d  チョキ%d  パー%d" % [
		totals.get("rock", 0),
		totals.get("scissors", 0),
		totals.get("paper", 0),
	]

func _fade_in() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	bg.modulate.a = 0.0
	_panel_vbox.modulate.a = 0.0
	visible = true
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(bg, "modulate:a", 1.0, 0.25)
	_fade_tween.tween_property(_panel_vbox, "modulate:a", 1.0, 0.3).set_delay(0.1)

func show_match(data: Dictionary) -> void:
	_kill_cancel_tween()
	_zone_id = data.get("zoneId", "")
	var opp: Dictionary = data.get("opponent", {})

	# 自分のアバターと名前
	my_avatar.texture = PlayerCharacter._get_avatar_texture(GameState.player_avatar_id)
	my_name_label.text = GameState.player_name

	# 相手のアバターと名前
	var opp_avatar_id: int = opp.get("avatarId", 0)
	opp_avatar.texture = PlayerCharacter._get_avatar_texture(opp_avatar_id)
	opp_name_label.text = opp.get("name", "???")

	# 相手情報
	opponent_info_label.text = "★ %d  金 %d  カード残: %d枚" % [
		opp.get("stars", 0),
		opp.get("gold", 0),
		opp.get("cardsLeft", 0),
	]

	# 即座に手選択パネルを表示
	fight_panel.visible = true
	waiting_label.visible = false
	_selected_hand = ""

	# カード枚数表示 + 0枚の手は選択不可
	var mc: Dictionary = GameState.my_cards
	hand_rock_btn.text = "グー\n×%d" % mc.get("rock", 0)
	hand_scissors_btn.text = "チョキ\n×%d" % mc.get("scissors", 0)
	hand_paper_btn.text = "パー\n×%d" % mc.get("paper", 0)
	hand_rock_btn.disabled = mc.get("rock", 0) <= 0
	hand_scissors_btn.disabled = mc.get("scissors", 0) <= 0
	hand_paper_btn.disabled = mc.get("paper", 0) <= 0
	hand_rock_btn.button_pressed = false
	hand_scissors_btn.button_pressed = false
	hand_paper_btn.button_pressed = false

	# 賭け金の最大値
	bet_spin.max_value = GameState.my_gold
	bet_spin.value = 0

	_fade_in()

func show_result(data: Dictionary) -> void:
	# 既存パネルを全て非表示
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
		detail_label.text = "★+1  金+%d" % bet
		detail_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		detail_label.text = "★-1  金-%d" % bet
		detail_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

	# --- アニメーション ---
	my_hand_label.modulate.a = 0.0
	opp_hand_label.modulate.a = 0.0

	await get_tree().process_frame
	var my_orig_x := my_hand_label.position.x
	var opp_orig_x := opp_hand_label.position.x
	my_hand_label.position.x = my_orig_x - 200.0
	opp_hand_label.position.x = opp_orig_x + 200.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(my_hand_label, "position:x", my_orig_x, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(my_hand_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(opp_hand_label, "position:x", opp_orig_x, 0.4) \
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

	visible = true

func _on_result_finished() -> void:
	_fade_out_and_hide(func() -> void:
		GameState.in_zone_match = false
		GameState.zone_opponent = {}
	)

func show_cancelled(reason: String) -> void:
	fight_panel.visible = false
	waiting_label.visible = false
	_clear_result_container()

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

	# 2秒後に自動クローズ（フェードアウト）
	_kill_cancel_tween()
	_cancel_tween = create_tween()
	_cancel_tween.tween_interval(2.0)
	_cancel_tween.tween_callback(func() -> void:
		_fade_out_and_hide(func() -> void:
			GameState.in_zone_match = false
			GameState.zone_opponent = {}
		)
	)

func _kill_cancel_tween() -> void:
	if _cancel_tween and _cancel_tween.is_valid():
		_cancel_tween.kill()
		_cancel_tween = null

func _clear_result_container() -> void:
	if _result_container and is_instance_valid(_result_container):
		_result_container.queue_free()
		_result_container = null

func _fade_out_and_hide(on_complete: Callable = Callable()) -> void:
	_kill_cancel_tween()
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(bg, "modulate:a", 0.0, 0.4)
	_fade_tween.tween_property(_panel_vbox, "modulate:a", 0.0, 0.3)
	_fade_tween.set_parallel(false)
	_fade_tween.tween_callback(func() -> void:
		visible = false
		fight_panel.visible = false
		waiting_label.visible = false
		_clear_result_container()
		_selected_hand = ""
		_fade_tween = null
		if on_complete.is_valid():
			on_complete.call()
	)

func hide_dialog() -> void:
	_kill_cancel_tween()
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
		_fade_tween = null
	visible = false
	fight_panel.visible = false
	waiting_label.visible = false
	_clear_result_container()
	_selected_hand = ""

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
	fight_panel.visible = false
	waiting_label.visible = true
	waiting_label.text = "相手の選択を待っています..."
