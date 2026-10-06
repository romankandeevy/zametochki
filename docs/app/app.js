'use strict';
// Заметочки для iPhone: то же, что на Mac, только в браузере и на телефоне.
// Заметки - в IndexedDB этого устройства, в сеть ничего не уходит. С Маком - через Markdown и JSON-файлы.
(() => {
  // ───────── мелочи ─────────
  /// Видно в настройках: по нему ясно, доехало ли обновление.
  const APP_VERSION = 6;
  const $ = s => document.querySelector(s);
  const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const plural = (n, a, b, c) => { const x = n % 100, y = n % 10; return x > 10 && x < 15 ? c : y === 1 ? a : y > 1 && y < 5 ? b : c; };
  const local = {
    get(k, d) { try { const v = localStorage.getItem('z.' + k); return v === null ? d : JSON.parse(v); } catch { return d; } },
    set(k, v) { try { localStorage.setItem('z.' + k, JSON.stringify(v)); } catch {} },
  };
  const plainOf = html => { const d = document.createElement('div'); d.innerHTML = html || ''; return d.textContent.replace(/ /g, ' '); };
  const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  const ICON = {
    bullet: '<svg viewBox="0 0 24 24"><circle cx="5" cy="7" r="1.4"/><circle cx="5" cy="17" r="1.4"/><path d="M10 7h10M10 17h10"/></svg>',
    todo: '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="4"/><path d="m8.5 12 2.5 2.5 4.5-5"/></svg>',
    chevron: '<svg viewBox="0 0 24 24"><path d="m9 6 6 6-6 6"/></svg>',
    page: '<svg viewBox="0 0 24 24"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h4"/></svg>',
    image: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-9 9"/></svg>',
    board: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16M15 4v16"/></svg>',
    audio: '<svg viewBox="0 0 24 24"><path d="M4 10v4M8 7v10M12 4v16M16 8v8M20 11v2"/></svg>',
    table: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="3"/><path d="M3 10h18M3 15h18M10 4v16"/></svg>',
    divider: '<svg viewBox="0 0 24 24"><path d="M4 12h16"/></svg>',
    template: '<svg viewBox="0 0 24 24"><rect x="8" y="8" width="13" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/></svg>',
    bell: '<svg viewBox="0 0 24 24"><path d="M12 3a6 6 0 0 0-6 6v3.6L4.4 15.5A1 1 0 0 0 5.3 17h13.4a1 1 0 0 0 .9-1.5L18 12.6V9a6 6 0 0 0-6-6zM9.5 19a2.5 2.5 0 0 0 5 0"/></svg>',
    play: '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
    file: '<svg viewBox="0 0 24 24"><path d="M21 11.5 12.6 20a5.5 5.5 0 0 1-7.8-7.8l8.5-8.5a3.7 3.7 0 0 1 5.2 5.2l-8.5 8.5a1.8 1.8 0 0 1-2.6-2.6l7.8-7.8"/></svg>',
    pause: '<svg viewBox="0 0 24 24"><path d="M7 5h4v14H7zM13 5h4v14h-4z"/></svg>',
  };

  // ───────── типы блоков ─────────
  const BASIC = [
    ['text', 'Текст', 'Аа', '', ['текст', 'text', 'обычн']],
    ['title', 'Заголовок', 'H', '#', ['h1', 'заголовок', 'title']],
    ['heading', 'Подзаголовок', 'H2', '##', ['h2', 'подзаголовок']],
    ['subheading', 'Маленький заголовок', 'H3', '###', ['h3', 'маленький']],
    ['bullet', 'Список', ICON.bullet, '-', ['список', 'list', 'точк']],
    ['numbered', 'Нумерованный список', '1.', '1.', ['нумер', 'number']],
    ['todo', 'Чеклист', ICON.todo, '[]', ['чек', 'задач', 'todo']],
    ['toggle', 'Сворачиваемый список', '▸', '+', ['свор', 'toggle']],
    ['quote', 'Цитата', '❝', '>', ['цитат', 'quote']],
    ['code', 'Код', '&lt;/&gt;', '```', ['код', 'code']],
  ];
  const OBJECTS = [
    ['image', 'Картинка', ICON.image, 'Из фото или камеры', ['картин', 'фото', 'image']],
    ['file', 'Файл', ICON.file, 'Любой файл с телефона', ['файл', 'file', 'вложен']],
    ['board', 'Доска', ICON.board, 'Канбан: колонки и карточки', ['доск', 'канбан', 'board']],
    ['audio', 'Голосовая заметка', ICON.audio, 'Запись с расшифровкой', ['голос', 'аудио', 'запис', 'voice']],
    ['table', 'Таблица', ICON.table, 'Строки и столбцы', ['табл', 'table']],
    ['divider', 'Разделитель', ICON.divider, 'Линия', ['раздел', 'линия', '---']],
    ['page', 'Страница', ICON.page, 'Страница внутри заметки', ['страниц', 'page']],
    ['template', 'Шаблон', ICON.template, 'Встреча, план недели, идея…', ['шабл', 'templ', 'встреч', 'план']],
  ];
  const OBJECT_TYPES = new Set(['image', 'file', 'board', 'audio', 'table', 'divider', 'page']);
  const isObject = b => OBJECT_TYPES.has(b.type);
  const CONTINUES = new Set(['bullet', 'numbered', 'todo', 'done', 'quote', 'toggleItem', 'code']);
  const SHORTCUTS = [['###', 'subheading'], ['##', 'heading'], ['#', 'title'], ['[ ]', 'todo'], ['[]', 'todo'],
    ['1.', 'numbered'], ['-', 'bullet'], ['*', 'bullet'], ['>', 'quote'], ['+', 'toggle'], ['```', 'code']];
  const HINTS = { text: 'Пиши… или нажми /', title: 'Заголовок', heading: 'Подзаголовок', subheading: 'Маленький заголовок',
    bullet: 'Пункт списка', numbered: 'Пункт списка', todo: 'Задача', done: 'Задача', toggle: 'Сворачиваемый список',
    toggleItem: 'Внутри списка', quote: 'Цитата', code: 'Код' };

  // ───────── цвета текста и маркера (как на Mac) ─────────
  const TEXT_COLORS = [['white', '#ffffff', 'Белый'], ['yellow', '#ffe07a', 'Жёлтый'], ['pink', '#ffa8cc', 'Розовый'], ['green', '#a3f0b8', 'Зелёный'],
    ['sky', '#a3dbff', 'Голубой'], ['gray', '#a6a9b8', 'Серый'], ['orange', '#ffb873', 'Оранжевый'], ['lavender', '#ccbaff', 'Лавандовый'],
    ['mint', '#99ffe0', 'Мятный'], ['peach', '#ffccb8', 'Персиковый'], ['lemon', '#fff79e', 'Лимонный'], ['coral', '#ff8f8f', 'Коралловый'], ['blue', '#94b8ff', 'Синий']];
  const MARKS = [['yellow', 'rgba(255, 217, 77, 0.32)', 'Жёлтый'], ['green', 'rgba(89, 230, 128, 0.3)', 'Зелёный'], ['blue', 'rgba(89, 166, 255, 0.35)', 'Синий'],
    ['pink', 'rgba(255, 115, 191, 0.32)', 'Розовый'], ['purple', 'rgba(166, 115, 255, 0.35)', 'Фиолетовый'], ['orange', 'rgba(255, 153, 64, 0.34)', 'Оранжевый'],
    ['red', 'rgba(255, 77, 77, 0.34)', 'Красный'], ['gray', 'rgba(255, 255, 255, 0.18)', 'Серый']];
  /// Браузер записывает цвет по-своему («rgba(255, 217, 77, 0.32)») - узнаём маркер по нормальной записи.
  const markByColor = (() => {
    const map = new Map(), probe = document.createElement('i');
    for (const [key, c] of MARKS) { probe.style.backgroundColor = c; map.set(probe.style.backgroundColor, key); }
    return color => { probe.style.backgroundColor = color; return map.get(probe.style.backgroundColor) || 'yellow'; };
  })();

  // ───────── стили страниц (как на Mac) ─────────
  const COLORS = [['blue', '#1D3594'], ['navy', '#121a45'], ['violet', '#452e85'], ['forest', '#174538'], ['wine', '#541f33'],
    ['graphite', '#26292e'], ['clay', '#783d29'], ['teal', '#0a4d54'], ['plum', '#542161'], ['rose', '#782947'],
    ['olive', '#40451f'], ['slate', '#29384f'], ['cocoa', '#452e24'], ['ink', '#0f1217']];
  const GRADIENTS = [['ocean', '#1c3594', '#0a6b85'], ['sunset', '#542a8c', '#9e3854'], ['night', '#1a2461', '#080a1a'],
    ['aurora', '#0f544d', '#242e85'], ['dawn', '#8c472e', '#3d246b'], ['lagoon', '#085c66', '#0d2654']];
  const FONTS = [['hand', 'От руки', 'var(--hand)'], ['system', 'Обычный', 'var(--ui)'],
    ['serif', 'С засечками', '"New York", ui-serif, Georgia, serif'], ['mono', 'Моно', 'var(--mono)'],
    ['rounded', 'Округлый', 'ui-rounded, "SF Pro Rounded", var(--ui)']];
  const defaultStyle = () => local.get('defaultStyle', { font: 'hand', bg: 'color:blue', bullet: 'dot' });
  const textScale = () => local.get('scale', 1);
  function styleVars(style) {
    const s = style || defaultStyle();
    const [kind, id] = (s.bg || 'color:blue').split(':');
    let bg, base, bottom;
    if (kind === 'gradient') {
      const g = GRADIENTS.find(x => x[0] === id) || GRADIENTS[0];
      bg = `linear-gradient(180deg, ${g[1]}, ${g[2]})`; base = g[1]; bottom = g[2];
    } else if (kind === 'image') {
      base = '#14171f'; bg = base; bottom = base;
    } else {
      base = (COLORS.find(x => x[0] === id) || COLORS[0])[1]; bg = base; bottom = base;
    }
    const font = (FONTS.find(f => f[0] === s.font) || FONTS[0]);
    const hand = font[0] === 'hand';
    const text = (TEXT_COLORS.find(c => c[0] === s.text) || TEXT_COLORS[0])[1];
    return { bg, base, bottom, font: font[2], fontKey: font[0], px: (hand ? 27 : 17.5) * textScale(), size: (hand ? 27 : 17.5) * textScale() + 'px',
      line: hand ? 1.28 : 1.5, dash: s.bullet === 'dash', text, image: kind === 'image' ? id : null, cover: s.cover || null,
      divider: s.divider || 'line', card: s.card || 'plain', wide: s.width === 'wide' };
  }

  // ───────── хранилище: IndexedDB ─────────
  const DB = {
    db: null,
    open() {
      return new Promise((resolve, reject) => {
        const req = indexedDB.open('zametochki', 2);
        req.onupgradeneeded = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains('notes')) db.createObjectStore('notes', { keyPath: 'id' });
          if (!db.objectStoreNames.contains('files')) db.createObjectStore('files', { keyPath: 'id' });
          if (!db.objectStoreNames.contains('backups')) db.createObjectStore('backups', { keyPath: 'key' });
        };
        req.onsuccess = () => { this.db = req.result; resolve(); };
        req.onerror = () => reject(req.error);
      });
    },
    tx(store, mode, fn) {
      return new Promise((resolve, reject) => {
        const t = this.db.transaction(store, mode);
        const res = fn(t.objectStore(store));
        t.oncomplete = () => resolve(res && res.result !== undefined ? res.result : res);
        t.onerror = () => reject(t.error);
      });
    },
    all(store) { return this.tx(store, 'readonly', s => s.getAll()); },
    get(store, id) { return this.tx(store, 'readonly', s => s.get(id)); },
    put(store, obj) { return this.tx(store, 'readwrite', s => s.put(obj)); },
    del(store, id) { return this.tx(store, 'readwrite', s => s.delete(id)); },
  };

  // ───────── заметки ─────────
  const notes = new Map();
  let openId = null;
  let expanded = new Set(local.get('expanded', []));
  const saveTimers = new Map();

  const note = id => notes.get(id);
  const blocksText = n => n.blocks.filter(b => !isObject(b)).map(b => plainOf(b.html));
  function titleOf(n) { return blocksText(n).map(t => t.trim()).find(Boolean) || 'Без названия'; }
  function previewOf(n) { return blocksText(n).map(t => t.trim()).filter(Boolean)[1] || ''; }
  const children = parent => [...notes.values()].filter(n => (n.parent || null) === parent).sort((a, b) => a.order - b.order);

  const written = new Map(); // id → последняя записанная версия (JSON) - для резервных копий
  const textLength = n => blocksText(n).join('\n').length + boardText(n).length;
  function write(n) {
    saveTimers.delete(n.id);
    keepVersion(n);
    DB.put('notes', n).catch(e => toast('Не сохранилось: ' + e.message));
  }
  /// Как на Mac: заметка разом потеряла заметную часть текста - прошлая версия кладётся в резервные.
  function keepVersion(n) {
    const prev = written.get(n.id);
    const now = JSON.stringify(n);
    written.set(n.id, now);
    if (!prev) return;
    const old = JSON.parse(prev), lost = textLength(old) - textLength(n);
    if (!(lost >= 40 || (lost >= 12 && textLength(n) < textLength(old) * 0.5))) return;
    DB.put('backups', { key: n.id + '@' + Date.now(), note: n.id, saved: Date.now(), data: old }).catch(() => {});
  }
  function save(n, now = true) {
    n.modified = Date.now();
    clearTimeout(saveTimers.get(n.id));
    if (now) write(n); else saveTimers.set(n.id, setTimeout(() => write(n), 250));
    scheduleListRender();
    scheduleReminders();
  }
  function flushSaves() { for (const [id, t] of saveTimers) { clearTimeout(t); const n = note(id); if (n) write(n); } saveTimers.clear(); }
  addEventListener('pagehide', flushSaves);
  document.addEventListener('visibilitychange', () => { if (document.hidden) flushSaves(); });

  function newNote({ parent = null, blocks = null, style = null, open = true } = {}) {
    const siblings = children(parent);
    const n = {
      id: uid(), parent,
      order: parent ? (siblings.length ? siblings[siblings.length - 1].order + 1 : 0) : (siblings.length ? siblings[0].order - 1 : 0),
      style: style || (parent && note(parent) ? note(parent).style : null) || defaultStyle(),
      blocks: blocks || [{ id: uid(), type: 'title', html: '' }],
      created: Date.now(), modified: Date.now(),
    };
    notes.set(n.id, n);
    save(n);
    if (parent) { expanded.add(parent); local.set('expanded', [...expanded]); }
    if (open) openNote(n.id, true);
    return n;
  }

  /// Заметка и все её страницы - в удалённые; несколько секунд можно вернуть.
  function deleteNote(id) {
    const gone = [];
    const walk = nid => { for (const c of children(nid)) walk(c.id); const n = note(nid); if (n) { gone.push(n); notes.delete(nid); DB.del('notes', nid); } };
    walk(id);
    const parent = gone.length ? gone[gone.length - 1].parent : null;
    if (parent && note(parent)) {
      const p = note(parent);
      p.blocks = p.blocks.filter(b => !(b.type === 'page' && b.page === id));
      save(p);
    }
    showList();
    if (parent && note(parent)) openNote(parent);
    renderList();
    toast(gone.length > 1 ? `Удалено заметок: ${gone.length}` : 'Заметка удалена', 'Вернуть', () => {
      for (const n of gone) { notes.set(n.id, n); DB.put('notes', n); }
      if (parent && note(parent)) {
        const p = note(parent);
        if (!p.blocks.some(b => b.page === id)) { p.blocks.push({ id: uid(), type: 'page', page: id }); save(p); }
      }
      renderList();
      openNote(id);
    });
  }

  // ───────── список ─────────
  const listEl = $('#notes');
  let query = '';
  let listTimer = null;
  const scheduleListRender = () => { clearTimeout(listTimer); listTimer = setTimeout(renderList, 400); };

  function when(ts) {
    const d = new Date(ts), now = new Date();
    if (now - d < 60000) return 'Сейчас';
    const sameDay = (a, b) => a.toDateString() === b.toDateString();
    const hm = d.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
    if (sameDay(d, now)) return 'Сегодня, ' + hm;
    const y = new Date(now); y.setDate(now.getDate() - 1);
    if (sameDay(d, y)) return 'Вчера';
    return d.toLocaleDateString('ru-RU', { day: 'numeric', month: 'short' });
  }

  function renderList() {
    clearTimeout(listTimer);
    const q = query.trim().toLowerCase();
    const rows = [];
    if (q) {
      for (const n of [...notes.values()].sort((a, b) => b.modified - a.modified)) {
        if (blocksText(n).join('\n').toLowerCase().includes(q) || boardText(n).includes(q)) rows.push([n, 0]);
      }
    } else {
      const walk = (parent, depth) => {
        for (const n of children(parent)) { rows.push([n, depth]); if (expanded.has(n.id)) walk(n.id, depth + 1); }
      };
      walk(null, 0);
    }
    if (!rows.length) {
      listEl.innerHTML = q ? `<div class="empty">Ничего не нашлось по «${esc(query)}»</div>`
        : '<div class="empty"><b>Пусто</b>Нажми + внизу - и пиши.</div>';
      return;
    }
    listEl.innerHTML = rows.map(([n, depth]) => {
      const kids = !q && children(n.id).length > 0;
      const preview = previewOf(n);
      return `<div class="row${depth ? ' child' : ''}${n.id === openId ? ' on' : ''}" role="listitem" data-id="${n.id}" style="padding-left:${8 + depth * 16}px">
        ${kids ? `<button class="twist${expanded.has(n.id) ? ' open' : ''}" data-twist="${n.id}" aria-label="Раскрыть">${ICON.chevron}</button>` : '<span class="twist"></span>'}
        <button class="body" data-open="${n.id}"><span class="t">${esc(titleOf(n))}</span>${depth ? '' : `<span class="m">${when(n.modified)}${preview ? ' · ' + esc(preview) : ''}</span>`}</button>
      </div>`;
    }).join('');
  }
  const boardText = n => n.blocks.filter(b => b.type === 'board').flatMap(b => b.columns.flatMap(c => [c.title, ...c.cards.map(k => k.text)])).join('\n').toLowerCase();

  listEl.addEventListener('click', e => {
    const twist = e.target.closest('[data-twist]');
    if (twist) {
      const id = twist.dataset.twist;
      expanded.has(id) ? expanded.delete(id) : expanded.add(id);
      local.set('expanded', [...expanded]);
      return renderList();
    }
    const open = e.target.closest('[data-open]');
    if (open) openNote(open.dataset.open, true);
  });
  $('#search').addEventListener('input', e => { query = e.target.value; renderList(); });

  // ───────── экраны ─────────
  const listScreen = $('#list'), noteScreen = $('#note'), editor = $('#editor'), scroller = $('#scroller');
  const wide = () => matchMedia('(min-width: 900px)').matches;

  /// Пустая заметка без страниц внутри - как на Mac: ушёл из неё, её нет. Страницы-внутри не трогаем: у них карточка в родителе.
  const isEmptyNote = n => !n.parent && !children(n.id).length && n.id !== local.get('inbox', null)
    && n.blocks.every(b => !isObject(b) && !plainOf(b.html).trim());
  function dropIfEmpty(id) {
    const n = note(id);
    if (!n || !isEmptyNote(n)) return;
    clearTimeout(saveTimers.get(id)); saveTimers.delete(id);
    notes.delete(id);
    DB.del('notes', id).catch(() => {});
  }
  /// Уходим со страницы: клавиатура и панель над ней прячутся, пустая заметка удаляется.
  function leaveNote(next) {
    hideKeyboard();
    if (openId && openId !== next) dropIfEmpty(openId);
  }
  function hideKeyboard() {
    if (document.activeElement && editor.contains(document.activeElement)) document.activeElement.blur();
    $('#kbar').hidden = true;
    noteScreen.classList.remove('typing');
    setTimeout(fitViewport, 350);
  }

  function openNote(id, push = false) {
    const n = note(id);
    if (!n) return;
    flushSaves();
    leaveNote(id);
    openId = id;
    document.body.classList.remove('no-note');
    if (!wide()) { listScreen.hidden = true; }
    noteScreen.hidden = false;
    applyStyle(n.style);
    renderNote();
    scroller.scrollTop = 0;
    const parent = n.parent && note(n.parent);
    $('#back-label').textContent = parent ? titleOf(parent) : 'Заметки';
    renderList();
    local.set('lastOpen', id);
    // Одна запись в истории: жест или кнопка «назад» у телефона возвращают к списку.
    if (push && !wide() && !(history.state && history.state.note)) history.pushState({ note: true }, '');
    // Новая пустая заметка - сразу печатать.
    if (n.blocks.length === 1 && !plainOf(n.blocks[0].html)) setTimeout(() => focusBlock(n.blocks[0], 0), 60);
  }

  function showList() {
    flushSaves();
    closePopup();
    leaveNote(null);
    if (!wide()) { noteScreen.hidden = true; listScreen.hidden = false; openId = null; document.body.classList.add('no-note'); }
    setThemeColor('#1D3594', 'linear-gradient(180deg, #1D3594, #142670)');
    renderList();
  }

  function goBack() {
    const n = note(openId);
    if (n && n.parent && note(n.parent)) return openNote(n.parent);
    if (history.state && history.state.note) history.back(); else showList();
  }
  $('#btn-back').addEventListener('click', goBack);
  addEventListener('popstate', () => showList());

  /// Цвет вокруг приложения: зона часов сверху, полоска снизу и фон под страницей - в цвет открытой заметки.
  function setThemeColor(c, bg = c) {
    const m = document.querySelector('meta[name="theme-color"]');
    if (m) m.content = c;
    document.documentElement.style.background = bg;
    document.body.style.background = bg;
  }
  function applyStyle(style) {
    const v = styleVars(style);
    noteScreen.style.setProperty('--page-bg', v.bg);
    noteScreen.style.setProperty('--page-base', v.base);
    noteScreen.style.setProperty('--page-font', v.font);
    noteScreen.style.setProperty('--page-size', v.size);
    noteScreen.style.setProperty('--page-line', v.line);
    noteScreen.style.setProperty('--page-fg', v.text);
    noteScreen.classList.toggle('dash', v.dash);
    noteScreen.classList.toggle('wide', v.wide);
    noteScreen.classList.toggle('div-dots', v.divider === 'dots');
    noteScreen.classList.toggle('div-washi', v.divider === 'washi');
    noteScreen.classList.toggle('cards-outline', v.card === 'outline');
    noteScreen.classList.toggle('cards-filled', v.card === 'filled');
    $('#kbar').style.setProperty('--page-base', v.base);
    setThemeColor(v.base, v.bg);
    // Своя картинка фоном - размытая и притемнённая; обложка - полосой сверху.
    const img = $('#page-img'), cover = $('#cover');
    img.style.backgroundImage = '';
    if (v.image) fileURL(v.image).then(u => { if (u) img.style.backgroundImage = `url("${u}")`; });
    cover.hidden = !v.cover;
    cover.style.backgroundImage = '';
    if (v.cover) fileURL(v.cover).then(u => { if (u) cover.style.backgroundImage = `url("${u}")`; });
  }

  // ───────── отрисовка заметки ─────────
  const blockById = id => note(openId) && note(openId).blocks.find(b => b.id === id);
  const elOf = b => editor.querySelector(`.blk[data-id="${b.id}"]`);
  const blockOfEl = el => { const blk = el && el.closest && el.closest('.blk'); return blk ? blockById(blk.dataset.id) : null; };

  function renderNote() {
    const n = note(openId);
    editor.replaceChildren(...n.blocks.map(renderBlock));
    decorate();
    updateStats();
  }

  function renderBlock(b) {
    const el = document.createElement('div');
    el.dataset.id = b.id;
    if (isObject(b)) {
      el.className = `blk obj b-${b.type}`;
      el.innerHTML = objectHTML(b) + `<div class="objbar">${b.type === 'image' ? '<button data-obj="size">Размер</button>' : ''}<button data-obj="up" aria-label="Выше">↑</button><button data-obj="down" aria-label="Ниже">↓</button><button class="del" data-obj="del">Удалить</button></div>`;
      if (b.type === 'image') loadImage(b, el);
      if (b.type === 'audio') setupPlayer(b, el);
      return el;
    }
    el.className = `blk b-${b.type}${b.collapsed ? ' collapsed' : ''}`;
    const txt = document.createElement('div');
    txt.className = 'txt';
    txt.contentEditable = 'true';
    txt.dataset.hint = HINTS[b.type] || '';
    if (b.type === 'code') { txt.textContent = plainOf(b.html); txt.setAttribute('autocapitalize', 'off'); txt.setAttribute('autocorrect', 'off'); txt.spellcheck = false; }
    else { txt.innerHTML = b.html || ''; txt.setAttribute('autocapitalize', 'sentences'); }
    el.append(markerFor(b), txt);
    return el;
  }

  function markerFor(b) {
    const m = document.createElement('span');
    m.className = 'marker';
    m.contentEditable = 'false';
    if (b.type === 'todo' || b.type === 'done') m.innerHTML = '<span class="check" role="checkbox" aria-label="Отметить"></span>';
    else if (b.type === 'toggle') m.innerHTML = ICON.chevron;
    else if (!['bullet', 'numbered'].includes(b.type)) m.hidden = true;
    return m;
  }

  /// Поменять тип строки, не пересоздавая поле ввода: курсор и клавиатура остаются на месте.
  function setType(b, type) {
    const el = elOf(b);
    b.type = type;
    if (type !== 'toggle') delete b.collapsed;
    if (el) {
      el.className = `blk b-${type}`;
      el.querySelector('.marker').replaceWith(markerFor(b));
      const txt = el.querySelector('.txt');
      txt.dataset.hint = HINTS[type] || '';
    }
    decorate();
    save(note(openId), false);
  }

  /// Нумерация, свёрнутые списки, края блоков кода, напоминания у задач.
  function decorate() {
    const n = note(openId);
    if (!n) return;
    let num = 0, collapsed = false;
    const now = new Date();
    n.blocks.forEach((b, i) => {
      const el = elOf(b);
      if (!el) return;
      num = b.type === 'numbered' ? num + 1 : 0;
      if (b.type === 'numbered') el.querySelector('.marker').textContent = num + '.';
      if (b.type === 'toggle') collapsed = !!b.collapsed;
      else if (b.type !== 'toggleItem') collapsed = false;
      el.classList.toggle('hidden-item', b.type === 'toggleItem' && collapsed);
      if (b.type === 'code') {
        const first = (n.blocks[i - 1] || {}).type !== 'code';
        el.classList.toggle('first', first);
        el.classList.toggle('last', (n.blocks[i + 1] || {}).type !== 'code');
        codeLine(n, b, el, i, first);
      }
      remindChip(b, el, now);
    });
  }

  // ───────── код: язык, подсветка, «Скопировать» ─────────
  /// Подряд идущие строки кода - один блок; язык (выбранный или угаданный) хранится на первой строке.
  function codeGroup(n, i) {
    let a = i, z = i;
    while (a > 0 && n.blocks[a - 1].type === 'code') a--;
    while (z < n.blocks.length - 1 && n.blocks[z + 1].type === 'code') z++;
    return n.blocks.slice(a, z + 1);
  }
  function codeLine(n, b, el, i, first) {
    const group = codeGroup(n, i);
    const head = group[0];
    const lang = head.lang || Code.detect(group.map(x => plainOf(x.html)).join('\n'));
    let bar = el.querySelector('.codehead');
    if (first) {
      if (!bar) { bar = document.createElement('div'); bar.className = 'codehead'; bar.contentEditable = 'false'; el.prepend(bar); }
      bar.innerHTML = `<span>КОД</span><button data-lang>${head.lang ? '' : 'Авто · '}${esc(Code.name(lang))} ▾</button><button data-copy>Скопировать</button>`;
    } else if (bar) bar.remove();
    const txt = el.querySelector('.txt');
    if (document.activeElement !== txt) txt.innerHTML = Code.paint(plainOf(b.html), lang) || '';
  }

  const Code = {
    langs: [['swift', 'Swift'], ['python', 'Python'], ['javascript', 'JavaScript'], ['typescript', 'TypeScript'], ['html', 'HTML'], ['css', 'CSS'],
      ['json', 'JSON'], ['bash', 'Bash'], ['sql', 'SQL'], ['go', 'Go'], ['rust', 'Rust'], ['kotlin', 'Kotlin'], ['java', 'Java'], ['c', 'C'],
      ['cpp', 'C++'], ['ruby', 'Ruby'], ['php', 'PHP'], ['plain', 'Текст']],
    name(l) { return (this.langs.find(x => x[0] === l) || this.langs[this.langs.length - 1])[1]; },
    /// Те же приметы, что на Mac.
    detect(t) {
      const has = s => t.includes(s);
      if (has('import SwiftUI') || has('import Foundation') || (has('func ') && (has('let ') || has('var ')) && has('{')) || has('guard let')) return 'swift';
      if (has('<html') || has('<div') || (has('</') && has('>') && has('<'))) return 'html';
      if (has('#include')) return has('std::') || has('cout') || has('class ') ? 'cpp' : 'c';
      if (has('<?php')) return 'php';
      if (has('fn ') && (has('let mut') || has('->') || has('println!'))) return 'rust';
      if (has('package main') || (has('func ') && has(':='))) return 'go';
      if (has('fun ') && (has('val ') || has('println('))) return 'kotlin';
      if (has('public class') || has('System.out') || has('public static void')) return 'java';
      if ((has('def ') && has(':')) || (has('import ') && !has('{') && !has(';')) || (has('print(') && !has('{'))) return 'python';
      if ((has('interface ') && has(': ')) || has(': string') || has(': number')) return 'typescript';
      if (has('const ') || has('=>') || has('function ') || has('console.log') || (has('let ') && has(';'))) return 'javascript';
      if (has('SELECT ') || (has('select ') && has(' from ')) || has('INSERT INTO') || has('CREATE TABLE')) return 'sql';
      if (has('#!/bin/') || has('echo ') || has('$ ') || has('sudo ') || has('brew ') || (has('cd ') && !has('{'))) return 'bash';
      const tt = t.trim();
      if ((tt.startsWith('{') || tt.startsWith('[')) && has('":')) return 'json';
      if (has('{') && has(':') && has(';') && !has('(')) return 'css';
      if ((has('end') && has('def ')) || has('puts ')) return 'ruby';
      return 'plain';
    },
    words: {
      swift: 'func let var if else guard return struct class enum case switch for in while import private public static self Self true false nil init extension protocol some any async await throws try do catch where override final lazy weak default break continue repeat inout mutating',
      python: 'def class if elif else for while in return import from as with try except finally raise lambda yield pass break continue and or not is None True False async await global self',
      javascript: 'const let var function return if else for while of in new class extends import from export default async await try catch throw this true false null undefined typeof switch case break interface type implements enum public private readonly',
      go: 'func package import var const type struct interface map chan go defer return if else for range switch case default nil true false break continue select',
      rust: 'fn let mut pub struct enum impl trait use mod match if else for in while loop return self Self true false as ref move async await where const static crate',
      kotlin: 'fun val var class object interface if else when for while return import package private public override null true false this in is data suspend',
      java: 'public private protected class interface static final void int long double boolean new return if else for while import package extends implements this null true false try catch throw throws',
      c: 'int char float double void long short unsigned const static struct return if else for while do switch case break continue include define typedef sizeof class public private namespace using new delete template auto nullptr true false std',
      ruby: 'def end class module if elsif else unless do while return require self nil true false puts yield and or not attr_accessor',
      php: 'function echo return if else foreach as class public private new array null true false use namespace',
      sql: 'select from where insert into values update set delete create table drop alter join left right inner on and or not null order by group having limit as primary key distinct count',
      bash: 'if then else fi for do done while case esac function return export echo cd sudo brew git npm local in',
      css: 'important',
    },
    /// Раскраска одной строки: ключевые слова, типы, числа, строки, комментарии - как на Mac.
    paint(text, lang) {
      if (!text || lang === 'plain') return esc(text);
      const kw = new Set((this.words[lang === 'typescript' ? 'javascript' : lang === 'cpp' ? 'c' : lang] || '').split(' '));
      const col = new Array(text.length).fill('');
      const mark = (re, cls) => { re.lastIndex = 0; let m; while ((m = re.exec(text))) { for (let i = m.index; i < m.index + m[0].length; i++) col[i] = cls; if (!m[0].length) re.lastIndex++; } };
      if (lang === 'html') mark(/<\/?[A-Za-z][A-Za-z0-9-]*|\/?>/g, 'g');
      if (lang === 'css') mark(/[a-z-]+(?=\s*:)/g, 't');
      const words = /\b[A-Za-z_][A-Za-z0-9_]*\b/g;
      let m;
      while ((m = words.exec(text))) {
        const w = m[0];
        const cls = kw.has(lang === 'sql' ? w.toLowerCase() : w) ? 'k' : (/^[A-Z]/.test(w) && lang !== 'sql' && lang !== 'json') ? 't' : '';
        if (cls) for (let i = m.index; i < m.index + w.length; i++) col[i] = cls;
      }
      mark(/\b\d+(?:\.\d+)?\b/g, 'n');
      mark(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`/g, 's');
      const lc = ['python', 'bash', 'ruby'].includes(lang) ? '#' : lang === 'sql' ? '--' : ['html', 'json', 'css'].includes(lang) ? null : '//';
      if (lc) { const at = text.indexOf(lc); if (at >= 0 && col[at] !== 's') for (let i = at; i < text.length; i++) col[i] = 'c'; }
      mark(/\/\*.*?\*\/|<!--.*?-->/g, 'c');
      let out = '', i = 0;
      while (i < text.length) {
        let j = i + 1;
        while (j < text.length && col[j] === col[i]) j++;
        const piece = esc(text.slice(i, j));
        out += col[i] ? `<span class="hl-${col[i]}">${piece}</span>` : piece;
        i = j;
      }
      return out;
    },
  };
  // В строке кода с курсором - простой текст (так печатать надёжно), в остальных - раскраска.
  editor.addEventListener('focusin', e => {
    const b = blockOfEl(e.target);
    if (!b || b.type !== 'code' || !e.target.classList.contains('txt')) return;
    const txt = e.target;
    setTimeout(() => { const at = caretOffset(txt); if (txt.querySelector('span')) { txt.textContent = plainOf(b.html); placeCaret(txt, at); } }, 0);
  });
  editor.addEventListener('focusout', e => {
    const b = blockOfEl(e.target);
    if (b && b.type === 'code') setTimeout(decorate, 0);
  });

  function remindChip(b, el, now = new Date()) {
    let chip = el.querySelector('.remind');
    const found = b.type === 'todo' ? Reminders.find(plainOf(b.html), now) : null;
    if (!found) { if (chip) chip.remove(); return; }
    if (!chip) { chip = document.createElement('div'); chip.className = 'remind'; chip.contentEditable = 'false'; el.append(chip); }
    chip.classList.toggle('past', found.date <= now);
    chip.innerHTML = ICON.bell + esc(Reminders.label(found.date));
  }

  // ───────── курсор ─────────
  function caretOffset(root) {
    const sel = getSelection();
    if (!sel.rangeCount) return 0;
    const r = sel.getRangeAt(0);
    if (!root.contains(r.startContainer)) return 0;
    const pre = document.createRange();
    pre.selectNodeContents(root);
    pre.setEnd(r.startContainer, r.startOffset);
    return pre.toString().length;
  }
  function placeCaret(root, offset) {
    const sel = getSelection(), r = document.createRange();
    let left = Math.max(0, offset), node = null;
    const walk = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    while (walk.nextNode()) {
      if (walk.currentNode.length >= left) { node = walk.currentNode; break; }
      left -= walk.currentNode.length;
    }
    if (node) r.setStart(node, left);
    else { r.selectNodeContents(root); r.collapse(false); }
    r.collapse(true);
    sel.removeAllRanges();
    sel.addRange(r);
  }
  function focusBlock(b, offset = 0) {
    const el = elOf(b);
    const txt = el && el.querySelector('.txt');
    if (!txt) return;
    txt.focus({ preventScroll: true });
    placeCaret(txt, offset === 'end' ? txt.textContent.length : offset);
    keepCaretVisible();
  }
  /// Убрать первые n букв, не трогая оформление остального.
  function trimStart(root, n) {
    const walk = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walk.nextNode()) nodes.push(walk.currentNode);
    for (const t of nodes) {
      if (n <= 0) break;
      const cut = Math.min(n, t.length);
      t.deleteData(0, cut);
      n -= cut;
    }
  }

  // ───────── чистка HTML строки ─────────
  const TAGS = { B: 'b', STRONG: 'b', I: 'i', EM: 'i', U: 'u', S: 's', STRIKE: 's', DEL: 's', MARK: 'mark', BR: 'br', SPAN: 'span', FONT: 'span', A: 'a' };
  const markTag = (key, inner) => key && key !== 'yellow' ? `<mark class="m-${key}">${inner}</mark>` : `<mark>${inner}</mark>`;
  function sanitize(html) {
    const t = document.createElement('template');
    t.innerHTML = html;
    const out = clean(t.content).replace(/(<br>)+$/, '');
    return out;
  }
  function clean(node) {
    let out = '';
    for (const n of node.childNodes) {
      if (n.nodeType === 3) { out += esc(n.nodeValue); continue; }
      if (n.nodeType !== 1) continue;
      const tag = TAGS[n.tagName];
      const inner = clean(n);
      if (!tag) { out += (/^(DIV|P)$/.test(n.tagName) && out) ? '<br>' + inner : inner; continue; }
      if (tag === 'br') { out += '<br>'; continue; }
      if (!inner) continue;
      if (tag === 'span') {
        const st = n.style;
        let wrapped = inner;
        if (st.fontWeight === 'bold' || +st.fontWeight >= 600) wrapped = `<b>${wrapped}</b>`;
        if (st.fontStyle === 'italic') wrapped = `<i>${wrapped}</i>`;
        if ((st.textDecorationLine || st.textDecoration || '').includes('line-through')) wrapped = `<s>${wrapped}</s>`;
        const bg = st.backgroundColor;
        if (bg && !/transparent|rgba\(0, 0, 0, 0\)/.test(bg)) wrapped = markTag(markByColor(bg), wrapped);
        const color = st.color || n.getAttribute('color');
        if (color) wrapped = `<span style="color:${esc(color)}">${wrapped}</span>`;
        out += wrapped;
        continue;
      }
      if (tag === 'a') { const href = n.getAttribute('href') || ''; out += /^https?:/i.test(href) ? `<a href="${esc(href)}">${inner}</a>` : inner; continue; }
      if (tag === 'mark') { const m = /\bm-([a-z]+)\b/.exec(n.className || ''); out += markTag(m && MARKS.some(x => x[0] === m[1]) ? m[1] : 'yellow', inner); continue; }
      out += `<${tag}>${inner}</${tag}>`;
    }
    return out;
  }

  // ───────── ввод ─────────
  let handledKey = false;

  /// Строка из поля ввода - в заметку.
  function syncBlock(b, el) {
    const txt = el.querySelector('.txt');
    b.html = b.type === 'code' ? esc(txt.textContent) : sanitize(txt.innerHTML);
    if (!txt.textContent && txt.innerHTML) txt.innerHTML = ''; // пустая строка - чтобы показалась подсказка
    save(note(openId), false);
  }

  function insertAfter(b, nb) {
    const n = note(openId);
    const i = n.blocks.indexOf(b);
    n.blocks.splice(i + 1, 0, nb);
    const el = renderBlock(nb);
    el.classList.add('appear');
    elOf(b).after(el);
    return el;
  }

  function removeBlock(b) {
    const n = note(openId);
    n.blocks.splice(n.blocks.indexOf(b), 1);
    const el = elOf(b);
    if (el) el.remove();
    if (!n.blocks.length) { const nb = { id: uid(), type: 'text', html: '' }; n.blocks.push(nb); editor.append(renderBlock(nb)); }
  }

  /// Enter: строка делится, хвост уходит в новую. В списке - новый пункт, на пустом пункте - выход из списка.
  function enter(b, el) {
    const txt = el.querySelector('.txt');
    const sel = getSelection();
    if (!sel.rangeCount) return;
    let r = sel.getRangeAt(0);
    if (!r.collapsed) { r.deleteContents(); r = sel.getRangeAt(0); }
    if (CONTINUES.has(b.type) && !txt.textContent.trim()) { setType(b, 'text'); return; }
    const tail = document.createRange();
    tail.setStart(r.startContainer, r.startOffset);
    tail.setEnd(txt, txt.childNodes.length);
    const holder = document.createElement('div');
    holder.append(tail.extractContents());
    syncBlock(b, el);
    const next = b.type === 'done' ? 'todo' : b.type === 'toggle' ? 'toggleItem' : CONTINUES.has(b.type) ? b.type : 'text';
    const nb = { id: uid(), type: next, html: sanitize(holder.innerHTML) };
    if (b.type === 'toggle' && b.collapsed) { b.collapsed = false; el.classList.remove('collapsed'); }
    insertAfter(b, nb);
    decorate();
    focusBlock(nb, 0);
    save(note(openId), false);
    click('enter');
  }

  /// Backspace в начале строки: сначала тип строки становится обычным, потом строка склеивается с верхней.
  function backspaceAtStart(b, el) {
    const n = note(openId);
    const txt = el.querySelector('.txt');
    const i = n.blocks.indexOf(b);
    let prev = n.blocks[i - 1];
    while (prev && prev.type === 'toggleItem' && elOf(prev).classList.contains('hidden-item')) prev = n.blocks[n.blocks.indexOf(prev) - 1];
    // В коде и внутри сворачиваемого строка просто склеивается с верхней такого же типа.
    const glue = (b.type === 'code' || b.type === 'toggleItem') && prev && prev.type === b.type;
    if (b.type !== 'text' && !glue) { setType(b, 'text'); return true; }
    if (!prev) return false;
    if (isObject(prev)) {
      if (!txt.textContent) { removeBlock(b); }
      selectObject(prev);
      return true;
    }
    const prevEl = elOf(prev), prevTxt = prevEl.querySelector('.txt');
    const len = prevTxt.textContent.length;
    if (prev.type === 'code') prevTxt.textContent += txt.textContent;
    else prevTxt.innerHTML = sanitize(prevTxt.innerHTML) + sanitize(txt.innerHTML);
    syncBlock(prev, prevEl);
    removeBlock(b);
    decorate();
    focusBlock(prev, len);
    return true;
  }

  editor.addEventListener('keydown', e => {
    if (e.isComposing) return;
    const b = blockOfEl(e.target);
    if (!b || isObject(b)) return;
    const el = elOf(b), txt = el.querySelector('.txt');
    if (popupOpen() && ['ArrowDown', 'ArrowUp', 'Enter', 'Escape'].includes(e.key)) {
      e.preventDefault();
      if (e.key === 'Escape') return closePopup();
      if (e.key === 'Enter') return popupChoose();
      return popupMove(e.key === 'ArrowDown' ? 1 : -1);
    }
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handledKey = true; enter(b, el); return; }
    if (e.key === 'Backspace') {
      const sel = getSelection();
      if (sel.isCollapsed && caretOffset(txt) === 0) {
        if (backspaceAtStart(b, el)) { e.preventDefault(); handledKey = true; click('delete'); }
      }
      return;
    }
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      // Стрелки по краям строки переходят в соседние строки.
      const n = note(openId), i = n.blocks.indexOf(b);
      const atEdge = e.key === 'ArrowUp' ? caretOffset(txt) === 0 : caretOffset(txt) === txt.textContent.length;
      if (!atEdge) return;
      const step = e.key === 'ArrowUp' ? -1 : 1;
      let j = i + step;
      while (n.blocks[j] && isObject(n.blocks[j])) j += step;
      if (n.blocks[j]) { e.preventDefault(); focusBlock(n.blocks[j], step < 0 ? 'end' : 0); }
    }
    if ((e.metaKey || e.ctrlKey) && ['b', 'i', 'u'].includes(e.key.toLowerCase())) {
      e.preventDefault();
      format({ b: 'bold', i: 'italic', u: 'underline' }[e.key.toLowerCase()]);
    }
  });

  // Запасной путь: если клавиатура не прислала keydown (так бывает на телефонах), ловим Enter и Backspace здесь.
  editor.addEventListener('beforeinput', e => {
    const b = blockOfEl(e.target);
    if (!b || isObject(b)) return;
    if (handledKey) { handledKey = false; return; }
    const el = elOf(b), txt = el.querySelector('.txt');
    if (e.inputType === 'insertParagraph' || (e.inputType === 'insertLineBreak' && b.type !== 'code')) {
      e.preventDefault(); enter(b, el); return;
    }
    if (e.inputType === 'deleteContentBackward' && getSelection().isCollapsed && caretOffset(txt) === 0) {
      if (backspaceAtStart(b, el)) e.preventDefault();
      return;
    }
    if (e.inputType === 'insertText' && e.data) click(e.data === ' ' ? 'space' : 'letter');
    if (e.inputType === 'insertFromPaste' || e.inputType === 'insertFromDrop') {
      const text = e.dataTransfer && e.dataTransfer.getData('text/plain');
      if (text != null) { e.preventDefault(); pasteText(b, el, text); }
    }
  });

  editor.addEventListener('paste', e => {
    const b = blockOfEl(e.target);
    if (!b || isObject(b)) return;
    e.preventDefault();
    pasteText(b, elOf(b), (e.clipboardData && e.clipboardData.getData('text/plain')) || '');
  });

  /// Вставка: одна строка - в текущую, несколько - новыми строками (с разметкой «# », «- », «[] »).
  function pasteText(b, el, text) {
    text = text.replace(/\r\n?/g, '\n');
    if (!text.includes('\n')) { document.execCommand('insertText', false, text); return; }
    const parsed = b.type === 'code' ? text.split('\n').map(l => ({ id: uid(), type: 'code', html: esc(l) })) : parseMarkdown(text);
    const first = parsed.shift();
    if (first && !isObject(first)) document.execCommand('insertHTML', false, first.html);
    syncBlock(b, el);
    let last = b;
    for (const nb of parsed) { insertAfter(last, nb); last = nb; }
    decorate();
    if (!isObject(last)) focusBlock(last, 'end');
    save(note(openId));
  }

  editor.addEventListener('input', e => {
    const b = blockOfEl(e.target);
    if (b && b.type === 'table' && e.target.closest('td')) return syncTable(b);
    if (!b || isObject(b)) return;
    const el = elOf(b), txt = el.querySelector('.txt');
    const text = txt.textContent.replace(/ /g, ' ');
    // «# », «- », «[] », «> » в начале строки - превращают её в блок; «---» - разделитель.
    if (b.type === 'text') {
      if (/^(---|—-|–-)$/.test(text)) {
        const nb = { id: uid(), type: 'divider' };
        b.type = 'text'; b.html = '';
        txt.innerHTML = '';
        const n = note(openId);
        n.blocks.splice(n.blocks.indexOf(b), 0, nb);
        el.before(renderBlock(nb));
        save(n);
        return;
      }
      for (const [key, type] of SHORTCUTS) {
        if (text.startsWith(key + ' ')) {
          trimStart(txt, key.length + 1);
          setType(b, type);
          placeCaret(txt, 0);
          syncBlock(b, el);
          return;
        }
      }
    }
    syncBlock(b, el);
    if (b.type === 'todo') remindChip(b, el);
    // «/» в пустой строке - меню блоков; дальше буквы его фильтруют.
    if (text.startsWith('/') && text.length <= 16 && !/\s/.test(text) && (popupFor === b || text === '/')) openPopup(b, text.slice(1));
    else if (popupOpen() && popupSlash) closePopup();
    updateStats();
    keepCaretVisible();
  });

  // Квадратик задачи, стрелка списка, карточки, доска, плеер - нажатия.
  editor.addEventListener('click', e => {
    const blk = e.target.closest('.blk');
    if (!blk) return;
    const b = blockById(blk.dataset.id);
    if (!b) return;
    if (e.target.closest('.check')) {
      setType(b, b.type === 'todo' ? 'done' : 'todo');
      click('space');
      if (navigator.vibrate) navigator.vibrate(8);
      return;
    }
    if (b.type === 'toggle' && e.target.closest('.marker')) {
      b.collapsed = !b.collapsed;
      blk.classList.toggle('collapsed', b.collapsed);
      decorate();
      save(note(openId));
      return;
    }
    if (b.type === 'code' && e.target.closest('[data-copy]')) {
      const n = note(openId), text = codeGroup(n, n.blocks.indexOf(b)).map(x => plainOf(x.html)).join('\n');
      navigator.clipboard.writeText(text).then(() => { e.target.textContent = 'Скопировано'; setTimeout(decorate, 1200); }, () => toast('Не получилось скопировать'));
      return;
    }
    if (b.type === 'code' && e.target.closest('[data-lang]')) return pickLanguage(b);
    if (!isObject(b)) return;
    const act = e.target.closest('[data-obj]');
    if (act) return objectAction(b, act.dataset.obj);
    if (b.type === 'page') return openNote(b.page, true);
    if (b.type === 'file') return openFile(b);
    if (b.type === 'board') return boardClick(b, e);
    if (b.type === 'audio' && e.target.closest('.play')) return togglePlay(b);
    if (b.type === 'table' && e.target.closest('[data-tbl]')) return tableAction(b, e.target.closest('[data-tbl]').dataset.tbl);
    if (b.type === 'table' && e.target.closest('td')) return;
    selectObject(b);
  });
  // Кнопки панели и меню не забирают фокус у строки - клавиатура не прячется.
  for (const sel of ['#kbar', '#popup']) $(sel).addEventListener('pointerdown', e => { if (e.target.closest('button')) e.preventDefault(); });

  let selectedObj = null;
  function selectObject(b) {
    if (selectedObj) { const old = elOf(selectedObj); if (old) old.classList.remove('sel'); }
    selectedObj = b;
    const el = elOf(b);
    if (el) el.classList.add('sel');
    if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
  }
  document.addEventListener('pointerdown', e => {
    if (selectedObj && !e.target.closest('.obj.sel')) { const el = elOf(selectedObj); if (el) el.classList.remove('sel'); selectedObj = null; }
  });
  function objectAction(b, act) {
    const n = note(openId), i = n.blocks.indexOf(b);
    if (act === 'size') {
      const sizes = [1, 0.75, 0.5, 0.35];
      b.width = sizes[(sizes.indexOf(b.width || 1) + 1) % sizes.length];
      const img = elOf(b).querySelector('img');
      if (img) img.style.width = b.width * 100 + '%';
      save(n);
      return;
    }
    if (act === 'del') {
      const saved = { b, i };
      removeBlock(b); decorate(); save(n);
      toast('Удалено: ' + OBJECTS.find(o => o[0] === b.type)[1].toLowerCase(), 'Вернуть', () => { n.blocks.splice(saved.i, 0, saved.b); renderNote(); save(n); });
      return;
    }
    const j = act === 'up' ? i - 1 : i + 1;
    if (j < 0 || j >= n.blocks.length) return;
    [n.blocks[i], n.blocks[j]] = [n.blocks[j], n.blocks[i]];
    renderNote(); save(n); selectObject(b);
    elOf(b).scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  // Текущая строка: для фокуса, панели и меню.
  let currentBlock = null;
  document.addEventListener('selectionchange', () => {
    const sel = getSelection();
    const b = sel.rangeCount ? blockOfEl(sel.anchorNode && (sel.anchorNode.nodeType === 1 ? sel.anchorNode : sel.anchorNode.parentElement)) : null;
    if (b !== currentBlock) {
      if (currentBlock) { const el = elOf(currentBlock); if (el) el.classList.remove('current'); }
      currentBlock = b;
      if (b) { const el = elOf(b); if (el) el.classList.add('current'); }
      if (popupOpen() && popupFor !== b) closePopup();
    }
    updateStats();
  });

  // ───────── панель над клавиатурой ─────────
  const kbar = $('#kbar');
  editor.addEventListener('focusin', e => {
    if (!e.target.classList.contains('txt')) return;
    kbar.hidden = false;
    noteScreen.classList.add('typing');
  });
  editor.addEventListener('focusout', () => setTimeout(() => {
    if (!editor.contains(document.activeElement)) { kbar.hidden = true; noteScreen.classList.remove('typing'); closePopup(); }
    // Клавиатура уезжает с анимацией - пересчитываем экран, когда она уже спряталась.
    setTimeout(fitViewport, 400);
  }, 120));

  kbar.addEventListener('click', e => {
    const btn = e.target.closest('[data-act]');
    if (!btn) return;
    const b = currentBlock;
    const act = btn.dataset.act;
    if (act === 'done') { document.activeElement.blur(); return; }
    if (act === 'voice') return recordVoice(b);
    if (!b || isObject(b)) return;
    if (act === 'menu') return popupOpen() ? closePopup() : openPopup(b, '', false);
    if (act === 'color') return popupOpen() ? closePopup() : openColors(b);
    if (act === 'up' || act === 'down') return moveBlock(b, act === 'up' ? -1 : 1);
    if (['title', 'todo', 'bullet'].includes(act)) {
      const same = b.type === act || (act === 'todo' && b.type === 'done');
      setType(b, same ? 'text' : act);
      return;
    }
    format(act);
  });

  /// Жирный, курсив, зачёркнутый, подчёркнутый, маркер - у выделенного (или для того, что будет набрано).
  function format(kind) {
    const b = currentBlock;
    if (!b || b.type === 'code') return;
    if (kind === 'mark') {
      const sel = getSelection();
      if (sel.isCollapsed) return toast('Выдели слова - и нажми маркер');
      const r = sel.getRangeAt(0);
      const marks = [...elOf(b).querySelectorAll('mark, span[style*="background"]')].filter(m => r.intersectsNode(m));
      if (marks.length) { for (const m of marks) m.replaceWith(...m.childNodes); }
      else applyMark(local.get('lastMark', 'yellow'));
    } else {
      document.execCommand('styleWithCSS', false, false);
      document.execCommand({ bold: 'bold', italic: 'italic', strike: 'strikeThrough', underline: 'underline' }[kind]);
    }
    syncBlock(b, elOf(b));
  }

  /// Цвет текста у выделенного. Белый - снять цвет.
  function applyColor(key) {
    const b = currentBlock, sel = getSelection();
    if (!b || sel.isCollapsed) return toast('Выдели слова - и выбери цвет');
    const r = sel.getRangeAt(0);
    for (const s of [...elOf(b).querySelectorAll('span[style*="color"], font[color]')].filter(x => r.intersectsNode(x) && !/background/.test(x.getAttribute('style') || ''))) s.replaceWith(...s.childNodes);
    if (key !== 'white') {
      document.execCommand('styleWithCSS', false, true);
      document.execCommand('foreColor', false, TEXT_COLORS.find(c => c[0] === key)[1]);
      document.execCommand('styleWithCSS', false, false);
    }
    syncBlock(b, elOf(b));
  }
  /// Маркер выбранного цвета; null - снять маркер.
  function applyMark(key) {
    const b = currentBlock, sel = getSelection();
    if (!b || sel.isCollapsed) return toast('Выдели слова - и выбери маркер');
    const r = sel.getRangeAt(0);
    for (const m of [...elOf(b).querySelectorAll('mark, span[style*="background"]')].filter(x => r.intersectsNode(x))) m.replaceWith(...m.childNodes);
    if (key) {
      local.set('lastMark', key);
      document.execCommand('styleWithCSS', false, true);
      document.execCommand('hiliteColor', false, MARKS.find(x => x[0] === key)[1]);
      document.execCommand('styleWithCSS', false, false);
    }
    syncBlock(b, elOf(b));
  }
  function openColors(b) {
    popupFor = b; popupSlash = false; popupItems = [];
    popup.innerHTML = `<div class="group">ЦВЕТ ТЕКСТА</div><div class="colors">${TEXT_COLORS.map(c => `<button class="tc" data-color="${c[0]}" style="color:${c[1]}" aria-label="${c[2]}">А</button>`).join('')}</div>
      <div class="group">МАРКЕР</div><div class="colors">${MARKS.map(c => `<button class="mk" data-mark="${c[0]}" style="background:${c[1]}" aria-label="${c[2]}"></button>`).join('')}<button class="mk none" data-mark="" aria-label="Без маркера">✕</button></div>`;
    popup.hidden = false;
  }
  /// Строку с курсором - выше или ниже; курсор едет вместе с ней.
  function moveBlock(b, dir) {
    const n = note(openId), i = n.blocks.indexOf(b), j = i + dir;
    if (j < 0 || j >= n.blocks.length) return;
    const el = elOf(b), txt = el.querySelector('.txt'), at = txt ? caretOffset(txt) : 0;
    [n.blocks[i], n.blocks[j]] = [n.blocks[j], n.blocks[i]];
    const other = elOf(n.blocks[i]);
    if (dir < 0) other.before(el); else other.after(el);
    decorate(); save(n);
    if (txt) focusBlock(b, at);
    el.scrollIntoView({ block: 'nearest' });
  }

  // ───────── меню блоков («/» и «+») ─────────
  const popup = $('#popup');
  let popupFor = null, popupSlash = false, popupItems = [], popupIndex = 0;
  const popupOpen = () => !popup.hidden;

  function openPopup(b, q, slash = true) {
    popupFor = b; popupSlash = slash;
    const ql = q.toLowerCase();
    const match = it => !ql || it[1].toLowerCase().includes(ql) || it[4].some(k => k.startsWith(ql) || (ql.startsWith(k) && k.length >= 2)) || it[3] === ql;
    const basic = BASIC.filter(match), objs = OBJECTS.filter(match);
    popupItems = [...basic.map(x => ['basic', x]), ...objs.map(x => ['obj', x])];
    if (!popupItems.length) return closePopup();
    popupIndex = Math.min(popupIndex, popupItems.length - 1);
    let html = '', idx = 0;
    if (basic.length) html += '<div class="group">БАЗОВЫЕ</div>' + basic.map(x => itemHTML(x, idx++, x[3])).join('');
    if (objs.length) html += '<div class="group">ВСТАВИТЬ</div>' + objs.map(x => itemHTML(x, idx++, '', x[3])).join('');
    popup.innerHTML = html;
    popup.hidden = false;
  }
  const itemHTML = (x, i, key, sub) => `<button class="item${i === popupIndex ? ' on' : ''}" data-i="${i}"><span class="ic">${x[2]}</span><span class="lbl">${x[1]}${sub ? `<small>${sub}</small>` : ''}</span>${key ? `<span class="k">${esc(key)}</span>` : ''}</button>`;
  function closePopup() { popup.hidden = true; popupFor = null; popupIndex = 0; }
  function popupMove(d) {
    popupIndex = (popupIndex + d + popupItems.length) % popupItems.length;
    popup.querySelectorAll('.item').forEach((it, i) => it.classList.toggle('on', i === popupIndex));
    popup.querySelector('.item.on').scrollIntoView({ block: 'nearest' });
  }
  popup.addEventListener('click', e => {
    const color = e.target.closest('[data-color]'), mark = e.target.closest('[data-mark]');
    if (color) { applyColor(color.dataset.color); return closePopup(); }
    if (mark) { applyMark(mark.dataset.mark || null); return closePopup(); }
    const it = e.target.closest('.item');
    if (!it) return;
    popupIndex = +it.dataset.i;
    popupChoose();
  });

  function popupChoose() {
    const [kind, item] = popupItems[popupIndex] || [];
    const b = popupFor;
    const slash = popupSlash;
    closePopup();
    if (!kind || !b) return;
    const el = elOf(b), txt = el.querySelector('.txt');
    if (slash) { txt.innerHTML = ''; syncBlock(b, el); }
    const empty = !txt.textContent.trim();
    if (kind === 'basic') { setType(b, item[0]); focusBlock(b, 'end'); return; }
    const type = item[0];
    if (type === 'template') return pickTemplate(b);
    if (type === 'audio') return recordVoice(b);
    if (type === 'image') { pendingImageFor = b; $('#file-image').click(); return; }
    if (type === 'file') { pendingImageFor = b; $('#file-any').click(); return; }
    if (type === 'page') return makePage(b);
    const ob = { id: uid(), type };
    if (type === 'board') ob.columns = emptyBoard();
    if (type === 'table') ob.cells = [['', '', ''], ['', '', ''], ['', '', '']];
    placeObject(b, ob, empty);
  }

  /// Предмет встаёт на пустую строку (а она уходит под него) или под непустую.
  function placeObject(b, ob, empty) {
    const n = note(openId);
    const i = n.blocks.indexOf(b);
    if (empty && b.type === 'text') {
      n.blocks.splice(i, 0, ob);
      elOf(b).before(renderBlock(ob));
      decorate(); save(n);
      focusBlock(b, 0);
    } else {
      insertAfter(b, ob);
      const after = { id: uid(), type: 'text', html: '' };
      insertAfter(ob, after);
      decorate(); save(n);
      focusBlock(after, 0);
    }
    elOf(ob).scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    return ob;
  }

  function makePage(b) {
    const el = elOf(b), txt = el.querySelector('.txt');
    const title = txt.textContent.trim();
    const parent = note(openId);
    const child = newNote({ parent: parent.id, blocks: [{ id: uid(), type: 'title', html: esc(title) }], open: false });
    const card = { id: uid(), type: 'page', page: child.id };
    const i = parent.blocks.indexOf(b);
    if (b.type === 'text' || title) { parent.blocks.splice(i, 1, card); el.replaceWith(renderBlock(card)); }
    else { insertAfter(b, card); }
    decorate(); save(parent);
    if (!title) openNote(child.id, true);
  }

  // ───────── предметы ─────────
  const emptyBoard = () => [{ id: uid(), title: 'Надо сделать', cards: [] }, { id: uid(), title: 'В работе', cards: [] }, { id: uid(), title: 'Готово', cards: [] }];

  function objectHTML(b) {
    switch (b.type) {
      case 'divider': return '';
      case 'image': return `<img alt="Картинка" style="width:${(b.width || 1) * 100}%">`;
      case 'file': return `<div class="card">${ICON.file}<span class="cbody"><span class="ct">${esc(b.name || 'Файл')}</span><span class="cp">${fmtSize(b.size)} · открыть</span></span></div>`;
      case 'page': {
        const p = note(b.page);
        return `<div class="card">${ICON.page}<span class="cbody"><span class="ct">${esc(p ? titleOf(p) : 'Страница удалена')}</span>${p && previewOf(p) ? `<span class="cp">${esc(previewOf(p))}</span>` : ''}</span>${ICON.chevron}</div>`;
      }
      case 'board': return boardHTML(b);
      case 'audio': return `<div class="player"><button class="play" aria-label="Играть">${ICON.play}</button><div class="wave">${(b.peaks || []).map(p => `<i style="height:${Math.max(10, p * 100)}%"></i>`).join('')}</div><time>${fmtTime(b.duration || 0)}</time></div>`;
      case 'table': return `<div class="table"><table>${b.cells.map(row => `<tr>${row.map(c => `<td contenteditable="true">${esc(c)}</td>`).join('')}</tr>`).join('')}</table></div>
        <div class="tablebtns"><button data-tbl="row+">+ строка</button><button data-tbl="col+">+ столбец</button><button data-tbl="row-">− строка</button><button data-tbl="col-">− столбец</button></div>`;
    }
    return '';
  }

  function boardHTML(b) {
    return `<div class="board">${b.columns.map((c, ci) => `<div class="lane"><h4 data-col="${ci}">${esc(c.title || 'Колонка')}<small>${c.cards.length}</small></h4>
      ${c.cards.map((k, ki) => `<button class="kcard" data-card="${ci}:${ki}">${esc(k.text || 'Пустая карточка')}</button>`).join('')}
      <button class="kadd" data-addcard="${ci}">+ Карточка</button></div>`).join('')}
      <button class="lane addcol" data-addcol>+ Колонка</button></div>`;
  }
  function refreshObject(b) { const el = elOf(b); if (!el) return; const fresh = renderBlock(b); el.replaceWith(fresh); }

  function boardClick(b, e) {
    const n = note(openId);
    const card = e.target.closest('[data-card]'), add = e.target.closest('[data-addcard]'), col = e.target.closest('[data-col]');
    if (e.target.closest('[data-addcol]')) {
      b.columns.push({ id: uid(), title: 'Новая колонка', cards: [] });
      save(n); refreshObject(b); return editColumn(b, b.columns.length - 1);
    }
    if (add) {
      const ci = +add.dataset.addcard;
      b.columns[ci].cards.push({ id: uid(), text: '' });
      save(n); refreshObject(b); return editCard(b, ci, b.columns[ci].cards.length - 1, true);
    }
    if (card) { const [ci, ki] = card.dataset.card.split(':').map(Number); return editCard(b, ci, ki); }
    if (col) return editColumn(b, +col.dataset.col);
    selectObject(b);
  }

  function editCard(b, ci, ki, isNew = false) {
    const n = note(openId), card = b.columns[ci].cards[ki];
    openSheet(`<h3>Карточка</h3>
      <textarea class="field" id="card-text" placeholder="Что сделать">${esc(card.text)}</textarea>
      <div class="group">ПЕРЕНЕСТИ В КОЛОНКУ</div>
      <div class="chips">${b.columns.map((c, i) => `<button class="chip${i === ci ? ' on' : ''}" data-move="${i}">${esc(c.title)}</button>`).join('')}</div>
      <div class="btns"><button class="btn danger" data-del>Удалить</button><button class="btn primary" data-ok>Готово</button></div>`, root => {
      const area = root.querySelector('#card-text');
      if (isNew) area.focus();
      const commit = () => { card.text = area.value.trim(); };
      root.addEventListener('click', e => {
        const mv = e.target.closest('[data-move]');
        if (mv) {
          commit();
          const to = +mv.dataset.move;
          if (to !== ci) { b.columns[ci].cards.splice(ki, 1); b.columns[to].cards.push(card); }
          save(n); refreshObject(b); closeSheet(); toast('Перенесено в «' + b.columns[to].title + '»');
        }
        if (e.target.closest('[data-del]')) { b.columns[ci].cards.splice(ki, 1); save(n); refreshObject(b); closeSheet(); }
        if (e.target.closest('[data-ok]')) { commit(); if (!card.text && isNew) b.columns[ci].cards.splice(ki, 1); save(n); refreshObject(b); closeSheet(); }
      });
    }, () => { if (b.columns[ci] && b.columns[ci].cards.includes(card)) { card.text = $('#card-text') ? $('#card-text').value.trim() : card.text; if (!card.text && isNew) b.columns[ci].cards.splice(b.columns[ci].cards.indexOf(card), 1); save(n); refreshObject(b); } });
  }

  function editColumn(b, ci) {
    const n = note(openId), col = b.columns[ci];
    openSheet(`<h3>Колонка</h3>
      <input class="field" id="col-title" value="${esc(col.title)}" enterkeyhint="done">
      <div class="btns"><button class="btn" data-left ${ci === 0 ? 'disabled' : ''}>← Левее</button><button class="btn" data-right ${ci === b.columns.length - 1 ? 'disabled' : ''}>Правее →</button></div>
      <div class="btns"><button class="btn danger" data-del ${b.columns.length <= 1 ? 'disabled' : ''}>Удалить колонку</button><button class="btn primary" data-ok>Готово</button></div>`, root => {
      const input = root.querySelector('#col-title');
      root.addEventListener('click', e => {
        col.title = input.value.trim() || col.title;
        if (e.target.closest('[data-left]') && ci > 0) { b.columns.splice(ci, 1); b.columns.splice(ci - 1, 0, col); }
        if (e.target.closest('[data-right]') && ci < b.columns.length - 1) { b.columns.splice(ci, 1); b.columns.splice(ci + 1, 0, col); }
        if (e.target.closest('[data-del]') && b.columns.length > 1) b.columns.splice(b.columns.indexOf(col), 1);
        if (e.target.closest('button')) { save(n); refreshObject(b); closeSheet(); }
      });
      input.addEventListener('keydown', e => { if (e.key === 'Enter') { col.title = input.value.trim() || col.title; save(n); refreshObject(b); closeSheet(); } });
    });
  }

  function syncTable(b) {
    const el = elOf(b);
    b.cells = [...el.querySelectorAll('tr')].map(tr => [...tr.children].map(td => td.textContent));
    save(note(openId), false);
  }
  function tableAction(b, act) {
    const cols = Math.max(...b.cells.map(r => r.length));
    if (act === 'row+') b.cells.push(Array(cols).fill(''));
    if (act === 'col+') b.cells.forEach(r => r.push(''));
    if (act === 'row-' && b.cells.length > 1) b.cells.pop();
    if (act === 'col-' && cols > 1) b.cells.forEach(r => r.pop());
    save(note(openId)); refreshObject(b);
  }

  function pickLanguage(b) {
    const n = note(openId), head = codeGroup(n, n.blocks.indexOf(b))[0];
    openSheet(`<h3>Язык кода</h3><button class="item${!head.lang ? ' on' : ''}" data-l=""><span class="lbl">Авто</span></button>
      ${Code.langs.map(l => `<button class="item${head.lang === l[0] ? ' on' : ''}" data-l="${l[0]}"><span class="lbl">${l[1]}</span></button>`).join('')}`, root => {
      root.addEventListener('click', e => {
        const it = e.target.closest('[data-l]');
        if (!it) return;
        if (it.dataset.l) head.lang = it.dataset.l; else delete head.lang;
        save(n); decorate(); closeSheet();
      });
    });
  }

  // ───────── картинки и файлы ─────────
  const urls = new Map();
  async function fileURL(id) {
    if (urls.has(id)) return urls.get(id);
    const f = await DB.get('files', id);
    if (!f) return null;
    const u = URL.createObjectURL(f.blob);
    urls.set(id, u);
    return u;
  }
  async function loadImage(b, el) { const u = await fileURL(b.file); const img = el.querySelector('img'); if (u && img) img.src = u; else if (img) img.alt = 'Картинка не найдена'; }

  let pendingImageFor = null;
  $('#file-image').addEventListener('change', async e => {
    const file = e.target.files[0];
    e.target.value = '';
    const b = pendingImageFor;
    pendingImageFor = null;
    if (!file || !b) return;
    try {
      const blob = await shrinkImage(file);
      const id = uid();
      await DB.put('files', { id, blob, type: blob.type });
      const el = elOf(b);
      const empty = !el.querySelector('.txt').textContent.trim();
      placeObject(b, { id: uid(), type: 'image', file: id }, empty);
    } catch (err) { toast('Не получилось вставить картинку'); }
  });
  $('#file-any').addEventListener('change', async e => {
    const file = e.target.files[0];
    e.target.value = '';
    const b = pendingImageFor;
    pendingImageFor = null;
    if (!file || !b) return;
    const id = uid();
    await DB.put('files', { id, blob: file, type: file.type, name: file.name });
    const empty = !elOf(b).querySelector('.txt').textContent.trim();
    placeObject(b, { id: uid(), type: 'file', file: id, name: file.name, size: file.size }, empty);
  });
  const fmtSize = n => !n ? '' : n < 1024 ? n + ' Б' : n < 1048576 ? Math.round(n / 1024) + ' КБ' : (n / 1048576).toFixed(1) + ' МБ';
  /// Файл открывается через «Поделиться»: оттуда - в «Файлы», в нужную программу или в мессенджер.
  async function openFile(b) {
    const f = await DB.get('files', b.file);
    if (!f) return toast('Файл не найден');
    shareFile(new File([f.blob], b.name || 'файл', { type: f.type || 'application/octet-stream' }));
  }

  /// Фото с телефона огромные - уменьшаем до 1600 точек по длинной стороне.
  async function shrinkImage(file) {
    const bitmap = await createImageBitmap(file).catch(() => null);
    if (!bitmap) return file;
    const scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
    const c = document.createElement('canvas');
    c.width = Math.round(bitmap.width * scale); c.height = Math.round(bitmap.height * scale);
    c.getContext('2d').drawImage(bitmap, 0, 0, c.width, c.height);
    return new Promise(res => c.toBlob(bl => res(bl || file), 'image/jpeg', 0.86));
  }

  // ───────── голосовые заметки ─────────
  const fmtTime = s => { s = Math.round(s); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); };

  async function recordVoice(b) {
    if (!navigator.mediaDevices || !window.MediaRecorder) return toast('Запись звука здесь не работает');
    let stream;
    try { stream = await navigator.mediaDevices.getUserMedia({ audio: true }); }
    catch { return toast('Нет доступа к микрофону - разреши его в настройках Safari'); }
    const type = ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm'].find(t => MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(t)) || '';
    const rec = new MediaRecorder(stream, type ? { mimeType: type } : undefined);
    const chunks = [];
    rec.ondataavailable = e => { if (e.data.size) chunks.push(e.data); };
    const started = Date.now();
    let transcript = '', interim = '', recognition = null, cancelled = false;
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    openSheet(`<h3>Голосовая заметка</h3>
      <div class="rec"><div class="time"><span class="pulse"></span><span id="rec-time">0:00</span></div>
      <div class="live" id="rec-live">${SR ? 'Говори - текст появится здесь' : 'Запись идёт. Расшифровку в этом браузере сделать нельзя - останется только звук.'}</div></div>
      <div class="btns"><button class="btn" data-cancel>Отмена</button><button class="btn primary" data-stop>Готово</button></div>`, root => {
      root.addEventListener('click', e => {
        if (e.target.closest('[data-stop]')) stop(false);
        if (e.target.closest('[data-cancel]')) stop(true);
      });
    }, () => stop(true));
    const timer = setInterval(() => { const t = $('#rec-time'); if (t) t.textContent = fmtTime((Date.now() - started) / 1000); }, 250);
    rec.start(250);
    if (SR) {
      try {
        recognition = new SR();
        recognition.lang = 'ru-RU'; recognition.continuous = true; recognition.interimResults = true;
        recognition.onresult = ev => {
          interim = '';
          for (let i = ev.resultIndex; i < ev.results.length; i++) {
            if (ev.results[i].isFinal) transcript += ev.results[i][0].transcript + ' '; else interim += ev.results[i][0].transcript;
          }
          const live = $('#rec-live'); if (live) live.textContent = (transcript + interim).trim() || '…';
        };
        recognition.onerror = () => {};
        recognition.start();
      } catch { recognition = null; }
    }
    let stopped = false;
    function stop(cancel) {
      if (stopped) return;
      stopped = true; cancelled = cancel;
      clearInterval(timer);
      try { recognition && recognition.stop(); } catch {}
      rec.onstop = finish;
      try { rec.stop(); } catch { finish(); }
      stream.getTracks().forEach(t => t.stop());
      closeSheet(true);
    }
    async function finish() {
      if (cancelled) return;
      const spokenOnly = (transcript + interim).trim();
      if (!chunks.length) {
        const target = lastTextBlock();
        if (spokenOnly && target) { const tb = { id: uid(), type: 'text', html: esc(spokenOnly) }; insertAfter(target, tb); decorate(); save(note(openId)); }
        else toast('Запись не получилась');
        return;
      }
      const blob = new Blob(chunks, { type: rec.mimeType || type || 'audio/mp4' });
      const id = uid();
      await DB.put('files', { id, blob, type: blob.type });
      const { peaks, duration } = await audioInfo(blob, (Date.now() - started) / 1000);
      const target = b && note(openId) && note(openId).blocks.includes(b) ? b : lastTextBlock();
      if (!target) return;
      const ob = placeObject(target, { id: uid(), type: 'audio', file: id, peaks, duration }, !plainOf(target.html).trim());
      const spoken = (transcript + interim).trim();
      if (spoken) {
        const tb = { id: uid(), type: 'text', html: esc(spoken.charAt(0).toUpperCase() + spoken.slice(1)) };
        insertAfter(ob, tb); decorate(); save(note(openId));
      }
    }
  }
  const lastTextBlock = () => { const n = note(openId); return n && [...n.blocks].reverse().find(x => !isObject(x)); };

  async function audioInfo(blob, fallback) {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const data = await blob.arrayBuffer();
      const audio = await new Promise((res, rej) => ctx.decodeAudioData(data, res, rej));
      const ch = audio.getChannelData(0), bars = 48, step = Math.max(1, Math.floor(ch.length / bars));
      const peaks = [];
      for (let i = 0; i < bars; i++) {
        let sum = 0;
        for (let j = i * step; j < Math.min(ch.length, (i + 1) * step); j++) sum += ch[j] * ch[j];
        peaks.push(Math.sqrt(sum / step));
      }
      const top = Math.max(...peaks, 1e-4);
      ctx.close && ctx.close();
      return { peaks: peaks.map(p => +(p / top).toFixed(2)), duration: audio.duration };
    } catch {
      return { peaks: Array.from({ length: 48 }, (_, i) => +(0.3 + 0.5 * Math.abs(Math.sin(i / 3))).toFixed(2)), duration: fallback };
    }
  }

  let playing = null; // { b, audio }
  function setupPlayer(b, el) { if (playing && playing.b.id === b.id) paintPlayer(); }
  async function togglePlay(b) {
    if (playing && playing.b.id === b.id) {
      if (playing.audio.paused) playing.audio.play(); else playing.audio.pause();
      return paintPlayer();
    }
    if (playing) { playing.audio.pause(); const old = playing; playing = null; paintPlayer(old.b); }
    const u = await fileURL(b.file);
    if (!u) return toast('Запись не найдена');
    const audio = new Audio(u);
    playing = { b, audio };
    audio.addEventListener('timeupdate', () => paintPlayer());
    audio.addEventListener('pause', () => paintPlayer());
    audio.addEventListener('ended', () => { const was = playing; playing = null; if (was) paintPlayer(was.b); });
    audio.play().catch(() => toast('Не получилось включить звук'));
    paintPlayer();
  }
  function paintPlayer(b = playing && playing.b) {
    if (!b) return;
    const el = elOf(b);
    if (!el) return;
    const on = playing && playing.b.id === b.id;
    const a = on ? playing.audio : null;
    const progress = a && a.duration ? a.currentTime / a.duration : 0;
    el.querySelector('.play').innerHTML = a && !a.paused ? ICON.pause : ICON.play;
    el.querySelectorAll('.wave i').forEach((i, k, all) => i.classList.toggle('on', k / all.length < progress));
    el.querySelector('time').textContent = fmtTime(a ? (a.duration || b.duration) - a.currentTime : b.duration || 0);
  }

  // ───────── напоминания ─────────
  const Reminders = {
    re: /@(?:(сегодня|завтра|послезавтра|пн|вт|ср|чт|пт|сб|вс|\d{1,2}\.\d{1,2}(?:\.\d{2,4})?)(?![\p{L}\d])(?:\s+(?:в\s+)?(\d{1,2}):(\d{2}))?|(\d{1,2}):(\d{2}))/iu,
    days: { вс: 0, пн: 1, вт: 2, ср: 3, чт: 4, пт: 5, сб: 6 },
    /// Как на Mac: @сегодня, @завтра, @послезавтра, @пн…@вс, @15.10, @15.10.2026 и время; без времени - 9:00.
    find(line, now = new Date()) {
      const m = line.match(this.re);
      if (!m) return null;
      let hour = 9, minute = 0;
      if (m[2] !== undefined) { hour = +m[2]; minute = +m[3]; }
      if (m[4] !== undefined) { hour = +m[4]; minute = +m[5]; }
      if (hour > 23 || minute > 59) return null;
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const at = (d, add = 0) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + add, hour, minute);
      let date;
      const word = m[1] && m[1].toLowerCase();
      if (!word) { date = at(today); if (date <= now) date = at(today, 1); }
      else if (word === 'сегодня') date = at(today);
      else if (word === 'завтра') date = at(today, 1);
      else if (word === 'послезавтра') date = at(today, 2);
      else if (word in this.days) {
        let ahead = (this.days[word] - today.getDay() + 7) % 7;
        if (ahead === 0 && at(today) <= now) ahead = 7;
        date = at(today, ahead);
      } else {
        const p = word.split('.').map(Number);
        let year = p[2] !== undefined ? (p[2] < 100 ? 2000 + p[2] : p[2]) : now.getFullYear();
        date = new Date(year, p[1] - 1, p[0], hour, minute);
        if (p[2] === undefined && date <= now) date = new Date(year + 1, p[1] - 1, p[0], hour, minute);
        if (date.getDate() !== p[0] || date.getMonth() !== p[1] - 1) return null;
      }
      return { index: m.index, length: m[0].length, date };
    },
    label(d) {
      const now = new Date(), days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 864e5);
      const hm = d.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
      const day = days === 0 ? 'сегодня' : days === 1 ? 'завтра' : days === -1 ? 'вчера' : d.toLocaleDateString('ru-RU', { weekday: 'short', day: 'numeric', month: 'short' });
      return day + ', ' + hm;
    },
    /// Все задачи с отметкой времени, ближайшие сверху.
    all() {
      const now = new Date(), out = [];
      for (const n of notes.values()) for (const b of n.blocks) {
        if (b.type !== 'todo') continue;
        const text = plainOf(b.html), f = this.find(text, now);
        if (f) out.push({ note: n, block: b, date: f.date, text: (text.slice(0, f.index) + text.slice(f.index + f.length)).replace(/\s+/g, ' ').trim() || 'Напоминание' });
      }
      return out.sort((a, b) => a.date - b.date);
    },
  };

  let remindersTimer = null;
  const scheduleReminders = () => { clearTimeout(remindersTimer); remindersTimer = setTimeout(checkReminders, 1500); };
  /// Пока приложение открыто, пришло время - уведомление (или плашка). В фоне надёжнее «В Календарь».
  function checkReminders() {
    const list = Reminders.all(), now = Date.now();
    const fired = new Set(local.get('fired', []));
    $('#reminders-dot').hidden = !list.some(r => r.date > now && r.date - now < 864e5);
    for (const r of list) {
      const key = r.block.id + '@' + r.date.getTime();
      if (r.date <= now && now - r.date < 36e5 && !fired.has(key)) {
        fired.add(key);
        notify(r);
      }
    }
    local.set('fired', [...fired].slice(-300));
  }
  setInterval(checkReminders, 30000);
  async function notify(r) {
    if ('Notification' in window && Notification.permission === 'granted') {
      try {
        const reg = await navigator.serviceWorker.ready;
        return reg.showNotification(r.text, { body: titleOf(r.note), icon: 'icon-192.png', data: { note: r.note.id }, tag: r.block.id });
      } catch {}
    }
    toast('⏰ ' + r.text, 'Открыть', () => openNote(r.note.id, true));
  }

  function remindersSheet() {
    const list = Reminders.all(), now = new Date();
    const canNotify = 'Notification' in window && Notification.permission !== 'granted' && Notification.permission !== 'denied';
    openSheet(`<h3>Напоминания</h3>
      <p class="sub">Допиши к задаче <b>@завтра 10:00</b>, <b>@18:30</b>, <b>@пт</b> или <b>@15.10</b>. Чтобы напомнило, даже когда приложение закрыто, добавь в Календарь.</p>
      ${canNotify ? '<button class="btn" data-perm style="width:100%">Уведомлять, пока приложение открыто</button>' : ''}
      ${list.length ? list.map((r, i) => `<div class="item"><span class="ic">${ICON.bell}</span><button class="lbl" data-open="${i}" style="text-align:left">${esc(r.text)}<small${r.date < now ? ' style="color:var(--danger)"' : ''}>${esc(Reminders.label(r.date))} · ${esc(titleOf(r.note))}</small></button><button class="chip" data-cal="${i}">В Календарь</button></div>`).join('')
        : '<p class="note-p">Пока нет задач со временем.</p>'}`, root => {
      root.addEventListener('click', async e => {
        const o = e.target.closest('[data-open]'), c = e.target.closest('[data-cal]');
        if (o) { closeSheet(); const r = list[+o.dataset.open]; openNote(r.note.id, true); setTimeout(() => focusBlock(r.block, 'end'), 80); }
        if (c) addToCalendar(list[+c.dataset.cal]);
        if (e.target.closest('[data-perm]')) {
          const p = await Notification.requestPermission();
          toast(p === 'granted' ? 'Готово: напомню, пока приложение открыто' : 'Уведомления выключены');
          closeSheet();
        }
      });
    });
  }
  $('#btn-reminders').addEventListener('click', remindersSheet);

  /// Событие с будильником для Календаря - он напомнит даже при закрытом приложении.
  function addToCalendar(r) {
    const z = d => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const end = new Date(r.date.getTime() + 15 * 60000);
    const ics = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Zametochki//RU', 'BEGIN:VEVENT', 'UID:' + r.block.id + '@zametochki',
      'DTSTAMP:' + z(new Date()), 'DTSTART:' + z(r.date), 'DTEND:' + z(end), 'SUMMARY:' + r.text.replace(/[,;]/g, '\\$&'),
      'DESCRIPTION:Из заметки «' + titleOf(r.note).replace(/[,;]/g, '\\$&') + '»', 'BEGIN:VALARM', 'TRIGGER:PT0M', 'ACTION:DISPLAY',
      'DESCRIPTION:' + r.text.replace(/[,;]/g, '\\$&'), 'END:VALARM', 'END:VEVENT', 'END:VCALENDAR'].join('\r\n');
    shareFile(new File([ics], 'napominanie.ics', { type: 'text/calendar' }));
  }

  // ───────── шаблоны ─────────
  const ruDate = (d, opts) => d.toLocaleDateString('ru-RU', opts);
  const TEMPLATES = [
    ['meeting', 'Встреча', d => `# Встреча · ${ruDate(d, { day: 'numeric', month: 'long' })}\n**Кто:**\n**Зачем:**\n## Обсудили\n- \n## Решили\n- \n## Задачи\n[ ] `],
    ['week', 'План недели', d => {
      const monday = new Date(d); monday.setDate(d.getDate() - ((d.getDay() + 6) % 7));
      const days = Array.from({ length: 7 }, (_, i) => { const x = new Date(monday); x.setDate(monday.getDate() + i); return x; });
      return `# Неделя ${ruDate(monday, { day: 'numeric', month: 'short' })} – ${ruDate(days[6], { day: 'numeric', month: 'short' })}\n## Главное на неделе\n[ ] \n` +
        days.map(x => { const w = ruDate(x, { weekday: 'long', day: 'numeric' }); return `## ${w.charAt(0).toUpperCase() + w.slice(1)}\n[ ] `; }).join('\n');
    }],
    ['idea', 'Идея проекта', () => '# Идея: \n> Одним предложением - что это и для кого\n## Зачем\n- \n## Как сделать\n- \n## Первые шаги\n[ ] \n## Что может пойти не так\n- '],
    ['diary', 'Дневник дня', d => { const t = ruDate(d, { day: 'numeric', month: 'long', weekday: 'long' }); return `# ${t}\n## Что было хорошего\n- \n## Что понял\n- \n## Спасибо за\n- \n## Завтра\n[ ] `; }],
    ['shopping', 'Список покупок', () => '# Покупки\n## Продукты\n[ ] \n## Для дома\n[ ] '],
    ['kanban', 'Проект с доской', () => '# Проект\n> Цель и срок\n## Доска'],
  ];
  function templateBlocks(t) {
    const blocks = parseMarkdown(t[2](new Date()));
    if (t[0] === 'kanban') blocks.push({ id: uid(), type: 'board', columns: emptyBoard() });
    return blocks;
  }
  function pickTemplate(b, asNew = false) {
    openSheet(`<h3>Шаблон</h3>${TEMPLATES.map((t, i) => `<button class="item" data-t="${i}"><span class="ic">${ICON.template}</span><span class="lbl">${t[1]}</span></button>`).join('')}`, root => {
      root.addEventListener('click', e => {
        const it = e.target.closest('[data-t]');
        if (!it) return;
        const t = TEMPLATES[+it.dataset.t];
        closeSheet();
        if (asNew || !b) return newNote({ blocks: templateBlocks(t) });
        const n = note(openId), blocks = templateBlocks(t);
        const i = n.blocks.indexOf(b);
        const empty = b.type === 'text' && !plainOf(b.html).trim();
        n.blocks.splice(empty ? i : i + 1, empty ? 1 : 0, ...blocks);
        renderNote(); save(n);
        focusBlock(blocks[0], 'end');
      });
    });
  }

  // ───────── Markdown туда и обратно ─────────
  function inlineMd(s) {
    let h = esc(s);
    // Без lookbehind: Safari до 16.4 его не понимает, и приложение не запустилось бы целиком.
    // «\S|\S.*?\S» - сначала самый короткий кусок: «**-** и **[]**» - два жирных, а не один длинный.
    h = h.replace(/\*\*\*(\S|\S.*?\S)\*\*\*/g, '<b><i>$1</i></b>')
      .replace(/\*\*(\S|\S.*?\S)\*\*/g, '<b>$1</b>')
      .replace(/(^|[^\w])_([^\s_]|[^\s_].*?[^\s_])_(?!\w)/g, '$1<i>$2</i>')
      .replace(/(^|[^*\w])\*([^*\s]|[^*\s].*?[^*\s])\*(?![*\w])/g, '$1<i>$2</i>')
      .replace(/~~(\S|\S.*?\S)~~/g, '<s>$1</s>')
      .replace(/==(\S|\S.*?\S)==/g, '<mark>$1</mark>');
    return h;
  }
  const MD_PREFIX = [['### ', 'subheading'], ['## ', 'heading'], ['# ', 'title'], ['- [ ] ', 'todo'], ['- [x] ', 'done'], ['- [X] ', 'done'],
    ['[ ] ', 'todo'], ['[] ', 'todo'], ['[x] ', 'done'], ['☐ ', 'todo'], ['☑ ', 'done'], ['- ', 'bullet'], ['* ', 'bullet'], ['• ', 'bullet'], ['> ', 'quote'], ['│ ', 'quote']];
  function parseMarkdown(text) {
    const lines = text.replace(/\r\n?/g, '\n').split('\n');
    const out = [];
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i];
      if (/^```/.test(line)) {
        const lang = line.slice(3).trim().toLowerCase();
        const start = out.length;
        for (i++; i < lines.length && !/^```/.test(lines[i]); i++) out.push({ id: uid(), type: 'code', html: esc(lines[i]) });
        if (out[start] && Code.langs.some(l => l[0] === lang)) out[start].lang = lang;
        continue;
      }
      if (/^\s*(---|\*\*\*|———)\s*$/.test(line)) { out.push({ id: uid(), type: 'divider' }); continue; }
      if (/^\|.*\|\s*$/.test(line)) {
        const rows = [];
        for (; i < lines.length && /^\|.*\|\s*$/.test(lines[i]); i++) {
          if (/^\|[\s:-]+(\|[\s:-]+)*\|\s*$/.test(lines[i])) continue;
          rows.push(lines[i].trim().slice(1, -1).split('|').map(c => c.trim()));
        }
        i--;
        out.push({ id: uid(), type: 'table', cells: rows });
        continue;
      }
      if (/^ {2,}- /.test(line) || /^\t- /.test(line)) { out.push({ id: uid(), type: 'toggleItem', html: inlineMd(line.replace(/^\s+- /, '')) }); continue; }
      let type = 'text';
      const num = line.match(/^\d+[.)] /);
      const pre = MD_PREFIX.find(p => line.startsWith(p[0]) || line + ' ' === p[0]);
      if (pre) { type = pre[1]; line = line.slice(Math.min(pre[0].length, line.length)); }
      else if (num) { type = 'numbered'; line = line.slice(num[0].length); }
      out.push({ id: uid(), type, html: inlineMd(line) });
    }
    while (out.length > 1 && out[out.length - 1].type === 'text' && !out[out.length - 1].html) out.pop();
    return out;
  }

  function htmlToMd(html) {
    const t = document.createElement('template');
    t.innerHTML = html || '';
    const walk = node => [...node.childNodes].map(n => {
      if (n.nodeType === 3) return n.nodeValue;
      if (n.nodeType !== 1) return '';
      const inner = walk(n);
      if (!inner.trim()) return inner;
      switch (n.tagName) {
        case 'B': case 'STRONG': return `**${inner}**`;
        case 'I': case 'EM': return `_${inner}_`;
        case 'S': case 'STRIKE': case 'DEL': return `~~${inner}~~`;
        case 'MARK': return `==${inner}==`;
        case 'BR': return '\n';
        case 'A': return `[${inner}](${n.getAttribute('href')})`;
        default: return inner;
      }
    }).join('');
    return walk(t.content).replace(/ /g, ' ');
  }

  function toMarkdown(n) {
    let num = 0;
    return n.blocks.map((b, i) => {
      num = b.type === 'numbered' ? num + 1 : 0;
      const md = htmlToMd(b.html);
      switch (b.type) {
        case 'title': return '# ' + md;
        case 'heading': return '## ' + md;
        case 'subheading': return '### ' + md;
        case 'bullet': case 'toggle': return '- ' + md;
        case 'numbered': return num + '. ' + md;
        case 'todo': return '- [ ] ' + md;
        case 'done': return '- [x] ' + md;
        case 'quote': return '> ' + md;
        case 'toggleItem': return '  - ' + md;
        case 'code': {
          // Подряд идущие строки кода - один блок ``` … ```.
          const first = (n.blocks[i - 1] || {}).type !== 'code', last = (n.blocks[i + 1] || {}).type !== 'code';
          return (first ? '```' + (b.lang && b.lang !== 'plain' ? b.lang : '') + '\n' : '') + plainOf(b.html) + (last ? '\n```' : '');
        }
        case 'divider': return '---';
        case 'image': return '[картинка]';
        case 'file': return `[файл: ${b.name || ''}]`;
        case 'audio': return '[голосовая заметка]';
        case 'page': return '📄 ' + (note(b.page) ? titleOf(note(b.page)) : 'Страница');
        case 'board': return b.columns.map(c => [`**${c.title}**`, ...c.cards.map(k => '- ' + k.text)].join('\n')).join('\n\n');
        case 'table': return b.cells.map((r, i) => '| ' + r.join(' | ') + ' |' + (i === 0 ? '\n|' + r.map(() => ' --- |').join('') : '')).join('\n');
        default: return md;
      }
    }).join('\n');
  }

  /// Заметка с Мака (файл .json из папки Zametki): текст и куски оформления → строки.
  function fromMacDoc(doc) {
    const text = doc.text || '', runs = doc.runs || [];
    const at = i => runs.filter(r => i >= r.from && i < r.from + r.length);
    const blocks = [];
    let start = 0;
    const paras = text.split('\n');
    paras.forEach((p, pi) => {
      const end = start + p.length;
      const look = at(end < text.length ? end : Math.max(end - 1, start));
      const blockRun = look.find(r => r.block) || at(start).find(r => r.block);
      const type = blockRun ? blockRun.block : 'text';
      if (p === '￼') {
        const r = at(start).find(x => x.block) || {};
        if (r.board) { try { blocks.push({ id: uid(), type: 'board', columns: JSON.parse(r.board).columns }); } catch {} }
        else if (r.table) { try { blocks.push({ id: uid(), type: 'table', cells: JSON.parse(r.table).cells }); } catch {} }
        else if (r.block === 'divider') blocks.push({ id: uid(), type: 'divider' });
        else if (r.block === 'image') blocks.push({ id: uid(), type: 'text', html: '[картинка осталась на Mac]' });
        else if (r.block === 'audio') blocks.push({ id: uid(), type: 'text', html: '[голосовая заметка осталась на Mac]' });
      } else {
        let html = '';
        for (let i = start; i < end;) {
          const rs = at(i);
          let j = i + 1;
          const key = JSON.stringify(rs.map(r => [r.bold, r.italic, r.underline, r.strike, r.highlight]));
          while (j < end && JSON.stringify(at(j).map(r => [r.bold, r.italic, r.underline, r.strike, r.highlight])) === key) j++;
          let piece = esc(text.slice(i, j).replace(/￼/g, ''));
          if (rs.some(r => r.bold)) piece = `<b>${piece}</b>`;
          if (rs.some(r => r.italic)) piece = `<i>${piece}</i>`;
          if (rs.some(r => r.underline)) piece = `<u>${piece}</u>`;
          if (rs.some(r => r.strike)) piece = `<s>${piece}</s>`;
          if (rs.some(r => r.highlight)) piece = `<mark>${piece}</mark>`;
          html += piece;
          i = j;
        }
        if (pi < paras.length - 1 || p) blocks.push({ id: uid(), type: OBJECT_TYPES.has(type) ? 'text' : type, html });
      }
      start = end + 1;
    });
    return blocks.length ? blocks : [{ id: uid(), type: 'text', html: '' }];
  }

  // ───────── обмен файлами ─────────
  async function shareFile(file) {
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      try { await navigator.share({ files: [file] }); return; } catch (e) { if (e.name === 'AbortError') return; }
    }
    const a = document.createElement('a');
    a.href = URL.createObjectURL(file);
    a.download = file.name;
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 4000);
  }
  const safeName = s => (s.replace(/[\\/:*?"<>|]/g, '-').slice(0, 60) || 'Заметка');

  async function exportAllMarkdown() {
    const files = [...notes.values()].map(n => new File([toMarkdown(n)], safeName(titleOf(n)) + '.md', { type: 'text/markdown' }));
    if (navigator.canShare && navigator.canShare({ files })) {
      try { await navigator.share({ files }); return; } catch (e) { if (e.name === 'AbortError') return; }
    }
    shareFile(new File([[...notes.values()].map(toMarkdown).join('\n\n---\n\n')], 'Заметочки.md', { type: 'text/markdown' }));
  }

  /// Резервная копия: все заметки, картинки и записи - одним файлом.
  async function backup() {
    toast('Собираю копию…');
    const files = await DB.all('files');
    const toData = blob => new Promise(res => { const r = new FileReader(); r.onload = () => res(r.result); r.readAsDataURL(blob); });
    const packed = [];
    for (const f of files) packed.push({ id: f.id, type: f.type, data: await toData(f.blob) });
    const json = JSON.stringify({ app: 'zametochki', version: 1, saved: new Date().toISOString(), notes: [...notes.values()], files: packed });
    const date = new Date().toISOString().slice(0, 10);
    shareFile(new File([json], `Заметочки-копия-${date}.json`, { type: 'application/json' }));
  }

  $('#file-import').addEventListener('change', async e => {
    const list = [...e.target.files];
    e.target.value = '';
    let added = 0, restored = 0;
    let first = null;
    for (const f of list) {
      const text = await f.text();
      if (/\.json$/i.test(f.name) || f.type === 'application/json') {
        let data;
        try { data = JSON.parse(text); } catch { toast('Не читается: ' + f.name); continue; }
        if (data.app === 'zametochki' && Array.isArray(data.notes)) {
          for (const p of data.files || []) {
            const blob = await (await fetch(p.data)).blob();
            await DB.put('files', { id: p.id, blob, type: p.type });
          }
          for (const n of data.notes) { notes.set(n.id, n); await DB.put('notes', n); restored++; }
        } else if (typeof data.text === 'string') {
          const n = newNote({ blocks: fromMacDoc(data), style: data.style ? macStyle(data.style) : null, open: false });
          first = first || n; added++;
        }
      } else {
        const n = newNote({ blocks: parseMarkdown(text), open: false });
        first = first || n; added++;
      }
    }
    closeSheet();
    renderList();
    toast(restored ? `Восстановлено заметок: ${restored}` : added ? `Добавлено заметок: ${added}` : 'Ничего не добавилось');
    if (first) openNote(first.id, true);
  });
  /// Стиль заметки с Мака - на понятный здесь.
  function macStyle(s) {
    const bg = s.background || {};
    const kind = bg.gradient ? 'gradient' : 'color';
    const id = bg.gradient ? bg.gradient._0 : bg.color ? bg.color._0 : 'blue';
    return { font: s.font || 'hand', bg: `${kind}:${id || 'blue'}`, bullet: s.bullet || 'dot' };
  }

  // ───────── листы: стиль, ещё, настройки ─────────
  const sheet = $('#sheet'), scrim = $('#scrim');
  let sheetClose = null;
  function openSheet(html, setup, onClose) {
    if (!sheet.hidden) closeSheet(true);
    // Каждый раз новое содержимое: обработчики прошлого листа не должны сработать ещё раз.
    const fresh = document.createElement('div');
    fresh.id = 'sheet-body';
    $('#sheet-body').replaceWith(fresh);
    fresh.innerHTML = html;
    sheet.hidden = false; scrim.hidden = false;
    sheetClose = onClose || null;
    if (setup) setup($('#sheet-body'));
  }
  function closeSheet(silent = false) {
    if (sheet.hidden) return;
    const cb = sheetClose; sheetClose = null;
    sheet.hidden = true; scrim.hidden = true;
    if (!silent && cb) cb();
  }
  scrim.addEventListener('click', () => closeSheet());

  let stylePick = null; // что выбираем из фото: обложку или фон
  $('#btn-style').addEventListener('click', () => {
    const n = note(openId);
    if (!n) return;
    const chip = (key, value, cur, label, extra = '') => `<button class="chip${cur === value ? ' on' : ''}" data-k="${key}" data-v="${value}"${extra}>${label}</button>`;
    const draw = () => {
      const s = n.style || defaultStyle();
      return `<h3>Стиль страницы</h3>
        <div class="group">ШРИФТ</div><div class="chips">${FONTS.map(f => chip('font', f[0], s.font || 'hand', f[1], ` style="font-family:${f[2]}"`)).join('')}</div>
        <div class="group">ФОН</div><div class="swatches">${COLORS.map(c => `<button class="swatch${s.bg === 'color:' + c[0] ? ' on' : ''}" data-k="bg" data-v="color:${c[0]}" style="background:${c[1]}" aria-label="${c[0]}"></button>`).join('')}
        ${GRADIENTS.map(g => `<button class="swatch${s.bg === 'gradient:' + g[0] ? ' on' : ''}" data-k="bg" data-v="gradient:${g[0]}" style="background:linear-gradient(${g[1]},${g[2]})" aria-label="${g[0]}"></button>`).join('')}</div>
        <div class="btns"><button class="btn" data-pick="bg">${(s.bg || '').startsWith('image:') ? 'Другое фото фоном' : 'Своё фото фоном'}</button>${s.cover ? '<button class="btn" data-nocover>Убрать обложку</button>' : '<button class="btn" data-pick="cover">Обложка</button>'}</div>
        <div class="group">ЦВЕТ ТЕКСТА</div><div class="colors">${TEXT_COLORS.map(c => `<button class="tc${(s.text || 'white') === c[0] ? ' on' : ''}" data-k="text" data-v="${c[0]}" style="color:${c[1]}" aria-label="${c[2]}">А</button>`).join('')}</div>
        <div class="group">МАРКЕР СПИСКА</div><div class="chips">${chip('bullet', 'dot', s.bullet || 'dot', '• Точка')}${chip('bullet', 'dash', s.bullet || 'dot', '– Тире')}</div>
        <div class="group">РАЗДЕЛИТЕЛЬ</div><div class="chips">${chip('divider', 'line', s.divider || 'line', 'Линия')}${chip('divider', 'dots', s.divider || 'line', 'Точки')}${chip('divider', 'washi', s.divider || 'line', 'Лента')}</div>
        <div class="group">КАРТОЧКИ СТРАНИЦ И ФАЙЛОВ</div><div class="chips">${chip('card', 'plain', s.card || 'plain', 'Простые')}${chip('card', 'outline', s.card || 'plain', 'С рамкой')}${chip('card', 'filled', s.card || 'plain', 'Яркие')}</div>
        <div class="group">ШИРИНА (НА IPAD)</div><div class="chips">${chip('width', 'regular', s.width || 'regular', 'Обычная')}${chip('width', 'wide', s.width || 'regular', 'Широкая')}</div>
        <div class="btns"><button class="btn" data-default>Для новых заметок</button><button class="btn" data-all>Ко всем заметкам</button></div>`;
    };
    const apply = s => { n.style = s; save(n); applyStyle(s); $('#sheet-body').innerHTML = draw(); };
    openSheet(draw(), root => {
      root.addEventListener('click', e => {
        const t = e.target.closest('button');
        if (!t) return;
        const s = { ...(n.style || defaultStyle()) };
        if (t.dataset.k) s[t.dataset.k] = t.dataset.v;
        if (t.dataset.pick) { stylePick = { note: n, what: t.dataset.pick }; $('#file-style').click(); return; }
        if ('nocover' in t.dataset) delete s.cover;
        if ('default' in t.dataset) { local.set('defaultStyle', s); toast('Новые заметки будут в этом стиле'); }
        if ('all' in t.dataset) { for (const x of notes.values()) { x.style = { ...s }; save(x); } toast('Стиль - у всех заметок'); }
        apply(s);
      });
    });
    $('#file-style').onchange = async e => {
      const file = e.target.files[0];
      e.target.value = '';
      if (!file || !stylePick) return;
      const blob = await shrinkImage(file), id = uid();
      await DB.put('files', { id, blob, type: blob.type });
      const s = { ...(stylePick.note.style || defaultStyle()) };
      if (stylePick.what === 'cover') s.cover = id; else s.bg = 'image:' + id;
      stylePick = null;
      apply(s);
    };
  });

  $('#btn-more').addEventListener('click', () => {
    const n = note(openId);
    if (!n) return;
    const focus = editor.classList.contains('focus-mode');
    openSheet(`<h3>${esc(titleOf(n))}</h3>
      <button class="item" data-a="focus"><span class="ic">◎</span><span class="lbl">${focus ? 'Выключить режим фокуса' : 'Режим фокуса'}<small>Всё, кроме строки, которую пишешь, приглушено</small></span></button>
      <button class="item" data-a="template"><span class="ic">${ICON.template}</span><span class="lbl">Вставить шаблон</span></button>
      <button class="item" data-a="page"><span class="ic">${ICON.page}</span><span class="lbl">Новая страница внутри</span></button>
      <button class="item" data-a="move"><span class="ic">⇄</span><span class="lbl">Переместить<small>Внутрь другой заметки, наверх, выше или ниже</small></span></button>
      <div class="group">ПОДЕЛИТЬСЯ</div>
      <button class="item" data-a="png"><span class="ic">${ICON.image}</span><span class="lbl">Картинкой<small>Страница целиком - как она выглядит</small></span></button>
      <button class="item" data-a="copyimg"><span class="ic">⧉</span><span class="lbl">Скопировать картинкой<small>Вставить в мессенджер</small></span></button>
      <button class="item" data-a="pdf"><span class="ic">PDF</span><span class="lbl">PDF<small>Фон, почерк, галочки - как на экране</small></span></button>
      <button class="item" data-a="share"><span class="ic">↗</span><span class="lbl">Отправить текстом</span></button>
      <button class="item" data-a="md"><span class="ic">MD</span><span class="lbl">Сохранить в Markdown<small>Откроется и на Mac: «⋯ → Импорт»</small></span></button>
      <button class="item" data-a="copy"><span class="ic">⧉</span><span class="lbl">Скопировать текст</span></button>
      <div class="group"></div>
      <button class="item" data-a="versions"><span class="ic">↺</span><span class="lbl">Прошлые версии<small>Если текст случайно стёрся</small></span></button>
      <button class="item danger" data-a="delete"><span class="ic">✕</span><span class="lbl">Удалить заметку</span></button>`, root => {
      root.addEventListener('click', async e => {
        const a = e.target.closest('[data-a]');
        if (!a) return;
        const act = a.dataset.a;
        // Картинку в буфер кладём прямо в нажатии - иначе iPhone не разрешит.
        if (act === 'copyimg') return copyPageImage(n);
        closeSheet();
        if (act === 'png') return exportPage(n, 'png');
        if (act === 'pdf') return exportPage(n, 'pdf');
        if (act === 'move') return moveSheet(n);
        if (act === 'versions') return versionsSheet(n);
        if (act === 'focus') { editor.classList.toggle('focus-mode'); local.set('focus', editor.classList.contains('focus-mode')); updateStats(); }
        if (act === 'template') pickTemplate(lastTextBlock());
        if (act === 'page') { const last = lastTextBlock(); const nb = { id: uid(), type: 'text', html: '' }; insertAfter(n.blocks[n.blocks.length - 1], nb); makePage(nb); void last; }
        if (act === 'share') {
          const text = toMarkdown(n);
          if (navigator.share) navigator.share({ title: titleOf(n), text }).catch(() => {});
          else { await navigator.clipboard.writeText(text).catch(() => {}); toast('Текст скопирован'); }
        }
        if (act === 'md') shareFile(new File([toMarkdown(n)], safeName(titleOf(n)) + '.md', { type: 'text/markdown' }));
        if (act === 'copy') navigator.clipboard.writeText(toMarkdown(n)).then(() => toast('Текст скопирован'), () => toast('Не получилось скопировать'));
        if (act === 'delete') deleteNote(n.id);
      });
    });
  });

  $('#btn-settings').addEventListener('click', async () => {
    const est = navigator.storage && navigator.storage.estimate ? await navigator.storage.estimate().catch(() => null) : null;
    const persisted = navigator.storage && navigator.storage.persisted ? await navigator.storage.persisted().catch(() => false) : false;
    const mb = est ? (est.usage / 1048576).toFixed(1) : null;
    const sw = (key, on) => `<button class="switch${on ? ' on' : ''}" data-sw="${key}" role="switch" aria-checked="${on}"></button>`;
    openSheet(`<h3>Настройки</h3>
      <div class="toggle-row"><span>Звук печати<small>Мягкий щелчок на каждую букву</small></span>${sw('sound', local.get('sound', true))}</div>
      <div class="toggle-row"><span>Счётчик слов<small>Слова и время чтения в углу заметки</small></span>${sw('stats', local.get('stats', true))}</div>
      <div class="group">РАЗМЕР ТЕКСТА</div>
      <div class="chips">${[['Мелкий', 0.88], ['Обычный', 1], ['Крупный', 1.15], ['Огромный', 1.3]].map(([t, v]) => `<button class="chip${textScale() === v ? ' on' : ''}" data-scale="${v}">${t}</button>`).join('')}</div>
      <p class="note-p">Быстрая заметка: кнопка с лотком в списке или долгое нажатие на «+». Голосом - микрофон на клавиатуре iPhone.</p>
      <div class="group">С MAC И НА MAC</div>
      <button class="item" data-a="import"><span class="ic">↓</span><span class="lbl">Открыть файлы<small>.md, .txt, заметки .json с Мака, резервная копия</small></span></button>
      <button class="item" data-a="md"><span class="ic">MD</span><span class="lbl">Все заметки в Markdown<small>На Mac: «⋯ → Импорт»</small></span></button>
      <button class="item" data-a="template"><span class="ic">${ICON.template}</span><span class="lbl">Новая заметка из шаблона</span></button>
      <div class="group">ДАННЫЕ</div>
      <button class="item" data-a="backup"><span class="ic">⤓</span><span class="lbl">Резервная копия<small>Все заметки, картинки и записи одним файлом</small></span></button>
      <p class="note-p">Заметки хранятся только на этом телефоне: ${notes.size} ${plural(notes.size, 'заметка', 'заметки', 'заметок')}${mb ? `, ${mb} МБ` : ''}. ${persisted ? 'Система не сотрёт их сама.' : standalone ? '' : 'Поставь приложение на экран «Домой» - так Safari не сотрёт заметки, если долго не открывать.'} Ничего не уходит в сеть.</p>
      <p class="note-p"><a href="../" style="color:var(--warm)">Сайт Заметочек</a> · версия для Mac там же · <b>версия ${APP_VERSION}</b></p>`, root => {
      root.addEventListener('click', e => {
        const sc = e.target.closest('[data-scale]');
        if (sc) {
          local.set('scale', +sc.dataset.scale);
          root.querySelectorAll('[data-scale]').forEach(c => c.classList.toggle('on', c === sc));
          if (openId) applyStyle(note(openId).style);
          return;
        }
        const s = e.target.closest('[data-sw]');
        if (s) {
          const on = !s.classList.contains('on');
          s.classList.toggle('on', on); s.setAttribute('aria-checked', on);
          local.set(s.dataset.sw, on);
          updateStats();
          return;
        }
        const a = e.target.closest('[data-a]');
        if (!a) return;
        if (a.dataset.a === 'import') $('#file-import').click();
        if (a.dataset.a === 'md') exportAllMarkdown();
        if (a.dataset.a === 'backup') backup();
        if (a.dataset.a === 'template') pickTemplate(null, true);
      });
    });
  });

  // ───────── быстрая заметка во «Входящие» ─────────
  function inbox() {
    let n = note(local.get('inbox', null));
    if (!n) n = [...notes.values()].find(x => !x.parent && titleOf(x) === 'Входящие');
    if (!n) n = newNote({ blocks: [{ id: uid(), type: 'title', html: 'Входящие' }], open: false });
    local.set('inbox', n.id);
    return n;
  }
  function quickNote() {
    openSheet(`<h3>Во «Входящие»</h3>
      <textarea class="field" id="quick-text" placeholder="Мысль, задача, ссылка…" autofocus></textarea>
      <p class="note-p">Начни с [] - будет задача, с @завтра 10:00 - ещё и напоминание.</p>
      <div class="btns"><button class="btn" data-cancel>Отмена</button><button class="btn primary" data-ok>Сохранить</button></div>`, root => {
      const area = root.querySelector('#quick-text');
      area.focus();
      root.addEventListener('click', e => {
        if (e.target.closest('[data-cancel]')) return closeSheet();
        if (!e.target.closest('[data-ok]')) return;
        const text = area.value.trim();
        closeSheet();
        if (!text) return;
        const n = inbox();
        const blocks = parseMarkdown(text.split('\n').map(l => l.startsWith('[] ') ? '[ ] ' + l.slice(3) : l).join('\n'));
        if (n.blocks.length && !isObject(n.blocks[n.blocks.length - 1]) && !plainOf(n.blocks[n.blocks.length - 1].html) && n.blocks.length > 1) n.blocks.pop();
        n.blocks.push(...blocks);
        save(n);
        if (openId === n.id) renderNote();
        renderList();
        click('enter');
        toast('Сохранено во «Входящие»', 'Открыть', () => openNote(n.id, true));
      });
    });
  }
  $('#btn-quick').addEventListener('click', quickNote);
  // Долгое нажатие на «+» - быстрая заметка; обычное - новая заметка.
  {
    const fab = $('#btn-new');
    let timer = null, long = false;
    fab.addEventListener('pointerdown', () => { long = false; timer = setTimeout(() => { long = true; if (navigator.vibrate) navigator.vibrate(10); quickNote(); }, 480); });
    for (const ev of ['pointerup', 'pointercancel', 'pointerleave']) fab.addEventListener(ev, () => clearTimeout(timer));
    fab.addEventListener('click', () => { if (long) { long = false; return; } newNote(); });
  }

  // ───────── перенос заметок ─────────
  function isInside(id, ancestor) { let p = note(id) && note(id).parent; while (p) { if (p === ancestor) return true; p = note(p) && note(p).parent; } return false; }
  const depthOf = id => { let d = 0, p = note(id) && note(id).parent; while (p) { d++; p = note(p) && note(p).parent; } return d; };
  const heightOf = id => { const kids = children(id); return kids.length ? 1 + Math.max(...kids.map(k => heightOf(k.id))) : 0; };
  function moveNote(n, parent) {
    if (parent && (parent === n.id || isInside(parent, n.id))) return;
    if (parent && depthOf(parent) + 1 + heightOf(n.id) > 5) return toast('Глубже 5 уровней вкладывать нельзя');
    const old = n.parent;
    if (old !== parent) {
      if (old && note(old)) { const o = note(old); o.blocks = o.blocks.filter(b => !(b.type === 'page' && b.page === n.id)); if (!o.blocks.length) o.blocks.push({ id: uid(), type: 'text', html: '' }); save(o); }
      if (parent) { const p = note(parent); p.blocks.push({ id: uid(), type: 'page', page: n.id }); save(p); expanded.add(parent); local.set('expanded', [...expanded]); }
    }
    n.parent = parent || null;
    const sibs = children(n.parent).filter(x => x.id !== n.id);
    n.order = sibs.length ? sibs[sibs.length - 1].order + 1 : 0;
    save(n);
    renderList();
    toast(parent ? 'Теперь внутри «' + titleOf(note(parent)) + '»' : 'Перенесено наверх');
  }
  function shiftNote(n, dir) {
    const sibs = children(n.parent || null), i = sibs.findIndex(x => x.id === n.id), j = i + dir;
    if (j < 0 || j >= sibs.length) return;
    [sibs[i].order, sibs[j].order] = [sibs[j].order, sibs[i].order];
    if (sibs[i].order === sibs[j].order) sibs[i].order += dir;
    save(sibs[i]); save(sibs[j]);
    renderList();
  }
  function moveSheet(n) {
    const rows = [];
    const walk = (parent, depth) => { for (const x of children(parent)) { if (x.id === n.id || isInside(x.id, n.id)) continue; rows.push([x, depth]); walk(x.id, depth + 1); } };
    walk(null, 0);
    openSheet(`<h3>Переместить</h3>
      <div class="btns"><button class="btn" data-shift="-1">↑ Выше</button><button class="btn" data-shift="1">↓ Ниже</button></div>
      <div class="group">ПОЛОЖИТЬ ВНУТРЬ</div>
      <button class="item${!n.parent ? ' on' : ''}" data-to=""><span class="ic">⌂</span><span class="lbl">Наверх, без папки</span></button>
      ${rows.map(([x, d]) => `<button class="item${n.parent === x.id ? ' on' : ''}" data-to="${x.id}" style="padding-left:${8 + d * 18}px"><span class="ic">${ICON.page}</span><span class="lbl">${esc(titleOf(x))}</span></button>`).join('')}`, root => {
      root.addEventListener('click', e => {
        const sh = e.target.closest('[data-shift]'), to = e.target.closest('[data-to]');
        if (sh) { shiftNote(n, +sh.dataset.shift); toast(+sh.dataset.shift < 0 ? 'Выше в списке' : 'Ниже в списке'); }
        if (to) { closeSheet(); moveNote(n, to.dataset.to || null); openNote(n.id); }
      });
    });
  }

  // ───────── прошлые версии ─────────
  async function versionsSheet(n) {
    const all = (await DB.all('backups').catch(() => [])).filter(v => v.note === n.id).sort((a, b) => b.saved - a.saved);
    openSheet(`<h3>Прошлые версии</h3>
      <p class="sub">Когда заметка разом теряет заметную часть текста, прошлая версия сохраняется здесь.</p>
      ${all.length ? all.map((v, i) => `<button class="item" data-v="${i}"><span class="ic">↺</span><span class="lbl">${new Date(v.saved).toLocaleString('ru-RU', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}<small>${esc(titleOf(v.data))} · ${textLength(v.data)} знаков</small></span></button>`).join('')
        : '<p class="note-p">Пока ни одной - текст ни разу не пропадал.</p>'}`, root => {
      root.addEventListener('click', e => {
        const it = e.target.closest('[data-v]');
        if (!it) return;
        const v = all[+it.dataset.v];
        // Текущая версия сама уходит в резервные - вернуть можно и её.
        DB.put('backups', { key: n.id + '@' + Date.now(), note: n.id, saved: Date.now(), data: JSON.parse(JSON.stringify(n)) });
        n.blocks = v.data.blocks;
        n.style = v.data.style;
        written.set(n.id, JSON.stringify(n));
        save(n);
        closeSheet();
        openNote(n.id);
        toast('Версия возвращена');
      });
    });
  }

  // ───────── страница картинкой и в PDF ─────────
  const CANVAS_FONTS = { hand: 'Caveat, cursive', system: '-apple-system, system-ui, sans-serif', serif: '"New York", ui-serif, Georgia, serif',
    mono: 'ui-monospace, Menlo, monospace', rounded: 'ui-rounded, -apple-system, system-ui, sans-serif' };
  async function bitmapOf(id) {
    const f = id && await DB.get('files', id).catch(() => null);
    return f ? createImageBitmap(f.blob).catch(() => null) : null;
  }
  /// Страница целиком на холсте - фон, шрифт, маркеры, галочки, доски, плееры. Как экспорт на Mac.
  async function renderPage(n) {
    const v = styleVars(n.style), W = 820, pad = 64, colW = W - pad * 2;
    const fam = CANVAS_FONTS[v.fontKey] || CANVAS_FONTS.hand;
    await Promise.all([document.fonts.load('500 30px Caveat'), document.fonts.load('700 30px Caveat')]).catch(() => {});
    const bg = v.image && await bitmapOf(v.image), cover = v.cover && await bitmapOf(v.cover);
    const images = new Map();
    for (const b of n.blocks) if (b.type === 'image') images.set(b.id, await bitmapOf(b.file));
    const meter = document.createElement('canvas').getContext('2d');
    const base = v.px / textScale(), lh = v.line;
    const font = (size, weight = 500, f = fam) => `${weight} ${size}px ${f}`;
    const wrap = (text, f, width) => {
      meter.font = f;
      const out = [];
      for (const para of text.split('\n')) {
        let line = '';
        for (const word of para.split(/(\s+)/)) {
          const next = line + word;
          if (meter.measureText(next).width > width && line.trim()) { out.push(line.trimEnd()); line = word.trimStart(); } else line = next;
        }
        out.push(line);
      }
      return out;
    };
    const ops = [];
    let y = cover ? 210 : 56;
    let num = 0, collapsed = false;
    const fg = v.text;
    n.blocks.forEach((b, i) => {
      num = b.type === 'numbered' ? num + 1 : 0;
      if (b.type === 'toggle') collapsed = !!b.collapsed; else if (b.type !== 'toggleItem') collapsed = false;
      if (b.type === 'toggleItem' && collapsed) return;
      const text = plainOf(b.html);
      if (!isObject(b)) {
        const size = b.type === 'title' ? base * 1.55 : b.type === 'heading' ? base * 1.3 : b.type === 'subheading' ? base * 1.12 : b.type === 'code' ? 14 : base;
        const weight = ['title', 'heading', 'subheading'].includes(b.type) ? 700 : 500;
        const f = b.type === 'code' ? font(14, 400, CANVAS_FONTS.mono) : font(size, weight);
        const indent = ['bullet', 'numbered', 'todo', 'done', 'toggle', 'toggleItem'].includes(b.type) ? 32 : b.type === 'quote' ? 22 : b.type === 'code' ? 16 : 0;
        // Строка с оформлением: цвета, маркеры, жирный, курсив; у кода - раскраска.
        const html = b.type === 'code'
          ? Code.paint(text, (() => { const g = codeGroup(n, i); return g[0].lang || Code.detect(g.map(x => plainOf(x.html)).join('\n')); })())
          : b.html;
        const fontFor = st => b.type === 'code' ? font(14, st.bold ? 600 : 400, CANVAS_FONTS.mono) : `${st.italic ? 'italic ' : ''}${st.bold ? 700 : weight} ${size}px ${fam}`;
        const lines = layoutRich(segmentsOf(html), fontFor, colW - indent - (b.type === 'code' ? 16 : 0));
        const step = b.type === 'code' ? 22 : size * lh;
        if (['title', 'heading', 'subheading'].includes(b.type)) y += size * 0.3;
        const first = (n.blocks[i - 1] || {}).type !== 'code', last = (n.blocks[i + 1] || {}).type !== 'code';
        if (b.type === 'code' && first) y += 10;
        const top = y, h = lines.length * step;
        const kind = b.type, number = num;
        ops.push(ctx => {
          if (kind === 'code') {
            ctx.fillStyle = 'rgba(0,0,0,.32)';
            ctx.fillRect(pad, top - (first ? 10 : 0), colW, h + (first ? 10 : 0) + (last ? 10 : 0));
          }
          ctx.globalAlpha = kind === 'done' ? 0.45 : kind === 'quote' ? 0.88 : 1;
          ctx.textBaseline = 'middle';
          lines.forEach((line, k) => {
            const ly = top + k * step + step / 2;
            for (const tk of line) {
              const x = pad + indent + tk.x;
              if (tk.st.mark) { ctx.fillStyle = tk.st.mark; ctx.fillRect(x, ly - size * 0.55, tk.w, size * 1.1); }
              ctx.font = fontFor(tk.st);
              ctx.fillStyle = tk.st.color || fg;
              ctx.fillText(tk.text, x, ly);
              if (tk.st.strike || kind === 'done') ctx.fillRect(x, ly, tk.w, 1.5);
              if (tk.st.underline) ctx.fillRect(x, ly + size * 0.42, tk.w, 1.2);
            }
          });
          ctx.globalAlpha = 1;
          const mid = top + step / 2;
          ctx.fillStyle = fg; ctx.strokeStyle = fg;
          if (kind === 'bullet') { if (v.dash) ctx.fillRect(pad + 6, mid - 1, 11, 2); else { ctx.beginPath(); ctx.arc(pad + 12, mid, 3.3, 0, 7); ctx.fill(); } }
          if (kind === 'numbered') { ctx.globalAlpha = 0.75; ctx.font = font(base); ctx.fillText(number + '.', pad + 2, mid); ctx.globalAlpha = 1; }
          if (kind === 'todo' || kind === 'done') {
            ctx.lineWidth = 1.7; ctx.beginPath(); ctx.roundRect ? ctx.roundRect(pad + 4, mid - 9, 18, 18, 5) : ctx.rect(pad + 4, mid - 9, 18, 18);
            if (kind === 'done') { ctx.fill(); ctx.strokeStyle = v.base; ctx.lineWidth = 2.2; ctx.beginPath(); ctx.moveTo(pad + 8.5, mid); ctx.lineTo(pad + 11.5, mid + 3.5); ctx.lineTo(pad + 18, mid - 4); ctx.stroke(); }
            else ctx.stroke();
          }
          if (kind === 'toggle') { ctx.beginPath(); ctx.moveTo(pad + 8, mid - 5); ctx.lineTo(pad + 16, mid - 5); ctx.lineTo(pad + 12, mid + 4); ctx.fill(); }
          if (kind === 'quote') { ctx.globalAlpha = 0.55; ctx.fillRect(pad + 2, top + 4, 2.5, h - 8); ctx.globalAlpha = 1; }
        });
        y += h + (b.type === 'code' && last ? 10 : 0);
        if (b.type !== 'code') y += 2;
        return;
      }
      // Предметы.
      const top = y + 10;
      let h = 0;
      if (b.type === 'divider') {
        h = 26;
        ops.push(ctx => {
          const m = top + 13;
          ctx.fillStyle = fg;
          if (v.divider === 'dots') { ctx.globalAlpha = 0.45; for (const dx of [-16, 0, 16]) { ctx.beginPath(); ctx.arc(W / 2 + dx, m, 2.3, 0, 7); ctx.fill(); } }
          else if (v.divider === 'washi') { ctx.save(); ctx.translate(W / 2, m); ctx.rotate(-0.02); ctx.fillStyle = 'rgba(255,217,128,.28)'; ctx.fillRect(-colW * 0.3, -7, colW * 0.6, 14); ctx.restore(); }
          else { ctx.globalAlpha = 0.3; ctx.fillRect(pad, m - 0.75, colW, 1.5); }
          ctx.globalAlpha = 1;
        });
      } else if (b.type === 'image') {
        const img = images.get(b.id);
        if (img) {
          const w = Math.min(colW * (b.width || 1), img.width), hh = Math.min(w * img.height / img.width, 520), ww = hh * img.width / img.height;
          h = hh;
          ops.push(ctx => { ctx.save(); ctx.beginPath(); ctx.roundRect ? ctx.roundRect((W - ww) / 2, top, ww, hh, 12) : ctx.rect((W - ww) / 2, top, ww, hh); ctx.clip(); ctx.drawImage(img, (W - ww) / 2, top, ww, hh); ctx.restore(); });
        }
      } else if (b.type === 'page' || b.type === 'file') {
        h = 58;
        const title = b.type === 'page' ? (note(b.page) ? titleOf(note(b.page)) : 'Страница') : (b.name || 'Файл');
        ops.push(ctx => {
          ctx.fillStyle = v.card === 'filled' ? 'rgba(255,255,255,.16)' : 'rgba(255,255,255,.08)';
          ctx.beginPath(); ctx.roundRect ? ctx.roundRect(pad, top, Math.min(colW, 560), h, 14) : ctx.rect(pad, top, Math.min(colW, 560), h); ctx.fill();
          ctx.strokeStyle = v.card === 'outline' ? 'rgba(255,255,255,.5)' : 'rgba(255,255,255,.14)'; ctx.stroke();
          ctx.fillStyle = fg; ctx.font = font(base * 0.8, 650); ctx.textBaseline = 'middle';
          ctx.fillText((b.type === 'page' ? '📄 ' : '📎 ') + title, pad + 18, top + h / 2);
        });
      } else if (b.type === 'board') {
        const cols = b.columns.length || 1, gap = 8, lw = (colW - gap * (cols + 1)) / cols;
        const rows = Math.max(1, ...b.columns.map(c => c.cards.length));
        h = 44 + rows * 40 + 14;
        ops.push(ctx => {
          ctx.fillStyle = 'rgba(255,255,255,.04)'; ctx.fillRect(pad, top, colW, h);
          b.columns.forEach((c, ci) => {
            const x = pad + gap + ci * (lw + gap);
            ctx.fillStyle = 'rgba(0,0,0,.16)'; ctx.fillRect(x, top + 6, lw, h - 12);
            ctx.fillStyle = fg; ctx.font = font(v.fontKey === 'hand' ? 20 : 14, 700); ctx.textBaseline = 'middle';
            ctx.fillText(c.title, x + 10, top + 26);
            c.cards.forEach((k, ki) => {
              const cy = top + 44 + ki * 40;
              ctx.fillStyle = 'rgba(255,255,255,.1)'; ctx.fillRect(x + 6, cy, lw - 12, 34);
              ctx.fillStyle = fg; ctx.font = font(v.fontKey === 'hand' ? 18 : 13);
              ctx.fillText(wrap(k.text, ctx.font, lw - 28)[0] || '', x + 15, cy + 17);
            });
          });
        });
      } else if (b.type === 'audio') {
        h = 56;
        ops.push(ctx => {
          const w = Math.min(colW, 460);
          ctx.fillStyle = 'rgba(255,255,255,.08)'; ctx.beginPath(); ctx.roundRect ? ctx.roundRect(pad, top, w, h, 28) : ctx.rect(pad, top, w, h); ctx.fill();
          ctx.fillStyle = fg; ctx.beginPath(); ctx.arc(pad + 28, top + 28, 20, 0, 7); ctx.fill();
          ctx.fillStyle = v.base; ctx.beginPath(); ctx.moveTo(pad + 23, top + 20); ctx.lineTo(pad + 35, top + 28); ctx.lineTo(pad + 23, top + 36); ctx.fill();
          const peaks = b.peaks || [], left = pad + 62, right = pad + w - 64, step = (right - left) / Math.max(peaks.length, 1);
          ctx.fillStyle = fg; ctx.globalAlpha = 0.45;
          peaks.forEach((p, k) => { const ph = Math.max(3, p * 30); ctx.fillRect(left + k * step, top + 28 - ph / 2, Math.max(step * 0.55, 1.5), ph); });
          ctx.globalAlpha = 0.7; ctx.font = '500 13px -apple-system, system-ui'; ctx.textBaseline = 'middle';
          ctx.fillText(fmtTime(b.duration || 0), pad + w - 50, top + 28); ctx.globalAlpha = 1;
        });
      } else if (b.type === 'table') {
        const cols = Math.max(...b.cells.map(r => r.length), 1), cw = colW / cols, rh = 34;
        h = b.cells.length * rh;
        ops.push(ctx => {
          ctx.strokeStyle = 'rgba(255,255,255,.16)'; ctx.lineWidth = 1;
          ctx.fillStyle = 'rgba(255,255,255,.07)'; ctx.fillRect(pad, top, colW, rh);
          b.cells.forEach((r, ri) => r.forEach((c, ci) => {
            ctx.strokeRect(pad + ci * cw, top + ri * rh, cw, rh);
            ctx.fillStyle = fg; ctx.font = font(v.fontKey === 'hand' ? 19 : 14, ri ? 500 : 700); ctx.textBaseline = 'middle';
            ctx.fillText(wrap(c, ctx.font, cw - 16)[0] || '', pad + ci * cw + 8, top + ri * rh + rh / 2);
          }));
        });
      }
      y = top + h + 10;
    });
    const H = Math.ceil(y + 60);
    // Холст на iPhone - не больше ~16 млн точек: длинную страницу рисуем чуть мельче.
    const scale = Math.min(2, Math.sqrt(16e6 / (W * H)));
    const canvas = document.createElement('canvas');
    canvas.width = Math.floor(W * scale); canvas.height = Math.floor(H * scale);
    const ctx = canvas.getContext('2d');
    ctx.scale(scale, scale);
    if (v.bg.startsWith('linear')) { const g = ctx.createLinearGradient(0, 0, 0, H); g.addColorStop(0, v.base); g.addColorStop(1, v.bottom); ctx.fillStyle = g; } else ctx.fillStyle = v.base;
    ctx.fillRect(0, 0, W, H);
    if (bg) {
      const sc = Math.max(W / bg.width, Math.min(H, W * 0.75) / bg.height);
      ctx.save(); ctx.filter = 'blur(24px)'; ctx.drawImage(bg, (W - bg.width * sc) / 2, 0, bg.width * sc, bg.height * sc); ctx.restore();
      ctx.fillStyle = 'rgba(0,0,0,.4)'; ctx.fillRect(0, 0, W, H);
    }
    if (cover) {
      const sc = Math.max(W / cover.width, 190 / cover.height);
      ctx.save(); ctx.beginPath(); ctx.rect(0, 0, W, 190); ctx.clip();
      ctx.drawImage(cover, (W - cover.width * sc) / 2, (190 - cover.height * sc) / 2, cover.width * sc, cover.height * sc); ctx.restore();
      const g = ctx.createLinearGradient(0, 120, 0, 190); g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, v.base); ctx.fillStyle = g; ctx.fillRect(0, 120, W, 70);
    }
    for (const op of ops) op(ctx);
    return canvas;
  }
  const HL_COLORS = { k: '#ff7ab8', s: '#fac97a', n: '#bd9eff', c: 'rgba(255,255,255,.42)', t: '#73dbf5', g: '#ff8c8c' };
  /// HTML строки → куски текста со своим оформлением (для рисования на холсте).
  function segmentsOf(html) {
    const t = document.createElement('template');
    t.innerHTML = html || '';
    const out = [];
    const walk = (node, st) => {
      for (const el of node.childNodes) {
        if (el.nodeType === 3) { if (el.nodeValue) out.push({ text: el.nodeValue.replace(/\u00a0/g, ' '), st }); continue; }
        if (el.nodeType !== 1) continue;
        const tag = el.tagName, s2 = { ...st };
        if (tag === 'BR') { out.push({ text: '\n', st }); continue; }
        if (tag === 'B' || tag === 'STRONG') s2.bold = true;
        if (tag === 'I' || tag === 'EM') s2.italic = true;
        if (tag === 'S' || tag === 'STRIKE' || tag === 'DEL') s2.strike = true;
        if (tag === 'U') s2.underline = true;
        if (tag === 'MARK') { const m = /m-(\w+)/.exec(el.className); s2.mark = (MARKS.find(x => x[0] === (m ? m[1] : 'yellow')) || MARKS[0])[1]; }
        if (tag === 'SPAN') {
          if (el.style.color) s2.color = el.style.color;
          if (el.style.backgroundColor) s2.mark = el.style.backgroundColor;
          const hl = /hl-(\w)/.exec(el.className);
          if (hl) s2.color = HL_COLORS[hl[1]];
        }
        walk(el, s2);
      }
    };
    walk(t.content, {});
    return out.length ? out : [{ text: ' ', st: {} }];
  }
  /// Перенос по словам с учётом разных шрифтов кусков. Строки - списки слов с положением.
  function layoutRich(segs, fontFor, width) {
    const meter = layoutRich.meter || (layoutRich.meter = document.createElement('canvas').getContext('2d'));
    const lines = [[]];
    let x = 0;
    for (const seg of segs) {
      for (const piece of seg.text.split(/(\n|\s+)/)) {
        if (!piece) continue;
        if (piece === '\n') { lines.push([]); x = 0; continue; }
        meter.font = fontFor(seg.st);
        const w = meter.measureText(piece).width;
        const space = /^\s+$/.test(piece);
        if (space && x === 0) continue;
        if (!space && x > 0 && x + w > width) { lines.push([]); x = 0; }
        lines[lines.length - 1].push({ text: piece, x, w, st: seg.st });
        x += w;
      }
    }
    return lines;
  }
  const canvasBlob = (canvas, type, q) => new Promise(res => canvas.toBlob(res, type, q));

  /// PDF из одной картинки страницы: размер листа - размер страницы.
  async function makePDF(canvas) {
    const jpeg = new Uint8Array(await (await canvasBlob(canvas, 'image/jpeg', 0.92)).arrayBuffer());
    const W = 820, H = Math.round(canvas.height * 820 / canvas.width);
    const enc = new TextEncoder(), parts = [], offsets = [];
    let len = 0;
    const add = x => { const b = typeof x === 'string' ? enc.encode(x) : x; parts.push(b); len += b.length; };
    const obj = (n, body) => { offsets[n] = len; add(`${n} 0 obj\n`); body(); add('\nendobj\n'); };
    add('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    obj(1, () => add('<< /Type /Catalog /Pages 2 0 R >>'));
    obj(2, () => add('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'));
    obj(3, () => add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>`));
    obj(4, () => { add(`<< /Type /XObject /Subtype /Image /Width ${canvas.width} /Height ${canvas.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\nstream\n`); add(jpeg); add('\nendstream'); });
    const content = `q ${W} 0 0 ${H} 0 0 cm /Im0 Do Q`;
    obj(5, () => add(`<< /Length ${content.length} >>\nstream\n${content}\nendstream`));
    const xref = len;
    add(`xref\n0 6\n0000000000 65535 f \n${[1, 2, 3, 4, 5].map(i => String(offsets[i]).padStart(10, '0') + ' 00000 n \n').join('')}`);
    add(`trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`);
    return new Blob(parts, { type: 'application/pdf' });
  }

  async function exportPage(n, kind) {
    toast('Рисую страницу…');
    try {
      const canvas = await renderPage(n);
      const blob = kind === 'pdf' ? await makePDF(canvas) : await canvasBlob(canvas, 'image/png');
      shareFile(new File([blob], safeName(titleOf(n)) + (kind === 'pdf' ? '.pdf' : '.png'), { type: blob.type }));
    } catch (e) { toast('Не получилось: ' + e.message); }
  }
  function copyPageImage(n) {
    closeSheet();
    const png = renderPage(n).then(c => canvasBlob(c, 'image/png'));
    if (navigator.clipboard && window.ClipboardItem) {
      navigator.clipboard.write([new ClipboardItem({ 'image/png': png })])
        .then(() => toast('Картинка в буфере - вставляй куда угодно'), () => exportPage(n, 'png'));
    } else exportPage(n, 'png');
  }

  // ───────── счётчик слов и фокус ─────────
  const statsBtn = $('#stats');
  function updateStats() {
    const n = note(openId);
    if (!n || !local.get('stats', true)) { statsBtn.hidden = true; return; }
    const sel = getSelection();
    const picked = sel && !sel.isCollapsed && editor.contains(sel.anchorNode) ? (sel.toString().match(/\S+/g) || []).length : 0;
    const words = n.blocks.reduce((s, b) => s + (isObject(b) ? 0 : (plainOf(b.html).match(/\S+/g) || []).length), 0);
    statsBtn.hidden = !words && !picked;
    statsBtn.textContent = picked ? `выделено ${picked} ${plural(picked, 'слово', 'слова', 'слов')}`
      : `${words} ${plural(words, 'слово', 'слова', 'слов')} · ${Math.max(1, Math.ceil(words / 180))} мин чтения`;
    statsBtn.classList.toggle('focus', editor.classList.contains('focus-mode'));
  }
  statsBtn.addEventListener('click', () => {
    editor.classList.toggle('focus-mode');
    local.set('focus', editor.classList.contains('focus-mode'));
    toast(editor.classList.contains('focus-mode') ? 'Режим фокуса: видно только строку, которую пишешь' : 'Режим фокуса выключен');
    updateStats();
  });

  // ───────── звук печати ─────────
  let audioCtx = null;
  /// Safari даёт звуку заиграть только после касания - будим его на первом же тапе.
  function wakeAudio() {
    try {
      audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
      if (audioCtx.state === 'suspended') audioCtx.resume();
    } catch {}
  }
  document.addEventListener('pointerdown', wakeAudio, { passive: true });
  document.addEventListener('touchend', wakeAudio, { passive: true });
  function click(kind) {
    if (!local.get('sound', true)) return;
    try {
      wakeAudio();
      const len = Math.floor(audioCtx.sampleRate * (kind === 'enter' ? 0.05 : 0.025));
      const buf = audioCtx.createBuffer(1, len, audioCtx.sampleRate), data = buf.getChannelData(0);
      for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 4);
      const src = audioCtx.createBufferSource(), f = audioCtx.createBiquadFilter(), g = audioCtx.createGain();
      f.type = 'bandpass'; f.frequency.value = kind === 'space' ? 900 : kind === 'enter' ? 600 : 1800 + Math.random() * 500; f.Q.value = 1.2;
      g.gain.value = kind === 'enter' ? 0.5 : 0.3;
      src.buffer = buf; src.connect(f).connect(g).connect(audioCtx.destination); src.start();
    } catch {}
  }

  // ───────── плашка внизу ─────────
  let toastTimer = null;
  function toast(text, action, fn) {
    const t = $('#toast');
    t.innerHTML = `<span>${esc(text)}</span>${action ? `<button>${esc(action)}</button>` : ''}`;
    t.hidden = false;
    if (action) t.querySelector('button').onclick = () => { t.hidden = true; fn(); };
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, action ? 6000 : 2600);
  }

  /// Строка с курсором не прячется под клавиатурой и панелью.
  let caretFrame = 0;
  function keepCaretVisible() {
    cancelAnimationFrame(caretFrame);
    caretFrame = requestAnimationFrame(() => {
      const sel = getSelection();
      if (!sel.rangeCount || !editor.contains(sel.anchorNode)) return;
      let rect = sel.getRangeAt(0).getBoundingClientRect();
      if (!rect.height) { const el = sel.anchorNode.nodeType === 1 ? sel.anchorNode : sel.anchorNode.parentElement; rect = el.getBoundingClientRect(); }
      const box = scroller.getBoundingClientRect();
      const bottom = box.bottom - (kbar.hidden ? 0 : kbar.offsetHeight) - 24;
      if (rect.bottom > bottom) scroller.scrollTop += rect.bottom - bottom;
      else if (rect.top < box.top + 8) scroller.scrollTop -= box.top + 8 - rect.top;
    });
  }

  // ───────── клавиатура iPhone ─────────
  // Приложение подстраивается под видимую часть экрана: панель встаёт прямо над клавиатурой, шапка не уезжает.
  const app = $('#app');
  function fitViewport() {
    const vv = window.visualViewport;
    if (!vv) return;
    // Без клавиатуры приложение просто на весь экран; с ней - ровно по видимой части над клавиатурой.
    const open = innerHeight - vv.height > 120;
    document.body.classList.toggle('kb-open', open);
    document.body.classList.toggle('kb-rest', !open);
    if (open) {
      app.style.setProperty('--vvh', vv.height + 'px');
      app.style.setProperty('--vvt', vv.offsetTop + 'px');
    }
    keepCaretVisible();
  }
  if (window.visualViewport) {
    visualViewport.addEventListener('resize', fitViewport);
    visualViewport.addEventListener('scroll', fitViewport);
  }
  addEventListener('resize', fitViewport);
  addEventListener('orientationchange', () => setTimeout(fitViewport, 400));
  fitViewport();
  document.body.classList.add('kb-rest');

  // ───────── первый запуск ─────────
  function welcome() {
    const md = `# Заметочки
Пишешь от руки - а получается аккуратно. Всё хранится только на этом телефоне.
## Попробуй
[ ] Нажать на квадратик слева
[ ] Позвонить маме @завтра 10:00
[x] Поставить Заметочки на экран «Домой»
- Напиши **#** и пробел - будет заголовок
- **-** и пробел - список, **[]** - задача, **>** - цитата
- **/** в пустой строке - меню: доска, голос, картинка, шаблоны
> Лучшие заметки - те, которые хочется перечитывать.
## Доска`;
    const blocks = parseMarkdown(md);
    const board = { id: uid(), type: 'board', columns: emptyBoard() };
    board.columns[0].cards = [{ id: uid(), text: 'Нажми на карточку' }, { id: uid(), text: 'Перенеси в «Готово»' }];
    board.columns[1].cards = [{ id: uid(), text: 'Разобраться в Заметочках' }];
    blocks.push(board, { id: uid(), type: 'text', html: '' });
    return newNote({ blocks, open: false });
  }

  // ───────── запуск ─────────
  async function start() {
    try { await DB.open(); }
    catch { listEl.innerHTML = '<div class="empty"><b>Не открылось хранилище</b>Похоже, приватный режим Safari. Открой страницу в обычной вкладке.</div>'; return; }
    for (const n of await DB.all('notes')) { notes.set(n.id, n); written.set(n.id, JSON.stringify(n)); }
    // Пустые «Без названия», оставшиеся с прошлых раз, - убираем.
    for (const n of [...notes.values()]) dropIfEmpty(n.id);
    if (!notes.size && !local.get('welcomed', false)) { welcome(); local.set('welcomed', true); }
    if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
    if (local.get('focus', false)) editor.classList.add('focus-mode');
    renderList();
    const fromHash = location.hash.startsWith('#n-') && location.hash.slice(3);
    // На iPad и большом экране заметка открыта сразу: последняя или верхняя в списке.
    const top = children(null)[0];
    const last = fromHash || (wide() ? (note(local.get('lastOpen', null)) ? local.get('lastOpen', null) : top && top.id) : null);
    if (last && note(last)) openNote(last); else showList();
    if (fromHash) history.replaceState(null, '', location.pathname);
    if (/[?&]quick=1/.test(location.search)) { history.replaceState(null, '', location.pathname); quickNote(); }
    if (isIOS && !standalone && !local.get('installSeen', false)) $('#install').hidden = false;
    checkReminders();
    if ('serviceWorker' in navigator) {
      const hadWorker = !!navigator.serviceWorker.controller;
      navigator.serviceWorker.register('sw.js').then(reg => {
        // Вернулся в приложение - проверяем, не вышла ли новая версия.
        document.addEventListener('visibilitychange', () => { if (!document.hidden) reg.update().catch(() => {}); });
      }).catch(() => {});
      navigator.serviceWorker.addEventListener('message', e => { if (e.data && e.data.open) openNote(e.data.open, true); });
      // Новая версия встала - перезагружаемся на неё сами (если человек как раз печатает - после).
      navigator.serviceWorker.addEventListener('controllerchange', () => {
        if (!hadWorker) return;
        const reload = () => { flushSaves(); location.reload(); };
        if (editor.contains(document.activeElement)) { toast('Вышло обновление', 'Обновить', reload); document.addEventListener('visibilitychange', reload, { once: true }); }
        else reload();
      });
    }
  }
  $('#install-close').addEventListener('click', () => { $('#install').hidden = true; local.set('installSeen', true); });

  // Для проверок в браузере: заглянуть в заметки и разбор дат.
  window.zametochki = { notes, Reminders, parseMarkdown, toMarkdown, fromMacDoc, openNote, renderPage, makePDF, Code, moveNote };
  start();
})();
