// メッセージタイプ定義

// クライアント → サーバー
export const C2S = {
  SET_NAME: 'set_name',
  CREATE_ROOM: 'create_room',
  JOIN_ROOM: 'join_room',
  LEAVE_ROOM: 'leave_room',
  LIST_ROOMS: 'list_rooms',
  START_GAME: 'start_game',
  INPUT: 'input',
  SELECT_COMMAND: 'select_command',
  TRADE_OFFER: 'trade_offer',
  TRADE_RESPOND: 'trade_respond',
  ADD_AI: 'add_ai',
  REMOVE_AI: 'remove_ai',
  ZONE_FIGHT: 'zone_fight',       // ゾーン内で勝負選択 { hand, bet }
  ZONE_LEAVE: 'zone_leave',       // ゾーン内で「やめる」選択
};

// サーバー → クライアント
export const S2C = {
  CONNECTED: 'connected',
  ROOM_CREATED: 'room_created',
  ROOM_JOINED: 'room_joined',
  ROOM_LIST: 'room_list',
  PLAYER_JOINED: 'player_joined',
  PLAYER_LEFT: 'player_left',
  GAME_COUNTDOWN: 'game_countdown',
  GAME_STARTED: 'game_started',
  STATE: 'state',
  JANKEN_RESULT: 'janken_result',
  PLAYER_ELIMINATED: 'player_eliminated',
  PLAYER_CLEARED: 'player_cleared',
  TRADE_REQUEST: 'trade_request',
  TRADE_RESULT: 'trade_result',
  GAME_OVER: 'game_over',
  ERROR: 'error',
  YOUR_CARDS: 'your_cards',
  ZONE_MATCH: 'zone_match',             // ゾーン内2名マッチング通知
  ZONE_FIGHT_RESULT: 'zone_fight_result', // ゾーン勝負結果
  ZONE_CANCELLED: 'zone_cancelled',     // ゾーン対戦キャンセル
  YOUR_GOLD: 'your_gold',               // 所持金更新
};

// コマンド種別
export const COMMANDS = {
  NONE: 'none',
  ROCK: 'rock',
  SCISSORS: 'scissors',
  PAPER: 'paper',
  NEGOTIATE: 'negotiate',
};

// じゃんけん判定テーブル (key が value に勝つ)
export const BEATS = {
  rock: 'scissors',
  scissors: 'paper',
  paper: 'rock',
};

// デフォルトゲーム設定
export const DEFAULT_SETTINGS = {
  cardsPerType: 4,      // 各手のカード枚数
  initialStars: 3,      // 初期星数
  victoryStars: 3,      // 勝利に必要な星数
  timeLimit: 300,        // 制限時間（秒）
  fieldWidth: 800,       // フィールド幅
  fieldHeight: 800,      // フィールド高さ
  playerRadius: 20,      // プレイヤー当たり判定半径
  playerSpeed: 150,      // プレイヤー移動速度 (px/sec)
  collisionCooldown: 1.0, // 衝突クールダウン（秒）
  initialGold: 100,       // 初期所持金
  victoryGold: 50,        // ゴール条件の最低所持金
  battleZoneCount: 4,     // 勝負ゾーンの数
  battleZoneRadius: 60,   // 勝負ゾーンの半径 (px)
  zoneTimeout: 15,        // ゾーン内対戦のタイムアウト（秒）
};
