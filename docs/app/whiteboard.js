'use strict';
// Белая доска для iPhone - тот же формат, что у доски на Mac (Whiteboard.swift): предметы с мировыми
// координатами, точки - [x, y], рамки - [[x, y], [ширина, высота]]. Доска с Mac открывается здесь как есть,
// незнакомые поля предметов не теряются. Здесь: превью в заметке и окно доски во весь экран.
window.ZWhiteboard = (() => {
  const uid = () => Math.random().toString(36).slice(2, 10);
  const ASPECT = 16 / 9;
  const STICKY = [240, 180];

  // ───────── геометрия (как в Whiteboard.swift) ─────────
  const hyp = (x, y) => Math.hypot(x, y);
  const dist = (a, b) => hyp(b[0] - a[0], b[1] - a[1]);
  const isStroke = it => it.kind === 'pen' || it.kind === 'marker';
  const isConnector = it => it.kind === 'line' || it.kind === 'arrow';
  const isShape = it => ['rect', 'ellipse', 'diamond'].includes(it.kind);
  const isBox = it => !isStroke(it) && !isConnector(it);
  const holdsText = it => isShape(it) || it.kind === 'sticky' || it.kind === 'text';
  const heads = it => it.heads || (it.kind === 'arrow' ? 'end' : 'none');
  const fontSize = it => it.fontSize || (it.kind === 'text' ? 32 : 22);
  const width = it => it.width == null ? 4 : it.width;
  const itemById = (board, id) => id ? board.items.find(x => x.id === id) : null;

  function R(it) {
    const r = it.rect || [[0, 0], [0, 0]];
    let [[x, y], [w, h]] = r;
    if (w < 0) { x += w; w = -w; }
    if (h < 0) { y += h; h = -h; }
    return { x, y, w, h, X: x + w, Y: y + h, mx: x + w / 2, my: y + h / 2 };
  }
  const setRect = (it, x, y, w, h) => { it.rect = [[x, y], [w, h]]; };
  const center = it => { const r = R(it); return [r.mx, r.my]; };

  function anchoredPoint(item, anchor, gap = 7) {
    const r = R(item);
    const p = [r.x + anchor[0] * r.w, r.y + anchor[1] * r.h];
    let n;
    if (item.kind === 'ellipse' || item.kind === 'diamond') n = [p[0] - r.mx, p[1] - r.my];
    else n = sideNormal(anchor);
    const l = Math.max(hyp(n[0], n[1]), 0.001);
    return [p[0] + n[0] / l * gap, p[1] + n[1] / l * gap];
  }
  function sideNormal(a) {
    const dl = Math.abs(a[0]), dr = Math.abs(1 - a[0]), dt = Math.abs(a[1]), db = Math.abs(1 - a[1]);
    const m = Math.min(dl, dr, dt, db);
    return m === dl ? [-1, 0] : m === dr ? [1, 0] : m === dt ? [0, -1] : [0, 1];
  }
  function edgePoint(item, target, gap = 7) {
    const r0 = R(item);
    const r = { w: r0.w + gap * 2, h: r0.h + gap * 2, mx: r0.mx, my: r0.my };
    const dx = target[0] - r.mx, dy = target[1] - r.my;
    if ((Math.abs(dx) <= 0.01 && Math.abs(dy) <= 0.01) || r.w <= 0 || r.h <= 0) return [r.mx, r.my];
    const a = r.w / 2, b = r.h / 2;
    let t;
    if (item.kind === 'ellipse') t = 1 / Math.sqrt(dx * dx / (a * a) + dy * dy / (b * b));
    else if (item.kind === 'diamond') t = 1 / (Math.abs(dx) / a + Math.abs(dy) / b);
    else t = Math.min(Math.abs(dx) > 0.01 ? a / Math.abs(dx) : Infinity, Math.abs(dy) > 0.01 ? b / Math.abs(dy) : Infinity);
    return [r.mx + dx * t, r.my + dy * t];
  }
  function outward(item, p) {
    const r = R(item);
    if (r.w <= 0 || r.h <= 0) return [0, 0];
    if (item.kind === 'ellipse' || item.kind === 'diamond') {
      const d = [p[0] - r.mx, p[1] - r.my], l = Math.max(hyp(d[0], d[1]), 0.001);
      return [d[0] / l, d[1] / l];
    }
    return sideNormal([(p[0] - r.x) / r.w, (p[1] - r.y) / r.h]);
  }
  function autoSide(item, target) {
    const r = R(item);
    const dx = (target[0] - r.mx) / Math.max(r.w, 1), dy = (target[1] - r.my) / Math.max(r.h, 1);
    if (Math.abs(dx) >= Math.abs(dy)) return dx >= 0 ? [1, 0.5] : [0, 0.5];
    return dy >= 0 ? [0.5, 1] : [0.5, 0];
  }
  /// Где на краю предмета сесть концу стрелки (доля рамки); у серединок сторон - прилипает.
  function anchorNear(item, p, snap) {
    const r = R(item);
    if (r.w <= 0 || r.h <= 0) return [0.5, 0.5];
    let q;
    if (item.kind === 'ellipse' || item.kind === 'diamond') q = edgePoint(item, p, 0);
    else {
      const cx = Math.min(Math.max(p[0], r.x), r.X), cy = Math.min(Math.max(p[1], r.y), r.Y);
      const dl = cx - r.x, dr = r.X - cx, dt = cy - r.y, db = r.Y - cy, m = Math.min(dl, dr, dt, db);
      q = m === dl ? [r.x, cy] : m === dr ? [r.X, cy] : m === dt ? [cx, r.y] : [cx, r.Y];
    }
    const mids = [[r.mx, r.y], [r.X, r.my], [r.mx, r.Y], [r.x, r.my]];
    const mid = mids.reduce((best, m) => dist(m, q) < dist(best, q) ? m : best);
    if (dist(mid, q) < snap) q = mid;
    return [(q[0] - r.x) / r.w, (q[1] - r.y) / r.h];
  }
  /// Куда прицепить конец стрелки к предмету: палец у края - туда, где палец; палец в глубине предмета -
  /// на ту сторону, что смотрит на другой конец стрелки (иначе стрелка шла бы сквозь предмет).
  function attachAnchor(item, p, other, snap) {
    const r = R(item);
    const deep = p[0] > r.x + r.w * 0.22 && p[0] < r.X - r.w * 0.22 && p[1] > r.y + r.h * 0.22 && p[1] < r.Y - r.h * 0.22;
    return anchorNear(item, deep ? edgePoint(item, other, 0) : p, snap);
  }
  function refs(it, board) {
    const pts = it.points || [];
    const a0 = pts[0] || [0, 0], b0 = pts[1] || a0;
    const from = itemById(board, it.start), to = itemById(board, it.end);
    const a = from ? (it.startAnchor ? anchoredPoint(from, it.startAnchor) : center(from)) : a0;
    const b = to ? (it.endAnchor ? anchoredPoint(to, it.endAnchor) : center(to)) : b0;
    return [a, b];
  }
  function world(r, a, b) {
    const d = [b[0] - a[0], b[1] - a[1]], l = Math.max(hyp(d[0], d[1]), 1), n = [-d[1] / l, d[0] / l];
    return [a[0] + d[0] * r[0] + n[0] * r[1] * l, a[1] + d[1] * r[0] + n[1] * r[1] * l];
  }
  function waypointPositions(it, a, b) {
    const l = Math.max(dist(a, b), 1);
    let rel = it.waypoints || [];
    if (!it.waypoints && it.route === 'curved') {
      if (it.curve) rel = [[0.5 + it.curve[0], it.curve[1]]];
      else if (it.bend != null) rel = [[0.5, it.bend / l]];
    }
    return rel.map(r => world(r, a, b));
  }
  function simplify(points) {
    const out = [];
    for (const p of points) {
      const last = out[out.length - 1];
      if (last && Math.abs(last[0] - p[0]) < 0.5 && Math.abs(last[1] - p[1]) < 0.5) continue;
      if (out.length >= 2) {
        const a = out[out.length - 2], b = out[out.length - 1];
        const cross = (b[0] - a[0]) * (p[1] - b[1]) - (b[1] - a[1]) * (p[0] - b[0]);
        const dot = (b[0] - a[0]) * (p[0] - b[0]) + (b[1] - a[1]) * (p[1] - b[1]);
        if (Math.abs(cross) < 0.5 && dot >= 0) out.pop();
      }
      out.push(p);
    }
    return out;
  }
  const intersects = (s, b) => s.x < b.X && s.X > b.x && s.y < b.Y && s.Y > b.y;
  function orthogonalRoute(a, dirA, rectA, b, dirB, rectB) {
    const margin = 26;
    const pA = dirA ? [a[0] + dirA[0] * margin, a[1] + dirA[1] * margin] : a;
    const pB = dirB ? [b[0] + dirB[0] * margin, b[1] + dirB[1] * margin] : b;
    const midX = (pA[0] + pB[0]) / 2, midY = (pA[1] + pB[1]) / 2;
    const cands = [
      [pA, [pB[0], pA[1]], pB], [pA, [pA[0], pB[1]], pB],
      [pA, [midX, pA[1]], [midX, pB[1]], pB], [pA, [pA[0], midY], [pB[0], midY], pB],
    ];
    const boxes = [rectA, rectB].filter(Boolean);
    if (boxes.length) {
      const all = boxes.reduce((u, r) => ({ x: Math.min(u.x, r.x), y: Math.min(u.y, r.y), X: Math.max(u.X, r.X), Y: Math.max(u.Y, r.Y) }));
      for (const y of [all.y - margin, all.Y + margin]) cands.push([pA, [pA[0], y], [pB[0], y], pB]);
      for (const x of [all.x - margin, all.X + margin]) cands.push([pA, [x, pA[1]], [x, pB[1]], pB]);
    }
    let best = null;
    for (const c of cands) {
      const full = simplify([a, ...c, b]);
      let score = 0;
      for (let i = 1; i < full.length; i++) {
        const p = full[i - 1], q = full[i];
        score += Math.abs(q[0] - p[0]) + Math.abs(q[1] - p[1]);
        const seg = { x: Math.min(p[0], q[0]) - 0.5, y: Math.min(p[1], q[1]) - 0.5, X: Math.max(p[0], q[0]) + 0.5, Y: Math.max(p[1], q[1]) + 0.5 };
        for (const box of boxes) if (intersects(seg, { x: box.x + 3, y: box.y + 3, X: box.X - 3, Y: box.Y - 3 })) score += 100000;
      }
      score += Math.max(full.length - 2, 0) * 40;
      if (dirA && full.length > 1) { const d = [full[1][0] - full[0][0], full[1][1] - full[0][1]]; if (d[0] * dirA[0] + d[1] * dirA[1] < -0.5) score += 50000; }
      if (dirB && full.length > 1) { const n = full.length, d = [full[n - 2][0] - full[n - 1][0], full[n - 2][1] - full[n - 1][1]]; if (d[0] * dirB[0] + d[1] * dirB[1] < -0.5) score += 50000; }
      if (!best || score < best.score) best = { score, full };
    }
    return best && best.full.length > 2 ? best.full.slice(1, -1) : [];
  }

  /// Форма стрелки: концы и изломы или кривые.
  function connectorPath(it, board) {
    const pts = it.points || [];
    const a0 = pts[0] || [0, 0], b0 = pts[1] || a0;
    const from = itemById(board, it.start), to = itemById(board, it.end);
    const [aRef, bRef] = refs(it, board);
    const via = waypointPositions(it, aRef, bRef);
    const fixedA = from && it.startAnchor ? anchoredPoint(from, it.startAnchor) : null;
    const fixedB = to && it.endAnchor ? anchoredPoint(to, it.endAnchor) : null;
    const route = it.route || 'straight';
    if (route === 'elbow') {
      const otherA = via[0] || (to ? (it.endAnchor ? anchoredPoint(to, it.endAnchor, 0) : center(to)) : b0);
      const otherB = via[via.length - 1] || (from ? (it.startAnchor ? anchoredPoint(from, it.startAnchor, 0) : center(from)) : a0);
      const anA = from ? (it.startAnchor || autoSide(from, otherA)) : null;
      const anB = to ? (it.endAnchor || autoSide(to, otherB)) : null;
      const a = from ? anchoredPoint(from, anA, 2) : a0, b = to ? anchoredPoint(to, anB, 7) : b0;
      const dA = anA && sideNormal(anA), dB = anB && sideNormal(anB);
      const rA = from && R(from), rB = to && R(to);
      if (!via.length) return { a, b, bends: orthogonalRoute(a, dA, rA, b, dB, rB), curves: [] };
      let all = [a, ...orthogonalRoute(a, dA, rA, via[0], null, null), via[0]];
      for (let k = 1; k < via.length; k++) {
        const p = via[k - 1], q = via[k], prev = all.length > 1 ? all[all.length - 2] : p;
        const horizontal = Math.abs(p[1] - prev[1]) < 0.5 ? true : Math.abs(p[0] - prev[0]) < 0.5 ? false : Math.abs(q[0] - p[0]) >= Math.abs(q[1] - p[1]);
        all.push(horizontal ? [q[0], p[1]] : [p[0], q[1]], q);
      }
      all = all.concat(orthogonalRoute(via[via.length - 1], null, null, b, dB, rB), [b]);
      const clean = simplify(all);
      return { a, b, bends: clean.slice(1, -1), curves: [] };
    }
    if (route === 'curved' && via.length) {
      const a = fixedA || (from ? edgePoint(from, via[0]) : a0);
      const b = fixedB || (to ? edgePoint(to, via[via.length - 1]) : b0);
      const nA = from ? outward(from, a) : [0, 0], nB = to ? outward(to, b) : [0, 0];
      const all = [a, ...via, b], tan = [];
      for (let k = 0; k < all.length; k++) {
        if (k === 0) { const d = dist(all[0], all[1]); tan.push(nA[0] || nA[1] ? [nA[0] * d, nA[1] * d] : [all[1][0] - all[0][0], all[1][1] - all[0][1]]); }
        else if (k === all.length - 1) { const d = dist(all[k - 1], all[k]); tan.push(nB[0] || nB[1] ? [-nB[0] * d, -nB[1] * d] : [all[k][0] - all[k - 1][0], all[k][1] - all[k - 1][1]]); }
        else tan.push([(all[k + 1][0] - all[k - 1][0]) / 2, (all[k + 1][1] - all[k - 1][1]) / 2]);
      }
      const curves = [];
      for (let k = 0; k < all.length - 1; k++) {
        curves.push([all[k], [all[k][0] + tan[k][0] / 3, all[k][1] + tan[k][1] / 3], [all[k + 1][0] - tan[k + 1][0] / 3, all[k + 1][1] - tan[k + 1][1] / 3], all[k + 1]]);
      }
      return { a, b, bends: [], curves };
    }
    if (!via.length) {
      const a = fixedA || (from ? edgePoint(from, bRef) : a0);
      const b = fixedB || (to ? edgePoint(to, aRef) : b0);
      return { a, b, bends: [], curves: [] };
    }
    const a = fixedA || (from ? edgePoint(from, via[0]) : a0);
    const b = fixedB || (to ? edgePoint(to, via[via.length - 1]) : b0);
    return { a, b, bends: via, curves: [] };
  }
  const bez = (s, t) => { const u = 1 - t, w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t;
    return [w0 * s[0][0] + w1 * s[1][0] + w2 * s[2][0] + w3 * s[3][0], w0 * s[0][1] + w1 * s[1][1] + w2 * s[2][1] + w3 * s[3][1]]; };
  function samples(path) {
    if (path.curves.length) { const out = [path.a]; for (const s of path.curves) for (let i = 1; i <= 16; i++) out.push(bez(s, i / 16)); return out; }
    return [path.a, ...path.bends, path.b];
  }
  function segDist(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1], len = dx * dx + dy * dy;
    if (!len) return dist(p, a);
    const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len));
    return hyp(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
  }
  function bounds(it, board) {
    if (isConnector(it)) {
      const s = samples(connectorPath(it, board)), pad = width(it) + 8;
      return box(s, pad);
    }
    if (isStroke(it)) return box(it.points || [], it.kind === 'marker' ? width(it) * 2 : width(it));
    const r = R(it);
    return { x: r.x, y: r.y, X: r.X, Y: r.Y };
  }
  function box(pts, pad = 0) {
    if (!pts.length) return { x: 0, y: 0, X: 0, Y: 0 };
    let x = Infinity, y = Infinity, X = -Infinity, Y = -Infinity;
    for (const p of pts) { x = Math.min(x, p[0]); y = Math.min(y, p[1]); X = Math.max(X, p[0]); Y = Math.max(Y, p[1]); }
    return { x: x - pad, y: y - pad, X: X + pad, Y: Y + pad };
  }
  function hit(it, p, tol, board) {
    if (isStroke(it)) {
      const reach = tol + (it.kind === 'marker' ? width(it) * 2 : width(it) / 2), pts = it.points || [];
      if (pts.length < 2) return pts[0] ? dist(pts[0], p) < reach : false;
      for (let i = 1; i < pts.length; i++) if (segDist(p, pts[i - 1], pts[i]) < reach) return true;
      return false;
    }
    if (isConnector(it)) {
      const s = samples(connectorPath(it, board));
      for (let i = 1; i < s.length; i++) if (segDist(p, s[i - 1], s[i]) < tol + width(it) / 2) return true;
      return false;
    }
    const r = R(it);
    const inR = (q, d) => q[0] >= r.x - d && q[0] <= r.X + d && q[1] >= r.y - d && q[1] <= r.Y + d;
    if (isShape(it)) {
      if (it.fill || it.text) return inR(p, tol);
      return inR(p, tol) && !(r.w > tol * 2 && r.h > tol * 2 && p[0] > r.x + tol && p[0] < r.X - tol && p[1] > r.y + tol && p[1] < r.Y - tol);
    }
    return inR(p, tol / 2);
  }
  function contentBounds(board) {
    if (!board.items.length) return null;
    return board.items.map(it => bounds(it, board)).reduce((u, b) => ({ x: Math.min(u.x, b.x), y: Math.min(u.y, b.y), X: Math.max(u.X, b.X), Y: Math.max(u.Y, b.Y) }));
  }
  /// Что показать в превью: всё нарисованное с полями, в пропорциях превью (как на Mac).
  function previewViewport(board, aspect = ASPECT) {
    const b = contentBounds(board);
    if (!b) return { x: 0, y: 0, w: 1600, h: 900 };
    const bx = { x: b.x - 60, y: b.y - 60, w: b.X - b.x + 120, h: b.Y - b.y + 120 };
    const w = Math.max(bx.w, bx.h * aspect, 900), h = w / aspect;
    return { x: bx.x + bx.w / 2 - w / 2, y: bx.y + bx.h / 2 - h / 2, w, h };
  }

  // ───────── цвета и текст ─────────
  let env = {};
  const ink = id => (env.colors && env.colors[id]) || env.colors && env.colors.white || '#fff';
  function pastel(id) {
    if (['pink', 'coral', 'peach'].includes(id)) return '#ffc2db';
    if (['green', 'mint'].includes(id)) return '#bdf0c7';
    if (['sky', 'blue'].includes(id)) return '#b8dbff';
    if (id === 'lavender') return '#dbccff';
    if (id === 'orange') return '#ffd4a3';
    if (id === 'white' || id === 'gray') return '#f2f2f2';
    return '#ffeb8c';
  }
  function fillColor(it) {
    if (it.kind === 'sticky') return pastel(it.fill || it.color);
    if (!it.fill || !env.colors || !env.colors[it.fill]) return null;
    return hexA(env.colors[it.fill], 0.32);
  }
  function hexA(hex, a) {
    const n = parseInt(hex.slice(1), 16);
    return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`;
  }
  const textColor = it => it.kind === 'sticky' ? '#1f1f1f' : ink(it.color);
  const fontOf = (it, scale = 1) => `600 ${fontSize(it) * (env.hand ? 1.3 : 1) * scale}px ${env.family || 'system-ui'}`;
  const lineHeight = it => fontSize(it) * (env.hand ? 1.3 : 1) * 1.2;
  const meter = document.createElement('canvas').getContext('2d');
  function wrapLines(text, font, maxW) {
    meter.font = font;
    const out = [];
    for (const para of text.split('\n')) {
      let line = '';
      for (const word of para.split(/(\s+)/)) {
        const next = line + word;
        if (meter.measureText(next).width > maxW && line.trim()) { out.push(line.trimEnd()); line = word.trimStart(); }
        else line = next;
      }
      out.push(line);
    }
    return out;
  }
  function textSize(it, maxW) {
    const lines = wrapLines(it.text || 'Текст', fontOf(it), maxW);
    meter.font = fontOf(it);
    return [Math.ceil(Math.max(...lines.map(l => meter.measureText(l).width))), Math.ceil(lines.length * lineHeight(it))];
  }
  function textBox(it) {
    const r = R(it);
    const inset = (dx, dy) => ({ x: r.x + dx, y: r.y + dy, w: r.w - dx * 2, h: r.h - dy * 2 });
    switch (it.kind) {
      case 'sticky': return inset(16, 14);
      case 'text': return inset(4, 2);
      case 'diamond': return inset(r.w * 0.2, r.h * 0.2);
      case 'ellipse': return inset(r.w * 0.12, r.h * 0.12);
      default: return inset(12, 10);
    }
  }
  /// Надпись подстраивается под текст; стикер растёт вниз, если текст не влезает.
  function fitText(it) {
    const r = R(it);
    if (it.kind === 'text') {
      if (it.fixedWidth) setRect(it, r.x, r.y, r.w, textSize(it, Math.max(r.w - 8, 20))[1] + 6);
      else { const [w, h] = textSize(it, 700); setRect(it, r.x, r.y, Math.max(w + 10, 40), h + 6); }
    } else if (it.kind === 'sticky') {
      const need = textSize(it, Math.max(r.w - 32, 20))[1] + 30;
      if (need > r.h) setRect(it, r.x, r.y, r.w, need);
    }
  }

  // ───────── рисование ─────────
  const images = new Map(); // имя картинки → HTMLImageElement (или null, пока грузится/нет)
  let onImageReady = null;
  function imageFor(name) {
    if (images.has(name)) return images.get(name);
    images.set(name, null);
    if (env.imageURL) Promise.resolve(env.imageURL(name)).then(url => {
      if (!url) return;
      const img = new Image();
      img.onload = () => { images.set(name, img); if (onImageReady) onImageReady(); };
      img.src = url;
    });
    return null;
  }
  function smooth(ctx, pts) {
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    if (pts.length < 3) { for (const p of pts.slice(1)) ctx.lineTo(p[0], p[1]); return; }
    for (let i = 1; i < pts.length - 1; i++) {
      const mid = [(pts[i][0] + pts[i + 1][0]) / 2, (pts[i][1] + pts[i + 1][1]) / 2];
      ctx.quadraticCurveTo(pts[i][0], pts[i][1], mid[0], mid[1]);
    }
    const last = pts[pts.length - 1];
    ctx.lineTo(last[0], last[1]);
  }
  function strokeStyle(ctx, it) {
    const w = width(it);
    ctx.lineWidth = w; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.setLineDash(it.dash === 'dashed' ? [w * 3, w * 2.2] : it.dash === 'dotted' ? [0.01, w * 2.2] : []);
    ctx.strokeStyle = ink(it.color);
  }
  function shapePath(ctx, it) {
    const r = R(it);
    ctx.beginPath();
    if (it.kind === 'ellipse') ctx.ellipse(r.mx, r.my, r.w / 2, r.h / 2, 0, 0, Math.PI * 2);
    else if (it.kind === 'diamond') { ctx.moveTo(r.mx, r.y); ctx.lineTo(r.X, r.my); ctx.lineTo(r.mx, r.Y); ctx.lineTo(r.x, r.my); ctx.closePath(); }
    else roundRect(ctx, r.x, r.y, r.w, r.h, Math.min(14, Math.min(r.w, r.h) / 4));
  }
  function roundRect(ctx, x, y, w, h, rad) {
    rad = Math.max(0, Math.min(rad, w / 2, h / 2));
    ctx.moveTo(x + rad, y); ctx.arcTo(x + w, y, x + w, y + h, rad); ctx.arcTo(x + w, y + h, x, y + h, rad);
    ctx.arcTo(x, y + h, x, y, rad); ctx.arcTo(x, y, x + w, y, rad); ctx.closePath();
  }
  function drawHead(ctx, it, tip, tail) {
    if (dist(tip, tail) <= 2) return;
    const ang = Math.atan2(tip[1] - tail[1], tip[0] - tail[0]), len = Math.max(14, width(it) * 3.6), sp = Math.PI / 7.5;
    ctx.setLineDash([]);
    ctx.beginPath();
    ctx.moveTo(tip[0] - len * Math.cos(ang - sp), tip[1] - len * Math.sin(ang - sp));
    ctx.lineTo(tip[0], tip[1]);
    ctx.lineTo(tip[0] - len * Math.cos(ang + sp), tip[1] - len * Math.sin(ang + sp));
    ctx.stroke();
  }
  function drawText(ctx, it) {
    if (!it.text) return;
    const tb = textBox(it), font = fontOf(it), lh = lineHeight(it);
    // Надпись без заданной ширины - по строкам как есть: шрифт на телефоне чуть шире, чем на Mac,
    // и перенос по ширине с Mac резал бы слова.
    const free = it.kind === 'text' && !it.fixedWidth;
    const lines = free ? it.text.split('\n') : wrapLines(it.text, font, Math.max(tb.w + (it.kind === 'text' ? 6 : 0), 10));
    let y = tb.y;
    if (isShape(it)) y = tb.y + tb.h / 2 - Math.min(lines.length * lh, tb.h) / 2;
    ctx.save();
    const r = R(it);
    ctx.beginPath();
    if (isShape(it)) ctx.rect(r.x - 4, r.y - 4, r.w + 8, r.h + 8); else ctx.rect(tb.x - 4, tb.y - 4, tb.w + 14, tb.h + 8);
    if (!free) ctx.clip();
    ctx.font = font; ctx.fillStyle = textColor(it); ctx.textBaseline = 'middle';
    ctx.textAlign = isShape(it) ? 'center' : 'left';
    const x = isShape(it) ? tb.x + tb.w / 2 : tb.x;
    for (const line of lines) { ctx.fillText(line, x, y + lh / 2); y += lh; }
    ctx.restore();
  }
  function drawItem(ctx, it, board, scale, hidingText) {
    ctx.save();
    switch (it.kind) {
      case 'pen': case 'marker': {
        const pts = it.points || [];
        if (!pts.length) break;
        if (pts.length === 1) {
          const d = it.kind === 'marker' ? width(it) * 4 : width(it);
          ctx.fillStyle = it.kind === 'marker' ? hexA(ink(it.color), 0.5) : ink(it.color);
          ctx.beginPath(); ctx.arc(pts[0][0], pts[0][1], d / 2, 0, Math.PI * 2); ctx.fill();
          break;
        }
        smooth(ctx, pts);
        if (it.kind === 'marker') {
          ctx.lineWidth = width(it) * 4; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
          ctx.strokeStyle = hexA(ink(it.color), 0.5);
        } else strokeStyle(ctx, it);
        ctx.stroke();
        break;
      }
      case 'line': case 'arrow': {
        const path = connectorPath(it, board);
        strokeStyle(ctx, it);
        ctx.beginPath();
        ctx.moveTo(path.a[0], path.a[1]);
        if (path.curves.length) for (const s of path.curves) ctx.bezierCurveTo(s[1][0], s[1][1], s[2][0], s[2][1], s[3][0], s[3][1]);
        else if (path.bends.length) {
          const all = [path.a, ...path.bends, path.b];
          for (let i = 1; i < all.length - 1; i++) {
            const rad = Math.min(14, dist(all[i - 1], all[i]) / 2, dist(all[i], all[i + 1]) / 2);
            if (rad > 1) ctx.arcTo(all[i][0], all[i][1], all[i + 1][0], all[i + 1][1], rad); else ctx.lineTo(all[i][0], all[i][1]);
          }
          ctx.lineTo(path.b[0], path.b[1]);
        } else ctx.lineTo(path.b[0], path.b[1]);
        ctx.stroke();
        const h = heads(it);
        const lastC = path.curves.length ? path.curves[path.curves.length - 1][2] : null, firstC = path.curves.length ? path.curves[0][1] : null;
        if (h !== 'none') drawHead(ctx, it, path.b, lastC || path.bends[path.bends.length - 1] || path.a);
        if (h === 'both') drawHead(ctx, it, path.a, firstC || path.bends[0] || path.b);
        break;
      }
      case 'rect': case 'ellipse': case 'diamond': {
        shapePath(ctx, it);
        const f = fillColor(it);
        if (f) { ctx.fillStyle = f; ctx.fill(); }
        strokeStyle(ctx, it);
        ctx.stroke();
        if (!hidingText) drawText(ctx, it);
        break;
      }
      case 'sticky': {
        const r = R(it);
        ctx.shadowColor = 'rgba(0,0,0,.28)'; ctx.shadowBlur = 12 * scale; ctx.shadowOffsetY = 5 * scale;
        ctx.fillStyle = fillColor(it);
        ctx.beginPath(); roundRect(ctx, r.x, r.y, r.w, r.h, 6); ctx.fill();
        ctx.shadowColor = 'transparent';
        if (!hidingText) drawText(ctx, it);
        break;
      }
      case 'text': if (!hidingText) drawText(ctx, it); break;
      case 'image': {
        const r = R(it), img = it.image ? imageFor(it.image) : null;
        ctx.beginPath(); roundRect(ctx, r.x, r.y, r.w, r.h, 8);
        if (img) { ctx.clip(); ctx.drawImage(img, r.x, r.y, r.w, r.h); }
        else { ctx.fillStyle = 'rgba(255,255,255,.08)'; ctx.fill(); }
        break;
      }
    }
    ctx.restore();
  }
  function drawGrid(ctx, w, h, origin, zoom) {
    let step = 40;
    while (step * zoom < 16) step *= 2;
    ctx.fillStyle = 'rgba(255,255,255,.1)';
    const dot = 2;
    for (let x = Math.floor(origin[0] / step) * step; x <= origin[0] + w / zoom; x += step) {
      for (let y = Math.floor(origin[1] / step) * step; y <= origin[1] + h / zoom; y += step) {
        ctx.fillRect((x - origin[0]) * zoom - dot / 2, (y - origin[1]) * zoom - dot / 2, dot, dot);
      }
    }
  }
  /// Нарисовать доску: view = { x, y, zoom } - мировая точка в левом верхнем углу и масштаб.
  function drawBoard(ctx, board, w, h, view, hidden) {
    drawGrid(ctx, w, h, [view.x, view.y], view.zoom);
    ctx.save();
    ctx.scale(view.zoom, view.zoom);
    ctx.translate(-view.x, -view.y);
    for (const it of board.items) drawItem(ctx, it, board, view.zoom, it.id === hidden);
    ctx.restore();
  }

  // ───────── превью в заметке ─────────
  function sizeCanvas(canvas, w, h) {
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
    canvas.style.width = w + 'px'; canvas.style.height = h + 'px';
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return ctx;
  }
  function paintPreview(canvas, board, e) {
    env = e;
    const w = canvas.parentElement.clientWidth || 320, h = w / ASPECT;
    const ctx = sizeCanvas(canvas, w, h);
    const vp = previewViewport(board);
    onImageReady = () => paintPreview(canvas, board, e);
    drawBoard(ctx, board, w, h, { x: vp.x, y: vp.y, zoom: w / vp.w });
    if (!board.items.length) {
      ctx.font = `500 ${env.hand ? 22 : 15}px ${env.family}`; ctx.fillStyle = hexA(ink('white'), 0.45);
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText('Доска - нажми, чтобы рисовать', w / 2, h / 2);
    } else {
      ctx.font = '600 10px -apple-system, system-ui'; ctx.fillStyle = 'rgba(255,255,255,.4)'; ctx.textBaseline = 'top';
      ctx.fillText('ДОСКА', 12, 10);
    }
  }
  /// Для экспорта страницы: нарисовать превью в прямоугольник готового холста.
  function drawPreviewInto(ctx, board, x, y, w, h, e) {
    env = e;
    const vp = previewViewport(board, w / h);
    ctx.save();
    ctx.beginPath(); roundRect(ctx, x, y, w, h, 12); ctx.clip();
    ctx.fillStyle = 'rgba(255,255,255,.05)'; ctx.fillRect(x, y, w, h);
    ctx.translate(x, y);
    drawBoard(ctx, board, w, h, { x: vp.x, y: vp.y, zoom: w / vp.w });
    ctx.restore();
  }
  const texts = board => (board.items || []).filter(holdsText).map(it => it.text).filter(Boolean);
  /// Перед экспортом: дождаться картинок доски, чтобы они попали в PDF/PNG.
  function preload(board, e) {
    env = e;
    const names = (board.items || []).filter(it => it.kind === 'image' && it.image && !images.get(it.image)).map(it => it.image);
    return Promise.all(names.map(name => Promise.resolve(e.imageURL(name)).then(url => url && new Promise(res => {
      const img = new Image();
      img.onload = () => { images.set(name, img); res(); };
      img.onerror = () => res();
      img.src = url;
    })).catch(() => {})));
  }

  // ───────── окно доски ─────────
  const TOOLS = [
    ['select', 'Выбор', '<path d="M5 3l14 8-6 2-2 6z"/>'],
    ['pen', 'Карандаш', '<path d="M4 20l4-1 11-11-3-3L5 16z"/><path d="M14 6l3 3"/>'],
    ['marker', 'Маркер', '<path d="M9 15l-4 5h5l2-2"/><path d="M8 13l8-8 4 4-8 8z"/>'],
    ['eraser', 'Ластик', '<path d="M8 20h12"/><path d="M4 15l9-9 6 6-7 7H8z"/>'],
    ['arrow', 'Стрелка', '<path d="M5 19L19 5"/><path d="M10 5h9v9"/>'],
    ['rect', 'Прямоугольник', '<rect x="4" y="6" width="16" height="12" rx="3"/>'],
    ['ellipse', 'Овал', '<ellipse cx="12" cy="12" rx="8" ry="6"/>'],
    ['diamond', 'Ромб', '<path d="M12 3l9 9-9 9-9-9z"/>'],
    ['sticky', 'Стикер', '<path d="M5 4h14v10l-5 6H5z"/><path d="M14 20v-6h5"/>'],
    ['text', 'Надпись', '<path d="M5 6V4h14v2M12 4v16M9 20h6"/>'],
    ['image', 'Картинка', '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-9 9"/>'],
  ];
  const COLORS = ['white', 'yellow', 'pink', 'green', 'sky', 'orange', 'lavender', 'coral', 'gray'];
  const WIDTHS = [2, 4, 8];
  const svg = d => `<svg viewBox="0 0 24 24">${d}</svg>`;

  function open(board, e, onChange) {
    env = e;
    board.items = board.items || [];
    const root = document.createElement('div');
    root.className = 'wb';
    root.innerHTML = `
      <div class="wb-top">
        <button class="wb-done" data-a="done">Готово</button>
        <span class="wb-title">Доска</span>
        <div class="wb-acts">
          <button data-a="undo" aria-label="Отменить">${svg('<path d="M9 14L4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>')}</button>
          <button data-a="redo" aria-label="Повторить">${svg('<path d="M15 14l5-5-5-5"/><path d="M20 9H10a6 6 0 0 0 0 12h3"/>')}</button>
          <button data-a="fit" aria-label="Показать всё">${svg('<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>')}</button>
        </div>
      </div>
      <canvas class="wb-canvas"></canvas>
      <textarea class="wb-text" hidden spellcheck="false"></textarea>
      <div class="wb-sel" hidden>
        <button data-s="fill">Заливка</button><button data-s="dup">Копия</button><button data-s="front">Наверх</button><button data-s="del" class="del">Удалить</button>
      </div>
      <div class="wb-bottom">
        <div class="wb-props">
          ${COLORS.map(c => `<button class="wb-color" data-c="${c}" style="--c:${ink(c)}" aria-label="Цвет"></button>`).join('')}
          <span class="wb-sep"></span>
          ${WIDTHS.map(w => `<button class="wb-width" data-w="${w}" aria-label="Толщина ${w}"><i style="height:${w}px"></i></button>`).join('')}
        </div>
        <div class="wb-tools">${TOOLS.map(t => `<button data-t="${t[0]}" aria-label="${t[1]}" title="${t[1]}">${svg(t[2])}</button>`).join('')}</div>
      </div>
      <input type="file" accept="image/*" hidden class="wb-file">`;
    root.style.setProperty('--wb-bg', e.background || '#1D3594');
    document.body.append(root);
    document.body.classList.add('wb-open');
    const canvas = root.querySelector('.wb-canvas'), ta = root.querySelector('.wb-text'), selBar = root.querySelector('.wb-sel');
    let ctx, W = 0, H = 0;
    let tool = localGet('tool', 'pen'), color = localGet('color', 'white'), strokeW = localGet('width', 4);
    let selected = null, editing = null;
    const undo = [], redo = [];
    let view = { x: 0, y: 0, zoom: 0.5 };

    function localGet(k, d) { try { const v = localStorage.getItem('z.wb.' + k); return v == null ? d : JSON.parse(v); } catch { return d; } }
    function localSet(k, v) { try { localStorage.setItem('z.wb.' + k, JSON.stringify(v)); } catch {} }

    function resize() {
      const r = canvas.getBoundingClientRect();
      W = r.width; H = r.height;
      ctx = sizeCanvas(canvas, W, H);
      canvas.style.width = ''; canvas.style.height = '';
      draw();
    }
    function fit() {
      const vp = board.items.length ? previewViewport(board, W / H) : { x: 800 - W / 2 / 0.5, y: 450 - H / 2 / 0.5, w: W / 0.5, h: H / 0.5 };
      const zoom = Math.min(W / vp.w, H / vp.h);
      view = { zoom, x: vp.x + vp.w / 2 - W / 2 / zoom, y: vp.y + vp.h / 2 - H / 2 / zoom };
      draw();
    }
    const toWorld = (sx, sy) => [view.x + sx / view.zoom, view.y + sy / view.zoom];
    const toScreen = p => [(p[0] - view.x) * view.zoom, (p[1] - view.y) * view.zoom];

    function draw() {
      if (!ctx) return;
      ctx.clearRect(0, 0, W, H);
      drawBoard(ctx, board, W, H, view, editing && editing.id);
      if (selected && board.items.includes(selected)) drawSelection();
      placeSelBar();
    }
    function drawSelection() {
      const b = bounds(selected, board);
      const [x, y] = toScreen([b.x, b.y]), [X, Y] = toScreen([b.X, b.Y]);
      ctx.save();
      ctx.strokeStyle = 'rgba(140,190,255,.95)'; ctx.lineWidth = 1.5; ctx.setLineDash([5, 4]);
      ctx.strokeRect(x - 4, y - 4, X - x + 8, Y - y + 8);
      ctx.setLineDash([]);
      if (isBox(selected)) {
        ctx.fillStyle = '#fff'; ctx.strokeStyle = 'rgba(80,140,255,1)'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(X + 4, Y + 4, 9, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      }
      if (isConnector(selected)) {
        const path = connectorPath(selected, board);
        for (const p of [path.a, path.b]) { const s = toScreen(p); ctx.fillStyle = '#fff'; ctx.strokeStyle = 'rgba(80,140,255,1)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(s[0], s[1], 8, 0, Math.PI * 2); ctx.fill(); ctx.stroke(); }
      }
      ctx.restore();
    }
    function placeSelBar() {
      if (!selected || editing || !board.items.includes(selected)) { selBar.hidden = true; return; }
      const b = bounds(selected, board);
      const [x, y] = toScreen([b.x, b.y]), [X] = toScreen([b.X, b.Y]);
      selBar.hidden = false;
      selBar.querySelector('[data-s="fill"]').hidden = !isShape(selected);
      const bw = selBar.offsetWidth || 260;
      selBar.style.left = Math.max(8, Math.min(W - bw - 8, (x + X) / 2 - bw / 2)) + 'px';
      // Над предметом; если сверху места нет - под ним. Координаты холста + его место в окне.
      const above = y - 52, below = toScreen([b.X, b.Y])[1] + 14;
      selBar.style.top = canvas.offsetTop + (above > 6 ? above : Math.min(below, H - 50)) + 'px';
    }
    function paintUI() {
      root.querySelectorAll('[data-t]').forEach(b => b.classList.toggle('on', b.dataset.t === tool));
      root.querySelectorAll('[data-c]').forEach(b => b.classList.toggle('on', b.dataset.c === color));
      root.querySelectorAll('[data-w]').forEach(b => b.classList.toggle('on', +b.dataset.w === strokeW));
      root.querySelector('[data-a="undo"]').disabled = !undo.length;
      root.querySelector('[data-a="redo"]').disabled = !redo.length;
    }

    // Отмена: снимок доски до изменения.
    let pendingSnap = null;
    const snap = () => JSON.stringify(board.items);
    function begin() { pendingSnap = snap(); }
    function commit() {
      if (pendingSnap == null) return;
      if (pendingSnap !== snap()) { undo.push(pendingSnap); if (undo.length > 100) undo.shift(); redo.length = 0; onChange(board); }
      pendingSnap = null;
      paintUI();
    }
    function restore(from, to) {
      if (!from.length) return;
      to.push(snap());
      board.items = JSON.parse(from.pop());
      selected = null;
      onChange(board);
      paintUI(); draw();
    }
    const findSelected = () => { if (selected) selected = board.items.find(x => x.id === selected.id) || null; };

    // ── текст ──
    function editText(it) {
      selected = it; editing = it;
      const tb = textBox(it);
      // Буквы при вводе - не мельче 17 точек: отдалённую доску приближаем к предмету.
      const k = env.hand ? 1.3 : 1;
      if (fontSize(it) * k * view.zoom < 17) view.zoom = Math.min(6, 17 / (fontSize(it) * k));
      // Предмет - по центру по ширине и в верхней части экрана, чтобы клавиатура его не закрыла.
      const r0 = R(it);
      if ((r0.X - r0.x) * view.zoom < W - 24) view.x = r0.mx - W / 2 / view.zoom;
      else view.x = r0.x - 12 / view.zoom;
      view.y = r0.y - H * 0.12 / view.zoom;
      const p = toScreen([tb.x, tb.y]);
      p[0] += canvas.offsetLeft; p[1] += canvas.offsetTop;
      ta.hidden = false;
      ta.value = it.text || '';
      const fs = fontSize(it) * (env.hand ? 1.3 : 1) * view.zoom;
      Object.assign(ta.style, {
        left: p[0] + 'px', top: p[1] + 'px', width: Math.max(tb.w * view.zoom + (it.kind === 'text' ? 60 : 0), 80) + 'px',
        height: Math.max(tb.h * view.zoom, fs * 1.4) + 'px', font: `600 ${fs}px/${1.2} ${env.family}`, color: textColor(it),
        textAlign: isShape(it) ? 'center' : 'left',
      });
      draw();
      ta.focus();
    }
    function endEdit() {
      if (!editing) return;
      const it = editing;
      editing = null;
      it.text = ta.value.replace(/\s+$/, '');
      ta.hidden = true;
      ta.blur();
      if (it.kind === 'text' && !it.text) { board.items = board.items.filter(x => x !== it); selected = null; }
      else fitText(it);
      commit();
      draw();
    }
    ta.addEventListener('input', () => {
      if (!editing) return;
      editing.text = ta.value; fitText(editing);
      onChange(board); // заметка сохраняется на каждую букву - закрыли приложение посреди ввода, текст цел
      ta.style.height = Math.max(textBox(editing).h * view.zoom, parseFloat(ta.style.height)) + 'px';
    });
    ta.addEventListener('blur', () => setTimeout(endEdit, 0));

    // ── жесты ──
    const pointers = new Map();
    let gesture = null, lastTap = { t: 0, id: null };
    const tol = () => 12 / view.zoom;
    // Сначала точное попадание (контур, штрих); не попал - пустая фигура берётся и изнутри: пальцем в тонкий контур не попасть.
    const topHit = p => {
      for (let i = board.items.length - 1; i >= 0; i--) if (hit(board.items[i], p, tol(), board)) return board.items[i];
      for (let i = board.items.length - 1; i >= 0; i--) {
        const it = board.items[i];
        if (isShape(it)) { const r = R(it); if (p[0] >= r.x && p[0] <= r.X && p[1] >= r.y && p[1] <= r.Y) return it; }
      }
      return null;
    };
    const boxAt = (p, except) => { for (let i = board.items.length - 1; i >= 0; i--) { const it = board.items[i]; if (it !== except && isBox(it) && it.kind !== 'text') { const r = R(it); if (p[0] >= r.x && p[0] <= r.X && p[1] >= r.y && p[1] <= r.Y) return it; } } return null; };

    canvas.addEventListener('pointerdown', ev => {
      ev.preventDefault();
      if (editing) { ta.blur(); return; }
      try { canvas.setPointerCapture(ev.pointerId); } catch {}
      pointers.set(ev.pointerId, [ev.offsetX, ev.offsetY]);
      if (pointers.size === 2) {
        // Второй палец: прервать начатое и двигать/увеличивать холст.
        if (gesture && gesture.cancel) gesture.cancel();
        const [a, b] = [...pointers.values()];
        gesture = { kind: 'pinch', d0: dist(a, b), c0: [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2], v0: { ...view } };
        return;
      }
      if (pointers.size > 2) return;
      startGesture(ev.offsetX, ev.offsetY);
    });
    canvas.addEventListener('pointermove', ev => {
      if (!pointers.has(ev.pointerId)) return;
      pointers.set(ev.pointerId, [ev.offsetX, ev.offsetY]);
      if (!gesture) return;
      if (gesture.kind === 'pinch') {
        if (pointers.size < 2) return;
        const [a, b] = [...pointers.values()];
        const c = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
        const zoom = Math.max(0.08, Math.min(6, gesture.v0.zoom * dist(a, b) / Math.max(gesture.d0, 1)));
        const w0 = [gesture.v0.x + gesture.c0[0] / gesture.v0.zoom, gesture.v0.y + gesture.c0[1] / gesture.v0.zoom];
        view = { zoom, x: w0[0] - c[0] / zoom, y: w0[1] - c[1] / zoom };
        draw();
        return;
      }
      gesture.move(ev.offsetX, ev.offsetY);
      draw();
    });
    const up = ev => {
      if (!pointers.has(ev.pointerId)) return;
      pointers.delete(ev.pointerId);
      if (!gesture) return;
      if (gesture.kind === 'pinch') { if (!pointers.size) gesture = null; return; }
      if (pointers.size) return;
      const g = gesture; gesture = null;
      g.end(ev.offsetX, ev.offsetY);
      draw();
    };
    canvas.addEventListener('pointerup', up);
    canvas.addEventListener('pointercancel', ev => { if (gesture && gesture.cancel) gesture.cancel(); gesture = null; pointers.delete(ev.pointerId); draw(); });

    function startGesture(sx, sy) {
      const p = toWorld(sx, sy);
      const pan = () => { const v0 = { ...view }; return { kind: 'pan', move: (x, y) => { view.x = v0.x - (x - sx) / view.zoom; view.y = v0.y - (y - sy) / view.zoom; }, end() {} }; };
      if (tool === 'pen' || tool === 'marker') {
        begin();
        const it = { id: uid(), kind: tool, points: [p], color, width: strokeW / view.zoom };
        board.items.push(it);
        gesture = {
          move: (x, y) => { const q = toWorld(x, y), last = it.points[it.points.length - 1]; if (dist(q, last) > 1.5 / view.zoom) it.points.push(q); },
          end: () => commit(),
          cancel: () => { board.items = board.items.filter(x => x !== it); pendingSnap = null; },
        };
        return;
      }
      if (tool === 'eraser') {
        begin();
        const erase = q => { const before = board.items.length; board.items = board.items.filter(it => !hit(it, q, tol(), board)); if (board.items.length !== before) cleanLinks(); };
        erase(p);
        gesture = { move: (x, y) => erase(toWorld(x, y)), end: () => commit(), cancel: () => { if (pendingSnap) board.items = JSON.parse(pendingSnap); pendingSnap = null; } };
        return;
      }
      if (tool === 'arrow') {
        begin();
        const from = boxAt(p);
        const it = { id: uid(), kind: 'arrow', points: [p, p], color, width: strokeW / view.zoom };
        if (from) { it.start = from.id; it.startAnchor = anchorNear(from, p, 20 / view.zoom); }
        board.items.push(it);
        gesture = {
          move: (x, y) => {
            const q = toWorld(x, y);
            it.points[1] = q;
            const to = boxAt(q, from);
            const snapD = 20 / view.zoom;
            if (from) it.startAnchor = attachAnchor(from, p, to ? center(to) : q, snapD);
            if (to) { it.end = to.id; it.endAnchor = attachAnchor(to, q, from ? center(from) : p, snapD); } else { delete it.end; delete it.endAnchor; }
          },
          end: () => {
            if (dist(it.points[0], it.points[1]) * view.zoom < 12 && !it.end) { board.items = board.items.filter(x => x !== it); pendingSnap = null; return; }
            selected = it; commit(); setTool('select');
          },
          cancel: () => { board.items = board.items.filter(x => x !== it); pendingSnap = null; },
        };
        return;
      }
      if (tool === 'rect' || tool === 'ellipse' || tool === 'diamond') {
        begin();
        const it = { id: uid(), kind: tool, rect: [p, [0, 0]], color, width: strokeW / view.zoom };
        board.items.push(it);
        gesture = {
          move: (x, y) => { const q = toWorld(x, y); setRect(it, p[0], p[1], q[0] - p[0], q[1] - p[1]); },
          end: () => {
            const r = R(it);
            if (r.w * view.zoom < 14 && r.h * view.zoom < 14) setRect(it, p[0] - 100, p[1] - 65, 200, 130);
            else setRect(it, r.x, r.y, r.w, r.h);
            selected = it; commit(); setTool('select');
          },
          cancel: () => { board.items = board.items.filter(x => x !== it); pendingSnap = null; },
        };
        return;
      }
      if (tool === 'sticky' || tool === 'text') {
        gesture = {
          move() {},
          end: () => {
            begin();
            const it = tool === 'sticky'
              ? { id: uid(), kind: 'sticky', rect: [[p[0] - STICKY[0] / 2, p[1] - STICKY[1] / 2], [...STICKY]], color: 'white', fill: color === 'white' ? 'yellow' : color, width: 4, text: '' }
              : { id: uid(), kind: 'text', rect: [[p[0], p[1] - 24], [40, 48]], color, width: 4, text: '' };
            if (it.kind === 'text') fitText(it);
            board.items.push(it);
            setTool('select');
            editText(it);
          },
        };
        return;
      }
      if (tool === 'image') { gesture = { move() {}, end: () => pickImage(p) }; return; }
      // Выбор: ручка размера, предмет (двигать) или пустое место (двигать холст).
      if (selected && isBox(selected)) {
        const b = bounds(selected, board), h = toScreen([b.X, b.Y]);
        if (dist([sx, sy], [h[0] + 4, h[1] + 4]) < 22) {
          begin();
          const it = selected, r0 = R(it), keep = r0.w / Math.max(r0.h, 1);
          gesture = {
            move: (x, y) => {
              const q = toWorld(x, y);
              let w = Math.max(30, q[0] - r0.x), hh = Math.max(24, q[1] - r0.y);
              if (it.kind === 'image') hh = w / keep;
              setRect(it, r0.x, r0.y, w, hh);
              if (it.kind === 'text') it.fixedWidth = true;
              if (holdsText(it)) fitText(it);
            },
            end: () => commit(),
          };
          return;
        }
      }
      if (selected && isConnector(selected)) {
        const path = connectorPath(selected, board);
        const ends = [path.a, path.b].map(toScreen);
        const k = ends.findIndex(e => dist(e, [sx, sy]) < 22);
        if (k >= 0) {
          begin();
          const it = selected;
          gesture = {
            move: (x, y) => {
              const q = toWorld(x, y);
              it.points = it.points || [[0, 0], [0, 0]];
              it.points[k] = q;
              const other = itemById(board, k === 0 ? it.end : it.start);
              const box = boxAt(q, other);
              const [idKey, anKey] = k === 0 ? ['start', 'startAnchor'] : ['end', 'endAnchor'];
              const far = other ? center(other) : (it.points[1 - k] || q);
              if (box) { it[idKey] = box.id; it[anKey] = attachAnchor(box, q, far, 20 / view.zoom); } else { delete it[idKey]; delete it[anKey]; }
            },
            end: () => commit(),
          };
          return;
        }
      }
      const target = topHit(p);
      if (!target) { selected = null; gesture = pan(); return; }
      const now = Date.now();
      const doubleTap = lastTap.id === target.id && now - lastTap.t < 350;
      lastTap = { t: now, id: target.id };
      selected = target;
      if (doubleTap && holdsText(target)) { gesture = { move() {}, end: () => { begin(); editText(target); } }; return; }
      begin();
      let moved = false;
      const start = p;
      const orig = JSON.parse(JSON.stringify(target));
      gesture = {
        move: (x, y) => {
          const q = toWorld(x, y), d = [q[0] - start[0], q[1] - start[1]];
          if (!moved && hyp(d[0], d[1]) * view.zoom < 4) return;
          moved = true;
          if (orig.points) target.points = orig.points.map(pt => [pt[0] + d[0], pt[1] + d[1]]);
          if (orig.rect) target.rect = [[orig.rect[0][0] + d[0], orig.rect[0][1] + d[1]], orig.rect[1]];
        },
        end: () => commit(),
      };
    }
    /// Стрелки, у которых пропал предмет на конце, остаются - конец становится свободным.
    function cleanLinks() {
      const ids = new Set(board.items.map(x => x.id));
      for (const it of board.items) if (isConnector(it)) {
        for (const [idKey, anKey] of [['start', 'startAnchor'], ['end', 'endAnchor']]) {
          if (it[idKey] && !ids.has(it[idKey])) { delete it[idKey]; delete it[anKey]; }
        }
      }
    }
    async function pickImage(p) {
      const input = root.querySelector('.wb-file');
      input.onchange = async () => {
        const file = input.files[0]; input.value = '';
        if (!file || !env.saveImage) return;
        const name = await env.saveImage(file);
        if (!name) return;
        const url = await env.imageURL(name);
        const img = new Image();
        img.onload = () => {
          images.set(name, img);
          begin();
          const w = 420, h = w * img.height / Math.max(img.width, 1);
          const it = { id: uid(), kind: 'image', rect: [[p[0] - w / 2, p[1] - h / 2], [w, h]], color: 'white', width: 4, image: name, text: '' };
          board.items.push(it);
          selected = it; commit(); setTool('select'); draw();
        };
        img.src = url;
      };
      input.click();
    }

    function setTool(t) { tool = t; localSet('tool', t); if (t !== 'select') selected = null; paintUI(); draw(); }

    root.addEventListener('click', ev => {
      const b = ev.target.closest('button');
      if (!b) return;
      if (b.dataset.t) return setTool(b.dataset.t);
      if (b.dataset.c) {
        color = b.dataset.c; localSet('color', color);
        if (selected) {
          begin();
          if (selected.kind === 'sticky') selected.fill = color === 'white' ? 'yellow' : color; else selected.color = color;
          commit();
        }
        paintUI(); draw(); return;
      }
      if (b.dataset.w) {
        strokeW = +b.dataset.w; localSet('width', strokeW);
        if (selected && (isStroke(selected) || isConnector(selected) || isShape(selected))) { begin(); selected.width = strokeW / view.zoom; commit(); }
        paintUI(); draw(); return;
      }
      if (b.dataset.s && selected) {
        begin();
        const s = b.dataset.s;
        if (s === 'del') { board.items = board.items.filter(x => x !== selected); selected = null; cleanLinks(); }
        if (s === 'dup') {
          const copy = JSON.parse(JSON.stringify(selected)); copy.id = uid();
          const d = 30;
          if (copy.points) copy.points = copy.points.map(pt => [pt[0] + d, pt[1] + d]);
          if (copy.rect) copy.rect = [[copy.rect[0][0] + d, copy.rect[0][1] + d], copy.rect[1]];
          delete copy.start; delete copy.end; delete copy.startAnchor; delete copy.endAnchor;
          board.items.push(copy); selected = copy;
        }
        if (s === 'front') { board.items = board.items.filter(x => x !== selected); board.items.push(selected); }
        if (s === 'fill' && isShape(selected)) { if (selected.fill) delete selected.fill; else selected.fill = selected.color || 'white'; }
        commit(); draw(); return;
      }
      const a = b.dataset.a;
      if (a === 'undo') restore(undo, redo);
      if (a === 'redo') restore(redo, undo);
      if (a === 'fit') fit();
      if (a === 'done') close();
    });
    // Кнопки не забирают фокус у надписи, которую печатаешь.
    root.addEventListener('pointerdown', ev => { if (ev.target.closest('button')) ev.preventDefault(); });

    function close() {
      if (editing) endEdit();
      removeEventListener('resize', resize);
      document.body.classList.remove('wb-open');
      root.remove();
      if (open.onClose) open.onClose();
      if (e.onClose) e.onClose();
    }
    addEventListener('resize', resize);
    onImageReady = () => draw();
    paintUI();
    setTimeout(() => { resize(); fit(); }, 0);
    void findSelected;
    return { close };
  }

  return { newBoard: () => ({ id: uid(), items: [] }), paintPreview, drawPreviewInto, preload, open, texts, ASPECT };
})();
