import { COMMANDS, DEFAULT_SETTINGS } from './protocol.js';

export class PlayerState {
  constructor(id, ws, name = '') {
    this.id = id;
    this.ws = ws;
    this.name = name;
    this.roomId = null;
    this.isAI = false;

    // ゲーム中の状態
    this.x = 0;
    this.y = 0;
    this.inputDx = 0;
    this.inputDy = 0;
    this.command = COMMANDS.NONE;
    this.alive = true;
    this.cleared = false;

    // 勝負状態（旧: battling/battlePartnerId は廃止）
    this.battling = false;
    this.battlePartnerId = null;

    // カード・星・ゴールド
    this.stars = 0;
    this.cards = { rock: 0, scissors: 0, paper: 0 };
    this.gold = 0;

    // ゾーン状態
    this.inZoneId = null;           // 現在いるゾーンID (null = いない)
    this.zoneMatchedWith = null;    // ゾーン内でマッチした相手ID
    this.zoneFightChoice = null;    // { hand: 'rock', bet: 100 } or null
  }

  initForGame(settings, spawnX, spawnY) {
    this.x = spawnX;
    this.y = spawnY;
    this.inputDx = 0;
    this.inputDy = 0;
    this.command = COMMANDS.NONE;
    this.alive = true;
    this.cleared = false;
    this.battling = false;
    this.battlePartnerId = null;
    this.stars = settings.initialStars;
    this.cards = {
      rock: settings.cardsPerType,
      scissors: settings.cardsPerType,
      paper: settings.cardsPerType,
    };
    this.gold = settings.initialGold || 0;
    this.inZoneId = null;
    this.zoneMatchedWith = null;
    this.zoneFightChoice = null;
  }

  get totalCards() {
    return this.cards.rock + this.cards.scissors + this.cards.paper;
  }

  get canGoal() {
    return this.totalCards === 0
      && this.stars >= this._victoryStars
      && this.gold >= (this._victoryGold || 0);
  }

  setVictoryStars(n) {
    this._victoryStars = n;
  }

  setVictoryGold(n) {
    this._victoryGold = n;
  }

  addGold(n) {
    this.gold += n;
  }

  removeGold(n) {
    this.gold = Math.max(0, this.gold - n);
  }

  hasCard(type) {
    return this.cards[type] > 0;
  }

  useCard(type) {
    if (this.cards[type] > 0) {
      this.cards[type]--;
      return true;
    }
    return false;
  }

  addStars(n) {
    this.stars += n;
  }

  removeStars(n) {
    this.stars = Math.max(0, this.stars - n);
  }

  /** ブロードキャスト用の公開情報 */
  toPublicData() {
    return {
      id: this.id,
      name: this.name,
      x: Math.round(this.x * 10) / 10,
      y: Math.round(this.y * 10) / 10,
      command: this.command,
      stars: this.stars,
      gold: this.gold,
      cardsLeft: this.totalCards,
      alive: this.alive,
      cleared: this.cleared,
      battling: this.battling,
      inZoneId: this.inZoneId,
    };
  }

  /** 本人専用のカード内訳情報 */
  toPrivateCardData() {
    return {
      rock: this.cards.rock,
      scissors: this.cards.scissors,
      paper: this.cards.paper,
    };
  }

  send(data) {
    if (this.ws && this.ws.readyState === 1) {
      this.ws.send(JSON.stringify(data));
    }
  }
}
