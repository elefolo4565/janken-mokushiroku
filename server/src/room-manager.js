import { v4 as uuidv4 } from 'uuid';
import { S2C, DEFAULT_SETTINGS } from './protocol.js';
import { GameLoop } from './game-loop.js';
import { createAIPlayer } from './ai-player.js';

class Room {
  constructor(id, name, hostId, settings) {
    this.id = id;
    this.name = name;
    this.hostId = hostId;
    this.settings = { ...DEFAULT_SETTINGS, ...settings };
    this.players = new Map(); // playerId -> PlayerState
    this.aiControllers = new Map(); // aiPlayerId -> AIController
    this.state = 'waiting'; // waiting | playing | finished
    this.gameLoop = null;
  }

  get playerCount() {
    return this.players.size;
  }

  addPlayer(player) {
    this.players.set(player.id, player);
    player.roomId = this.id;
  }

  removePlayer(playerId) {
    const player = this.players.get(playerId);
    if (player) {
      player.roomId = null;
      this.players.delete(playerId);
    }
    // ホストが抜けたら次のプレイヤーをホストに
    if (playerId === this.hostId && this.players.size > 0) {
      this.hostId = this.players.keys().next().value;
    }
    return player;
  }

  broadcast(data, excludeId = null) {
    for (const [id, player] of this.players) {
      if (id !== excludeId) {
        player.send(data);
      }
    }
  }

  toListData() {
    return {
      id: this.id,
      name: this.name,
      playerCount: this.playerCount,
      maxPlayers: 20,
      state: this.state,
      settings: {
        cardsPerType: this.settings.cardsPerType,
        initialStars: this.settings.initialStars,
        victoryStars: this.settings.victoryStars,
        timeLimit: this.settings.timeLimit,
        initialGold: this.settings.initialGold,
        victoryGold: this.settings.victoryGold,
        battleZoneCount: this.settings.battleZoneCount,
      },
    };
  }

  toDetailData() {
    return {
      ...this.toListData(),
      hostId: this.hostId,
      players: Array.from(this.players.values()).map(p => ({
        id: p.id,
        name: p.name,
        isAI: !!p.isAI,
      })),
    };
  }
}

class RoomManager {
  constructor() {
    this.rooms = new Map();
  }

  createRoom(player, roomName, settings = {}) {
    const roomId = uuidv4().substring(0, 8);
    const room = new Room(roomId, roomName || `${player.name}の部屋`, player.id, settings);
    room.addPlayer(player);
    this.rooms.set(roomId, room);

    player.send({
      type: S2C.ROOM_CREATED,
      room: room.toDetailData(),
    });

    return room;
  }

  joinRoom(player, roomId) {
    const room = this.rooms.get(roomId);
    if (!room) {
      player.send({ type: S2C.ERROR, message: 'ルームが見つかりません' });
      return null;
    }
    if (room.state !== 'waiting') {
      player.send({ type: S2C.ERROR, message: 'ゲームが既に開始されています' });
      return null;
    }
    if (room.playerCount >= 20) {
      player.send({ type: S2C.ERROR, message: 'ルームが満員です' });
      return null;
    }

    // 既に別のルームにいる場合は退出
    if (player.roomId) {
      this.leaveRoom(player);
    }

    room.addPlayer(player);

    // 参加者に通知
    room.broadcast({
      type: S2C.PLAYER_JOINED,
      player: { id: player.id, name: player.name },
      room: room.toDetailData(),
    }, player.id);

    // 本人にルーム情報を送信
    player.send({
      type: S2C.ROOM_JOINED,
      room: room.toDetailData(),
    });

    return room;
  }

  leaveRoom(player) {
    if (!player.roomId) return;

    const room = this.rooms.get(player.roomId);
    if (!room) {
      player.roomId = null;
      return;
    }

    // ゲーム中なら退場扱い
    if (room.state === 'playing' && room.gameLoop) {
      room.gameLoop.eliminatePlayer(player.id, 'disconnected');
    }

    room.removePlayer(player.id);

    // 残りのプレイヤーに通知
    room.broadcast({
      type: S2C.PLAYER_LEFT,
      playerId: player.id,
      room: room.toDetailData(),
    });

    // ルームが空になったら削除
    if (room.playerCount === 0) {
      if (room.gameLoop) {
        room.gameLoop.stop();
      }
      this.rooms.delete(room.id);
    }
  }

  listRooms(player) {
    const roomList = Array.from(this.rooms.values()).map(r => r.toListData());
    player.send({
      type: S2C.ROOM_LIST,
      rooms: roomList,
    });
  }

  startGame(player) {
    if (!player.roomId) {
      player.send({ type: S2C.ERROR, message: 'ルームに参加していません' });
      return;
    }

    const room = this.rooms.get(player.roomId);
    if (!room) return;

    if (room.hostId !== player.id) {
      player.send({ type: S2C.ERROR, message: 'ホストのみがゲームを開始できます' });
      return;
    }

    if (room.playerCount < 2) {
      player.send({ type: S2C.ERROR, message: '2人以上必要です' });
      return;
    }

    if (room.state !== 'waiting') {
      player.send({ type: S2C.ERROR, message: '既にゲームが開始されています' });
      return;
    }

    room.state = 'playing';
    room.gameLoop = new GameLoop(room);
    room.gameLoop.start();
  }

  addAI(player) {
    if (!player.roomId) {
      player.send({ type: S2C.ERROR, message: 'ルームに参加していません' });
      return;
    }

    const room = this.rooms.get(player.roomId);
    if (!room) return;

    if (room.hostId !== player.id) {
      player.send({ type: S2C.ERROR, message: 'ホストのみがAIを追加できます' });
      return;
    }

    if (room.state !== 'waiting') {
      player.send({ type: S2C.ERROR, message: 'ゲーム中はAIを追加できません' });
      return;
    }

    if (room.playerCount >= 20) {
      player.send({ type: S2C.ERROR, message: 'ルームが満員です' });
      return;
    }

    const { player: aiPlayer, controller } = createAIPlayer();
    room.addPlayer(aiPlayer);
    room.aiControllers.set(aiPlayer.id, controller);

    room.broadcast({
      type: S2C.PLAYER_JOINED,
      player: { id: aiPlayer.id, name: aiPlayer.name, isAI: true },
      room: room.toDetailData(),
    });
  }

  removeAI(player) {
    if (!player.roomId) return;

    const room = this.rooms.get(player.roomId);
    if (!room) return;

    if (room.hostId !== player.id) {
      player.send({ type: S2C.ERROR, message: 'ホストのみがAIを削除できます' });
      return;
    }

    if (room.state !== 'waiting') {
      player.send({ type: S2C.ERROR, message: 'ゲーム中はAIを削除できません' });
      return;
    }

    // 最後に追加されたAIを削除
    let lastAIId = null;
    for (const [id, p] of room.players) {
      if (p.isAI) lastAIId = id;
    }

    if (!lastAIId) {
      player.send({ type: S2C.ERROR, message: 'AIプレイヤーがいません' });
      return;
    }

    room.removePlayer(lastAIId);
    room.aiControllers.delete(lastAIId);

    room.broadcast({
      type: S2C.PLAYER_LEFT,
      playerId: lastAIId,
      room: room.toDetailData(),
    });
  }

  getRoom(roomId) {
    return this.rooms.get(roomId);
  }

  handleGameEnd(roomId) {
    const room = this.rooms.get(roomId);
    if (room) {
      room.state = 'waiting';
      room.gameLoop = null;
    }
  }
}

export const roomManager = new RoomManager();
