# Посредник переноса заметок

Маленький Cloudflare Worker (Durable Object на SQLite), через который Mac и iPhone находят друг друга по шестизначному коду.

**Что он видит:** публичные ключи и зашифрованные куски. Ключ шифрования получается на самих устройствах (ECDH P-256 → HKDF), сюда он не попадает. Четыре цифры для сверки зависят от обоих ключей, поэтому подмену видно. Комната живёт 5 минут и стирается сама, код работает один раз, в логи ничего не пишется.

**Лимиты:** до ~20 МБ на перенос; тариф Workers Free хватает с большим запасом.

## Протокол

| | |
|---|---|
| `POST /s/new` `{pub}` | получатель создаёт комнату, в ответ `{code}` |
| `POST /s/{code}/join` `{pub}` | отправитель входит один раз, в ответ `{pub}` получателя |
| `GET /s/{code}` | `{joined, count}` - ждёт получатель |
| `PUT /s/{code}/chunk/{n}` | отправитель кладёт кусок (до ~1 МБ) |
| `POST /s/{code}/done` `{count}` | сколько кусков |
| `GET /s/{code}/chunk/{n}` · `DELETE /s/{code}` | получатель забирает и стирает |

Клиенты: `docs/app/transfer.js` (iPhone) и `Sources/Zametki/TransferLink.swift` (Mac) - формат один, это проверяют тесты с общими векторами.

## Поднять свой

```bash
cd transfer-worker
npm install
npx wrangler login      # один раз, откроется браузер
npx wrangler deploy     # напечатает адрес вида https://zametochki-transfer.<вы>.workers.dev
```

Адрес прописывается в `TransferLink.defaultRelay` (Mac) и `RELAY` в `docs/app/app.js` (iPhone).
Для своего адреса на Mac без пересборки: `defaults write com.romankandeevy.zametki transferRelay <url>`.

## Проверка

```bash
npx wrangler dev --port 8799 --local &
npm test                 # протокол целиком: 2 МБ, одноразовость кода, подмена, чужой ключ
```
