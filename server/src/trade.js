import { S2C, COMMANDS } from './protocol.js';

/**
 * 取引セッション管理
 */
export class TradeSession {
  constructor(player1, player2) {
    this.player1 = player1;
    this.player2 = player2;
    this.offer1 = null; // player1の提案
    this.offer2 = null; // player2の提案（応答）
    this.state = 'pending'; // pending | offered | completed | cancelled
  }
}

export class TradeManager {
  constructor() {
    this.activeTrades = new Map(); // "id1:id2" -> TradeSession
  }

  /**
   * 取引セッションを開始
   */
  startTrade(p1, p2) {
    const key = this._pairKey(p1.id, p2.id);
    if (this.activeTrades.has(key)) return;

    const session = new TradeSession(p1, p2);
    this.activeTrades.set(key, session);

    // 両者に取引開始を通知
    p1.send({
      type: S2C.TRADE_REQUEST,
      partnerId: p2.id,
      partnerName: p2.name,
      partnerStars: p2.stars,
      partnerGold: p2.gold,
      partnerCardsLeft: p2.totalCards,
    });
    p2.send({
      type: S2C.TRADE_REQUEST,
      partnerId: p1.id,
      partnerName: p1.name,
      partnerStars: p1.stars,
      partnerGold: p1.gold,
      partnerCardsLeft: p1.totalCards,
    });
  }

  /**
   * 取引提案を処理
   * offer: { cards: { rock: N, scissors: N, paper: N }, stars: N }
   * request: { cards: { rock: N, scissors: N, paper: N }, stars: N }
   */
  handleOffer(playerId, offer, request) {
    const session = this._findSession(playerId);
    if (!session) return;

    const isPlayer1 = session.player1.id === playerId;
    const offerer = isPlayer1 ? session.player1 : session.player2;
    const partner = isPlayer1 ? session.player2 : session.player1;

    // 提案を保存
    if (isPlayer1) {
      session.offer1 = { offer, request };
    } else {
      session.offer2 = { offer, request };
    }

    // 相手に提案を通知
    partner.send({
      type: S2C.TRADE_REQUEST,
      partnerId: offerer.id,
      partnerName: offerer.name,
      offer,
      request,
    });

    session.state = 'offered';
  }

  /**
   * 取引応答を処理
   */
  handleRespond(playerId, accept) {
    const session = this._findSession(playerId);
    if (!session) return;

    const key = this._pairKey(session.player1.id, session.player2.id);

    if (!accept) {
      // 取引キャンセル
      session.player1.send({ type: S2C.TRADE_RESULT, success: false, message: '取引がキャンセルされました' });
      session.player2.send({ type: S2C.TRADE_RESULT, success: false, message: '取引がキャンセルされました' });
      this.activeTrades.delete(key);
      return;
    }

    // 取引を実行（最後に提案された内容を適用）
    const lastOffer = session.offer2 || session.offer1;
    if (!lastOffer) {
      this.activeTrades.delete(key);
      return;
    }

    const isPlayer1Offerer = session.offer1 && !session.offer2;
    const offerer = isPlayer1Offerer ? session.player1 : session.player2;
    const accepter = isPlayer1Offerer ? session.player2 : session.player1;

    const { offer, request } = lastOffer;

    // バリデーション: 提案者がofferを持っているか
    if (!this._canAfford(offerer, offer) || !this._canAfford(accepter, request)) {
      session.player1.send({ type: S2C.TRADE_RESULT, success: false, message: 'リソースが不足しています' });
      session.player2.send({ type: S2C.TRADE_RESULT, success: false, message: 'リソースが不足しています' });
      this.activeTrades.delete(key);
      return;
    }

    // 交換実行
    this._transferResources(offerer, accepter, offer);
    this._transferResources(accepter, offerer, request);

    session.player1.send({ type: S2C.TRADE_RESULT, success: true, message: '取引が成立しました' });
    session.player2.send({ type: S2C.TRADE_RESULT, success: true, message: '取引が成立しました' });

    // カード・ゴールド情報を更新
    session.player1.send({ type: S2C.YOUR_CARDS, cards: session.player1.toPrivateCardData() });
    session.player2.send({ type: S2C.YOUR_CARDS, cards: session.player2.toPrivateCardData() });
    session.player1.send({ type: S2C.YOUR_GOLD, gold: session.player1.gold });
    session.player2.send({ type: S2C.YOUR_GOLD, gold: session.player2.gold });

    this.activeTrades.delete(key);
  }

  cancelTradesForPlayer(playerId) {
    for (const [key, session] of this.activeTrades) {
      if (session.player1.id === playerId || session.player2.id === playerId) {
        const partner = session.player1.id === playerId ? session.player2 : session.player1;
        partner.send({ type: S2C.TRADE_RESULT, success: false, message: '相手が取引を離脱しました' });
        this.activeTrades.delete(key);
      }
    }
  }

  _canAfford(player, resources) {
    if (resources.stars && player.stars < resources.stars) return false;
    if (resources.gold && player.gold < resources.gold) return false;
    if (resources.cards) {
      for (const [type, count] of Object.entries(resources.cards)) {
        if (count > 0 && (player.cards[type] || 0) < count) return false;
      }
    }
    return true;
  }

  _transferResources(from, to, resources) {
    if (resources.stars) {
      from.removeStars(resources.stars);
      to.addStars(resources.stars);
    }
    if (resources.gold) {
      from.removeGold(resources.gold);
      to.addGold(resources.gold);
    }
    if (resources.cards) {
      for (const [type, count] of Object.entries(resources.cards)) {
        for (let i = 0; i < count; i++) {
          if (from.cards[type] > 0) {
            from.cards[type]--;
            to.cards[type]++;
          }
        }
      }
    }
  }

  _findSession(playerId) {
    for (const session of this.activeTrades.values()) {
      if (session.player1.id === playerId || session.player2.id === playerId) {
        return session;
      }
    }
    return null;
  }

  _pairKey(id1, id2) {
    return id1 < id2 ? `${id1}:${id2}` : `${id2}:${id1}`;
  }
}
