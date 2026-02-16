import express from 'express';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import path from 'path';
import { fileURLToPath } from 'url';
import { handleConnection } from './connection-handler.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const server = createServer(app);
const PORT = process.env.PORT || 10000;

// HTMLファイルはキャッシュしない（常に最新を取得）
app.use((req, res, next) => {
  if (req.path === '/' || req.path.endsWith('.html')) {
    res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
  }
  next();
});

// 静的ファイル配信（HTML5エクスポート）- 1時間キャッシュ
app.use(express.static(path.join(__dirname, '../../export'), {
  maxAge: '1h',
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.html')) {
      res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    }
  }
}));

// ヘルスチェック
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'janken-mokushiroku-server' });
});

// WebSocket サーバー
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws) => {
  handleConnection(ws);
});

server.listen(PORT, () => {
  console.log(`Janken Mokushiroku Server running on port ${PORT}`);
  console.log(`WebSocket: ws://localhost:${PORT}/ws`);
});
