extends Control

## 半透明の円形バーチャルジョイスティック（画面左下に固定表示）
## タッチ/マウス入力を処理し、GameState.input_vector に反映する

const BASE_RADIUS := 60.0
const THUMB_RADIUS := 20.0
const MAX_DRAG := 60.0

const BASE_COLOR := Color(1, 1, 1, 0.1)
const BORDER_COLOR := Color(1, 1, 1, 0.25)
const THUMB_COLOR := Color(1, 1, 1, 0.35)
const THUMB_ACTIVE_COLOR := Color(1, 1, 1, 0.5)

var _is_touching := false
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

	# キーボード入力がある場合はそちらを優先
	if _key_vector.length() > 0.0:
		GameState.input_vector = _key_vector
	else:
		GameState.input_vector = _touch_vector
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
	var is_active: bool = _is_touching or _key_vector.length() > 0.0
	var col := THUMB_ACTIVE_COLOR if is_active else THUMB_COLOR
	draw_circle(thumb_pos, THUMB_RADIUS, col)

func _get_joystick_center_screen() -> Vector2:
	return global_position + size / 2.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_is_touching = true
			_touch_vector = Vector2.ZERO
		else:
			_is_touching = false
			_touch_vector = Vector2.ZERO

	elif event is InputEventScreenDrag and _is_touching:
		var center := _get_joystick_center_screen()
		var diff: Vector2 = Vector2(event.position) - center
		if diff.length() > MAX_DRAG:
			diff = diff.normalized() * MAX_DRAG
		_touch_vector = diff / MAX_DRAG

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_touching = true
				_touch_vector = Vector2.ZERO
			else:
				_is_touching = false
				_touch_vector = Vector2.ZERO

	elif event is InputEventMouseMotion and _is_touching:
		var center := _get_joystick_center_screen()
		var diff: Vector2 = Vector2(event.global_position) - center
		if diff.length() > MAX_DRAG:
			diff = diff.normalized() * MAX_DRAG
		_touch_vector = diff / MAX_DRAG
