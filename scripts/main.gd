extends Node

## メインシーン: シーン遷移管理
## NetworkManagerのメッセージを監視し、ゲーム状態に応じてシーンを切り替える

@onready var current_scene_container: Node = $CurrentScene

var _current_scene: Node = null

func _ready() -> void:
	NetworkManager.connected.connect(_on_connected)
	NetworkManager.disconnected.connect(_on_disconnected)
	NetworkManager.message_received.connect(_on_message_received)

	# タイトル画面を表示
	change_scene("res://scenes/lobby/title_screen.tscn")

func change_scene(scene_path: String) -> void:
	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null

	var scene := load(scene_path) as PackedScene
	if scene:
		_current_scene = scene.instantiate()
		current_scene_container.add_child(_current_scene)

func _on_connected() -> void:
	print("サーバーに接続しました")

func _on_disconnected() -> void:
	print("サーバーから切断されました")
	GameState.reset()
	change_scene("res://scenes/lobby/title_screen.tscn")

func _on_message_received(data: Dictionary) -> void:
	var msg_type: String = data.get("type", "")

	match msg_type:
		"connected":
			GameState.player_id = data.get("playerId", "")

		"room_created", "room_joined":
			GameState.current_room = data.get("room", {})
			GameState.is_host = (GameState.current_room.get("hostId", "") == GameState.player_id)
			change_scene("res://scenes/lobby/waiting_room.tscn")

		"player_joined", "player_left":
			GameState.current_room = data.get("room", {})
			GameState.is_host = (GameState.current_room.get("hostId", "") == GameState.player_id)

		"game_started":
			_handle_game_started(data)

		"state":
			_handle_state_update(data)

		"your_cards":
			GameState.my_cards = data.get("cards", {})

		"your_gold":
			GameState.my_gold = data.get("gold", 0)

		"janken_result", "zone_fight_result":
			pass # ゲーム画面側で処理

		"zone_match", "zone_cancelled":
			pass # ゲーム画面側で処理

		"player_eliminated":
			pass # ゲーム画面側で処理

		"player_cleared":
			pass # ゲーム画面側で処理

		"game_over":
			GameState.in_game = false
			GameState.game_results = data.get("results", [])
			change_scene("res://scenes/result/game_result.tscn")

		"error":
			print("サーバーエラー: ", data.get("message", ""))

func _handle_game_started(data: Dictionary) -> void:
	var settings: Dictionary = data.get("settings", {})
	GameState.in_game = true
	GameState.field_width = settings.get("fieldWidth", 800.0)
	GameState.field_height = settings.get("fieldHeight", 800.0)
	GameState.victory_stars = settings.get("victoryStars", 3)
	GameState.victory_gold = settings.get("victoryGold", 50)
	GameState.goal_gate = settings.get("goalGate", {"x": 400.0, "y": 50.0, "radius": 40.0})
	GameState.battle_zones = settings.get("battleZones", [])
	GameState.my_command = "none"
	GameState.my_gold = settings.get("initialGold", 0)

	change_scene("res://scenes/game/game_screen.tscn")

func _handle_state_update(data: Dictionary) -> void:
	GameState.time_left = data.get("timeLeft", 0)
	GameState.card_totals = data.get("cardTotals", {})
	GameState.players_data = data.get("players", [])

	# yourCardsがstateに含まれている場合
	if data.has("yourCards"):
		GameState.my_cards = data.get("yourCards", {})

	# yourGoldがstateに含まれている場合
	if data.has("yourGold"):
		GameState.my_gold = data.get("yourGold", 0)

	# ゾーン情報
	if data.has("zones"):
		GameState.battle_zones = data.get("zones", [])

	# 自分の星数を更新
	var my_data := GameState.get_my_player_data()
	if not my_data.is_empty():
		GameState.my_stars = my_data.get("stars", 0)
