import { resolveJanken } from './janken.js';

export class BattleZone {
  constructor(id, x, y, radius) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.radius = radius;
    this.playerIds = [];         // ゾーン内プレイヤーID（最大2）
    this.matchedPair = null;     // { p1Id, p2Id, timer }
    this.state = 'empty';        // empty | waiting | matched | fighting
  }

  toPublicData() {
    return {
      id: this.id,
      x: this.x,
      y: this.y,
      radius: this.radius,
      state: this.state,
      playerIds: [...this.playerIds],
    };
  }
}

export class BattleZoneManager {
  constructor(settings) {
    this.zones = [];
    this.settings = settings;
    this._initZones(settings);
  }

  _initZones(settings) {
    const count = settings.battleZoneCount || 4;
    const fw = settings.fieldWidth;
    const fh = settings.fieldHeight;
    const radius = settings.battleZoneRadius || 60;

    // フィールドをグリッド状に均等分割して配置
    const cols = Math.ceil(Math.sqrt(count));
    const rows = Math.ceil(count / cols);
    const cellW = fw / (cols + 1);
    const cellH = fh / (rows + 1);

    for (let i = 0; i < count; i++) {
      const col = i % cols;
      const row = Math.floor(i / cols);
      const x = cellW * (col + 1);
      const y = cellH * (row + 1);
      this.zones.push(new BattleZone(`zone-${i}`, x, y, radius));
    }
  }

  /**
   * 毎tick呼ばれる: プレイヤー位置からゾーン入退場を検出
   * @returns {Array} 発生したイベントの配列
   */
  update(players, dt) {
    const events = [];

    for (const zone of this.zones) {
      // 1. ゾーン内プレイヤーの更新（離脱検出）
      const removedIds = [];
      zone.playerIds = zone.playerIds.filter(pid => {
        const p = players.get(pid);
        if (!p || !p.alive || p.cleared) {
          removedIds.push(pid);
          return false;
        }
        const dx = p.x - zone.x;
        const dy = p.y - zone.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist > zone.radius) {
          // ゾーンから離脱
          p.inZoneId = null;
          removedIds.push(pid);
          return false;
        }
        return true;
      });

      // 離脱者がマッチ中のペアにいる場合はキャンセル
      for (const rid of removedIds) {
        if (zone.matchedPair && (zone.matchedPair.p1Id === rid || zone.matchedPair.p2Id === rid)) {
          events.push({ type: 'zone_cancelled', zone, leaverId: rid });
        }
      }

      // 2. 新規プレイヤーのゾーン進入検出
      if (zone.playerIds.length < 2) {
        for (const p of players.values()) {
          if (!p.alive || p.cleared) continue;
          if (p.inZoneId !== null) continue;       // 既に別ゾーン内
          if (p.zoneMatchedWith !== null) continue; // マッチ中
          if (zone.playerIds.includes(p.id)) continue;
          if (zone.playerIds.length >= 2) break;   // 満員

          const dx = p.x - zone.x;
          const dy = p.y - zone.y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist <= zone.radius) {
            zone.playerIds.push(p.id);
            p.inZoneId = zone.id;

            // 2人になったらマッチング
            if (zone.playerIds.length === 2 && !zone.matchedPair) {
              events.push({
                type: 'zone_matched',
                zone,
                p1Id: zone.playerIds[0],
                p2Id: zone.playerIds[1],
              });
            }
          }
        }
      }

      // 3. マッチングタイマー更新
      if (zone.matchedPair) {
        zone.matchedPair.timer -= dt;

        // 両者のzoneFightChoiceが揃ったら勝負判定（タイムアウトより優先）
        if (!zone.matchedPair.resolved) {
          const p1 = players.get(zone.matchedPair.p1Id);
          const p2 = players.get(zone.matchedPair.p2Id);
          if (p1 && p2 && p1.zoneFightChoice && p2.zoneFightChoice) {
            zone.matchedPair.resolved = true;
            events.push({
              type: 'zone_both_ready',
              zone,
              p1Id: zone.matchedPair.p1Id,
              p2Id: zone.matchedPair.p2Id,
            });
          } else if (zone.matchedPair.timer <= 0) {
            events.push({ type: 'zone_timeout', zone });
          }
        } else if (zone.matchedPair.timer <= 0) {
          events.push({ type: 'zone_timeout', zone });
        }
      }

      // ゾーン状態を更新
      this._updateZoneState(zone);
    }

    return events;
  }

  _updateZoneState(zone) {
    if (zone.playerIds.length === 0) {
      zone.state = 'empty';
    } else if (zone.playerIds.length === 1) {
      zone.state = 'waiting';
    } else if (zone.matchedPair) {
      zone.state = 'matched';
    } else {
      zone.state = 'waiting';
    }
  }

  startMatch(zone, p1Id, p2Id) {
    zone.matchedPair = {
      p1Id,
      p2Id,
      timer: this.settings.zoneTimeout || 15,
      resolved: false,
    };
    zone.state = 'matched';
  }

  /**
   * 両者が「勝負する」を選んだ場合のじゃんけん判定
   */
  resolveFight(p1, p2) {
    const hand1 = p1.zoneFightChoice.hand;
    const hand2 = p2.zoneFightChoice.hand;
    const bet1 = p1.zoneFightChoice.bet;
    const bet2 = p2.zoneFightChoice.bet;
    const actualBet = Math.min(bet1, bet2); // 低い方に合わせる

    // カード消費
    p1.useCard(hand1);
    p2.useCard(hand2);

    // じゃんけん判定
    const result = resolveJanken(hand1, hand2);

    let winnerId = null;
    if (result === 'player1') {
      p2.removeStars(1);
      p1.addStars(1);
      p2.removeGold(actualBet);
      p1.addGold(actualBet);
      winnerId = p1.id;
    } else if (result === 'player2') {
      p1.removeStars(1);
      p2.addStars(1);
      p1.removeGold(actualBet);
      p2.addGold(actualBet);
      winnerId = p2.id;
    }
    // あいこ: カード消費のみ（星・金の移動なし）

    return { result, winnerId, hand1, hand2, actualBet };
  }

  /**
   * ゾーンのマッチ状態をリセット
   */
  clearZone(zone, p1, p2) {
    zone.matchedPair = null;
    if (p1) {
      p1.zoneMatchedWith = null;
      p1.zoneFightChoice = null;
    }
    if (p2) {
      p2.zoneMatchedWith = null;
      p2.zoneFightChoice = null;
    }
    this._updateZoneState(zone);
  }

  getZonesPublicData() {
    return this.zones.map(z => z.toPublicData());
  }

  findZoneById(zoneId) {
    return this.zones.find(z => z.id === zoneId);
  }
}
