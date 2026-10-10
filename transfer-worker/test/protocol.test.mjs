// Прогон протокола целиком против локального посредника: node test/protocol.test.mjs (при `wrangler dev --port 8799`).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const relay = process.env.RELAY || 'http://localhost:8799';
vm.runInThisContext(readFileSync(new URL('../../docs/app/transfer.js', import.meta.url), 'utf8'));
const T = globalThis.ZTransfer;

const payload = { v: 1, from: 'mac', notes: [{ id: 'a', title: 'Привет', text: 'x'.repeat(2_000_000) }] };

let code, sasR, sasS;
const received = T.receive({
  relay, onCode: c => { code = c; },
  confirm: async sas => { sasR = sas; return true; },
});
while (!code) await new Promise(r => setTimeout(r, 50));
assert.match(code, /^\d{6}$/);
await T.send({ relay, code, payload, confirm: async sas => { sasS = sas; return true; } });
const got = await received;
assert.deepEqual(got, payload);
assert.equal(sasR, sasS);
assert.match(sasS, /^\d{4}$/);
console.log('ok: перенос', JSON.stringify(payload).length, 'байт, цифры', sasS);

// Код одноразовый: вторая попытка войти отклоняется, комната после переноса удалена.
await assert.rejects(T.send({ relay, code, payload, confirm: async () => true }));

// Подмена: «посредник» с другим ключом даёт другие цифры.
const a = await T.newKeyPair(), b = await T.newKeyPair(), evil = await T.newKeyPair();
const honest = await T.derive(a.priv, b.pub, a.pub, b.pub);
const viaEvil = await T.derive(a.priv, evil.pub, a.pub, evil.pub);
assert.notEqual(honest.sas, viaEvil.sas);

// Шифртекст не открывается чужим ключом.
const k = await T.derive(a.priv, b.pub, a.pub, b.pub);
const sealed = await T.encrypt(k.key, new TextEncoder().encode('секрет'));
await assert.rejects(T.decrypt(viaEvil.key, sealed));

// Отправитель не должен слать в чужую комнату без join; несуществующий код — 404.
await assert.rejects(T.send({ relay, code: '000000', payload, confirm: async () => true }));
console.log('ok: защита');
