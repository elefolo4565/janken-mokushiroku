extends Control

## ルーム一覧/作成画面

@onready var room_name_input: LineEdit = %RoomNameInput
@onready var create_button: Button = %CreateButton
@onready var room_list_container: VBoxContainer = %RoomListContainer
@onready var refresh_button: Button = %RefreshButton
@onready var join_id_input: LineEdit = %JoinIdInput
@onready var join_button: Button = %JoinButton
@onready var back_button: Button = %BackButton

# ルーム設定
@onready var cards_spinbox: SpinBox = %CardsSpinBox
@onready var stars_spinbox: SpinBox = %StarsSpinBox
@onready var victory_spinbox: SpinBox = %VictorySpinBox
@onready var time_spinbox: SpinBox = %TimeSpinBox
@onready var initial_gold_spinbox: SpinBox = %InitialGoldSpinBox
@onready var victory_gold_spinbox: SpinBox = %VictoryGoldSpinBox
@onready var zone_count_spinbox: SpinBox = %ZoneCountSpinBox

var _refresh_timer := 0.0

func _ready() -> void:
	NetworkManager.message_received.connect(_on_message)
	create_button.pressed.connect(_on_create_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# ルーム一覧を取得
	NetworkManager.list_rooms()

func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 3.0:
		_refresh_timer = 0.0
		NetworkManager.list_rooms()

func _on_create_pressed() -> void:
	var room_name := room_name_input.text.strip_edges()
	if room_name.is_empty():
		room_name = GameState.player_name + "の部屋"

	var settings := {
		"cardsPerType": int(cards_spinbox.value),
		"initialStars": int(stars_spinbox.value),
		"victoryStars": int(victory_spinbox.value),
		"timeLimit": int(time_spinbox.value),
		"initialGold": int(initial_gold_spinbox.value),
		"victoryGold": int(victory_gold_spinbox.value),
		"battleZoneCount": int(zone_count_spinbox.value),
	}
	NetworkManager.create_room(room_name, settings)

func _on_refresh_pressed() -> void:
	NetworkManager.list_rooms()

func _on_join_pressed() -> void:
	var room_id := join_id_input.text.strip_edges()
	if not room_id.is_empty():
		NetworkManager.join_room(room_id)

func _on_back_pressed() -> void:
	var main_node := get_tree().root.get_node("Main")
	if main_node and main_node.has_method("change_scene"):
		main_node.change_scene("res://scenes/lobby/title_screen.tscn")

func _on_message(data: Dictionary) -> void:
	match data.get("type", ""):
		"room_list":
			_update_room_list(data.get("rooms", []))

func _update_room_list(rooms: Array) -> void:
	# 既存のリスト項目をクリア
	for child in room_list_container.get_children():
		child.queue_free()

	if rooms.is_empty():
		var label := Label.new()
		label.text = "ルームがありません"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		room_list_container.add_child(label)
		return

	for room_data: Dictionary in rooms:
		var hbox := HBoxContainer.new()
		hbox.custom_minimum_size.y = 60

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.text = room_data.get("name", "???")
		info_vbox.add_child(name_label)

		var detail_label := Label.new()
		var player_count: int = room_data.get("playerCount", 0)
		var state_text: String = "待機中" if room_data.get("state", "") == "waiting" else "プレイ中"
		detail_label.text = "%d/20人 | %s" % [player_count, state_text]
		detail_label.add_theme_font_size_override("font_size", 18)
		info_vbox.add_child(detail_label)

		hbox.add_child(info_vbox)

		if room_data.get("state", "") == "waiting":
			var join_btn := Button.new()
			join_btn.text = "参加"
			join_btn.custom_minimum_size = Vector2(120, 50)
			var room_id: String = room_data.get("id", "")
			join_btn.pressed.connect(func() -> void: NetworkManager.join_room(room_id))
			hbox.add_child(join_btn)

		var panel := PanelContainer.new()
		panel.add_child(hbox)
		room_list_container.add_child(panel)
