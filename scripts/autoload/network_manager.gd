extends Node

## WebSocket通信管理 Autoload
## サーバーとの接続・メッセージ送受信を一元管理する

signal connected
signal disconnected
signal message_received(data: Dictionary)

var _socket := WebSocketPeer.new()
var _connected := false

# サーバーURL (開発時はlocalhost、本番はRender.comのURL)
var server_url := "ws://localhost:10000/ws"

func _ready() -> void:
	# 本番環境の場合はwssに切り替え
	if OS.has_feature("web"):
		# ブラウザで動作している場合、同一ホストに接続
		var host: String = str(JavaScriptBridge.eval("window.location.host", true))
		var protocol: String = str(JavaScriptBridge.eval("window.location.protocol", true))
		if protocol == "https:":
			server_url = "wss://" + str(host) + "/ws"
		else:
			server_url = "ws://" + str(host) + "/ws"

func connect_to_server() -> void:
	var err := _socket.connect_to_url(server_url)
	if err != OK:
		push_error("WebSocket接続に失敗: %d" % err)
		return
	set_process(true)

func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				connected.emit()
			while _socket.get_available_packet_count() > 0:
				var packet := _socket.get_packet()
				var text := packet.get_string_from_utf8()
				var json = JSON.parse_string(text)
				if json != null and json is Dictionary:
					message_received.emit(json)
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				disconnected.emit()
			set_process(false)

func send_message(data: Dictionary) -> void:
	if _connected:
		_socket.send_text(JSON.stringify(data))

func close() -> void:
	_socket.close()

func is_connected_to_server() -> bool:
	return _connected

# --- 便利メソッド ---

func set_player_name(player_name: String) -> void:
	send_message({"type": "set_name", "name": player_name})

func create_room(room_name: String, settings: Dictionary = {}) -> void:
	send_message({"type": "create_room", "roomName": room_name, "settings": settings})

func join_room(room_id: String) -> void:
	send_message({"type": "join_room", "roomId": room_id})

func leave_room() -> void:
	send_message({"type": "leave_room"})

func list_rooms() -> void:
	send_message({"type": "list_rooms"})

func start_game() -> void:
	send_message({"type": "start_game"})

func send_input(dx: float, dy: float) -> void:
	send_message({"type": "input", "dx": dx, "dy": dy})

func select_command(command: String) -> void:
	send_message({"type": "select_command", "command": command})

func send_trade_offer(offer: Dictionary, request: Dictionary) -> void:
	send_message({"type": "trade_offer", "offer": offer, "request": request})

func send_trade_respond(accept: bool) -> void:
	send_message({"type": "trade_respond", "accept": accept})

func add_ai() -> void:
	send_message({"type": "add_ai"})

func remove_ai() -> void:
	send_message({"type": "remove_ai"})

func send_zone_fight(hand: String, bet: int) -> void:
	send_message({"type": "zone_fight", "hand": hand, "bet": bet})

func send_zone_leave() -> void:
	send_message({"type": "zone_leave"})
