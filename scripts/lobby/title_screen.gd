extends Control

## タイトル画面
## 名前入力 → サーバー接続 → ルーム一覧画面へ

@onready var name_input: LineEdit = %NameInput
@onready var connect_button: Button = %ConnectButton
@onready var status_label: Label = %StatusLabel

func _ready() -> void:
	NetworkManager.connected.connect(_on_server_connected)
	NetworkManager.disconnected.connect(_on_server_disconnected)
	NetworkManager.message_received.connect(_on_message)
	connect_button.pressed.connect(_on_connect_pressed)

	# 既に接続済みの場合
	if NetworkManager.is_connected_to_server():
		status_label.text = "接続済み"
		connect_button.text = "ルーム一覧へ"

func _on_connect_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		status_label.text = "名前を入力してください"
		return

	GameState.player_name = player_name

	if NetworkManager.is_connected_to_server():
		# 既に接続済みなら名前を設定してルーム一覧へ
		NetworkManager.set_player_name(player_name)
	else:
		status_label.text = "接続中..."
		connect_button.disabled = true
		NetworkManager.connect_to_server()

func _on_server_connected() -> void:
	status_label.text = "接続成功！"
	NetworkManager.set_player_name(GameState.player_name)

func _on_server_disconnected() -> void:
	status_label.text = "接続が切断されました"
	connect_button.disabled = false

func _on_message(data: Dictionary) -> void:
	if data.get("type", "") == "name_set":
		# 名前設定完了 → ルーム一覧へ
		var main_node := get_tree().root.get_node("Main")
		if main_node and main_node.has_method("change_scene"):
			main_node.change_scene("res://scenes/lobby/room_list.tscn")
