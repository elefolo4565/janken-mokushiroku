/**
 * 衝突検出システム
 * - 円形の当たり判定
 * - 衝突クールダウン管理
 */

export class CollisionSystem {
  constructor() {
    // 衝突クールダウン: "id1:id2" -> 残りクールダウン秒数
    this.cooldowns = new Map();
  }

  /**
   * 全プレイヤーペアの衝突を検出
   * @param {Map} players - playerId -> PlayerState
   * @param {number} radius - 当たり判定半径
   * @returns {Array} 衝突したペアの配列 [{p1, p2, distance}]
   */
  detectCollisions(players, radius, extraFilter = null) {
    const collisions = [];
    const alivePlayers = Array.from(players.values()).filter(p => {
      if (!p.alive || p.cleared) return false;
      if (extraFilter && !extraFilter(p)) return false;
      return true;
    });
    const collisionDist = radius * 2;

    for (let i = 0; i < alivePlayers.length; i++) {
      for (let j = i + 1; j < alivePlayers.length; j++) {
        const p1 = alivePlayers[i];
        const p2 = alivePlayers[j];

        const dx = p1.x - p2.x;
        const dy = p1.y - p2.y;
        const distSq = dx * dx + dy * dy;
        const dist = Math.sqrt(distSq);

        if (dist < collisionDist) {
          const pairKey = this._pairKey(p1.id, p2.id);
          if (!this.cooldowns.has(pairKey)) {
            collisions.push({ p1, p2, distance: dist });
          }
        }
      }
    }

    return collisions;
  }

  /**
   * プレイヤー同士の重なりを押し出し処理
   */
  resolveOverlaps(players, radius, extraFilter = null) {
    const alivePlayers = Array.from(players.values()).filter(p => {
      if (!p.alive || p.cleared) return false;
      if (extraFilter && !extraFilter(p)) return false;
      return true;
    });
    const collisionDist = radius * 2;

    for (let i = 0; i < alivePlayers.length; i++) {
      for (let j = i + 1; j < alivePlayers.length; j++) {
        const p1 = alivePlayers[i];
        const p2 = alivePlayers[j];

        const dx = p1.x - p2.x;
        const dy = p1.y - p2.y;
        const distSq = dx * dx + dy * dy;

        if (distSq < collisionDist * collisionDist && distSq > 0) {
          const dist = Math.sqrt(distSq);
          const overlap = (collisionDist - dist) / 2;
          const nx = dx / dist;
          const ny = dy / dist;

          p1.x += nx * overlap;
          p1.y += ny * overlap;
          p2.x -= nx * overlap;
          p2.y -= ny * overlap;
        }
      }
    }
  }

  /**
   * クールダウンを設定
   */
  setCooldown(id1, id2, seconds) {
    this.cooldowns.set(this._pairKey(id1, id2), seconds);
  }

  /**
   * クールダウンを更新（毎tick呼ぶ）
   */
  updateCooldowns(dt) {
    for (const [key, remaining] of this.cooldowns) {
      const newVal = remaining - dt;
      if (newVal <= 0) {
        this.cooldowns.delete(key);
      } else {
        this.cooldowns.set(key, newVal);
      }
    }
  }

  _pairKey(id1, id2) {
    return id1 < id2 ? `${id1}:${id2}` : `${id2}:${id1}`;
  }
}
