import { S2C, COMMANDS } from './protocol.js';
import { CollisionSystem } from './collision.js';
import { TradeManager } from './trade.js';
import { BattleZoneManager } from './battle-zone.js';
import { BattleLogger } from './battle-logger.js';

const TICK_RATE = 20; // 20 ticks/sec
const TICK_INTERVAL = 1000 / TICK_RATE;
const GOAL_GATE = { x: 400, y: 50, radius: 40 }; // フィールド上部中央
const JUMP_TICKS = 40; // ジャンプ所要時間: 2秒 × 20tick/sec

export class GameLoop {
  constructor(room) {
    this.room = room;
    this.settings = room.settings;
    this.collision = new CollisionSystem();
    this.tradeManager = new TradeManager();
    this.zoneManager = new BattleZoneManager(room.settings);
    this.tick = 0;
    this.timeLeft = this.settings.timeLimit;
    this.running = false;
    this.intervalId = null;
    this.logger = new BattleLogger(room.id, room.name);
  }

  start() {
    // プレイヤーの初期配置（フィールド最下部に横一列）
    const players = Array.from(this.room.players.values());
    const r = this.settings.playerRadius;
    const fw = this.settings.fieldWidth;
    const fh = this.settings.fieldHeight;
    const spawnY = fh - r;

    players.forEach((player, i) => {
      const sx = r + (fw - r * 2) * (i + 1) / (players.length + 1);
      player.initForGame(this.settings, sx, spawnY);
      player.setVictoryStars(this.settings.victoryStars);
      player.setVictoryGold(this.settings.victoryGold || 0);
    });

    // ゲーム開始を通知
    this.room.broadcast({
      type: S2C.GAME_STARTED,
      settings: {
        fieldWidth: this.settings.fieldWidth,
        fieldHeight: this.settings.fieldHeight,
        timeLimit: this.settings.timeLimit,
        victoryStars: this.settings.victoryStars,
        victoryGold: this.settings.victoryGold || 0,
        cardsPerType: this.settings.cardsPerType,
        initialGold: this.settings.initialGold || 0,
        goalGate: GOAL_GATE,
        battleZones: this.zoneManager.getZonesPublicData(),
      },
      players: players.map(p => ({
        id: p.id,
        name: p.name,
        x: p.x,
        y: p.y,
        stars: p.stars,
      })),
    });

    // 各プレイヤーに初期カード・ゴールド情報を送信
    for (const player of players) {
      player.send({ type: S2C.YOUR_CARDS, cards: player.toPrivateCardData() });
      player.send({ type: S2C.YOUR_GOLD, gold: player.gold });
    }

    this.logger.logGameStart(
      players.map(p => ({ name: p.name, id: p.id, isAI: !!p.isAI })),
      this.settings
    );

    this.running = true;
    this.intervalId = setInterval(() => this.update(), TICK_INTERVAL);
  }

  stop() {
    this.running = false;
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  update() {
    if (!this.running) return;

    const dt = TICK_INTERVAL / 1000; // 秒単位
    this.tick++;

    // 時間経過
    this.timeLeft -= dt;
    if (this.timeLeft <= 0) {
      this.timeLeft = 0;
      this.endGame();
      return;
    }

    const players = this.room.players;

    // 0. AI更新（ゾーンマッチ中はゾーン内判断のみ）
    for (const [aiId, controller] of this.room.aiControllers) {
      const aiPlayer = players.get(aiId);
      if (aiPlayer && aiPlayer.alive && !aiPlayer.cleared) {
        const action = controller.update(players, this.settings, dt, this.zoneManager);
        // AIのゾーン離脱処理
        if (action && action.type === 'leave') {
          this.handleZoneLeave(aiPlayer);
        }
      }
    }

    // 0.5. ジャンプ終了チェック
    for (const player of players.values()) {
      if (player.jumping && this.tick >= player.jumpEndTick) {
        player.jumping = false;
      }
    }

    // 1. プレイヤー位置更新（ゾーンマッチ中・ジャンプ中は移動停止）
    for (const player of players.values()) {
      if (!player.alive || player.cleared) continue;
      if (player.zoneMatchedWith !== null) continue;
      if (player.jumping) continue;

      const speed = this.settings.playerSpeed;
      player.x += player.inputDx * speed * dt;
      player.y += player.inputDy * speed * dt;

      // フィールド境界チェック
      const r = this.settings.playerRadius;
      player.x = Math.max(r, Math.min(this.settings.fieldWidth - r, player.x));
      player.y = Math.max(r, Math.min(this.settings.fieldHeight - r, player.y));
    }

    // 2. 衝突クールダウン更新
    this.collision.updateCooldowns(dt);

    // 3. ゾーン更新（進入/離脱/マッチング/タイムアウト検出）
    const zoneEvents = this.zoneManager.update(players, dt);
    this.handleZoneEvents(zoneEvents);

    // 4. 衝突検出（交渉モード同士のみ → 取引開始）
    const collisions = this.collision.detectCollisions(
      players, this.settings.playerRadius,
      (p) => p.zoneMatchedWith === null && !p.jumping
    );
    for (const { p1, p2 } of collisions) {
      if (p1.command === COMMANDS.NEGOTIATE && p2.command === COMMANDS.NEGOTIATE) {
        this.tradeManager.startTrade(p1, p2);
        this.collision.setCooldown(p1.id, p2.id, this.settings.collisionCooldown);
      }
    }

    // 5. 押し出し処理（ゾーンマッチ中を除外）
    this.collision.resolveOverlaps(
      players, this.settings.playerRadius,
      (p) => p.zoneMatchedWith === null && !p.jumping
    );

    // 6. ゴールゲート判定（ゾーンマッチ中はスキップ）
    for (const player of players.values()) {
      if (!player.alive || player.cleared) continue;
      if (!player.canGoal) continue;
      if (player.zoneMatchedWith !== null) continue;
      if (player.jumping) continue;

      const dx = player.x - GOAL_GATE.x;
      const dy = player.y - GOAL_GATE.y;
      if (Math.sqrt(dx * dx + dy * dy) < GOAL_GATE.radius + this.settings.playerRadius) {
        player.cleared = true;
        this.logger.logCleared(player.name);
        this.room.broadcast({
          type: S2C.PLAYER_CLEARED,
          playerId: player.id,
          playerName: player.name,
        });
      }
    }

    // 7. ゲーム終了チェック（全員がゴールまたは退場）
    const activePlayers = Array.from(players.values()).filter(p => p.alive && !p.cleared);
    if (activePlayers.length === 0) {
      this.endGame();
      return;
    }

    // 7.5. 敗北チェック: 対戦相手がいない（他全員ゴールか退場）のにクリア条件未達成
    if (activePlayers.length === 1 && !activePlayers[0].canGoal) {
      this.eliminatePlayer(activePlayers[0].id, 'no_opponents');
      this.endGame();
      return;
    }

    // 8. 状態ブロードキャスト
    this.broadcastState();
  }

  // --- ゾーンイベント処理 ---

  handleZoneEvents(events) {
    for (const event of events) {
      switch (event.type) {
        case 'zone_matched':
          this.onZoneMatched(event);
          break;
        case 'zone_cancelled':
          this.onZoneCancelled(event);
          break;
        case 'zone_timeout':
          this.onZoneTimeout(event);
          break;
        case 'zone_both_ready':
          this.onZoneBothReady(event);
          break;
      }
    }
  }

  onZoneMatched(event) {
    const p1 = this.room.players.get(event.p1Id);
    const p2 = this.room.players.get(event.p2Id);
    if (!p1 || !p2) return;

    p1.zoneMatchedWith = p2.id;
    p2.zoneMatchedWith = p1.id;
    p1.inputDx = 0;
    p1.inputDy = 0;
    p2.inputDx = 0;
    p2.inputDy = 0;

    this.zoneManager.startMatch(event.zone, p1.id, p2.id);
    this.logger.logZoneMatch(p1.name, p2.name, event.zone.id);

    // 各プレイヤーに相手情報を送信
    p1.send({
      type: S2C.ZONE_MATCH,
      zoneId: event.zone.id,
      opponent: {
        id: p2.id,
        name: p2.name,
        stars: p2.stars,
        gold: p2.gold,
        cardsLeft: p2.totalCards,
        avatarId: p2.avatarId,
      },
    });
    p2.send({
      type: S2C.ZONE_MATCH,
      zoneId: event.zone.id,
      opponent: {
        id: p1.id,
        name: p1.name,
        stars: p1.stars,
        gold: p1.gold,
        cardsLeft: p1.totalCards,
        avatarId: p1.avatarId,
      },
    });
  }

  onZoneCancelled(event, reason = 'opponent_left') {
    const zone = event.zone;
    if (!zone.matchedPair) return;

    const p1 = this.room.players.get(zone.matchedPair.p1Id);
    const p2 = this.room.players.get(zone.matchedPair.p2Id);

    const names = [p1?.name, p2?.name].filter(Boolean);
    this.logger.logZoneCancelled('cancelled', names);

    this.zoneManager.clearZone(zone, p1, p2);

    // 両者をゾーンから3キャラ分離れた位置に強制移動
    this._ejectFromZone(zone, p1, p2);

    if (p1) p1.send({ type: S2C.ZONE_CANCELLED, reason });
    if (p2) p2.send({ type: S2C.ZONE_CANCELLED, reason });
  }

  onZoneTimeout(event) {
    const zone = event.zone;
    if (zone.matchedPair) {
      const p1 = this.room.players.get(zone.matchedPair.p1Id);
      const p2 = this.room.players.get(zone.matchedPair.p2Id);
      const names = [p1?.name, p2?.name].filter(Boolean);
      this.logger.logZoneCancelled('timeout', names);
    }
    this.onZoneCancelled(event, 'timeout');
  }

  onZoneBothReady(event) {
    const zone = event.zone;
    const p1 = this.room.players.get(event.p1Id);
    const p2 = this.room.players.get(event.p2Id);
    if (!p1 || !p2) return;

    // じゃんけん判定
    const result = this.zoneManager.resolveFight(p1, p2);

    // マッチ状態をリセット
    this.zoneManager.clearZone(zone, p1, p2);

    // 両者をゾーンから3キャラ分離れた位置に強制移動
    this._ejectFromZone(zone, p1, p2);

    // ログ記録
    this.logger.logZoneFightResult({
      p1Name: p1.name, p1Hand: result.hand1,
      p2Name: p2.name, p2Hand: result.hand2,
      winnerId: result.winnerId,
      winnerName: result.winnerId === p1.id ? p1.name : result.winnerId === p2.id ? p2.name : null,
      outcome: result.result,
      bet: result.actualBet,
    });

    // 結果をルーム全体にブロードキャスト
    this.room.broadcast({
      type: S2C.ZONE_FIGHT_RESULT,
      player1: { id: p1.id, name: p1.name, hand: result.hand1 },
      player2: { id: p2.id, name: p2.name, hand: result.hand2 },
      winner: result.winnerId,
      result: result.result,
      bet: result.actualBet,
    });

    // カード・ゴールド情報を個別送信
    for (const p of [p1, p2]) {
      p.send({ type: S2C.YOUR_CARDS, cards: p.toPrivateCardData() });
      p.send({ type: S2C.YOUR_GOLD, gold: p.gold });
    }

    // 星0チェック
    if (p1.stars === 0) this.eliminatePlayer(p1.id, 'no_stars');
    if (p2.stars === 0) this.eliminatePlayer(p2.id, 'no_stars');
  }

  // --- ゾーン勝負ハンドラ（connection-handlerから呼ばれる） ---

  handleZoneFight(player, hand, bet) {
    if (!player.inZoneId || !player.zoneMatchedWith) return;

    const zone = this.zoneManager.findZoneById(player.inZoneId);
    if (!zone || !zone.matchedPair) return;

    // バリデーション
    if (!player.hasCard(hand)) {
      player.send({ type: S2C.ERROR, message: 'そのカードは残っていません' });
      return;
    }
    if (bet < 0 || bet > player.gold) {
      player.send({ type: S2C.ERROR, message: '賭け金が不正です' });
      return;
    }

    player.zoneFightChoice = { hand, bet };
    // 両者揃いチェックはzoneManager.update()内のイベント検出で行う
  }

  handleZoneLeave(player) {
    if (!player.inZoneId) return;

    const zone = this.zoneManager.findZoneById(player.inZoneId);
    if (!zone) return;

    if (zone.matchedPair) {
      const otherId = zone.matchedPair.p1Id === player.id
        ? zone.matchedPair.p2Id
        : zone.matchedPair.p1Id;
      const other = this.room.players.get(otherId);

      this.zoneManager.clearZone(zone, player, other);

      // 両者をゾーンから3キャラ分離れた位置に強制移動
      this._ejectFromZone(zone, player, other);

      if (other) other.send({ type: S2C.ZONE_CANCELLED, reason: 'opponent_left' });
      player.send({ type: S2C.ZONE_CANCELLED, reason: 'self_left' });
    }

    // ゾーンから離脱
    zone.playerIds = zone.playerIds.filter(id => id !== player.id);
    player.inZoneId = null;
    this.zoneManager._updateZoneState(zone);
  }

  // --- ゾーン退出時の強制移動 ---

  /**
   * 勝負終了後、両プレイヤーをゾーン中心から3キャラ分離れた位置にテレポート
   */
  _ejectFromZone(zone, p1, p2) {
    const r = this.settings.playerRadius;
    const fw = this.settings.fieldWidth;
    const fh = this.settings.fieldHeight;

    for (const p of [p1, p2]) {
      if (!p || !p.alive) continue;

      // スタート位置（フィールド最下部）に戻す。横位置はランダム
      p.x = r + Math.random() * (fw - r * 2);
      p.y = fh - r;

      // ジャンプ状態開始
      p.jumping = true;
      p.jumpEndTick = this.tick + JUMP_TICKS;
    }
  }

  // --- 状態ブロードキャスト ---

  broadcastState() {
    const players = this.room.players;

    // カード総数の計算
    const cardTotals = { rock: 0, scissors: 0, paper: 0 };
    for (const player of players.values()) {
      if (player.alive) {
        cardTotals.rock += player.cards.rock;
        cardTotals.scissors += player.cards.scissors;
        cardTotals.paper += player.cards.paper;
      }
    }

    const allPlayersData = Array.from(players.values()).map(p => p.toPublicData());
    const zonesData = this.zoneManager.getZonesPublicData();

    // 各プレイヤーに個別送信（negotiateのみマスク対象）
    for (const player of players.values()) {
      const maskedPlayers = allPlayersData.map(pd => {
        if (pd.id === player.id) return pd;
        // 手のマスクは不要（フィールド上で手を出さないため）
        // negotiateはそのまま表示
        const cmd = pd.command;
        if (cmd === 'rock' || cmd === 'scissors' || cmd === 'paper') {
          return { ...pd, command: 'hand' };
        }
        return pd;
      });

      player.send({
        type: S2C.STATE,
        tick: this.tick,
        timeLeft: Math.ceil(this.timeLeft),
        cardTotals,
        goalGate: GOAL_GATE,
        players: maskedPlayers,
        yourCards: player.toPrivateCardData(),
        yourGold: player.gold,
        zones: zonesData,
      });
    }
  }

  // --- プレイヤー退場 ---

  eliminatePlayer(playerId, reason) {
    const player = this.room.players.get(playerId);
    if (!player || !player.alive) return;

    player.alive = false;
    this.logger.logElimination(player.name, reason);

    // ゾーンマッチ中ならキャンセル
    if (player.inZoneId) {
      const zone = this.zoneManager.findZoneById(player.inZoneId);
      if (zone && zone.matchedPair) {
        const otherId = zone.matchedPair.p1Id === playerId
          ? zone.matchedPair.p2Id
          : zone.matchedPair.p1Id;
        const other = this.room.players.get(otherId);
        this.zoneManager.clearZone(zone, player, other);
        if (other) other.send({ type: S2C.ZONE_CANCELLED, reason: 'opponent_eliminated' });
      }
      if (zone) {
        zone.playerIds = zone.playerIds.filter(id => id !== playerId);
        this.zoneManager._updateZoneState(zone);
      }
      player.inZoneId = null;
    }

    this.tradeManager.cancelTradesForPlayer(playerId);

    this.room.broadcast({
      type: S2C.PLAYER_ELIMINATED,
      playerId: player.id,
      playerName: player.name,
      reason,
    });
  }

  // --- ゲーム終了 ---

  endGame() {
    this.stop();

    const players = Array.from(this.room.players.values());
    const results = players.map(p => ({
      id: p.id,
      name: p.name,
      stars: p.stars,
      gold: p.gold,
      cleared: p.cleared,
      alive: p.alive,
      cardsLeft: p.totalCards,
      isAI: !!p.isAI,
    }));

    // クリアした人を先に、星の多い順、ゴールドの多い順でソート
    results.sort((a, b) => {
      if (a.cleared !== b.cleared) return a.cleared ? -1 : 1;
      if (a.alive !== b.alive) return a.alive ? -1 : 1;
      if (b.stars !== a.stars) return b.stars - a.stars;
      return b.gold - a.gold;
    });

    this.logger.logGameEnd(results);

    this.room.broadcast({
      type: S2C.GAME_OVER,
      results,
    });

    // ルームの状態をリセット
    this.room.state = 'waiting';
    this.room.gameLoop = null;
  }
}
