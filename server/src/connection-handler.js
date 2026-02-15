import { v4 as uuidv4 } from 'uuid';
import { C2S, S2C, COMMANDS } from './protocol.js';
import { PlayerState } from './player-state.js';
import { roomManager } from './room-manager.js';

// 全接続プレイヤー
const players = new Map();

export function handleConnection(ws) {
  const playerId = uuidv4();
  const player = new PlayerState(playerId, ws);
  players.set(playerId, player);

  // 接続成功を通知
  player.send({ type: S2C.CONNECTED, playerId });

  // keepalive ping
  const pingInterval = setInterval(() => {
    if (ws.readyState === 1) {
      ws.ping();
    }
  }, 30000);

  ws.on('message', (rawData) => {
    try {
      const data = JSON.parse(rawData.toString());
      handleMessage(player, data);
    } catch (e) {
      player.send({ type: S2C.ERROR, message: '不正なメッセージ形式です' });
    }
  });

  ws.on('close', () => {
    clearInterval(pingInterval);
    handleDisconnect(player);
    players.delete(playerId);
  });

  ws.on('error', () => {
    clearInterval(pingInterval);
    players.delete(playerId);
  });
}

function handleMessage(player, data) {
  switch (data.type) {
    case C2S.SET_NAME:
      player.name = String(data.name || '').substring(0, 20) || 'ゲスト';
      player.send({ type: 'name_set', name: player.name });
      break;

    case C2S.CREATE_ROOM:
      roomManager.createRoom(
        player,
        String(data.roomName || '').substring(0, 30),
        data.settings || {}
      );
      break;

    case C2S.JOIN_ROOM:
      roomManager.joinRoom(player, data.roomId);
      break;

    case C2S.LEAVE_ROOM:
      roomManager.leaveRoom(player);
      break;

    case C2S.LIST_ROOMS:
      roomManager.listRooms(player);
      break;

    case C2S.START_GAME:
      roomManager.startGame(player);
      break;

    case C2S.INPUT:
      handleInput(player, data);
      break;

    case C2S.SELECT_COMMAND:
      handleSelectCommand(player, data);
      break;

    case C2S.TRADE_OFFER:
      handleTradeOffer(player, data);
      break;

    case C2S.TRADE_RESPOND:
      handleTradeRespond(player, data);
      break;

    case C2S.ADD_AI:
      roomManager.addAI(player);
      break;

    case C2S.REMOVE_AI:
      roomManager.removeAI(player);
      break;

    case C2S.ZONE_FIGHT:
      handleZoneFight(player, data);
      break;

    case C2S.ZONE_LEAVE:
      handleZoneLeave(player);
      break;

    default:
      player.send({ type: S2C.ERROR, message: `不明なメッセージタイプ: ${data.type}` });
  }
}

function handleInput(player, data) {
  if (!player.roomId || !player.alive || player.cleared) return;

  // 入力ベクトルを正規化
  let dx = Number(data.dx) || 0;
  let dy = Number(data.dy) || 0;
  const len = Math.sqrt(dx * dx + dy * dy);
  if (len > 1) {
    dx /= len;
    dy /= len;
  }
  player.inputDx = dx;
  player.inputDy = dy;
}

function handleSelectCommand(player, data) {
  if (!player.roomId || !player.alive || player.cleared) return;

  const command = data.command;
  const validCommands = Object.values(COMMANDS);
  if (!validCommands.includes(command)) {
    player.send({ type: S2C.ERROR, message: '不正なコマンドです' });
    return;
  }

  // カードの在庫確認（手を選択する場合）
  if (command === COMMANDS.ROCK || command === COMMANDS.SCISSORS || command === COMMANDS.PAPER) {
    if (!player.hasCard(command)) {
      player.send({ type: S2C.ERROR, message: 'そのカードは残っていません' });
      return;
    }
  }

  player.command = command;
}

function handleTradeOffer(player, data) {
  if (!player.roomId) return;
  const room = roomManager.getRoom(player.roomId);
  if (!room || !room.gameLoop) return;

  room.gameLoop.tradeManager.handleOffer(player.id, data.offer, data.request);
}

function handleTradeRespond(player, data) {
  if (!player.roomId) return;
  const room = roomManager.getRoom(player.roomId);
  if (!room || !room.gameLoop) return;

  room.gameLoop.tradeManager.handleRespond(player.id, data.accept);
}

function handleZoneFight(player, data) {
  if (!player.roomId || !player.alive || !player.inZoneId) return;
  const room = roomManager.getRoom(player.roomId);
  if (!room || !room.gameLoop) return;

  const hand = data.hand;
  const bet = Number(data.bet) || 0;

  if (!['rock', 'scissors', 'paper'].includes(hand)) {
    player.send({ type: S2C.ERROR, message: '不正な手です' });
    return;
  }

  room.gameLoop.handleZoneFight(player, hand, bet);
}

function handleZoneLeave(player) {
  if (!player.roomId || !player.alive || !player.inZoneId) return;
  const room = roomManager.getRoom(player.roomId);
  if (!room || !room.gameLoop) return;

  room.gameLoop.handleZoneLeave(player);
}

function handleDisconnect(player) {
  if (player.roomId) {
    roomManager.leaveRoom(player);
  }
}
