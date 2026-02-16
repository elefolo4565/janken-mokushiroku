extends Control

## 取引ダイアログ
## 交渉モードの2人が接触した際に表示される

@onready var partner_name_label: Label = %PartnerNameLabel
@onready var offer_rock_spin: SpinBox = %OfferRockSpin
@onready var offer_scissors_spin: SpinBox = %OfferScissorsSpin
@onready var offer_paper_spin: SpinBox = %OfferPaperSpin
@onready var offer_stars_spin: SpinBox = %OfferStarsSpin
@onready var offer_gold_spin: SpinBox = %OfferGoldSpin
@onready var request_rock_spin: SpinBox = %RequestRockSpin
@onready var request_scissors_spin: SpinBox = %RequestScissorsSpin
@onready var request_paper_spin: SpinBox = %RequestPaperSpin
@onready var request_stars_spin: SpinBox = %RequestStarsSpin
@onready var request_gold_spin: SpinBox = %RequestGoldSpin
@onready var send_offer_btn: Button = %SendOfferBtn
@onready var accept_btn: Button = %AcceptBtn
@onready var cancel_btn: Button = %CancelBtn
@onready var status_label: Label = %TradeStatusLabel

var _partner_id := ""
var _received_offer: Dictionary = {}
var _received_request: Dictionary = {}

func _ready() -> void:
	visible = false
	NetworkManager.message_received.connect(_on_message)
	send_offer_btn.pressed.connect(_on_send_offer)
	accept_btn.pressed.connect(_on_accept)
	cancel_btn.pressed.connect(_on_cancel)
	accept_btn.visible = false

func show_trade(data: Dictionary) -> void:
	_partner_id = data.get("partnerId", "")
	partner_name_label.text = "取引相手: " + data.get("partnerName", "???")
	status_label.text = "提案を作成してください"
	visible = true

	# SpinBoxの最大値を手持ちに制限
	offer_rock_spin.max_value = GameState.my_cards.get("rock", 0)
	offer_scissors_spin.max_value = GameState.my_cards.get("scissors", 0)
	offer_paper_spin.max_value = GameState.my_cards.get("paper", 0)
	offer_stars_spin.max_value = GameState.my_stars
	offer_gold_spin.max_value = GameState.my_gold

	# 相手からの提案がある場合
	if data.has("offer"):
		_received_offer = data.get("offer", {})
		_received_request = data.get("request", {})
		_show_received_offer()

func _show_received_offer() -> void:
	var offer_cards: Dictionary = _received_offer.get("cards", {})
	var offer_stars: int = _received_offer.get("stars", 0)
	var offer_gold: int = _received_offer.get("gold", 0)
	var req_cards: Dictionary = _received_request.get("cards", {})
	var req_stars: int = _received_request.get("stars", 0)
	var req_gold: int = _received_request.get("gold", 0)

	status_label.text = "相手の提案:\n提供: グー%d チョキ%d パー%d ★%d 金%d\n要求: グー%d チョキ%d パー%d ★%d 金%d" % [
		offer_cards.get("rock", 0), offer_cards.get("scissors", 0), offer_cards.get("paper", 0), offer_stars, offer_gold,
		req_cards.get("rock", 0), req_cards.get("scissors", 0), req_cards.get("paper", 0), req_stars, req_gold,
	]
	accept_btn.visible = true

func _on_send_offer() -> void:
	var offer := {
		"cards": {
			"rock": int(offer_rock_spin.value),
			"scissors": int(offer_scissors_spin.value),
			"paper": int(offer_paper_spin.value),
		},
		"stars": int(offer_stars_spin.value),
		"gold": int(offer_gold_spin.value),
	}
	var request := {
		"cards": {
			"rock": int(request_rock_spin.value),
			"scissors": int(request_scissors_spin.value),
			"paper": int(request_paper_spin.value),
		},
		"stars": int(request_stars_spin.value),
		"gold": int(request_gold_spin.value),
	}
	NetworkManager.send_trade_offer(offer, request)
	status_label.text = "提案を送信しました..."

func _on_accept() -> void:
	NetworkManager.send_trade_respond(true)
	status_label.text = "取引を承認しました"

func _on_cancel() -> void:
	NetworkManager.send_trade_respond(false)
	visible = false

func _on_message(data: Dictionary) -> void:
	match data.get("type", ""):
		"trade_request":
			show_trade(data)
		"trade_result":
			var success: bool = data.get("success", false)
			status_label.text = data.get("message", "")
			if success:
				get_tree().create_timer(1.5).timeout.connect(func() -> void: visible = false)
			else:
				get_tree().create_timer(1.5).timeout.connect(func() -> void: visible = false)
