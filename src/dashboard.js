import 'dotenv/config';
import http from 'http';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const PORT = process.env.DASHBOARD_PORT ?? 3001;
const __dirname = dirname(fileURLToPath(import.meta.url));

// Cache data so we don't hammer TradingView on every request
let cache = null;
let cacheTime = 0;
const CACHE_TTL = 3000; // 3 seconds (balance between real-time and CLI overhead)

function getTVData() {
  const now = Date.now();
  if (cache && now - cacheTime < CACHE_TTL) return cache;

  try {
    const raw = execSync(
      'node src/cli/index.js ohlcv --bars 200',
      { cwd: join(__dirname, '..'), encoding: 'utf8', timeout: 10000, stdio: ['pipe','pipe','pipe'] }
    );
    const start = raw.indexOf('{');
    if (start < 0) return cache;
    const data = JSON.parse(raw.substring(start));

    const now8 = new Date();
    const twOffset = 8 * 3600 * 1000;
    const twNow = new Date(now8.getTime() + twOffset);
    const dateStr = twNow.toISOString().slice(0, 10);

    const dayStart = Math.floor(new Date(`${dateStr}T08:45:00+08:00`).getTime() / 1000);
    const dayEnd   = Math.floor(new Date(`${dateStr}T13:45:00+08:00`).getTime() / 1000);
    const pmStart  = Math.floor(new Date(`${dateStr}T15:00:00+08:00`).getTime() / 1000);

    const dayBars = data.bars.filter(b => b.time >= dayStart && b.time <= dayEnd);
    const pmBars  = data.bars.filter(b => b.time >= pmStart);

    const dayLow  = dayBars.length  ? Math.min(...dayBars.map(b => b.low))  : null;
    const pmLow   = pmBars.length   ? Math.min(...pmBars.map(b => b.low))   : null;
    const dayHigh = dayBars.length  ? Math.max(...dayBars.map(b => b.high)) : null;
    const pmHigh  = pmBars.length   ? Math.max(...pmBars.map(b => b.high))  : null;

    // Get latest price
    const quoteRaw = execSync(
      'node src/cli/index.js quote',
      { cwd: join(__dirname, '..'), encoding: 'utf8', timeout: 10000, stdio: ['pipe','pipe','pipe'] }
    );
    const qStart = quoteRaw.indexOf('{');
    const quote = qStart >= 0 ? JSON.parse(quoteRaw.substring(qStart)) : null;
    const price = quote?.last ?? data.close;

    cache = { price, dayLow, dayHigh, pmLow, pmHigh, symbol: 'TXFM2026', updated: new Date().toLocaleTimeString('zh-TW') };
    cacheTime = Date.now();
    return cache;
  } catch (e) {
    return cache ?? { error: e.message };
  }
}

const HTML = `<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>台指期 盤中監控</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', sans-serif; background: #0d1117; color: #e6edf3; padding: 20px; }
  h1 { text-align: center; font-size: 1.4rem; margin-bottom: 6px; color: #58a6ff; }
  .updated { text-align: center; font-size: 0.75rem; color: #8b949e; margin-bottom: 20px; }
  table { width: 100%; border-collapse: collapse; }
  th { background: #161b22; padding: 12px 16px; text-align: left; font-size: 0.8rem; color: #8b949e; text-transform: uppercase; border-bottom: 1px solid #30363d; }
  td { padding: 14px 16px; border-bottom: 1px solid #21262d; font-size: 1rem; }
  .price { font-size: 1.3rem; font-weight: bold; color: #58a6ff; }
  .low   { color: #ff7b72; }
  .high  { color: #3fb950; }
  .diff-pos { color: #3fb950; font-weight: bold; }
  .diff-neg { color: #ff7b72; font-weight: bold; }
  .label { color: #8b949e; font-size: 0.85rem; }
  .na { color: #484f58; }
  .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; margin-bottom: 16px; }
  .row { display: flex; justify-content: space-between; align-items: center; padding: 10px 0; border-bottom: 1px solid #21262d; }
  .row:last-child { border-bottom: none; }
  .row-label { color: #8b949e; font-size: 0.9rem; }
  .row-value { font-size: 1.1rem; font-weight: bold; }
  .btn-group { display: flex; gap: 12px; margin-bottom: 16px; }
  .btn { flex: 1; padding: 14px; font-size: 1.1rem; font-weight: bold; border: none; border-radius: 8px; cursor: pointer; transition: all 0.2s; opacity: 0.4; }
  .btn-long { background: #3fb950; color: #0d1117; }
  .btn-short { background: #ff7b72; color: #0d1117; }
  .btn.active { opacity: 1; transform: scale(1.03); box-shadow: 0 0 12px rgba(255,255,255,0.15); }
</style>
</head>
<body>
<h1>📊 台指期 TXFM2026 盤中監控</h1>
<div class="updated" id="updated">載入中...</div>

<div class="btn-group">
  <button class="btn btn-long active" id="btnLong" onclick="setMode('long')">📈 做多</button>
  <button class="btn btn-short" id="btnShort" onclick="setMode('short')">📉 做空</button>
</div>

<div class="card">
  <div class="row">
    <span class="row-label">現價</span>
    <span class="row-value price" id="price">—</span>
  </div>
</div>

<div id="cardLow" class="card">
  <div class="row">
    <span class="row-label" id="sessionLabel">— 盤</span>
    <span class="row-value" id="sessionName" style="color:#8b949e;font-size:0.85rem">偵測中...</span>
  </div>
  <div class="row">
    <span class="row-label">最低點</span>
    <span class="row-value low" id="sessionLow">—</span>
  </div>
  <div class="row">
    <span class="row-label">距最低點</span>
    <span class="row-value" id="diffSessionLow">—</span>
  </div>
</div>

<div id="cardHigh" class="card">
  <div class="row">
    <span class="row-label" id="otherLabel">— 盤</span>
    <span class="row-value" id="otherName" style="color:#8b949e;font-size:0.85rem"></span>
  </div>
  <div class="row">
    <span class="row-label">最高點</span>
    <span class="row-value high" id="otherHigh">—</span>
  </div>
  <div class="row">
    <span class="row-label">距最高點</span>
    <span class="row-value" id="diffOtherHigh">—</span>
  </div>
</div>

<script>
let latest = null;
let mode = 'long'; // 'long' or 'short'

function setMode(m) {
  mode = m;
  document.getElementById('btnLong').classList.toggle('active', m === 'long');
  document.getElementById('btnShort').classList.toggle('active', m === 'short');
  const container = document.querySelector('body');
  const cardLow  = document.getElementById('cardLow');
  const cardHigh = document.getElementById('cardHigh');
  const priceCard = cardLow.previousElementSibling; // card with price
  if (m === 'long') {
    priceCard.after(cardLow);
    cardLow.after(cardHigh);
  } else {
    priceCard.after(cardHigh);
    cardHigh.after(cardLow);
  }
  if (latest) render(latest);
}

function fmt(n) { return n != null ? Number(n).toLocaleString() : '—'; }
function diff(price, level) {
  if (price == null || level == null) return '<span class="na">—</span>';
  const d = price - level;
  const cls = d >= 0 ? 'diff-pos' : 'diff-neg';
  const sign = d >= 0 ? '+' : '';
  return '<span class="' + cls + '">' + sign + d.toLocaleString() + ' 點</span>';
}

function currentSession() {
  const now = new Date();
  const h = now.getHours(), m = now.getMinutes();
  const mins = h * 60 + m;
  if (mins >= 8*60+45 && mins <= 13*60+45) return 'day';
  if (mins >= 15*60) return 'pm';
  return 'pm'; // 夜盤也算下午盤延伸
}

function render(d) {
  if (!d || d.error) {
    document.getElementById('price').textContent = '—';
    document.getElementById('updated').textContent = '⏳ 等待 TradingView 連線中...';
    ['sessionLow','sessionLabel','diffSessionLow','otherHigh','otherLabel','diffOtherHigh'].forEach(id => {
      const el = document.getElementById(id);
      if (el) el.textContent = '—';
    });
    return;
  }
  document.getElementById('price').textContent = fmt(d.price);

  const session = currentSession();
  const isDay = session === 'day';
  const low  = isDay ? d.dayLow  : d.pmLow;
  const high = isDay ? d.dayHigh : d.pmHigh;
  const label = isDay ? '🌅 日盤' : '🌆 下午盤';

  // Top card: current session LOW
  document.getElementById('sessionLabel').textContent = label + ' 當前盤';
  document.getElementById('sessionName').textContent  = isDay ? '08:45–13:45' : '15:00–';
  document.getElementById('sessionLow').textContent   = low  ? fmt(low)  : '尚無資料';
  document.getElementById('diffSessionLow').innerHTML = diff(d.price, low);

  // Bottom card: same session HIGH
  document.getElementById('otherLabel').textContent    = label + ' 當前盤';
  document.getElementById('otherName').textContent     = isDay ? '08:45–13:45' : '15:00–';
  document.getElementById('otherHigh').textContent     = high ? fmt(high) : '尚無資料';
  document.getElementById('diffOtherHigh').innerHTML   = diff(d.price, high);
}

// SSE: receive new data from server every ~3 seconds
const es = new EventSource('/stream');
es.onmessage = e => { latest = JSON.parse(e.data); render(latest); };

// UI clock ticks every 1 second
setInterval(() => {
  const now = new Date().toLocaleTimeString('zh-TW');
  document.getElementById('updated').textContent = '更新時間：' + now;
}, 1000);
</script>
</body>
</html>`;

// SSE clients
const clients = new Set();

// Background data refresh every 3 seconds
setInterval(() => {
  const data = getTVData();
  const msg = `data: ${JSON.stringify(data)}\n\n`;
  clients.forEach(res => { try { res.write(msg); } catch {} });
}, 3000);

const server = http.createServer((req, res) => {
  if (req.url === '/api') {
    const data = getTVData();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data));

  } else if (req.url === '/stream') {
    // SSE endpoint
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });
    res.write(`data: ${JSON.stringify(getTVData())}\n\n`);
    clients.add(res);
    req.on('close', () => clients.delete(res));

  } else {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(HTML);
  }
});

server.listen(PORT, () => {
  process.stderr.write(`[Dashboard] http://localhost:${PORT}\n`);
});
