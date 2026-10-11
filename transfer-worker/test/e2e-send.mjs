// Сквозная проверка с Swift-тестом TransferE2ETests: браузерный код отправляет «с телефона», принимает Mac; и обратно.
import { readFileSync, writeFileSync, existsSync, unlinkSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
vm.runInThisContext(readFileSync(new URL('../../docs/app/transfer.js', import.meta.url), 'utf8'));
const T = globalThis.ZTransfer, relay = process.env.RELAY || 'http://localhost:8799';
const wait = async f => { while (!existsSync(f)) await new Promise(r => setTimeout(r, 100)); await new Promise(r => setTimeout(r, 200)); return readFileSync(f, 'utf8'); };

// 1. Mac принимает: код пишет Swift.
const code = await wait('/tmp/ztransfer-code');
let sasPhone;
await T.send({ relay, code, payload: { v: 1, from: 'phone', notes: [{ id: 'p1', md: '# Привет\nс телефона' }] }, confirm: async s => { sasPhone = s; return true; } });
assert.equal(await wait('/tmp/ztransfer-sas-mac'), sasPhone);
console.log('ok: Mac принял, цифры', sasPhone);

// 2. Mac отправляет: код создаёт браузерный получатель.
let got, sas2;
const pending = T.receive({ relay, onCode: c => writeFileSync('/tmp/ztransfer-code-phone', c), confirm: async s => { sas2 = s; return true; } });
got = await pending;
assert.equal(got.notes[0].doc.text, 'Заметка с Mac');
assert.equal(await wait('/tmp/ztransfer-sas-mac2'), sas2);
console.log('ok: Mac отправил, цифры', sas2);
