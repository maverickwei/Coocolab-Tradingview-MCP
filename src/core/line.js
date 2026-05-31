import https from 'https';

/**
 * Send a LINE push message via the Messaging API.
 * Reads LINE_CHANNEL_TOKEN and LINE_USER_ID from process.env.
 */
export async function pushMessage(text) {
  const token = process.env.LINE_CHANNEL_TOKEN;

  // Collect all configured user IDs (LINE_USER_ID, LINE_USER_ID_2, ...)
  const userIds = Object.entries(process.env)
    .filter(([k]) => k === 'LINE_USER_ID' || k.startsWith('LINE_USER_ID_'))
    .map(([, v]) => v)
    .filter(Boolean);

  if (!token || userIds.length === 0) {
    throw new Error('LINE_CHANNEL_TOKEN and LINE_USER_ID must be set in .env');
  }

  // Use multicast when multiple recipients, push when single
  const endpoint = userIds.length > 1 ? '/v2/bot/message/multicast' : '/v2/bot/message/push';
  const body = userIds.length > 1
    ? JSON.stringify({ to: userIds, messages: [{ type: 'text', text }] })
    : JSON.stringify({ to: userIds[0], messages: [{ type: 'text', text }] });

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'api.line.me',
        path: endpoint,
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = '';
        res.on('data', chunk => (data += chunk));
        res.on('end', () => {
          if (res.statusCode === 200) {
            resolve({ ok: true });
          } else {
            reject(new Error(`LINE API ${res.statusCode}: ${data}`));
          }
        });
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}
