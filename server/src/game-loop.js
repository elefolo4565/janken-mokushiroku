import { S2C, COMMANDS } from './protocol.js';
import { CollisionSystem } from './collision.js';
import { TradeManager } from './trade.js';
import { BattleZoneManager } from './battle-zone.js';

const TICK_RATE = 20; // 20 ticks/sec
const TICK_INTERVAL = 1000 / TICK_RATE;
const GOAL_GATE = { x: 400, y: 50, radius: 40 }; // フィールド上部中央

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
  }

  start() {
    // プレイヤーの初期配置（円形に配置）
    const players = Array.from(this.room.players.values());
    const cx = this.settings.fieldWidth / 2;
    const cy = this.settings.fieldHeight / 2;
    const spawnRadius = Math.min(this.settings.fieldWidth, this.settings.fieldHeight) * 0.35;

    players.forEach((player, i) => {
      const angle = (2 * Math.PI * i) / players.length;
      const sx = cx + Math.cos(angle) * spawnRadius;
      const sy = cy + Math.sin(angle) * spawnRadius;
      player.initForGame(this.settings, sx, sy);
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

    // 1. プレイヤー位置更新（ゾーンマッチ中は移動停止）
    for (const player of players.values()) {
      if (!player.alive || player.cleared) continue;
      if (player.zoneMatchedWith !== null) continue;

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
      (p) => p.zoneMatchedWith === null
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
      (p) => p.zoneMatchedWith === null
    );

    // 6. ゴールゲート判定（ゾーンマッチ中はスキップ）
    for (const player of players.values()) {
      if (!player.alive || player.cleared) continue;
      if (!player.canGoal) continue;
      if (player.zoneMatchedWith !== null) continue;

      const dx = player.x - GOAL_GATE.x;
      const dy = player.y - GOAL_GATE.y;
      if (Math.sqrt(dx * dx + dy * dy) < GOAL_GATE.radius + this.settings.playerRadius) {
        player.cleared = true;
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
      },
    });
  }

  onZoneCancelled(event) {
    const zone = event.zone;
    if (!zone.matchedPair) return;

    const p1 = this.room.players.get(zone.matchedPair.p1Id);
    const p2 = this.room.players.get(zone.matchedPair.p2Id);

    this.zoneManager.clearZone(zone, p1, p2);

    // 両者をゾーンから3キャラ分離れた位置に強制移動
    this._ejectFromZone(zone, p1, p2);

    if (p1) p1.send({ type: S2C.ZONE_CANCELLED });
    if (p2) p2.send({ type: S2C.ZONE_CANCELLED });
  }

  onZoneTimeout(event) {
    this.onZoneCancelled(event);
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

      if (other) other.send({ type: S2C.ZONE_CANCELLED });
      player.send({ type: S2C.ZONE_CANCELLED });
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
    const ejectDist = this.settings.playerRadius * 2 * 3; // 3キャラ分
    const r = this.settings.playerRadius;
    const fw = this.settings.fieldWidth;
    const fh = this.settings.fieldHeight;

    for (const p of [p1, p2]) {
      if (!p || !p.alive) continue;

      // プレイヤーからゾーン中心への方向ベクトル
      let dx = p.x - zone.x;
      let dy = p.y - zone.y;
      const len = Math.sqrt(dx * dx + dy * dy);

      if (len > 0.1) {
        // ゾーン中心から外向きに飛ばす
        dx = dx / len;
        dy = dy / len;
      } else {
        // ゾーン中心にぴったり重なっている場合はランダム方向
        const angle = Math.random() * Math.PI * 2;
        dx = Math.cos(angle);
        dy = Math.sin(angle);
      }

      p.x = zone.x + dx * (zone.radius + ejectDist);
      p.y = zone.y + dy * (zone.radius + ejectDist);

      // フィールド境界クランプ
      p.x = Math.max(r, Math.min(fw - r, p.x));
      p.y = Math.max(r, Math.min(fh - r, p.y));
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

    // ゾーンマッチ中ならキャンセル
    if (player.inZoneId) {
      const zone = this.zoneManager.findZoneById(player.inZoneId);
      if (zone && zone.matchedPair) {
        const otherId = zone.matchedPair.p1Id === playerId
          ? zone.matchedPair.p2Id
          : zone.matchedPair.p1Id;
        const other = this.room.players.get(otherId);
        this.zoneManager.clearZone(zone, player, other);
        if (other) other.send({ type: S2C.ZONE_CANCELLED });
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

    this.room.broadcast({
      type: S2C.GAME_OVER,
      results,
    });

    // ルームの状態をリセット
    this.room.state = 'waiting';
    this.room.gameLoop = null;
  }
}
