extends Node2D

## 見下ろしフィールド: プレイヤーキャラの管理とカメラ制御
## 入力はVirtualJoystick（メインUI層）が処理し、GameState.input_vector経由で受け取る

const PlayerCharacterScene := preload("res://scenes/game/player_character.tscn")
const BattleZoneVisualScript := preload("res://scripts/game/battle_zone_visual.gd")

@onready var camera: Camera2D = $Camera2D
@onready var players_container: Node2D = $Players
@onready var zones_container: Node2D = $Zones
@onready var goal_gate_node: Node2D = $GoalGate
@onready var field_bg: ColorRect = $FieldBG

var _player_nodes: Dictionary = {} # playerId -> PlayerCharacter node

func _ready() -> void:
	# フィールド背景のサイズを設定
	field_bg.size = Vector2(GameState.field_width, GameState.field_height)
	field_bg.position = Vector2.ZERO

	# ゴールゲート配置
	var gate: Dictionary = GameState.goal_gate
	goal_gate_node.position = Vector2(gate.get("x", 400), gate.get("y", 50))

	# 勝負ゾーンを配置
	_init_zones()

func _process(_delta: float) -> void:
	if not GameState.in_game:
		return

	# プレイヤーの表示を更新
	_sync_players()

	# カメラを自分のキャラに常時中央追従
	_update_camera()

	# 入力をサーバーに送信（VirtualJoystickがGameState.input_vectorに書き込んだ値）
	NetworkManager.send_input(GameState.input_vector.x, GameState.input_vector.y)

func _sync_players() -> void:
	var current_ids: Array = []

	for p_data: Dictionary in GameState.players_data:
		var pid: String = p_data.get("id", "")
		current_ids.append(pid)

		if not _player_nodes.has(pid):
			# 新しいプレイヤーノードを作成
			var new_node: Node2D = PlayerCharacterScene.instantiate()
			new_node.setup(pid, p_data.get("name", "???"), pid == GameState.player_id)
			players_container.add_child(new_node)
			_player_nodes[pid] = new_node

		# 位置とデータを更新
		var node: Node2D = _player_nodes[pid]
		node.update_data(p_data)

	# 存在しなくなったプレイヤーを削除
	for pid: String in _player_nodes.keys():
		if pid not in current_ids:
			_player_nodes[pid].queue_free()
			_player_nodes.erase(pid)

func _init_zones() -> void:
	for zone_data: Dictionary in GameState.battle_zones:
		var visual := Node2D.new()
		visual.position = Vector2(zone_data.get("x", 0), zone_data.get("y", 0))
		var zone_node: Node2D = Node2D.new()
		zone_node.set_script(BattleZoneVisualScript)
		zone_node.radius = zone_data.get("radius", 60.0)
		zone_node.zone_id = zone_data.get("id", "")
		visual.add_child(zone_node)
		zones_container.add_child(visual)

func _update_camera() -> void:
	var my_node: Node2D = _player_nodes.get(GameState.player_id)
	if my_node:
		# カメラを常にプレイヤー中心に追従（クランプなし）
		camera.position = my_node.position
