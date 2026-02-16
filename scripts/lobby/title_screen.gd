extends Control

## タイトル画面
## 名前入力 + アバター選択 → サーバー接続 → ルーム一覧画面へ

const SAVE_PATH := "user://settings.cfg"
const AVATAR_COUNT := 12
const AVATAR_PREVIEW_SIZE := 40

@onready var name_input: LineEdit = %NameInput
@onready var connect_button: Button = %ConnectButton
@onready var status_label: Label = %StatusLabel
@onready var avatar_row: HBoxContainer = %AvatarRow

var _selected_avatar_id := 0
var _avatar_buttons: Array[Button] = []

func _ready() -> void:
	NetworkManager.connected.connect(_on_server_connected)
	NetworkManager.disconnected.connect(_on_server_disconnected)
	NetworkManager.message_received.connect(_on_message)
	connect_button.pressed.connect(_on_connect_pressed)

	# アバター選択ボタンを生成
	_create_avatar_buttons()

	# 保存された設定を復元
	_load_settings()

	# 既に接続済みの場合
	if NetworkManager.is_connected_to_server():
		status_label.text = "接続済み"
		connect_button.text = "ルーム一覧へ"

func _create_avatar_buttons() -> void:
	for i in range(AVATAR_COUNT):
		var btn := Button.new()
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(AVATAR_PREVIEW_SIZE + 10, AVATAR_PREVIEW_SIZE + 10)

		# アバタープレビュー用のTextureRect（ボタン内で中央配置）
		var tex_rect := TextureRect.new()
		tex_rect.texture = _generate_avatar_preview(i)
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tex_rect)

		btn.pressed.connect(_on_avatar_selected.bind(i))
		avatar_row.add_child(btn)
		_avatar_buttons.append(btn)

	# 初期選択をハイライト（アニメーションなし）
	_update_avatar_highlight(false)

func _generate_avatar_preview(aid: int) -> ImageTexture:
	var s := AVATAR_PREVIEW_SIZE
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
			var dl := px.distance_to(left_eye)
			var dr := px.distance_to(right_eye)
			if dl <= eye_r_white or dr <= eye_r_white:
				c = white
			if dl <= eye_r_pupil or dr <= eye_r_pupil:
				c = dark
			var dm := px.distance_to(mouth_center)
			if absf(dm - mouth_r) <= mouth_thick and px.y > mouth_min_y:
				c = dark

			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)

func _on_avatar_selected(aid: int) -> void:
	_selected_avatar_id = aid
	GameState.player_avatar_id = aid
	_update_avatar_highlight()

func _update_avatar_highlight(animate := true) -> void:
	for i in range(_avatar_buttons.size()):
		var btn := _avatar_buttons[i]
		var selected := (i == _selected_avatar_id)
		btn.button_pressed = selected
		var target_scale := Vector2(1.3, 1.3) if selected else Vector2(1.0, 1.0)
		var target_mod := Color.WHITE if selected else Color(0.5, 0.5, 0.5, 0.6)
		btn.z_index = 1 if selected else 0
		if animate:
			var tw := create_tween().set_parallel(true)
			tw.tween_property(btn, "scale", target_scale, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "modulate", target_mod, 0.12)
		else:
			btn.scale = target_scale
			btn.modulate = target_mod

func _on_connect_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		status_label.text = "名前を入力してください"
		return

	GameState.player_name = player_name
	GameState.player_avatar_id = _selected_avatar_id
	_save_settings()

	if NetworkManager.is_connected_to_server():
		# 既に接続済みなら名前を設定してルーム一覧へ
		NetworkManager.set_player_name(player_name, _selected_avatar_id)
	else:
		status_label.text = "接続中..."
		connect_button.disabled = true
		NetworkManager.connect_to_server()

func _on_server_connected() -> void:
	status_label.text = "接続成功！"
	NetworkManager.set_player_name(GameState.player_name, GameState.player_avatar_id)

func _on_server_disconnected() -> void:
	status_label.text = "接続が切断されました"
	connect_button.disabled = false

func _on_message(data: Dictionary) -> void:
	if data.get("type", "") == "name_set":
		# 名前設定完了 → ルーム一覧へ
		var main_node := get_tree().root.get_node("Main")
		if main_node and main_node.has_method("change_scene"):
			main_node.change_scene("res://scenes/lobby/room_list.tscn")

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", name_input.text.strip_edges())
	config.set_value("player", "avatar_id", _selected_avatar_id)
	config.save(SAVE_PATH)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var saved_name: String = config.get_value("player", "name", "")
		if not saved_name.is_empty():
			name_input.text = saved_name
		_selected_avatar_id = config.get_value("player", "avatar_id", 0)
		GameState.player_avatar_id = _selected_avatar_id
		_update_avatar_highlight(false)
