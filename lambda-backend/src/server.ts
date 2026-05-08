// Thin Express wrapper around the existing Lambda handler.
//
// The handler is a single async function that accepts an APIGatewayProxyEvent-
// shaped object and returns an APIGatewayProxyResult. We adapt Express requests
// into that shape so the same 2.5k-line handler runs unchanged on a real
// server. This keeps the migration risk low — no rewrite, just a glue layer.
import express from 'express';
import type { Request, Response } from 'express';
import { handler } from './index';

const app = express();
app.disable('x-powered-by');

// Capture the raw body so we forward exactly what the Lambda handler expects
// (JSON.parse-ing is done inside the handler itself).
app.use(express.text({ type: '*/*', limit: '10mb' }));

app.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, service: 'omyday-api', ts: new Date().toISOString() });
});

app.all('*', async (req: Request, res: Response) => {
  try {
    const event = {
      httpMethod: req.method,
      path: req.path,
      headers: req.headers,
      queryStringParameters: req.query,
      body: req.body && typeof req.body === 'string' ? req.body : null,
      isBase64Encoded: false,
      requestContext: { identity: { sourceIp: req.ip } }
    };
    const result = await handler(event as any);
    res.status(result.statusCode || 200);
    if (result.headers) {
      for (const [k, v] of Object.entries(result.headers)) {
        if (k.toLowerCase() === 'content-length') continue;
        res.setHeader(k, v as string);
      }
    }
    res.send(result.body);
  } catch (err: any) {
    console.error('Unhandled error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

const port = Number(process.env.PORT) || 3000;
app.listen(port, '127.0.0.1', () => {
  console.log(`OMyDay API listening on 127.0.0.1:${port}`);
});

process.on('SIGTERM', () => process.exit(0));
process.on('SIGINT', () => process.exit(0));
