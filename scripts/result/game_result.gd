extends Control

## ゲーム結果画面

@onready var result_list: VBoxContainer = %ResultList
@onready var my_result_label: Label = %MyResultLabel
@onready var back_button: Button = %BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	NetworkManager.message_received.connect(_on_message)
	_show_results()

func _show_results() -> void:
	if not GameState.game_results.is_empty():
		_display_results(GameState.game_results)

func _on_message(data: Dictionary) -> void:
	if data.get("type", "") == "game_over":
		_display_results(data.get("results", []))

func _display_results(results: Array) -> void:
	for child in result_list.get_children():
		child.queue_free()

	var rank := 1
	for r: Dictionary in results:
		var hbox := HBoxContainer.new()
		hbox.custom_minimum_size.y = 50

		var rank_label := Label.new()
		rank_label.text = "#%d" % rank
		rank_label.custom_minimum_size.x = 50
		hbox.add_child(rank_label)

		var name_label := Label.new()
		name_label.text = r.get("name", "???")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)

		var status_label := Label.new()
		if r.get("cleared", false):
			status_label.text = "クリア! ⭐%d 💰%d" % [r.get("stars", 0), r.get("gold", 0)]
			status_label.add_theme_color_override("font_color", Color.GREEN)
		elif r.get("alive", false):
			status_label.text = "未ゴール ⭐%d 💰%d" % [r.get("stars", 0), r.get("gold", 0)]
			status_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			status_label.text = "退場"
			status_label.add_theme_color_override("font_color", Color.RED)
		hbox.add_child(status_label)

		# 自分をハイライト
		if r.get("id", "") == GameState.player_id:
			var panel := PanelContainer.new()
			panel.add_child(hbox)
			result_list.add_child(panel)

			if r.get("cleared", false):
				my_result_label.text = "クリア！おめでとう！"
				my_result_label.add_theme_color_override("font_color", Color.GREEN)
			elif r.get("alive", false):
				my_result_label.text = "タイムオーバー..."
				my_result_label.add_theme_color_override("font_color", Color.YELLOW)
			else:
				my_result_label.text = "退場..."
				my_result_label.add_theme_color_override("font_color", Color.RED)
		else:
			result_list.add_child(hbox)

		rank += 1

func _on_back_pressed() -> void:
	GameState.reset()
	var main_node := get_tree().root.get_node("Main")
	if main_node and main_node.has_method("change_scene"):
		main_node.change_scene("res://scenes/lobby/room_list.tscn")
