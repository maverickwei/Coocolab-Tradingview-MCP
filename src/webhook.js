import http from 'http';
import { execSync, spawn } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { readFileSync, writeFileSync } from 'fs';
import { pushMessage } from './core/line.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Dashboard data ────────────────────────────────────────────────
let cache = null, cacheTime = 0;
const CACHE_TTL = 3000;

// Live historical high — only goes up, never down
let liveHistHigh = Number(process.env.HIST_HIGH ?? 46465);

// Session accumulators — track running high/low within each session
let sessionDay = { high: null, low: null };  // 08:45–13:45
let sessionPm  = { high: null, low: null };  // 15:00–
// Track which session dates we've initialized for
let lastDaySessionKey = '';
let lastPmSessionKey  = '';

function getTWParts() {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Taipei',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false
  });
  const p = Object.fromEntries(fmt.formatToParts(new Date()).map(x => [x.type, x.value]));
  return {
    dateStr: `${p.year}-${p.month}-${p.day}`,
    h: parseInt(p.hour),
    m: parseInt(p.minute),
  };
}

// Get Taiwan date string for a Date offset by days
function twDateStr(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86400000);
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Taipei',
    year: 'numeric', month: '2-digit', day: '2-digit'
  });
  const p = Object.fromEntries(fmt.formatToParts(d).map(x => [x.type, x.value]));
  return `${p.year}-${p.month}-${p.day}`;
}

function getTWHour() { const p = getTWParts(); return p.h * 60 + p.m; }

const SESSION_FILE = join(__dirname, '..', 'session-data.json');

function saveSession() {
  try {
    writeFileSync(SESSION_FILE, JSON.stringify({
      sessionDay, sessionPm, lastDaySessionKey, lastPmSessionKey,
      liveHistHigh, savedAt: new Date().toISOString()
    }));
  } catch {}
}

function loadSession() {
  try {
    const saved = JSON.parse(readFileSync(SESSION_FILE, 'utf8'));
    const { dateStr, h } = getTWParts();
    const currentDayKey = dateStr;
    const currentPmKey = h < 5 ? twDateStr(-1) : dateStr;

    // Restore pm session if same pm session date
    if (saved.lastPmSessionKey === currentPmKey && saved.sessionPm) {
      sessionPm = saved.sessionPm;
      lastPmSessionKey = saved.lastPmSessionKey;
      process.stderr.write(`[Dashboard] 恢復 pm session: low=${sessionPm.low} high=${sessionPm.high}\n`);
    }
    // Restore day session if same day
    if (saved.lastDaySessionKey === currentDayKey && saved.sessionDay) {
      sessionDay = saved.sessionDay;
      lastDaySessionKey = saved.lastDaySessionKey;
    }
    // Restore historical high
    if (saved.liveHistHigh > liveHistHigh) {
      liveHistHigh = saved.liveHistHigh;
      process.stderr.write(`[Dashboard] 恢復歷史最高: ${liveHistHigh}\n`);
    }
  } catch {}
}

// Load saved session on startup
loadSession();

function resetSessionIfNeeded() {
  const { dateStr, h, m } = getTWParts();
  const mins = h * 60 + m;

  // Day session key = today's date (08:45–13:45)
  if (dateStr !== lastDaySessionKey && mins >= 8*60+45) {
    sessionDay = { high: null, low: null };
    lastDaySessionKey = dateStr;
  }

  // Pm session key: if 00:00~04:59 TWN, pm started yesterday
  const pmKey = h < 5 ? twDateStr(-1) : dateStr;

  if (pmKey !== lastPmSessionKey && (mins >= 15*60 || h < 5)) {
    sessionPm = { high: null, low: null };
    lastPmSessionKey = pmKey;
    process.stderr.write(`[Dashboard] 新下午盤 pmKey=${pmKey}\n`);
  }
}

function updateSessionAccumulator(high, low) {
  resetSessionIfNeeded();
  const mins = getTWHour();
  const isDay = mins >= 8*60+45 && mins <= 13*60+45;
  // 下午/夜盤：15:00 以後 OR 隔天 00:00~05:00（夜盤延伸到凌晨）
  const isPm  = mins >= 15*60 || mins < 5*60;
  let updated = false;
  if (isDay) {
    if (high && (sessionDay.high === null || high > sessionDay.high)) { sessionDay.high = high; updated = true; }
    if (low  && (sessionDay.low  === null || low  < sessionDay.low))  { sessionDay.low  = low;  updated = true; }
  }
  if (isPm) {
    if (high && (sessionPm.high === null || high > sessionPm.high)) { sessionPm.high = high; updated = true; }
    if (low  && (sessionPm.low  === null || low  < sessionPm.low))  { sessionPm.low  = low;  updated = true; }
  }
  if (updated) saveSession();
}

function cli(cmd) {
  return execSync(cmd, { cwd: join(__dirname, '..'), encoding: 'utf8', timeout: 5000, stdio: ['pipe','pipe','pipe'] });
}

function getSessionDates() {
  const { dateStr: dayDateStr, h } = getTWParts();
  const pmDateStr = h < 5 ? twDateStr(-1) : dayDateStr;
  return {
    dayStart:      Math.floor(new Date(`${dayDateStr}T08:45:00+08:00`).getTime() / 1000),
    dayEnd:        Math.floor(new Date(`${dayDateStr}T13:45:00+08:00`).getTime() / 1000),
    pmStart:       Math.floor(new Date(`${pmDateStr}T15:00:00+08:00`).getTime() / 1000),
    todayMidnight: Math.floor(new Date(`${dayDateStr}T00:00:00+08:00`).getTime() / 1000),
  };
}

function getTVData() {
  if (cache && Date.now() - cacheTime < CACHE_TTL) return cache;
  try {
    const raw = cli('node src/cli/index.js ohlcv --bars 200');
    const start = raw.indexOf('{');
    if (start < 0) return cache;
    const data = JSON.parse(raw.substring(start));
    const { dayStart, dayEnd, pmStart, todayMidnight } = getSessionDates();
    const todayBars = data.bars.filter(b => b.time >= todayMidnight);
    const dayBars   = data.bars.filter(b => b.time >= dayStart && b.time <= dayEnd);
    const pmBars    = data.bars.filter(b => b.time >= pmStart);
    const quoteRaw = cli('node src/cli/index.js quote');
    const qs = quoteRaw.indexOf('{');
    const quote = qs >= 0 ? JSON.parse(quoteRaw.substring(qs)) : null;

    // Today's overall high (all sessions combined)
    const todayHigh = todayBars.length ? Math.max(...todayBars.map(b => b.high)) : null;

    // Update live historical high with current data — only ever goes up
    const candidates = [quote?.high, quote?.last, todayHigh].filter(n => n > 0);
    const currentMax = candidates.length ? Math.max(...candidates) : 0;
    if (currentMax > liveHistHigh) {
      process.stderr.write(`[Dashboard] 🏆 歷史新高更新：${liveHistHigh} → ${currentMax}\n`);
      liveHistHigh = currentMax;
    }
    const histHigh = liveHistHigh;

    // Merge bar-derived values with stream accumulators (take best of both)
    const bestDayLow  = [dayBars.length  ? Math.min(...dayBars.map(b => b.low))  : null, sessionDay.low ].filter(n => n !== null);
    const bestDayHigh = [dayBars.length  ? Math.max(...dayBars.map(b => b.high)) : null, sessionDay.high].filter(n => n !== null);
    const bestPmLow   = [pmBars.length   ? Math.min(...pmBars.map(b => b.low))   : null, sessionPm.low  ].filter(n => n !== null);
    const bestPmHigh  = [pmBars.length   ? Math.max(...pmBars.map(b => b.high))  : null, sessionPm.high ].filter(n => n !== null);

    cache = {
      price:     quote?.last ?? data.close,
      dayLow:    bestDayLow.length  ? Math.min(...bestDayLow)  : null,
      dayHigh:   bestDayHigh.length ? Math.max(...bestDayHigh) : null,
      pmLow:     bestPmLow.length   ? Math.min(...bestPmLow)   : null,
      pmHigh:    bestPmHigh.length  ? Math.max(...bestPmHigh)  : null,
      todayHigh,
      histHigh,
      symbol: 'TXFM2026',
      updated: new Date().toLocaleTimeString('en-GB'),
    };
    cacheTime = Date.now();
    return cache;
  } catch { return cache ?? { error: 'no_connection' }; }
}

const sseClients = new Set();

// Push to all SSE clients immediately
function pushSSE(data) {
  const msg = `data: ${JSON.stringify(data)}\n\n`;
  sseClients.forEach(r => { try { r.write(msg); } catch {} });
}

// Real-time price stream via Coocolab stream quote (300ms interval)
function startPriceStream() {
  const proc = spawn('node', ['src/cli/index.js', 'stream', 'quote'],
    { cwd: join(__dirname, '..'), stdio: ['ignore', 'pipe', 'ignore'] });

  let buf = '';
  proc.stdout.on('data', chunk => {
    buf += chunk.toString();
    const lines = buf.split('\n');
    buf = lines.pop(); // keep incomplete line
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        const q = JSON.parse(trimmed);
        if (!q.last && !q.close) continue;
        const price = q.last ?? q.close;
        const high  = q.high ?? price;
        const low   = q.low  ?? price;

        // Update session accumulators
        updateSessionAccumulator(high, low);

        // Update live historical high
        if (high > liveHistHigh) {
          process.stderr.write(`[Dashboard] 🏆 歷史新高：${liveHistHigh} → ${high}\n`);
          liveHistHigh = high;
        }

        // Merge into cache and push to browser immediately
        if (cache) {
          cache.price = price;
          cache.histHigh = liveHistHigh;
          cache.updated = new Date().toLocaleTimeString('en-GB');
          pushSSE(cache);
        }
      } catch {}
    }
  });

  proc.on('close', () => {
    process.stderr.write('[Dashboard] stream closed, restarting in 3s...\n');
    setTimeout(startPriceStream, 3000);
  });
}

// Session restored from session-data.json on startup via loadSession()

// Start real-time price stream
startPriceStream();

// Background full data refresh every 2s (for high/low recalculation)
// Uses a lock to avoid overlapping calls
let refreshing = false;
setInterval(async () => {
  if (refreshing) return;
  refreshing = true;
  try {
    const data = getTVData();
    if (data) pushSSE(data);
  } finally {
    refreshing = false;
  }
}, 2000);

// ── Dashboard HTML ────────────────────────────────────────────────
const DASHBOARD_HTML = `<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>台指期 盤中監控</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', sans-serif; background: #0d1117; color: #e6edf3; padding: 20px; max-width: 480px; margin: 0 auto; }
  h1 { text-align: center; font-size: 1.4rem; margin-bottom: 6px; color: #58a6ff; }
  .updated { text-align: center; font-size: 0.75rem; color: #8b949e; margin-bottom: 16px; }
  .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; margin-bottom: 16px; }
  .row { display: flex; justify-content: space-between; align-items: center; padding: 10px 0; border-bottom: 1px solid #21262d; }
  .row:last-child { border-bottom: none; }
  .row-label { color: #8b949e; font-size: 0.9rem; }
  .row-value { font-size: 1.1rem; font-weight: bold; }
  .price { font-size: 1.3rem; font-weight: bold; color: #58a6ff; }
  .low { color: #ff7b72; } .high { color: #3fb950; }
  .diff-pos { color: #3fb950; font-weight: bold; }
  .diff-neg { color: #ff7b72; font-weight: bold; }
  .na { color: #484f58; }
  .btn-group { display: flex; gap: 12px; margin-bottom: 16px; }
  .btn { flex: 1; padding: 14px; font-size: 1.1rem; font-weight: bold; border: none; border-radius: 8px; cursor: pointer; transition: all 0.2s; opacity: 0.4; }
  .btn-long { background: #3fb950; color: #0d1117; }
  .btn-short { background: #ff7b72; color: #0d1117; }
  .btn.active { opacity: 1; transform: scale(1.03); box-shadow: 0 0 12px rgba(255,255,255,0.15); }
</style>
</head>
<body>
<h1>📊 台指期 TXFM2026</h1>
<div class="updated" id="updated">載入中...</div>
<div class="btn-group">
  <button class="btn btn-long active" id="btnLong" onclick="setMode('long')">📈 做多</button>
  <button class="btn btn-short" id="btnShort" onclick="setMode('short')">📉 做空</button>
</div>
<div class="card">
  <div class="row"><span class="row-label">現價</span><span class="row-value price" id="price">—</span></div>
  <div class="row"><span class="row-label">📅 今日最高點</span><span class="row-value high" id="todayHigh">—</span></div>
  <div class="row"><span class="row-label">距今日最高點</span><span class="row-value" id="diffTodayHigh">—</span></div>
  <div class="row"><span class="row-label">🏆 歷史最高點</span><span class="row-value high" id="histHigh">—</span></div>
  <div class="row"><span class="row-label">距歷史最高點</span><span class="row-value" id="diffHistHigh">—</span></div>
</div>
<div id="cardLow" class="card">
  <div class="row"><span class="row-label" id="sessionLabel">— 盤</span><span style="color:#8b949e;font-size:0.85rem" id="sessionName"></span></div>
  <div class="row"><span class="row-label">最低點</span><span class="row-value low" id="sessionLow">—</span></div>
  <div class="row"><span class="row-label">距最低點</span><span class="row-value" id="diffSessionLow">—</span></div>
</div>
<div id="cardHigh" class="card">
  <div class="row"><span class="row-label" id="otherLabel">— 盤</span><span style="color:#8b949e;font-size:0.85rem" id="otherName"></span></div>
  <div class="row"><span class="row-label">最高點</span><span class="row-value high" id="otherHigh">—</span></div>
  <div class="row"><span class="row-label">距最高點</span><span class="row-value" id="diffOtherHigh">—</span></div>
</div>
<script>
let latest = null, mode = 'long';
function fmt(n) { return n != null ? Number(n).toLocaleString() : '—'; }
function diff(price, level) {
  if (price == null || level == null) return '<span class="na">—</span>';
  const d = price - level, cls = d >= 0 ? 'diff-pos' : 'diff-neg';
  return '<span class="' + cls + '">' + (d >= 0 ? '+' : '') + d.toLocaleString() + ' 點</span>';
}
function currentSession() {
  const h = new Date().getHours(), m = new Date().getMinutes(), mins = h*60+m;
  return (mins >= 8*60+45 && mins <= 13*60+45) ? 'day' : 'pm';
}
function setMode(m) {
  mode = m;
  document.getElementById('btnLong').classList.toggle('active', m === 'long');
  document.getElementById('btnShort').classList.toggle('active', m === 'short');
  const priceCard = document.getElementById('cardLow').previousElementSibling;
  const cL = document.getElementById('cardLow'), cH = document.getElementById('cardHigh');
  if (m === 'long') { priceCard.after(cL); cL.after(cH); }
  else              { priceCard.after(cH); cH.after(cL); }
  if (latest) render(latest);
}
function render(d) {
  if (!d || d.error || !d.price) {
    document.getElementById('updated').textContent = '⏳ 等待 TradingView 連線中...';
    return;
  }
  document.getElementById('price').textContent          = fmt(d.price);
  document.getElementById('todayHigh').textContent      = fmt(d.todayHigh);
  document.getElementById('diffTodayHigh').innerHTML    = diff(d.price, d.todayHigh);
  document.getElementById('histHigh').textContent       = fmt(d.histHigh);
  document.getElementById('diffHistHigh').innerHTML     = diff(d.price, d.histHigh);
  const isDay = currentSession() === 'day';
  const low = isDay ? d.dayLow : d.pmLow, high = isDay ? d.dayHigh : d.pmHigh;
  const label = isDay ? '🌅 日盤' : '🌆 下午盤', range = isDay ? '08:45–13:45' : '15:00–';
  document.getElementById('sessionLabel').textContent = label + ' 當前盤';
  document.getElementById('sessionName').textContent  = range;
  document.getElementById('sessionLow').textContent   = low  ? fmt(low)  : '尚無資料';
  document.getElementById('diffSessionLow').innerHTML = diff(d.price, low);
  document.getElementById('otherLabel').textContent   = label + ' 當前盤';
  document.getElementById('otherName').textContent    = range;
  document.getElementById('otherHigh').textContent    = high ? fmt(high) : '尚無資料';
  document.getElementById('diffOtherHigh').innerHTML  = diff(d.price, high);
}
const es = new EventSource('/stream');
es.onmessage = e => { latest = JSON.parse(e.data); render(latest); };
// 等待連線提示（連線前每秒顯示點點動畫）
let dots = 0;
setInterval(() => {
  if (latest && latest.price) {
    document.getElementById('updated').textContent = '更新時間：' + new Date().toLocaleTimeString('zh-TW');
  } else {
    dots = (dots + 1) % 4;
    document.getElementById('updated').textContent = '⏳ 等待 TradingView 連線中' + '.'.repeat(dots);
  }
}, 1000);
</script>
</body>
</html>`;

/**
 * Start an HTTP webhook server that receives TradingView alert POSTs
 * and forwards them to LINE.
 *
 * TradingView alert setup:
 *   Webhook URL: http://localhost:<port>/webhook  (expose via ngrok)
 *   Message    : 🔔 蓁蓁買進訊號觸發！商品：{{ticker}} 價格：{{close}} 時間：{{time}}
 */
export function startWebhookServer(port = Number(process.env.WEBHOOK_PORT ?? 3000)) {
  const server = http.createServer(async (req, res) => {
    // Health probe
    if (req.method === 'GET' && req.url === '/health') {
      res.writeHead(200).end('OK');
      return;
    }

    // Dashboard HTML
    if (req.method === 'GET' && req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(DASHBOARD_HTML);
      return;
    }

    // Dashboard API
    if (req.method === 'GET' && req.url === '/api') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(getTVData() ?? {}));
      return;
    }

    // Dashboard SSE stream
    if (req.method === 'GET' && req.url === '/stream') {
      res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      });
      res.write(`data: ${JSON.stringify(getTVData() ?? {})}\n\n`);
      sseClients.add(res);
      req.on('close', () => sseClients.delete(res));
      return;
    }

    // LINE Bot webhook — captures user IDs from incoming messages
    if (req.method === 'POST' && req.url === '/line-webhook') {
      let body = '';
      req.on('data', chunk => (body += chunk));
      req.on('end', () => {
        try {
          const payload = JSON.parse(body);
          const events = payload.events ?? [];
          events.forEach(event => {
            const userId = event.source?.userId;
            const type   = event.type;
            const text   = event.message?.text ?? '';
            if (userId) {
              process.stderr.write(`[LINE Bot] userId=${userId} type=${type} text=${text}\n`);
            }
          });
        } catch {}
        res.writeHead(200).end('OK');
      });
      return;
    }

    if (req.method !== 'POST' || req.url !== '/webhook') {
      res.writeHead(404).end('Not found');
      return;
    }

    // Read body
    let body = '';
    req.on('data', chunk => (body += chunk));
    req.on('end', async () => {
      // TradingView sends the alert message as a plain-text body.
      // If the user formats it as JSON, parse out a "message" field.
      let message;
      try {
        const parsed = JSON.parse(body);
        message = parsed.message ?? JSON.stringify(parsed, null, 2);
      } catch {
        message = body.trim();
      }

      if (!message) {
        res.writeHead(400).end('Empty body');
        return;
      }

      try {
        await pushMessage(message);
        process.stderr.write(`[LINE webhook] ✅ Sent: ${message.slice(0, 80)}\n`);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch (err) {
        process.stderr.write(`[LINE webhook] ❌ ${err.message}\n`);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: err.message }));
      }
    });
  });

  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      const fallback = port + 1;
      process.stderr.write(`[LINE webhook] port ${port} 被佔用，改用 ${fallback}\n`);
      server.listen(fallback, () => {
        process.stderr.write(`[LINE webhook] Listening on http://localhost:${fallback}/webhook\n`);
      });
    } else {
      throw err;
    }
  });

  server.listen(port, () => {
    process.stderr.write(`[LINE webhook] Listening on http://localhost:${port}/webhook\n`);
    process.stderr.write(`[LINE webhook] Expose with: ngrok http ${port}\n`);
  });

  return server;
}
