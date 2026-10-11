// Посредник для переноса заметок между Mac и iPhone по шестизначному коду.
// Видит только зашифрованные куски: ключ получается на самих устройствах (ECDH), сюда он не попадает.
// Комната живёт 5 минут и стирается сама; в логи и базы ничего не пишется.

const TTL_MS = 5 * 60 * 1000;
const MAX_CHUNKS = 24;          // × ~900 КБ ≈ 20 МБ на перенос
const MAX_CHUNK_BYTES = 1_000_000;

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'access-control-allow-headers': 'content-type',
  'access-control-max-age': '86400',
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json', ...CORS } });

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    const url = new URL(request.url);
    const parts = url.pathname.split('/').filter(Boolean);
    if (parts[0] !== 's') return json({ error: 'not found' }, 404);

    // POST /s/new — выдать свободный код и создать комнату.
    if (parts[1] === 'new' && request.method === 'POST') {
      for (let attempt = 0; attempt < 8; attempt++) {
        const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, '0');
        const room = env.ROOM.get(env.ROOM.idFromName(code));
        const res = await room.fetch(new Request('https://room/init', { method: 'POST', body: await request.clone().text() }));
        if (res.status === 200) return json({ code });
      }
      return json({ error: 'busy' }, 503);
    }

    const code = parts[1];
    if (!/^\d{6}$/.test(code || '')) return json({ error: 'bad code' }, 400);
    const room = env.ROOM.get(env.ROOM.idFromName(code));
    const res = await room.fetch(new Request('https://room/' + parts.slice(2).join('/'), {
      method: request.method, body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
    }));
    return new Response(res.body, { status: res.status, headers: { ...Object.fromEntries(res.headers), ...CORS } });
  },
};

export class Room {
  constructor(ctx) { this.ctx = ctx; }

  async fetch(request) {
    const parts = new URL(request.url).pathname.split('/').filter(Boolean);
    const store = this.ctx.storage;
    const meta = await store.get('meta');
    const alive = meta && Date.now() < meta.expires;
    const op = parts[0];

    if (op === 'init' && request.method === 'POST') {
      if (alive) return json({ error: 'taken' }, 409);
      let body;
      try { body = await request.json(); } catch { return json({ error: 'bad body' }, 400); }
      if (typeof body.pub !== 'string' || body.pub.length > 200) return json({ error: 'bad key' }, 400);
      await store.deleteAll();
      await store.put('meta', { pub: body.pub, joined: null, count: null, expires: Date.now() + TTL_MS });
      await store.setAlarm(Date.now() + TTL_MS + 1000);
      return json({ ok: true });
    }
    if (!alive) return json({ error: 'gone' }, 404);

    // Отправитель входит по коду: получает ключ получателя, оставляет свой. Войти можно один раз.
    if (op === 'join' && request.method === 'POST') {
      if (meta.joined) return json({ error: 'already joined' }, 409);
      let body;
      try { body = await request.json(); } catch { return json({ error: 'bad body' }, 400); }
      if (typeof body.pub !== 'string' || body.pub.length > 200) return json({ error: 'bad key' }, 400);
      meta.joined = body.pub;
      await store.put('meta', meta);
      return json({ pub: meta.pub });
    }
    // Состояние: получатель ждёт отправителя, потом данные.
    if (!op && request.method === 'GET') {
      return json({ joined: meta.joined, count: meta.count });
    }
    if (op === 'chunk') {
      const n = Number(parts[1]);
      if (!Number.isInteger(n) || n < 0 || n >= MAX_CHUNKS) return json({ error: 'bad chunk' }, 400);
      if (request.method === 'PUT') {
        if (!meta.joined || meta.count !== null) return json({ error: 'not accepting' }, 409);
        const bytes = await request.arrayBuffer();
        if (bytes.byteLength === 0 || bytes.byteLength > MAX_CHUNK_BYTES) return json({ error: 'too big' }, 413);
        await store.put('c' + n, bytes);
        return json({ ok: true });
      }
      if (request.method === 'GET') {
        const bytes = await store.get('c' + n);
        if (!bytes) return json({ error: 'no chunk' }, 404);
        return new Response(bytes, { headers: { 'content-type': 'application/octet-stream' } });
      }
    }
    // Отправитель сообщает, сколько кусков.
    if (op === 'done' && request.method === 'POST') {
      let body;
      try { body = await request.json(); } catch { return json({ error: 'bad body' }, 400); }
      if (!Number.isInteger(body.count) || body.count < 1 || body.count > MAX_CHUNKS || meta.count !== null) return json({ error: 'bad count' }, 400);
      meta.count = body.count;
      await store.put('meta', meta);
      return json({ ok: true });
    }
    // Получатель скачал — комната больше не нужна.
    if (!op && request.method === 'DELETE') {
      await store.deleteAll();
      return json({ ok: true });
    }
    return json({ error: 'not found' }, 404);
  }

  async alarm() { await this.ctx.storage.deleteAll(); }
}
