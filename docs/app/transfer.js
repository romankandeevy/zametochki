// Перенос заметок между Mac и iPhone по шестизначному коду.
// Ключ получается на устройствах (ECDH P-256 → HKDF), посредник видит только шифртекст.
// Протокол и формат те же, что в Sources/Zametki/TransferLink.swift.
(function (root) {
  const enc = new TextEncoder();
  const SALT = enc.encode('zametki-transfer-v1');
  const CHUNK = 900_000;

  const b64 = bytes => { let s = ''; for (const b of bytes) s += String.fromCharCode(b); return btoa(s); };
  const unb64 = str => Uint8Array.from(atob(str), c => c.charCodeAt(0));
  const concat = (...parts) => { const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0)); let at = 0; for (const p of parts) { out.set(p, at); at += p.length; } return out; };

  async function newKeyPair() {
    const pair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
    const pub = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey));
    return { priv: pair.privateKey, pub: b64(pub) };
  }

  /// Общий ключ AES-GCM и четыре цифры для сверки. receiverPub и sender Pub входят в вывод ключа - подмена видна по цифрам.
  async function derive(priv, theirPubB64, receiverPubB64, senderPubB64) {
    const theirs = await crypto.subtle.importKey('raw', unb64(theirPubB64), { name: 'ECDH', namedCurve: 'P-256' }, false, []);
    const secret = await crypto.subtle.deriveBits({ name: 'ECDH', public: theirs }, priv, 256);
    const ikm = await crypto.subtle.importKey('raw', secret, 'HKDF', false, ['deriveBits']);
    const binding = concat(unb64(receiverPubB64), unb64(senderPubB64));
    const bits = async (label, bytes) => new Uint8Array(await crypto.subtle.deriveBits(
      { name: 'HKDF', hash: 'SHA-256', salt: SALT, info: concat(enc.encode(label), binding) }, ikm, bytes * 8));
    const keyBytes = await bits('key', 32);
    const sasBytes = await bits('sas', 4);
    const sasNumber = ((sasBytes[0] << 24 | sasBytes[1] << 16 | sasBytes[2] << 8 | sasBytes[3]) >>> 0) % 10000;
    return {
      key: await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['encrypt', 'decrypt']),
      keyBytes, sas: String(sasNumber).padStart(4, '0'),
    };
  }

  /// nonce (12) + шифртекст + метка - как CryptoKit AES.GCM.SealedBox.combined.
  async function encrypt(key, bytes) {
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, key, bytes));
    return concat(nonce, ct);
  }
  async function decrypt(key, bytes) {
    return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.slice(0, 12) }, key, bytes.slice(12)));
  }

  // ── посредник ──
  async function call(relay, path, method = 'GET', body) {
    const res = await fetch(relay + path, { method, body });
    if (!res.ok) { const err = new Error('relay ' + res.status); err.status = res.status; throw err; }
    return res;
  }
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  /// Получатель: создаёт комнату, показывает код (onCode), ждёт отправителя, просит сверить цифры (confirm) и забирает данные.
  async function receive({ relay, onCode, confirm, signal }) {
    const mine = await newKeyPair();
    const { code } = await (await call(relay, '/s/new', 'POST', JSON.stringify({ pub: mine.pub }))).json();
    onCode(code);
    try {
      let state;
      for (;;) {
        if (signal && signal.aborted) throw new Error('cancelled');
        state = await (await call(relay, `/s/${code}`)).json();
        if (state.joined) break;
        await sleep(1200);
      }
      const { key, sas } = await derive(mine.priv, state.joined, mine.pub, state.joined);
      if (!(await confirm(sas))) throw new Error('mismatch');
      for (;;) {
        if (signal && signal.aborted) throw new Error('cancelled');
        state = await (await call(relay, `/s/${code}`)).json();
        if (state.count) break;
        await sleep(1000);
      }
      const parts = [];
      for (let i = 0; i < state.count; i++) parts.push(new Uint8Array(await (await call(relay, `/s/${code}/chunk/${i}`)).arrayBuffer()));
      const plain = await decrypt(key, concat(...parts));
      return JSON.parse(new TextDecoder().decode(plain));
    } finally {
      call(relay, `/s/${code}`, 'DELETE').catch(() => {});
    }
  }

  /// Отправитель: входит по коду, показывает цифры на сверку (confirm) и отправляет данные.
  async function send({ relay, code, payload, confirm }) {
    const mine = await newKeyPair();
    const { pub: receiverPub } = await (await call(relay, `/s/${code}/join`, 'POST', JSON.stringify({ pub: mine.pub }))).json();
    const { key, sas } = await derive(mine.priv, receiverPub, receiverPub, mine.pub);
    if (!(await confirm(sas))) throw new Error('mismatch');
    const sealed = await encrypt(key, enc.encode(JSON.stringify(payload)));
    const count = Math.ceil(sealed.length / CHUNK);
    for (let i = 0; i < count; i++) await call(relay, `/s/${code}/chunk/${i}`, 'PUT', sealed.slice(i * CHUNK, (i + 1) * CHUNK));
    await call(relay, `/s/${code}/done`, 'POST', JSON.stringify({ count }));
  }

  root.ZTransfer = { newKeyPair, derive, encrypt, decrypt, receive, send, b64, unb64, CHUNK };
})(globalThis);
