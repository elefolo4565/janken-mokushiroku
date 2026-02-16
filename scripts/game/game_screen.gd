extends Control

## メインゲーム画面
## 2分割: TopInfoBar / GameField + オーバーレイUI

const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_WHEEL_FACTOR := 1.1
const FREEZE_DURATION := 5.0

@onready var top_info_bar: Control = $VBox/TopInfoBar
@onready var game_field: SubViewportContainer = $VBox/GameFieldContainer
@onready var battle_log: Control = $BattleLog
@onready var zone_dialog: Control = $ZoneDialog
@onready var negotiate_btn: Button = $NegotiateButton

var _pinch_touches: Dictionary = {}
var _pinch_start_dist := 0.0
var _pinch_start_zoom := 1.0

func _ready() -> void:
	NetworkManager.message_received.connect(_on_message)
	negotiate_btn.toggled.connect(_on_negotiate_toggled)
	_show_start_overlay()

func _show_start_overlay() -> void:
	# 全画面暗幕（入力ブロック）
	var overlay := ColorRect.new()
	overlay.name = "StartOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# 中央配置用コンテナ
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	# タイトル
	var title := Label.new()
	title.text = "GAME START"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(title)

	# セパレータ
	var sep := HSeparator.new()
	sep.custom_minimum_size.x = 300
	vbox.add_child(sep)

	# 勝利条件
	var minutes := GameState.time_limit / 60
	var seconds := GameState.time_limit % 60
	var rules_text := ""
	rules_text += "[ 勝利条件 ]\n"
	rules_text += "★ %d 以上  &  金 %d 以上\n" % [GameState.victory_stars, GameState.victory_gold]
	rules_text += "カードを全て使い切りゴールゲートへ！\n"
	rules_text += "\n"
	rules_text += "手札: グー/チョキ/パー  各 %d 枚\n" % GameState.cards_per_type
	rules_text += "制限時間: %d:%02d" % [minutes, seconds]

	var rules := Label.new()
	rules.text = rules_text
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules.add_theme_font_size_override("font_size", 22)
	vbox.add_child(rules)

	# カウントダウン
	var countdown := Label.new()
	countdown.name = "Countdown"
	countdown.text = "5"
	countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown.add_theme_font_size_override("font_size", 60)
	countdown.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(countdown)

	# カウントダウンアニメーション
	var tw := create_tween()
	for i in range(4, 0, -1):
		tw.tween_interval(1.0)
		tw.tween_callback(func() -> void: countdown.text = str(i))
	tw.tween_interval(1.0)
	# フェードアウト
	tw.tween_property(overlay, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: overlay.queue_free())

func _input(event: InputEvent) -> void:
	# ピンチズーム（スマホ）
	if event is InputEventScreenTouch:
		if event.pressed:
			_pinch_touches[event.index] = event.position
		else:
			_pinch_touches.erase(event.index)
		# 2本指になった瞬間にピンチ開始
		if _pinch_touches.size() == 2:
			var pts: Array = _pinch_touches.values()
			_pinch_start_dist = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			_pinch_start_zoom = GameState.camera_zoom
			GameState.is_pinching = true
		elif _pinch_touches.size() < 2:
			GameState.is_pinching = false
		# 2本指以上のタッチイベントはジョイスティックに渡さない
		if _pinch_touches.size() >= 2:
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if _pinch_touches.has(event.index):
			_pinch_touches[event.index] = event.position
		if _pinch_touches.size() >= 2:
			var pts: Array = _pinch_touches.values()
			var dist := (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			if _pinch_start_dist > 10.0:
				var ratio := dist / _pinch_start_dist
				GameState.camera_zoom = clampf(_pinch_start_zoom * ratio, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# マウスホイールズーム（PC）
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			GameState.camera_zoom = clampf(GameState.camera_zoom * ZOOM_WHEEL_FACTOR, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			GameState.camera_zoom = clampf(GameState.camera_zoom / ZOOM_WHEEL_FACTOR, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()

func _on_message(data: Dictionary) -> void:
	match data.get("type", ""):
		"zone_fight_result":
			battle_log.show_janken_result(data)
			# 自分が関与した対戦のみ結果演出を表示
			var p1_id: String = data.get("player1", {}).get("id", "")
			var p2_id: String = data.get("player2", {}).get("id", "")
			if p1_id == GameState.player_id or p2_id == GameState.player_id:
				zone_dialog.show_result(data)
		"janken_result":
			battle_log.show_janken_result(data)
		"zone_match":
			_on_zone_match(data)
		"zone_cancelled":
			_on_zone_cancelled(data)
		"player_eliminated":
			_on_player_eliminated(data)
		"player_cleared":
			_on_player_cleared(data)

func _on_zone_match(data: Dictionary) -> void:
	GameState.in_zone_match = true
	GameState.zone_opponent = data.get("opponent", {})
	zone_dialog.show_match(data)

func _on_zone_cancelled(data: Dictionary = {}) -> void:
	var reason: String = data.get("reason", "")
	if reason == "self_left":
		# 自分が離脱した場合は即座に閉じる
		GameState.in_zone_match = false
		GameState.zone_opponent = {}
		zone_dialog.hide_dialog()
	else:
		# 相手側の事由によるキャンセルは理由を表示
		zone_dialog.show_cancelled(reason)

func _on_negotiate_toggled(pressed: bool) -> void:
	if pressed:
		NetworkManager.select_command("negotiate")
	else:
		NetworkManager.select_command("none")

func _on_player_eliminated(data: Dictionary) -> void:
	var pid: String = data.get("playerId", "")
	if pid == GameState.player_id:
		var reason: String = data.get("reason", "")
		var msg := ""
		if reason == "no_opponents":
			msg = "対戦相手がいません…敗北！"
		else:
			msg = "あなたは退場しました..."
		battle_log.show_elimination(msg)
		_show_elimination_overlay(msg)

func _show_elimination_overlay(msg: String) -> void:
	var overlay := ColorRect.new()
	overlay.name = "EliminationOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var label := Label.new()
	label.text = msg
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	vbox.add_child(label)

	var btn := Button.new()
	btn.text = "退場する"
	btn.custom_minimum_size = Vector2(200, 60)
	btn.pressed.connect(func() -> void:
		NetworkManager.leave_room()
		GameState.reset()
		var main_node := get_tree().root.get_node("Main")
		if main_node and main_node.has_method("change_scene"):
			main_node.change_scene("res://scenes/lobby/room_list.tscn")
	)
	vbox.add_child(btn)

	# フェードイン
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 0.85, 0.5)

func _on_player_cleared(data: Dictionary) -> void:
	var pid: String = data.get("playerId", "")
	if pid == GameState.player_id:
		battle_log.show_clear("ゴール！クリアおめでとう！")
