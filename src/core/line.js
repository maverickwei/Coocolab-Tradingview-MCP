import https from 'https';

/**
 * Push a LINE message to a single user with retry logic.
 */
async function pushToUser(token, userId, text, attempt = 1) {
  const body = JSON.stringify({ to: userId, messages: [{ type: 'text', text }] });
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'api.line.me',
        path: '/v2/bot/message/push',
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

/**
 * Send a LINE push message to all configured users.
 * Sends individually so each user's delivery is tracked independently.
 * Retries failed sends up to 3 times with 5s delay.
 */
export async function pushMessage(text) {
  const token = process.env.LINE_CHANNEL_TOKEN;

  const userIds = Object.entries(process.env)
    .filter(([k]) => k === 'LINE_USER_ID' || k.startsWith('LINE_USER_ID_'))
    .map(([, v]) => v)
    .filter(Boolean);

  if (!token || userIds.length === 0) {
    throw new Error('LINE_CHANNEL_TOKEN and LINE_USER_ID must be set in .env');
  }

  process.stderr.write(`[LINE] 送出對象(${userIds.length}人): ${userIds.join(', ')}\n`);

  const results = await Promise.all(userIds.map(async (userId) => {
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        await pushToUser(token, userId, text);
        process.stderr.write(`[LINE] ✅ ${userId.slice(0, 8)}... 成功 (第${attempt}次)\n`);
        return { userId, ok: true };
      } catch (err) {
        process.stderr.write(`[LINE] ❌ ${userId.slice(0, 8)}... 失敗 第${attempt}次: ${err.message}\n`);
        if (attempt < 3) await new Promise(r => setTimeout(r, 5000));
      }
    }
    return { userId, ok: false };
  }));

  const failed = results.filter(r => !r.ok);
  if (failed.length > 0) {
    process.stderr.write(`[LINE] ⚠️ ${failed.length} 人最終失敗: ${failed.map(r => r.userId.slice(0, 8)).join(', ')}\n`);
  }
  return { ok: true, results };
}
