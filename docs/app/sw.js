// Заметочки офлайн: всё приложение лежит в кэше, заметки - в IndexedDB на устройстве.
// Новая версия - новое имя кэша; старый удаляется, когда новая встала.
const VERSION = 'zametochki-v8';
const FILES = ['./', 'index.html', 'app.css', 'whiteboard.js', 'app.js', 'manifest.webmanifest', 'Caveat.woff2',
  'apple-touch-icon.png', 'icon-192.png', 'icon-512.png', 'icon-maskable.png'];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(VERSION).then(cache => cache.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

// Есть сеть - берём свежую версию (так обновления приходят сразу), нет сети или она медленная - из кэша.
self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  event.respondWith(caches.open(VERSION).then(async cache => {
    const fromNet = fetch(req, { cache: 'no-cache' }).then(res => {
      if (res.ok) cache.put(req, res.clone());
      return res;
    });
    const slow = new Promise(res => setTimeout(res, 3000));
    try {
      const res = await Promise.race([fromNet, slow.then(() => null)]);
      if (res) return res;
    } catch {}
    const hit = await cache.match(req, { ignoreSearch: true });
    return hit || fromNet.catch(() => cache.match('index.html'));
  }));
});

// Нажали на уведомление-напоминание - открываем приложение на этой заметке.
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const note = event.notification.data && event.notification.data.note;
  event.waitUntil(self.clients.matchAll({ type: 'window' }).then(list => {
    for (const c of list) { c.focus(); c.postMessage({ open: note }); return; }
    return self.clients.openWindow('./' + (note ? '#n-' + note : ''));
  }));
});
