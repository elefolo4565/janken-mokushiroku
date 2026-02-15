import { v4 as uuidv4 } from 'uuid';
import { COMMANDS } from './protocol.js';
import { PlayerState } from './player-state.js';

const AI_NAMES = [
  'カイジBot', '利根川Bot', '兵藤Bot', '大槻Bot', '佐原Bot',
  '安藤Bot', '石田Bot', '北見Bot', '前田Bot', '船井Bot',
  '坂崎Bot', '三好Bot', '村岡Bot', '渡辺Bot', '宮本Bot',
];

let aiNameIndex = 0;

/**
 * AIプレイヤーの思考・行動を制御するコントローラー（ゾーン制対応版）
 */
export class AIController {
  constructor(playerState) {
    this.player = playerState;
    this.player.isAI = true;

    // AI性格パラメータ (0.0〜1.0)
    this.aggression = 0.3 + Math.random() * 0.5;   // 攻撃性: 高いほど積極的にゾーンに入る
    this.caution = 0.2 + Math.random() * 0.5;       // 慎重さ: 高いほど不利な時にゾーン回避
    this.smartness = 0.3 + Math.random() * 0.6;     // 賢さ: 高いほど戦略的

    // 行動状態
    this._targetZoneId = null;   // 向かうゾーンID
    this._thinkTimer = 0;
    this._thinkInterval = 0.5 + Math.random() * 1.0;
    this._wanderAngle = Math.random() * Math.PI * 2;
    this._zoneDecisionMade = false; // ゾーンマッチ中の判断済みフラグ
  }

  /**
   * 毎tick呼ばれるAI更新処理
   * @returns {object|null} アクション（{ type: 'leave' } でゾーン離脱）
   */
  update(allPlayers, settings, dt, zoneManager) {
    if (!this.player.alive || this.player.cleared) {
      this.player.inputDx = 0;
      this.player.inputDy = 0;
      return null;
    }

    const me = this.player;

    // ゾーンマッチ中の処理
    if (me.zoneMatchedWith !== null) {
      return this._handleZoneMatch(allPlayers, settings, zoneManager);
    }

    // マッチ解除されたらフラグリセット
    this._zoneDecisionMade = false;

    this._thinkTimer -= dt;
    if (this._thinkTimer <= 0) {
      this._thinkTimer = this._thinkInterval;
      this._think(allPlayers, settings, zoneManager);
    }

    this._move(allPlayers, settings, zoneManager);
    return null;
  }

  /**
   * ゾーンマッチ中の判断処理
   */
  _handleZoneMatch(allPlayers, settings, zoneManager) {
    const me = this.player;

    // 既に判断済み（選択送信済み or 離脱判断済み）
    if (this._zoneDecisionMade) return null;
    this._zoneDecisionMade = true;

    const opponent = allPlayers.get(me.zoneMatchedWith);
    if (!opponent) return { type: 'leave' };

    // 勝負するかどうか判断
    if (!this._shouldFight(opponent)) {
      return { type: 'leave' };
    }

    // 手を選択
    const hand = this._chooseHand();
    if (!hand) return { type: 'leave' };

    // 賭け金を決定
    const bet = this._chooseBet(opponent);

    me.zoneFightChoice = { hand, bet };
    return null;
  }

  /**
   * 勝負すべきか判断
   */
  _shouldFight(opponent) {
    const me = this.player;

    // カードがなければ勝負できない
    if (me.totalCards === 0) return false;

    // 星が1以下で慎重なAIは勝負を避ける
    if (me.stars <= 1 && Math.random() < this.caution) return false;

    // 攻撃的なAIほど勝負を好む
    if (Math.random() < this.aggression) return true;

    // デフォルト: 50%の確率で勝負
    return Math.random() < 0.5;
  }

  /**
   * 出す手を選択する（ゾーン勝負用）
   */
  _chooseHand() {
    const me = this.player;
    const availableHands = [];
    if (me.cards.rock > 0) availableHands.push('rock');
    if (me.cards.scissors > 0) availableHands.push('scissors');
    if (me.cards.paper > 0) availableHands.push('paper');

    if (availableHands.length === 0) return null;

    // 賢いAIは残りカードのバランスを考えて手を選ぶ
    if (Math.random() < this.smartness) {
      let bestHand = availableHands[0];
      let maxCount = 0;
      for (const hand of availableHands) {
        if (me.cards[hand] > maxCount) {
          maxCount = me.cards[hand];
          bestHand = hand;
        }
      }
      return bestHand;
    }

    // ランダムに手を選ぶ（残りカードが多い手を優先）
    const weighted = [];
    for (const hand of availableHands) {
      const count = me.cards[hand] || 0;
      for (let i = 0; i < count; i++) {
        weighted.push(hand);
      }
    }
    return weighted[Math.floor(Math.random() * weighted.length)] || availableHands[0];
  }

  /**
   * 賭け金を決定
   */
  _chooseBet(opponent) {
    const me = this.player;
    const maxBet = me.gold;
    if (maxBet <= 0) return 0;

    // 攻撃的なAIは多く賭ける
    const betRatio = 0.1 + this.aggression * 0.3;
    // 慎重なAIは控えめ
    const cautionReduction = this.caution * 0.2;
    const finalRatio = Math.max(0.05, betRatio - cautionReduction);

    let bet = Math.floor(maxBet * finalRatio);
    // 最低でも10は賭ける（持っていれば）
    bet = Math.max(Math.min(10, maxBet), bet);
    // 10刻みに丸める
    bet = Math.floor(bet / 10) * 10;

    return Math.min(bet, maxBet);
  }

  /**
   * 戦略的思考（定期実行）
   */
  _think(allPlayers, settings, zoneManager) {
    const me = this.player;

    // カードが全て使い切り + 勝利条件 → ゴールに向かう
    if (me.totalCards === 0 && me.canGoal) {
      me.command = COMMANDS.NONE;
      this._targetZoneId = null;
      return;
    }

    // カードがない場合はうろうろする（ゴール条件未達）
    if (me.totalCards === 0) {
      me.command = COMMANDS.NONE;
      this._targetZoneId = null;
      return;
    }

    // ゾーン選択: 空 or 1人待ちのゾーンを狙う
    this._chooseTargetZone(zoneManager, allPlayers);

    // フィールド上のコマンドはnoneに（ゾーン内でのみ手を出す）
    me.command = COMMANDS.NONE;
  }

  /**
   * 目標ゾーンを選択
   */
  _chooseTargetZone(zoneManager, allPlayers) {
    const me = this.player;
    const zones = zoneManager.zones;
    if (!zones || zones.length === 0) {
      this._targetZoneId = null;
      return;
    }

    // 候補ゾーンを評価
    const candidates = [];
    for (const zone of zones) {
      // マッチ済みのゾーンはスキップ
      if (zone.matchedPair) continue;
      // 2人以上いるゾーンはスキップ
      if (zone.playerIds.length >= 2) continue;

      const dx = zone.x - me.x;
      const dy = zone.y - me.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      let score = 0;
      if (zone.playerIds.length === 0) {
        // 空のゾーン: 普通の優先度
        score = 100 - dist * 0.1;
      } else if (zone.playerIds.length === 1) {
        // 1人待ちゾーン: 攻撃的AIほど好む
        const waitingPlayer = allPlayers.get(zone.playerIds[0]);
        if (waitingPlayer && waitingPlayer.id !== me.id) {
          score = 200 + this.aggression * 100 - dist * 0.1;

          // 慎重なAIは星が少ない時に対戦を避ける
          if (me.stars <= 1 && Math.random() < this.caution) {
            score -= 200;
          }
        }
      }

      if (score > 0) {
        candidates.push({ zone, score });
      }
    }

    if (candidates.length === 0) {
      this._targetZoneId = null;
      return;
    }

    // スコアが高いゾーンを選ぶ（多少のランダム性あり）
    candidates.sort((a, b) => b.score - a.score);
    // 上位3つからランダムに選ぶ
    const top = candidates.slice(0, 3);
    const chosen = top[Math.floor(Math.random() * top.length)];
    this._targetZoneId = chosen.zone.id;
  }

  /**
   * 移動処理（毎tick）
   */
  _move(allPlayers, settings, zoneManager) {
    const me = this.player;
    let dx = 0;
    let dy = 0;

    // ゴール可能 → ゴールゲートへ向かう
    if (me.totalCards === 0 && me.canGoal) {
      const gx = settings.fieldWidth / 2;
      const gy = 50;
      dx = gx - me.x;
      dy = gy - me.y;
    }
    // ターゲットゾーンがある → そのゾーンへ向かう
    else if (this._targetZoneId && zoneManager) {
      const zone = zoneManager.findZoneById(this._targetZoneId);
      if (zone && zone.playerIds.length < 2 && !zone.matchedPair) {
        dx = zone.x - me.x;
        dy = zone.y - me.y;
        // ゾーンに十分近い場合は停止
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < zone.radius * 0.5) {
          dx = 0;
          dy = 0;
        }
      } else {
        this._targetZoneId = null;
      }
    }

    // ターゲットなし → ランダムうろうろ
    if (dx === 0 && dy === 0) {
      this._wanderAngle += (Math.random() - 0.5) * 0.5;
      dx = Math.cos(this._wanderAngle);
      dy = Math.sin(this._wanderAngle);

      // フィールド端に近い場合は中央方向に補正
      const margin = 100;
      if (me.x < margin) dx += 0.5;
      if (me.x > settings.fieldWidth - margin) dx -= 0.5;
      if (me.y < margin) dy += 0.5;
      if (me.y > settings.fieldHeight - margin) dy -= 0.5;
    }

    // 正規化
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      me.inputDx = dx / len;
      me.inputDy = dy / len;
    } else {
      me.inputDx = 0;
      me.inputDy = 0;
    }
  }

  // --- ユーティリティ ---

  _getAliveOpponents(allPlayers) {
    const results = [];
    for (const p of allPlayers.values()) {
      if (p.id !== this.player.id && p.alive && !p.cleared) {
        results.push(p);
      }
    }
    return results;
  }
}

/**
 * AIプレイヤーを作成する（WebSocket接続なし）
 */
export function createAIPlayer() {
  const id = 'ai-' + uuidv4().substring(0, 8);
  const name = AI_NAMES[aiNameIndex % AI_NAMES.length];
  aiNameIndex++;

  // ws=null のダミーPlayerState
  const player = new PlayerState(id, null, name);
  player.isAI = true;

  // send()をno-opにオーバーライド
  player.send = () => {};

  const controller = new AIController(player);
  return { player, controller };
}
