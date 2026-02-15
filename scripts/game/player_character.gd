extends Node2D

## プレイヤーキャラクター表示
## サーバーから受信した位置に補間移動する

@onready var body: ColorRect = $Body
@onready var name_label: Label = $NameLabel
@onready var command_label: Label = $CommandLabel
@onready var star_label: Label = $StarLabel

var player_id := ""
var player_name := ""
var is_me := false
var _target_pos := Vector2.ZERO
var _alive := true
var _cleared := false

const LERP_SPEED := 15.0

# コマンド表示用のアイコンマップ（ゾーン制のため手は表示しない）
const COMMAND_ICONS := {
	"none": "",
	"negotiate": "💰",
}

func setup(pid: String, pname: String, me: bool) -> void:
	player_id = pid
	player_name = pname
	is_me = me

func _ready() -> void:
	name_label.text = player_name

	# 自分のキャラは別色
	if is_me:
		body.color = Color(0.2, 0.6, 1.0)
	else:
		# ランダム色（IDベースで固定）
		var hash_val := player_id.hash()
		body.color = Color.from_hsv(
			fmod(abs(float(hash_val)) / 1000.0, 1.0),
			0.6,
			0.8
		)

func update_data(data: Dictionary) -> void:
	_target_pos = Vector2(data.get("x", 0), data.get("y", 0))
	_alive = data.get("alive", true)
	_cleared = data.get("cleared", false)
	var in_zone: bool = data.get("inZoneId", "") != "" and data.get("inZoneId", null) != null

	var cmd: String = data.get("command", "none")
	command_label.text = COMMAND_ICONS.get(cmd, "")

	var stars: int = data.get("stars", 0)
	var gold: int = data.get("gold", 0)
	star_label.text = "⭐%d 💰%d" % [stars, gold]

	# 退場・ゾーン内・クリアの表示
	if not _alive:
		visible = false
	elif in_zone:
		visible = true
		modulate = Color(1.2, 1.2, 0.6) # 黄色っぽくゾーン内を表現
	elif _cleared:
		visible = true
		modulate = Color(1.0, 1.0, 1.0, 0.4)
	else:
		visible = true
		modulate = Color.WHITE

func _process(delta: float) -> void:
	# 補間移動
	position = position.lerp(_target_pos, LERP_SPEED * delta)
