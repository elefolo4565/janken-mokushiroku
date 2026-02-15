extends Control

## 対戦ログ表示（画面上部、右からスライドイン、最大5行）

const MAX_ENTRIES := 5
const ENTRY_HEIGHT := 26.0
const ENTRY_GAP := 4.0
const SLIDE_DURATION := 0.3
const DISPLAY_DURATION := 5.0
const FADE_DURATION := 0.5

const HAND_ICONS := {
	"rock": "✊",
	"scissors": "✌",
	"paper": "✋",
}

var _entries: Array = [] # Array of Label

func add_message(text: String, color: Color = Color.WHITE) -> void:
	# 最大数を超えたら古いものを即削除
	while _entries.size() >= MAX_ENTRIES:
		var old: Label = _entries.pop_front()
		old.queue_free()

	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(label)
	_entries.append(label)

	# 全エントリのY位置を再配置
	_reposition()

	# 右端外からスライドイン
	label.position.x = size.x + 100.0
	var tween := create_tween()
	tween.tween_property(label, "position:x", 0.0, SLIDE_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(DISPLAY_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(_on_entry_expired.bind(label))

func show_janken_result(data: Dictionary) -> void:
	var p1: Dictionary = data.get("player1", {})
	var p2: Dictionary = data.get("player2", {})
	var winner_id: Variant = data.get("winner")
	var result_type: String = data.get("result", "draw")

	var p1_name: String = p1.get("name", "?")
	var p2_name: String = p2.get("name", "?")
	var p1_icon: String = HAND_ICONS.get(p1.get("hand", ""), "?")
	var p2_icon: String = HAND_ICONS.get(p2.get("hand", ""), "?")

	var text: String
	var color: Color

	if result_type == "draw":
		text = "%s%s vs %s%s あいこ!" % [p1_name, p1_icon, p2_name, p2_icon]
		# 自分が関与しているかで色を変える
		if _is_me(p1) or _is_me(p2):
			color = Color.YELLOW
		else:
			color = Color(0.8, 0.8, 0.8)
	else:
		var winner_name: String
		var loser_name: String
		var w_icon: String
		var l_icon: String
		if winner_id == p1.get("id"):
			winner_name = p1_name
			loser_name = p2_name
			w_icon = p1_icon
			l_icon = p2_icon
		else:
			winner_name = p2_name
			loser_name = p1_name
			w_icon = p2_icon
			l_icon = p1_icon

		text = "%s%s > %s%s" % [winner_name, w_icon, loser_name, l_icon]

		if winner_id == GameState.player_id:
			color = Color.GREEN
		elif _is_me(p1) or _is_me(p2):
			color = Color(1.0, 0.4, 0.4)
		else:
			color = Color(0.8, 0.8, 0.8)

	add_message(text, color)

func show_elimination(text: String) -> void:
	add_message(text, Color(1.0, 0.3, 0.3))

func show_clear(text: String) -> void:
	add_message(text, Color.GOLD)

func _is_me(p: Dictionary) -> bool:
	return p.get("id", "") == GameState.player_id

func _reposition() -> void:
	for i in range(_entries.size()):
		var target_y: float = i * (ENTRY_HEIGHT + ENTRY_GAP)
		var label: Label = _entries[i]
		var current_y: float = label.position.y
		if absf(current_y - target_y) > 1.0:
			var tween := create_tween()
			tween.tween_property(label, "position:y", target_y, 0.15)
		else:
			label.position.y = target_y

func _on_entry_expired(label: Label) -> void:
	if label in _entries:
		_entries.erase(label)
	label.queue_free()
	_reposition()
