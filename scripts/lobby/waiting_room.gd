extends Control

## 待機ルーム画面
## ゲーム開始を待つ。ホストのみ開始ボタン・AI追加ボタンが表示される。

@onready var room_name_label: Label = %RoomNameLabel
@onready var room_id_label: Label = %RoomIdLabel
@onready var player_list_container: VBoxContainer = %PlayerListContainer
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton
@onready var settings_label: Label = %SettingsLabel
@onready var add_ai_button: Button = %AddAIButton
@onready var remove_ai_button: Button = %RemoveAIButton

func _ready() -> void:
	NetworkManager.message_received.connect(_on_message)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	add_ai_button.pressed.connect(_on_add_ai_pressed)
	remove_ai_button.pressed.connect(_on_remove_ai_pressed)

	_update_display()

func _on_start_pressed() -> void:
	NetworkManager.start_game()

func _on_leave_pressed() -> void:
	NetworkManager.leave_room()
	GameState.reset()
	var main_node := get_tree().root.get_node("Main")
	if main_node and main_node.has_method("change_scene"):
		main_node.change_scene("res://scenes/lobby/room_list.tscn")

func _on_add_ai_pressed() -> void:
	NetworkManager.add_ai()

func _on_remove_ai_pressed() -> void:
	NetworkManager.remove_ai()

func _on_message(data: Dictionary) -> void:
	match data.get("type", ""):
		"player_joined", "player_left":
			_update_display()

func _update_display() -> void:
	var room: Dictionary = GameState.current_room
	room_name_label.text = room.get("name", "???")
	room_id_label.text = "ID: " + room.get("id", "???")

	# 設定表示
	var settings: Dictionary = room.get("settings", {})
	var fw: int = settings.get("fieldWidth", 800)
	var zone_count: int = settings.get("battleZoneCount", 4)
	var field_name := _get_field_size_name(fw, zone_count)
	settings_label.text = "カード: 各%d枚 | 星: %d個 | 勝利: 星%d+金%d | 制限: %d秒 | %s" % [
		settings.get("cardsPerType", 4),
		settings.get("initialStars", 3),
		settings.get("victoryStars", 3),
		settings.get("victoryGold", 50),
		settings.get("timeLimit", 300),
		field_name,
	]

	# ホストのみ開始ボタンとAIボタンを表示
	start_button.visible = GameState.is_host
	add_ai_button.visible = GameState.is_host
	remove_ai_button.visible = GameState.is_host

	# プレイヤー一覧を更新
	for child in player_list_container.get_children():
		child.queue_free()

	var players: Array = room.get("players", [])
	var has_ai := false
	for p: Dictionary in players:
		var label := Label.new()
		var is_host_mark := " (ホスト)" if p.get("id", "") == room.get("hostId", "") else ""
		var is_me_mark := " ← あなた" if p.get("id", "") == GameState.player_id else ""
		var is_ai_mark := " [AI]" if p.get("isAI", false) else ""
		if p.get("isAI", false):
			has_ai = true
		label.text = p.get("name", "???") + is_ai_mark + is_host_mark + is_me_mark
		label.custom_minimum_size.y = 40
		player_list_container.add_child(label)

	# AIがいない場合は削除ボタンを非表示
	if not has_ai:
		remove_ai_button.visible = false

static func _get_field_size_name(fw: int, zones: int) -> String:
	if fw <= 600:
		return "小(ゾーン%d)" % zones
	elif fw <= 800:
		return "中(ゾーン%d)" % zones
	elif fw <= 1200:
		return "大(ゾーン%d)" % zones
	else:
		return "特大(ゾーン%d)" % zones
