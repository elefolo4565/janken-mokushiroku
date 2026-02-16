import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LOGS_DIR = path.join(__dirname, '../logs');

// logsディレクトリがなければ作成
if (!fs.existsSync(LOGS_DIR)) {
  fs.mkdirSync(LOGS_DIR, { recursive: true });
}

export class BattleLogger {
  constructor(roomId, roomName) {
    const now = new Date();
    const timestamp = now.toISOString().replace(/[:.]/g, '-').slice(0, 19);
    this.filename = `${timestamp}_${roomId}.log`;
    this.filepath = path.join(LOGS_DIR, this.filename);
    this._write(`=== ゲームセッション開始 ===`);
    this._write(`ルーム: ${roomName} (${roomId})`);
    this._write(`日時: ${now.toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' })}`);
  }

  logGameStart(players, settings) {
    this._write(`\n--- ゲーム開始 ---`);
    this._write(`プレイヤー数: ${players.length}`);
    for (const p of players) {
      const tag = p.isAI ? ' [AI]' : '';
      this._write(`  ${p.name} (${p.id})${tag}`);
    }
    this._write(`設定: カード各${settings.cardsPerType}枚, 初期星${settings.initialStars}, 勝利星${settings.victoryStars}, 初期金${settings.initialGold}, 勝利金${settings.victoryGold}, 制限${settings.timeLimit}秒`);
  }

  logZoneMatch(p1Name, p2Name, zoneId) {
    this._write(`[MATCH] ${p1Name} vs ${p2Name} (${zoneId})`);
  }

  logZoneFightResult(result) {
    const { p1Name, p1Hand, p2Name, p2Hand, winnerId, winnerName, outcome, bet } = result;
    const handLabel = { rock: 'グー', scissors: 'チョキ', paper: 'パー' };
    const h1 = handLabel[p1Hand] || p1Hand;
    const h2 = handLabel[p2Hand] || p2Hand;
    if (outcome === 'draw') {
      this._write(`[RESULT] ${p1Name}(${h1}) vs ${p2Name}(${h2}) → あいこ 賭金:${bet}`);
    } else {
      this._write(`[RESULT] ${p1Name}(${h1}) vs ${p2Name}(${h2}) → 勝者:${winnerName} 賭金:${bet}`);
    }
  }

  logZoneCancelled(reason, playerNames) {
    this._write(`[CANCEL] ${playerNames.join(' / ')} - ${reason}`);
  }

  logElimination(playerName, reason) {
    this._write(`[ELIMINATED] ${playerName} (${reason})`);
  }

  logCleared(playerName) {
    this._write(`[CLEARED] ${playerName} ゴール達成`);
  }

  logGameEnd(results) {
    this._write(`\n--- ゲーム終了 ---`);
    for (let i = 0; i < results.length; i++) {
      const r = results[i];
      const status = r.cleared ? 'クリア' : r.alive ? '生存' : '退場';
      const tag = r.isAI ? ' [AI]' : '';
      this._write(`  ${i + 1}位: ${r.name}${tag} ⭐${r.stars} 💰${r.gold} カード残${r.cardsLeft} [${status}]`);
    }
    this._write(`=== セッション終了 ===\n`);
  }

  _write(line) {
    const ts = new Date().toISOString().slice(11, 23);
    fs.appendFileSync(this.filepath, `[${ts}] ${line}\n`);
  }
}
