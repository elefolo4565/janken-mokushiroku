extends Control

## 半透明の円形バーチャルジョイスティック（画面左下に固定表示）
## タッチ/マウス入力を処理し、GameState.input_vector に反映する
## _input() でイベントを早期取得し、ジョイスティック領域内のタッチのみ処理

const BASE_RADIUS := 90.0
const THUMB_RADIUS := 30.0
const MAX_DRAG := 90.0
const TOUCH_AREA_MARGIN := 50.0

const BASE_COLOR := Color(1, 1, 1, 0.15)
const BORDER_COLOR := Color(1, 1, 1, 0.3)
const THUMB_COLOR := Color(1, 1, 1, 0.4)
const THUMB_ACTIVE_COLOR := Color(1, 1, 1, 0.6)

var _active_touch_index := -1
var _mouse_active := false
var _touch_vector := Vector2.ZERO
var _key_vector := Vector2.ZERO

func _process(_delta: float) -> void:
	# キーボード入力（WASD / 矢印キー）
	_key_vector = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_key_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_key_vector.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_key_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_key_vector.x += 1.0
	if _key_vector.length() > 1.0:
		_key_vector = _key_vector.normalized()

	# ピンチズーム中はタッチ移動を無効化
	var effective_touch := Vector2.ZERO if GameState.is_pinching else _touch_vector

	# キーボード入力がある場合はそちらを優先
	if _key_vector.length() > 0.0:
		GameState.input_vector = _key_vector
	else:
		GameState.input_vector = effective_touch
	queue_redraw()

func _draw() -> void:
	var center := size / 2.0

	# ベース円（外枠）
	draw_circle(center, BASE_RADIUS, BASE_COLOR)
	draw_arc(center, BASE_RADIUS, 0, TAU, 64, BORDER_COLOR, 2.0)

	# サム円（入力方向に追従）
	var current_input: Vector2 = GameState.input_vector
	var thumb_offset: Vector2 = current_input * MAX_DRAG
	var thumb_pos: Vector2 = center + thumb_offset
	var is_active: bool = _active_touch_index >= 0 or _mouse_active or _key_vector.length() > 0.0
	var col := THUMB_ACTIVE_COLOR if is_active else THUMB_COLOR
	draw_circle(thumb_pos, THUMB_RADIUS, col)

func _get_joystick_center_screen() -> Vector2:
	return global_position + size / 2.0

func _is_in_touch_area(screen_pos: Vector2) -> bool:
	var center := _get_joystick_center_screen()
	return screen_pos.distance_to(center) <= BASE_RADIUS + TOUCH_AREA_MARGIN

func _update_touch(screen_pos: Vector2) -> void:
	var center := _get_joystick_center_screen()
	var diff := screen_pos - center
	if diff.length() > MAX_DRAG:
		diff = diff.normalized() * MAX_DRAG
	_touch_vector = diff / MAX_DRAG

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _active_touch_index == -1 and _is_in_touch_area(event.position):
				_active_touch_index = event.index
				_update_touch(event.position)
				get_viewport().set_input_as_handled()
		else:
			if event.index == _active_touch_index:
				_active_touch_index = -1
				_touch_vector = Vector2.ZERO
				get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if event.index == _active_touch_index:
			_update_touch(event.position)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_in_touch_area(event.global_position):
					_mouse_active = true
					_update_touch(event.global_position)
					get_viewport().set_input_as_handled()
			else:
				if _mouse_active:
					_mouse_active = false
					_touch_vector = Vector2.ZERO
					get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _mouse_active:
		_update_touch(event.global_position)
		get_viewport().set_input_as_handled()
