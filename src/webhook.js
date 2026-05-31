import http from 'http';
import { pushMessage } from './core/line.js';

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

  server.listen(port, () => {
    process.stderr.write(`[LINE webhook] Listening on http://localhost:${port}/webhook\n`);
    process.stderr.write(`[LINE webhook] Expose with: ngrok http ${port}\n`);
  });

  return server;
}
