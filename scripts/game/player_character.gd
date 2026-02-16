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

	# 瞬間移動: サーバーがjumping状態の場合は即座にターゲット位置へ移動
	var server_jumping: bool = data.get("jumping", false)
	if server_jumping:
		position = _target_pos

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
	# 通常の補間移動
	position = position.lerp(_target_pos, LERP_SPEED * delta)

## アバターテクスチャ生成（色付き円形 + 顔パーツ）
static func _get_avatar_texture(aid: int) -> ImageTexture:
	if _avatar_cache.has(aid):
		return _avatar_cache[aid]

	var s := AVATAR_SIZE
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var hue := float(aid) / float(AVATAR_COUNT)
	var body_color := Color.from_hsv(hue, 0.7, 0.9)
	var center := Vector2(s / 2.0, s / 2.0)
	var radius := s / 2.0 - 1.0

	# 顔パーツの位置
	var left_eye := Vector2(s * 0.34, s * 0.38)
	var right_eye := Vector2(s * 0.66, s * 0.38)
	var eye_r_white := s * 0.08
	var eye_r_pupil := s * 0.04
	var mouth_center := Vector2(s * 0.5, s * 0.42)
	var mouth_r := s * 0.2
	var mouth_thick := maxf(s * 0.03, 1.0)
	var mouth_min_y := s * 0.55
	var white := Color.WHITE
	var dark := Color(0.15, 0.15, 0.15)

	for y in range(s):
		for x in range(s):
			var px := Vector2(x + 0.5, y + 0.5)
			var dist := px.distance_to(center)
			if dist > radius:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			var c := body_color
			# 白目
			var dl := px.distance_to(left_eye)
			var dr := px.distance_to(right_eye)
			if dl <= eye_r_white or dr <= eye_r_white:
				c = white
			# 瞳
			if dl <= eye_r_pupil or dr <= eye_r_pupil:
				c = dark
			# 口（スマイルアーク）
			var dm := px.distance_to(mouth_center)
			if absf(dm - mouth_r) <= mouth_thick and px.y > mouth_min_y:
				c = dark

			img.set_pixel(x, y, c)

	var tex := ImageTexture.create_from_image(img)
	_avatar_cache[aid] = tex
	return tex
