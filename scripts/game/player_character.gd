extends Node2D

## プレイヤーキャラクター表示
## サーバーから受信した位置に補間移動する

@onready var body: Sprite2D = $Body
@onready var name_label: Label = $NameLabel
@onready var command_label: Label = $CommandLabel
@onready var star_label: Label = $StarLabel

var player_id := ""
var player_name := ""
var is_me := false
var avatar_id := 0
var _target_pos := Vector2.ZERO
var _alive := true
var _cleared := false

const LERP_SPEED := 15.0
const AVATAR_SIZE := 64
const BODY_SIZE := 30.0
const AVATAR_COUNT := 12

# ジャンプアニメーション
var _jumping := false
var _jump_start_pos := Vector2.ZERO
var _jump_end_pos := Vector2.ZERO
var _jump_time := 0.0
const JUMP_DURATION := 2.0
const JUMP_HEIGHT := 200.0

# コマンド表示用のアイコンマップ（ゾーン制のため手は表示しない）
const COMMAND_ICONS := {
	"none": "",
	"negotiate": "💰",
}

# アバターテクスチャキャッシュ（static相当）
static var _avatar_cache: Dictionary = {}

func setup(pid: String, pname: String, me: bool, aid: int = 0) -> void:
	player_id = pid
	player_name = pname
	is_me = me
	avatar_id = aid

func _ready() -> void:
	name_label.text = player_name
	body.texture = _get_avatar_texture(avatar_id)
	body.scale = Vector2(BODY_SIZE / AVATAR_SIZE, BODY_SIZE / AVATAR_SIZE)

func update_data(data: Dictionary) -> void:
	_target_pos = Vector2(data.get("x", 0), data.get("y", 0))
	_alive = data.get("alive", true)
	_cleared = data.get("cleared", false)
	var in_zone: bool = data.get("inZoneId", "") != "" and data.get("inZoneId", null) != null

	# ジャンプ開始検出
	var server_jumping: bool = data.get("jumping", false)
	if server_jumping and not _jumping:
		_jumping = true
		_jump_start_pos = position
		_jump_end_pos = _target_pos
		_jump_time = 0.0
	elif not server_jumping:
		_jumping = false

	var cmd: String = data.get("command", "none")
	command_label.text = COMMAND_ICONS.get(cmd, "")

	var stars: int = data.get("stars", 0)
	var gold: int = data.get("gold", 0)
	star_label.text = "☆%d" % [stars]

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
	if _jumping:
		_jump_time += delta
		var t := clampf(_jump_time / JUMP_DURATION, 0.0, 1.0)
		# 地面上の位置を線形補間
		var ground_pos := _jump_start_pos.lerp(_jump_end_pos, t)
		# 放物線アーク（上方向=負のY）
		var arc_offset := -JUMP_HEIGHT * 4.0 * t * (1.0 - t)
		position = ground_pos + Vector2(0, arc_offset)
		if t >= 1.0:
			_jumping = false
			position = _jump_end_pos
	else:
		# 通常の補間移動
		position = position.lerp(_target_pos, LERP_SPEED * delta)

## アバターテクスチャ生成（プレースホルダー: 色付き円形）
static func _get_avatar_texture(aid: int) -> ImageTexture:
	if _avatar_cache.has(aid):
		return _avatar_cache[aid]

	var img := Image.create(AVATAR_SIZE, AVATAR_SIZE, false, Image.FORMAT_RGBA8)
	var hue := float(aid) / float(AVATAR_COUNT)
	var color := Color.from_hsv(hue, 0.7, 0.9)
	var center := Vector2(AVATAR_SIZE / 2.0, AVATAR_SIZE / 2.0)
	var radius := AVATAR_SIZE / 2.0 - 1.0

	for y in range(AVATAR_SIZE):
		for x in range(AVATAR_SIZE):
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if dist <= radius:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	var tex := ImageTexture.create_from_image(img)
	_avatar_cache[aid] = tex
	return tex
