import { z } from 'zod';
import { jsonResult } from './_format.js';
import { pushMessage } from '../core/line.js';

export function registerLineTools(server) {
  server.tool(
    'line_push',
    'Send a LINE push message to the configured user (LINE_USER_ID in .env)',
    { text: z.string().describe('Message text to send via LINE') },
    async ({ text }) => {
      try { return jsonResult(await pushMessage(text)); }
      catch (err) { return jsonResult({ ok: false, error: err.message }, true); }
    },
  );
}
