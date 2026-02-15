extends Control

## メインゲーム画面
## 2分割: TopInfoBar / GameField + オーバーレイUI

@onready var top_info_bar: Control = $VBox/TopInfoBar
@onready var game_field: SubViewportContainer = $VBox/GameFieldContainer
@onready var battle_log: Control = $BattleLog
@onready var zone_dialog: Control = $ZoneDialog
@onready var negotiate_btn: Button = $NegotiateButton

func _ready() -> void:
	NetworkManager.message_received.connect(_on_message)
	negotiate_btn.toggled.connect(_on_negotiate_toggled)

func _on_message(data: Dictionary) -> void:
	match data.get("type", ""):
		"janken_result", "zone_fight_result":
			battle_log.show_janken_result(data)
		"zone_match":
			_on_zone_match(data)
		"zone_cancelled":
			_on_zone_cancelled()
		"player_eliminated":
			_on_player_eliminated(data)
		"player_cleared":
			_on_player_cleared(data)

func _on_zone_match(data: Dictionary) -> void:
	GameState.in_zone_match = true
	GameState.zone_opponent = data.get("opponent", {})
	zone_dialog.show_match(data)

func _on_zone_cancelled() -> void:
	GameState.in_zone_match = false
	GameState.zone_opponent = {}
	zone_dialog.hide_dialog()

func _on_negotiate_toggled(pressed: bool) -> void:
	if pressed:
		NetworkManager.select_command("negotiate")
	else:
		NetworkManager.select_command("none")

func _on_player_eliminated(data: Dictionary) -> void:
	var pid: String = data.get("playerId", "")
	if pid == GameState.player_id:
		battle_log.show_elimination("あなたは退場しました...")

func _on_player_cleared(data: Dictionary) -> void:
	var pid: String = data.get("playerId", "")
	if pid == GameState.player_id:
		battle_log.show_clear("ゴール！クリアおめでとう！")
