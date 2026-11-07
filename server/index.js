import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
try {
  const env = await readFile(resolve(here, '.env'), 'utf8');
  for (const line of env.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/);
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  }
} catch {}

const PORT = Number(process.env.PORT || 8787);
const MAX_BYTES = 12 * 1024 * 1024;
const DAILY_LIMIT = Number(process.env.MAX_DAILY_ANALYSES || 20);
const usageByIp = new Map();
const isUsableApiKey = key => typeof key === 'string' && key.trim() !== '' && key.trim() !== 'add-your-kindwise-api-key';
const getApiKey = async () => {
  if (isUsableApiKey(process.env.PLANT_ID_API_KEY)) return process.env.PLANT_ID_API_KEY.trim();
  try {
    const env = await readFile(resolve(here, '.env'), 'utf8');
    const line = env.split(/\r?\n/).find(entry => /^\s*PLANT_ID_API_KEY\s*=/.test(entry));
    const value = line?.replace(/^\s*PLANT_ID_API_KEY\s*=\s*/, '').replace(/^['"]|['"]$/g, '').trim();
    if (isUsableApiKey(value)) {
      process.env.PLANT_ID_API_KEY = value;
      return value;
    }
  } catch {}
  return undefined;
};
const readable = value => typeof value === 'string' ? [value] : Array.isArray(value) ? value.flatMap(readable) : value && typeof value === 'object' ? Object.values(value).flatMap(readable) : [];
const server = createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.writeHead(204).end(); return; }
  const send = (status, data) => { res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(data)); };
  if (req.method === 'GET' && req.url === '/health') { send(200, { ok: true, aiConfigured: Boolean(await getApiKey()) }); return; }
  if (req.method !== 'POST' || !['/identify', '/diagnose'].includes(req.url)) { send(404, { error: 'Route not found' }); return; }
  const apiKey = await getApiKey();
  if (!apiKey) { send(503, { error: 'Add a Kindwise Plant.id API key to server/.env to enable photo analysis.' }); return; }
  const ip = req.socket.remoteAddress || 'unknown';
  const now = Date.now();
  const usage = usageByIp.get(ip);
  if (!usage || now - usage.startedAt >= 86400000) usageByIp.set(ip, { startedAt: now, count: 0 });
  const currentUsage = usageByIp.get(ip);
  if (currentUsage.count >= DAILY_LIMIT) { send(429, { error: 'Daily photo analysis limit reached. Try again tomorrow.' }); return; }
  try {
    let body = ''; let tooLarge = false;
    for await (const chunk of req) { body += chunk; if (Buffer.byteLength(body) > MAX_BYTES) { tooLarge = true; break; } }
    if (tooLarge) { send(413, { error: 'Photo too large. Choose a smaller image.' }); return; }
    const input = JSON.parse(body);
    if (typeof input.imageBase64 !== 'string' || input.imageBase64.length < 100) { send(400, { error: 'A valid plant photo is required.' }); return; }
    currentUsage.count += 1;
    const image = input.imageBase64.replace(/^data:image\/[\w.+-]+;base64,/, '');
    const diagnosis = req.url === '/diagnose';
    const upstream = await fetch('https://api.plant.id/v3/identification?details=common_names,local_name,treatment,description,watering&language=en', {
      method: 'POST', headers: { 'Api-Key': apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(diagnosis ? { images: [image], health: 'only' } : { images: [image] }),
      signal: AbortSignal.timeout(60000)
    });
    const result = await upstream.json().catch(() => ({}));
    if (!upstream.ok) { send(upstream.status, { error: result.message || result.error || 'Plant analysis service returned an error.' }); return; }
    if (diagnosis) {
      const assessment = result.result?.is_healthy;
      const diseases = result.result?.disease?.suggestions || [];
      send(200, { healthy: assessment?.binary === true, confidence: assessment?.probability || 0, diseases: diseases.map(d => ({ name: d.details?.local_name || d.name, probability: d.probability || 0, treatment: readable(d.details?.treatment).slice(0, 4).join(' ') || d.details?.description || '' })) });
    } else {
      const suggestions = result.result?.classification?.suggestions || [];
      send(200, { suggestions: suggestions.map(p => ({ name: p.name, probability: p.probability || 0, commonName: p.details?.common_names?.[0] || '', watering: p.details?.watering || null })) });
    }
  } catch (error) {
    const timedOut = error instanceof Error && ['AbortError', 'TimeoutError'].includes(error.name);
    send(timedOut ? 504 : 500, { error: timedOut ? 'Plant analysis took too long. Try another photo.' : error instanceof Error ? error.message : 'Photo analysis failed.' });
  }
});
server.listen(PORT, '0.0.0.0', () => console.log(`KYARI AI bridge listening on ${PORT}`));
