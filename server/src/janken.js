import { COMMANDS, BEATS, S2C } from './protocol.js';

/**
 * じゃんけん判定
 * @param {string} hand1 - プレイヤー1の手 (rock/scissors/paper)
 * @param {string} hand2 - プレイヤー2の手 (rock/scissors/paper)
 * @returns {'player1'|'player2'|'draw'} 勝者
 */
export function resolveJanken(hand1, hand2) {
  if (hand1 === hand2) return 'draw';
  if (BEATS[hand1] === hand2) return 'player1';
  return 'player2';
}

/**
 * じゃんけんの手かどうかを判定
 */
export function isJankenHand(command) {
  return command === COMMANDS.ROCK ||
         command === COMMANDS.SCISSORS ||
         command === COMMANDS.PAPER;
}

/**
 * 2人のプレイヤー間でじゃんけんを処理
 * @param {PlayerState} p1
 * @param {PlayerState} p2
 * @param {Room} room
 * @returns {object|null} 結果オブジェクト
 */
export function processJanken(p1, p2, room) {
  const hand1 = p1.command;
  const hand2 = p2.command;

  // 両者がじゃんけんの手を選択しているか確認
  if (!isJankenHand(hand1) || !isJankenHand(hand2)) {
    return null;
  }

  // カードを持っているか確認
  if (!p1.hasCard(hand1) || !p2.hasCard(hand2)) {
    return null;
  }

  // カードを消費
  p1.useCard(hand1);
  p2.useCard(hand2);

  // 勝敗判定
  const result = resolveJanken(hand1, hand2);

  let winnerId = null;
  if (result === 'player1') {
    p2.removeStars(1);
    p1.addStars(1);
    winnerId = p1.id;
  } else if (result === 'player2') {
    p1.removeStars(1);
    p2.addStars(1);
    winnerId = p2.id;
  }

  // 両者の選択をリセット
  p1.command = COMMANDS.NONE;
  p2.command = COMMANDS.NONE;

  const resultData = {
    type: S2C.JANKEN_RESULT,
    player1: { id: p1.id, name: p1.name, hand: hand1 },
    player2: { id: p2.id, name: p2.name, hand: hand2 },
    winner: winnerId,
    result: result,
  };

  // ルーム全体に通知（全員がじゃんけんの発生を見られる）
  room.broadcast(resultData);

  // 各プレイヤーに個別のカード情報を送信
  p1.send({ type: S2C.YOUR_CARDS, cards: p1.toPrivateCardData() });
  p2.send({ type: S2C.YOUR_CARDS, cards: p2.toPrivateCardData() });

  return { result, winnerId, hand1, hand2 };
}
