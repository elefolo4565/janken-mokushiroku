extends Node

## グローバルゲーム状態管理 Autoload

# プレイヤー情報
var player_id := ""
var player_name := ""
var player_avatar_id := 0

# ルーム情報
var current_room: Dictionary = {}
var is_host := false

# ゲーム中の状態
var in_game := false
var field_width := 800.0
var field_height := 800.0
var time_left := 0
var victory_stars := 3
var goal_gate := {"x": 400.0, "y": 50.0, "radius": 40.0}

# 自分のカード情報
var my_cards := {"rock": 0, "scissors": 0, "paper": 0}
var my_stars := 0
var my_gold := 0
var my_command := "none"

# 全プレイヤーの公開情報 (サーバーから毎tick受信)
var players_data: Array = []

# カード総数
var card_totals := {"rock": 0, "scissors": 0, "paper": 0}

# ゴールド・ゾーン設定
var victory_gold := 50
var battle_zones: Array = []

# ゾーン対戦状態
var in_zone_match := false
var zone_opponent: Dictionary = {}

# ゲーム結果
var game_results: Array = []

# ジョイスティック入力（VirtualJoystick → GameField間の共有）
var input_vector := Vector2.ZERO

func reset() -> void:
	current_room = {}
	is_host = false
	in_game = false
	my_cards = {"rock": 0, "scissors": 0, "paper": 0}
	my_stars = 0
	my_gold = 0
	my_command = "none"
	players_data = []
	card_totals = {"rock": 0, "scissors": 0, "paper": 0}
	battle_zones = []
	in_zone_match = false
	zone_opponent = {}
	game_results = []
	input_vector = Vector2.ZERO

func get_my_total_cards() -> int:
	return my_cards.get("rock", 0) + my_cards.get("scissors", 0) + my_cards.get("paper", 0)

func can_goal() -> bool:
	return get_my_total_cards() == 0 and my_stars >= victory_stars and my_gold >= victory_gold

func get_my_player_data() -> Dictionary:
	for p in players_data:
		if p.get("id", "") == player_id:
			return p
	return {}
