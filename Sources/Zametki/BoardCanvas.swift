import AppKit
import UniformTypeIdentifiers

enum BoardTool: String, CaseIterable {
    case select, hand, pen, marker, eraser, line, arrow, rect, ellipse, diamond, sticky, text, image

    var name: String {
        switch self {
        case .select: "Выбор"
        case .hand: "Рука - двигать холст"
        case .pen: "Карандаш"
        case .marker: "Маркер"
        case .eraser: "Ластик"
        case .line: "Линия"
        case .arrow: "Стрелка"
        case .rect: "Прямоугольник"
        case .ellipse: "Овал"
        case .diamond: "Ромб"
        case .sticky: "Стикер"
        case .text: "Надпись"
        case .image: "Картинка"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .hand: "hand.raised"
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .eraser: "eraser"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .diamond: "diamond"
        case .sticky: "note"
        case .text: "textformat"
        case .image: "photo"
        }
    }

    var key: String {
        switch self {
        case .select: "V"
        case .hand: "H"
        case .pen: "P"
        case .marker: "M"
        case .eraser: "E"
        case .line: "L"
        case .arrow: "A"
        case .rect: "R"
        case .ellipse: "O"
        case .diamond: "D"
        case .sticky: "S"
        case .text: "T"
        case .image: "I"
        }
    }

    /// Физическая клавиша - та же в любой раскладке (V и М - одна кнопка).
    var keyCode: UInt16 {
        switch self {
        case .select: 9
        case .hand: 4
        case .pen: 35
        case .marker: 46
        case .eraser: 14
        case .line: 37
        case .arrow: 0
        case .rect: 15
        case .ellipse: 31
        case .diamond: 2
        case .sticky: 1
        case .text: 17
        case .image: 34
        }
    }
}

/// Холст доски: бесконечный, с зумом и панорамой; рисование, фигуры, связи, выделение рамкой,
/// ручки размера, направляющие при перетаскивании, копирование, вставка картинок, отмена и повтор.
final class BoardCanvas: NSView, NSTextViewDelegate {
    weak var controller: BoardController?

    private(set) var board = Board()
    /// Мировая точка в левом верхнем углу окна и масштаб.
    private(set) var origin = CGPoint.zero
    private(set) var zoom: CGFloat = 1
    var tool: BoardTool = .select { didSet { if tool != .select { hovered = nil }; window?.invalidateCursorRects(for: self); needsDisplay = true } }
    var color = "white"
    var strokeWidth: CGFloat = 4
    private(set) var selection: Set<String> = [] { didSet { needsDisplay = true } }

    private var hovered: String?
    private var undoStack: [Board] = []
    private var redoStack: [Board] = []
    private var snapshot: Board?

    private enum Handle: CaseIterable { case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }
    private enum Mode {
        case none
        case pan(screen: CGPoint, origin: CGPoint)
        case draw
        case move(start: CGPoint, originals: [String: BoardItem])
        case resize(id: String, handle: Handle, original: BoardItem)
        case endpoint(id: String, isStart: Bool)
        case waypoint(id: String, index: Int)
        case marquee(start: CGPoint, current: CGPoint, base: Set<String>)
        case erase
    }

    private var mode: Mode = .none
    private var drawing: BoardItem?
    private var dropTarget: String?
    /// Куда прилипнет конец стрелки: точка на краю (закреплённый) или nil - «плавающий», сам выберет сторону.
    private var dropAnchor: CGPoint?
    private var guides: [(CGPoint, CGPoint)] = []
    private var spaceHeld = false
    private var editor: NSTextView?
    private var editingID: String?
    private var backToSelect = false
    private var placed = false

    static let pasteType = NSPasteboard.PasteboardType("com.romankandeevy.zametki.board-items")
    private static let accent = NSColor(srgbRed: 0.38, green: 0.62, blue: 1, alpha: 1)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // С macOS 14 вид сам не обрезает рисунок по краям - без этого доска залезала на панель инструментов.
        clipsToBounds = true
        wantsLayer = true
        layer?.masksToBounds = true
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    func load(_ board: Board) {
        self.board = board
        placed = false
        needsLayout = true
        needsDisplay = true
    }

    // MARK: координаты

    private func world(_ s: CGPoint) -> CGPoint { CGPoint(x: s.x / zoom + origin.x, y: s.y / zoom + origin.y) }
    private func screen(_ w: CGPoint) -> CGPoint { CGPoint(x: (w.x - origin.x) * zoom, y: (w.y - origin.y) * zoom) }
    private func screen(_ r: CGRect) -> CGRect {
        CGRect(x: (r.minX - origin.x) * zoom, y: (r.minY - origin.y) * zoom, width: r.width * zoom, height: r.height * zoom)
    }

    private func location(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func layout() {
        super.layout()
        if !placed, bounds.width > 10 {
            placed = true
            fitContent(maxZoom: 1)
        }
        positionEditor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for delay in [0.05, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let window = self.window, self.editor == nil else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    // MARK: вид: зум и панорама

    func setZoom(_ value: CGFloat, around point: CGPoint? = nil) {
        let anchor = point ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let w = world(anchor)
        zoom = min(max(value, 0.1), 4)
        origin = CGPoint(x: w.x - anchor.x / zoom, y: w.y - anchor.y / zoom)
        viewChanged()
    }

    /// Показать всё нарисованное (пустая доска - начало координат по центру).
    func fitContent(maxZoom: CGFloat = 4) {
        guard bounds.width > 10 else { return }
        if let box = board.contentBounds {
            let z = min((bounds.width - 120) / max(box.width, 1), (bounds.height - 120) / max(box.height, 1), maxZoom)
            zoom = min(max(z, 0.1), 4)
            origin = CGPoint(x: box.midX - bounds.width / 2 / zoom, y: box.midY - bounds.height / 2 / zoom)
        } else {
            zoom = 1
            origin = CGPoint(x: -bounds.width / 2 + 400, y: -bounds.height / 2 + 250)
        }
        viewChanged()
    }

    private func viewChanged() {
        positionEditor()
        needsDisplay = true
        controller?.zoom = zoom
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.08
            setZoom(zoom * (1 + delta), around: location(event))
        } else {
            let k: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 14
            origin.x -= event.scrollingDeltaX * k / zoom
            origin.y -= event.scrollingDeltaY * k / zoom
            viewChanged()
        }
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification), around: location(event))
    }

    override func smartMagnify(with event: NSEvent) {
        if abs(zoom - 1) < 0.01 { fitContent() } else { setZoom(1, around: location(event)) }
    }

    // MARK: отрисовка

    override func draw(_ dirtyRect: NSRect) {
        BoardGrid.draw(in: bounds, origin: origin, zoom: zoom)

        var shown = board
        if let drawing { shown.items.append(drawing) }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: -origin.x * zoom, yBy: -origin.y * zoom)
        transform.scale(by: zoom)
        transform.concat()
        for item in shown.items { item.draw(in: shown, hidingText: item.id == editingID) }
        NSGraphicsContext.restoreGraphicsState()

        drawOverlays(shown)
    }

    private func drawOverlays(_ shown: Board) {
        let accent = Self.accent
        // Под мышью - тонкая подсветка; цель для стрелки - заметная.
        if tool == .select, let hovered, !selection.contains(hovered), let item = board.item(hovered), case .none = mode {
            outline(item, in: shown, color: accent.withAlphaComponent(0.6), width: 1.5)
        }
        if let dropTarget, let item = board.item(dropTarget) {
            outline(item, in: shown, color: accent, width: 2.5)
            if let dropAnchor {
                // Точка, к которой прилипнет конец.
                let c = screen(dropAnchor)
                let r = NSRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
                accent.setFill()
                NSBezierPath(ovalIn: r).fill()
                NSColor.white.setStroke()
                let ring = NSBezierPath(ovalIn: r)
                ring.lineWidth = 2
                ring.stroke()
            }
        }
        let selected = selection.compactMap { board.item($0) }
        for item in selected { outline(item, in: shown, color: accent, width: 1.5) }
        if selected.count > 1, let union = selectionBounds() {
            let r = screen(union).insetBy(dx: -6, dy: -6)
            let path = NSBezierPath(rect: r)
            path.setLineDash([4, 4], count: 2, phase: 0)
            accent.withAlphaComponent(0.7).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        if selected.count == 1, let item = selected.first, editingID == nil {
            if item.isConnector {
                let shape = item.connectorPath(in: board)
                // Полупрозрачные точки на участках: потяни - появится новая точка.
                for ghost in shape.ghosts {
                    let g = screen(ghost)
                    let r = NSRect(x: g.x - 4.5, y: g.y - 4.5, width: 9, height: 9)
                    Self.accent.withAlphaComponent(0.45).setFill()
                    NSBezierPath(ovalIn: r).fill()
                    NSColor.white.withAlphaComponent(0.8).setStroke()
                    let ring = NSBezierPath(ovalIn: r)
                    ring.lineWidth = 1.2
                    ring.stroke()
                }
                for p in [shape.a, shape.b] { knob(at: screen(p), round: true) }
                // Свои точки стрелки - их двигают; двойной клик убирает.
                let (aRef, bRef) = item.connectorRefs(in: board)
                for w in item.waypointPositions(aRef: aRef, bRef: bRef) {
                    let c = screen(w)
                    let r = NSRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
                    Self.accent.setFill()
                    NSBezierPath(ovalIn: r).fill()
                    NSColor.white.setStroke()
                    let ring = NSBezierPath(ovalIn: r)
                    ring.lineWidth = 2
                    ring.stroke()
                }
            } else {
                for handle in handles(for: item) { knob(at: handle.point, round: false) }
            }
        }
        // Точки-связи: потяни - выйдет стрелка, привязанная к этому предмету.
        if tool == .select, editingID == nil, case .none = mode {
            for item in connectable() {
                for dot in connectorDots(item) {
                    let r = NSRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)
                    accent.setFill()
                    NSBezierPath(ovalIn: r).fill()
                    NSColor.white.setStroke()
                    let ring = NSBezierPath(ovalIn: r)
                    ring.lineWidth = 1.5
                    ring.stroke()
                }
            }
        }
        if case let .marquee(start, current, _) = mode {
            let a = screen(start), b = screen(current)
            let r = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            accent.withAlphaComponent(0.12).setFill()
            r.fill()
            accent.withAlphaComponent(0.8).setStroke()
            NSBezierPath(rect: r).stroke()
        }
        if !guides.isEmpty {
            let pink = NSColor(srgbRed: 1, green: 0.35, blue: 0.65, alpha: 1)
            pink.setStroke()
            for (a, b) in guides {
                let path = NSBezierPath()
                path.move(to: screen(a))
                path.line(to: screen(b))
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    private func outline(_ item: BoardItem, in shown: Board, color: NSColor, width: CGFloat) {
        color.setStroke()
        if item.isConnector {
            // Подсветка ровно по форме стрелки - прямой, кривой или угловой.
            let shape = item.connectorPath(in: shown)
            let path = shape.bezier()
            let t = AffineTransform(translationByX: -origin.x * zoom, byY: -origin.y * zoom)
            path.transform(using: AffineTransform(scaleByX: zoom, byY: zoom))
            path.transform(using: t)
            path.lineWidth = width + 4
            color.withAlphaComponent(0.35).setStroke()
            path.lineCapStyle = .round
            path.stroke()
            return
        }
        let r = screen(item.bounds(in: shown)).insetBy(dx: -4, dy: -4)
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        path.lineWidth = width
        path.stroke()
    }

    private func knob(at p: CGPoint, round: Bool) {
        let r = NSRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
        let path = round ? NSBezierPath(ovalIn: r) : NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
        NSColor.white.setFill()
        path.fill()
        Self.accent.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    // MARK: ручки и точки-связи

    private func handles(for item: BoardItem) -> [(handle: Handle, point: CGPoint)] {
        let r = screen(item.isStroke ? item.strokeBounds : item.rect.standardized).insetBy(dx: item.isStroke ? -6 : 0, dy: item.isStroke ? -6 : 0)
        var list: [(Handle, CGPoint)] = [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)), (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)), (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
        ]
        // Боковые ручки - только там, где хватает места.
        if r.width > 40, r.height > 40 {
            list += [(.top, CGPoint(x: r.midX, y: r.minY)), (.bottom, CGPoint(x: r.midX, y: r.maxY)),
                     (.left, CGPoint(x: r.minX, y: r.midY)), (.right, CGPoint(x: r.maxX, y: r.midY))]
        } else if item.kind == .text {
            list += [(.left, CGPoint(x: r.minX, y: r.midY)), (.right, CGPoint(x: r.maxX, y: r.midY))]
        }
        return list.map { (handle: $0.0, point: $0.1) }
    }

    /// Предметы, у которых видны точки-связи: под мышью или единственный выделенный.
    private func connectable() -> [BoardItem] {
        // Выделена стрелка - точки-связи у предметов не нужны, они мешали бы её ручкам.
        if selection.count == 1, let one = selection.first, board.item(one)?.isConnector == true { return [] }
        var ids: [String] = []
        if let hovered { ids.append(hovered) }
        if selection.count == 1, let one = selection.first, !ids.contains(one) { ids.append(one) }
        return ids.compactMap { board.item($0) }.filter { $0.isBox && $0.kind != .text }
    }

    private func connectorDots(_ item: BoardItem) -> [CGPoint] {
        let r = screen(item.rect.standardized)
        let gap: CGFloat = 26
        return [CGPoint(x: r.midX, y: r.minY - gap), CGPoint(x: r.maxX + gap, y: r.midY),
                CGPoint(x: r.midX, y: r.maxY + gap), CGPoint(x: r.minX - gap, y: r.midY)]
    }

    private func selectionBounds() -> CGRect? {
        let rects = selection.compactMap { board.item($0)?.bounds(in: board) }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    // MARK: курсор

    override func resetCursorRects() {
        let cursor: NSCursor
        if spaceHeld || tool == .hand { cursor = .openHand } else {
            switch tool {
            case .select: cursor = .arrow
            case .text, .sticky: cursor = .iBeam
            default: cursor = .crosshair
            }
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let s = location(event)
        guard tool == .select, !spaceHeld else { return }
        let p = world(s)
        let hit = topItem(at: p)
        // Мышь над точками-связями держит подсветку предмета, чтобы точки не пропадали.
        let overDot = connectable().contains { item in connectorDots(item).contains { hypot($0.x - s.x, $0.y - s.y) < 10 } }
        let newHover = hit ?? (overDot ? hovered : nil)
        if newHover != hovered { hovered = newHover; needsDisplay = true }
        if selection.count == 1, let item = board.item(selection.first!), !item.isConnector,
           let handle = handles(for: item).first(where: { hypot($0.point.x - s.x, $0.point.y - s.y) < 12 })?.handle {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
        } else if overDot {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: мышь

    private func topItem(at p: CGPoint, excluding: Set<String> = [], boxesOnly: Bool = false) -> String? {
        let tolerance = 8 / zoom
        return board.items.last { item in
            !excluding.contains(item.id) && (!boxesOnly || item.isBox) && item.hit(p, tolerance: tolerance, in: board)
        }?.id
    }

    private func beginChange() { snapshot = board }

    /// Изменение закончено: в историю отмены и сразу в заметку.
    private func endChange() {
        defer { snapshot = nil }
        guard let snapshot, snapshot != board else { return }
        undoStack.append(snapshot)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        changed()
    }

    private func changed() {
        needsDisplay = true
        controller?.boardChanged(board)
        notifySelection()
    }

    private func notifySelection() {
        selection = selection.filter { board.item($0) != nil }
        controller?.selectionChanged(selection.compactMap { board.item($0) })
    }

    override func mouseDown(with event: NSEvent) {
        if editor != nil { endEditing() }
        window?.makeFirstResponder(self)
        let s = location(event)
        let p = world(s)
        if spaceHeld || tool == .hand {
            mode = .pan(screen: s, origin: origin)
            NSCursor.closedHand.set()
            return
        }
        beginChange()
        switch tool {
        case .select:
            selectDown(at: p, screen: s, event: event)
        case .hand:
            break
        case .pen, .marker:
            drawing = BoardItem(kind: tool == .pen ? .pen : .marker, points: [p], color: color, width: strokeWidth)
            mode = .draw
        case .line, .arrow:
            var item = BoardItem(kind: tool == .line ? .line : .arrow, points: [p, p], color: color, width: strokeWidth)
            item.start = topItem(at: p, boxesOnly: true)
            if let id = item.start, let target = board.item(id) { item.startAnchor = anchorForDrop(on: target, at: p) }
            drawing = item
            mode = .draw
        case .rect, .ellipse, .diamond:
            let kind: BoardItem.Kind = tool == .rect ? .rect : tool == .ellipse ? .ellipse : .diamond
            drawing = BoardItem(kind: kind, rect: CGRect(origin: p, size: .zero), color: color, width: strokeWidth)
            mode = .draw
        case .sticky, .text:
            if let id = topItem(at: p), let item = board.item(id), item.holdsText {
                select([id])
                beginEditing(id)
                return
            }
            var item: BoardItem
            if tool == .sticky {
                let size = BoardItem.stickySize
                item = BoardItem(kind: .sticky, rect: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), fill: color)
            } else {
                item = BoardItem(kind: .text, rect: CGRect(x: p.x, y: p.y - 20, width: 40, height: 40), color: color)
                item.fitText()
            }
            board.items.append(item)
            select([item.id])
            backToSelect = true
            beginEditing(item.id)
        case .image:
            insertImagesFromPicker(at: p)
        case .eraser:
            mode = .erase
            erase(at: p)
        }
    }

    private func selectDown(at p: CGPoint, screen s: CGPoint, event: NSEvent) {
        // 1. Ручки размера и концы стрелки у единственного выделенного.
        if selection.count == 1, let id = selection.first, let item = board.item(id) {
            if item.isConnector {
                let shape = item.connectorPath(in: board)
                let (a, b) = (shape.a, shape.b)
                if hypot(screen(a).x - s.x, screen(a).y - s.y) < 11 { mode = .endpoint(id: id, isStart: true); return }
                if hypot(screen(b).x - s.x, screen(b).y - s.y) < 11 { mode = .endpoint(id: id, isStart: false); return }
                let (aRef, bRef) = item.connectorRefs(in: board)
                let via = item.waypointPositions(aRef: aRef, bRef: bRef)
                if let index = via.firstIndex(where: { hypot(screen($0).x - s.x, screen($0).y - s.y) < 11 }) {
                    freezeAnchors(id)
                    guard let i = board.index(id) else { return }
                    board.items[i].adoptWaypoints(in: board)
                    if event.clickCount == 2 {
                        // Двойной клик - убрать точку.
                        board.items[i].waypoints?.remove(at: index)
                        if board.items[i].waypoints?.isEmpty == true { board.items[i].waypoints = nil }
                        endChange()
                        return
                    }
                    mode = .waypoint(id: id, index: index)
                    return
                }
                if let index = shape.ghosts.firstIndex(where: { hypot(screen($0).x - s.x, screen($0).y - s.y) < 10 }) {
                    // Потянули полупрозрачную точку - на этом участке появляется новая.
                    freezeAnchors(id)
                    guard let i = board.index(id) else { return }
                    board.items[i].adoptWaypoints(in: board)
                    let (ra, rb) = board.items[i].connectorRefs(in: board)
                    var list = board.items[i].waypoints ?? []
                    let at = min(index, list.count)
                    list.insert(BoardItem.relative(shape.ghosts[index], aRef: ra, bRef: rb), at: at)
                    board.items[i].waypoints = list
                    mode = .waypoint(id: id, index: at)
                    return
                }
            } else if let handle = handles(for: item).first(where: { hypot($0.point.x - s.x, $0.point.y - s.y) < 12 })?.handle {
                mode = .resize(id: id, handle: handle, original: item)
                return
            }
        }
        // 2. Точка-связь: тянем новую стрелку от предмета.
        for item in connectable() {
            guard let side = connectorDots(item).firstIndex(where: { hypot($0.x - s.x, $0.y - s.y) < 10 }) else { continue }
            var arrow = BoardItem(kind: .arrow, points: [item.center, p], color: color, width: max(strokeWidth, 3))
            arrow.start = item.id
            // Точка сверху, справа, снизу, слева - конец сидит ровно на середине этой стороны.
            arrow.startAnchor = [CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 0.5)][side]
            drawing = arrow
            mode = .draw
            hovered = nil
            return
        }
        // 3. Предмет.
        if let id = topItem(at: p) {
            if event.clickCount == 2, let item = board.item(id), item.holdsText {
                select([id])
                beginEditing(id)
                return
            }
            if event.modifierFlags.contains(.shift) {
                var next = selection
                if next.contains(id) { next.remove(id) } else { next.insert(id) }
                select(next)
            } else if !selection.contains(id) {
                select([id])
            }
            // С Option - тащим копию.
            if event.modifierFlags.contains(.option) { duplicateSelection(offset: .zero) }
            let originals = Dictionary(uniqueKeysWithValues: selection.compactMap { board.item($0) }.map { ($0.id, $0) })
            mode = .move(start: p, originals: originals)
            return
        }
        // 4. Пусто: рамка выделения.
        let base = event.modifierFlags.contains(.shift) ? selection : []
        if !event.modifierFlags.contains(.shift) { select([]) }
        mode = .marquee(start: p, current: p, base: base)
    }

    override func mouseDragged(with event: NSEvent) {
        let s = location(event)
        let p = world(s)
        switch mode {
        case let .pan(start, startOrigin):
            origin = CGPoint(x: startOrigin.x - (s.x - start.x) / zoom, y: startOrigin.y - (s.y - start.y) / zoom)
            viewChanged()
        case .draw:
            guard var item = drawing else { return }
            switch item.kind {
            case .pen, .marker:
                if let last = item.points.last, hypot(p.x - last.x, p.y - last.y) < 2 / zoom { return }
                item.points.append(CGPoint(x: (p.x * 10).rounded() / 10, y: (p.y * 10).rounded() / 10))
            case .line, .arrow:
                var end = p
                if event.modifierFlags.contains(.shift) {
                    let a = item.points[0]
                    let angle = (atan2(p.y - a.y, p.x - a.x) / (.pi / 4)).rounded() * (.pi / 4)
                    let length = hypot(p.x - a.x, p.y - a.y)
                    end = CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
                }
                item.points[1] = end
                dropTarget = topItem(at: p, excluding: Set([item.start].compactMap { $0 }), boxesOnly: true)
                updateDropPreview(at: p)
            default:
                let a = item.rect.origin
                var size = CGSize(width: p.x - a.x, height: p.y - a.y)
                if event.modifierFlags.contains(.shift) {
                    let side = max(abs(size.width), abs(size.height))
                    size = CGSize(width: side * (size.width < 0 ? -1 : 1), height: side * (size.height < 0 ? -1 : 1))
                }
                item.rect.size = size
            }
            drawing = item
            needsDisplay = true
        case let .move(start, originals):
            var delta = CGPoint(x: p.x - start.x, y: p.y - start.y)
            delta = snap(delta, originals: originals, disabled: event.modifierFlags.contains(.command))
            for (id, original) in originals {
                guard let i = board.index(id) else { continue }
                var moved = original
                moved.move(by: delta)
                board.items[i] = moved
            }
            needsDisplay = true
        case let .resize(id, handle, original):
            guard let i = board.index(id) else { return }
            board.items[i] = resized(original, handle: handle, to: p, keepAspect: event.modifierFlags.contains(.shift) || original.kind == .image)
            positionEditor()
            needsDisplay = true
        case let .endpoint(id, isStart):
            guard let i = board.index(id) else { return }
            freezeAnchors(id)
            var item = board.items[i]
            let (a, b) = item.endpoints(in: board)
            item.points = [a, b]
            if isStart { item.points[0] = p; item.start = nil; item.startAnchor = nil } else { item.points[1] = p; item.end = nil; item.endAnchor = nil }
            board.items[i] = item
            let other = isStart ? item.end : item.start
            dropTarget = topItem(at: p, excluding: Set([id] + [other].compactMap { $0 }), boxesOnly: true)
            updateDropPreview(at: p)
            needsDisplay = true
        case let .waypoint(id, index):
            guard let i = board.index(id), var list = board.items[i].waypoints, index < list.count else { return }
            let (aRef, bRef) = board.items[i].connectorRefs(in: board)
            var target = p
            // Подравниваем по соседям - ровные горизонтали и вертикали (особенно у угловой).
            let neighbours = [index > 0 ? BoardItem.world(list[index - 1], aRef: aRef, bRef: bRef) : board.items[i].connectorPath(in: board).a,
                              index + 1 < list.count ? BoardItem.world(list[index + 1], aRef: aRef, bRef: bRef) : board.items[i].connectorPath(in: board).b]
            let threshold = 8 / zoom
            guides = []
            if !event.modifierFlags.contains(.command) {
                if let n = neighbours.min(by: { abs($0.x - p.x) < abs($1.x - p.x) }), abs(n.x - p.x) < threshold {
                    target.x = n.x
                    guides.append((CGPoint(x: n.x, y: min(n.y, p.y) - 30), CGPoint(x: n.x, y: max(n.y, p.y) + 30)))
                }
                if let n = neighbours.min(by: { abs($0.y - p.y) < abs($1.y - p.y) }), abs(n.y - p.y) < threshold {
                    target.y = n.y
                    guides.append((CGPoint(x: min(n.x, p.x) - 30, y: n.y), CGPoint(x: max(n.x, p.x) + 30, y: n.y)))
                }
            }
            list[index] = BoardItem.relative(target, aRef: aRef, bRef: bRef)
            board.items[i].waypoints = list
            needsDisplay = true
        case let .marquee(start, _, base):
            mode = .marquee(start: start, current: p, base: base)
            let r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(start.x - p.x), height: abs(start.y - p.y))
            let inside = board.items.filter { r.intersects($0.bounds(in: board)) }.map(\.id)
            selection = base.union(inside)
            needsDisplay = true
        case .erase:
            erase(at: p)
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mode = .none
            dropTarget = nil
            dropAnchor = nil
            guides = []
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
        switch mode {
        case .pan:
            return
        case .draw:
            guard var item = drawing else { return }
            drawing = nil
            switch item.kind {
            case .line, .arrow:
                item.end = dropTarget
                if let id = dropTarget, let target = board.item(id) {
                    item.endAnchor = anchorForDrop(on: target, at: world(location(event)))
                }
                let (a, b) = item.endpoints(in: Board(id: board.id, items: board.items + [item]))
                // Короткий щелчок без привязки - ничего не рисуем.
                if hypot(b.x - a.x, b.y - a.y) < 6 / zoom, item.end == nil { snapshot = nil; return }
            case .rect, .ellipse, .diamond:
                item.rect = item.rect.standardized
                if item.rect.width < 6 / zoom && item.rect.height < 6 / zoom {
                    // Щелчок - фигура стандартного размера.
                    item.rect = CGRect(x: item.rect.minX - 80, y: item.rect.minY - 55, width: 160, height: 110)
                }
            default:
                break
            }
            board.items.append(item)
            if item.isConnector || item.isShape {
                select([item.id])
                finishPlacing()
            }
        case let .endpoint(id, isStart):
            if let i = board.index(id), let target = dropTarget, let item = board.item(target) {
                // Конец прилипает туда, куда его отпустили.
                let anchor = anchorForDrop(on: item, at: world(location(event)))
                if isStart { board.items[i].start = target; board.items[i].startAnchor = anchor } else { board.items[i].end = target; board.items[i].endAnchor = anchor }
            }
        case .resize, .move, .erase, .marquee, .waypoint:
            break
        case .none:
            break
        }
        endChange()
        notifySelection()
    }

    override func rightMouseDown(with event: NSEvent) {
        let p = world(location(event))
        if let id = topItem(at: p), !selection.contains(id) { select([id]) }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "", enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }
        let has = !selection.isEmpty
        add("Вырезать", #selector(cutAction), "x", enabled: has)
        add("Скопировать", #selector(copyAction), "c", enabled: has)
        add("Вставить", #selector(pasteAction), "v")
        add("Дублировать", #selector(duplicateAction), "d", enabled: has)
        menu.addItem(.separator())
        add("На передний план", #selector(frontAction), "]", enabled: has)
        add("На задний план", #selector(backAction), "[", enabled: has)
        menu.addItem(.separator())
        add("Выделить всё", #selector(selectAllAction), "a")
        add("Удалить", #selector(deleteAction), enabled: has)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func otherMouseDown(with event: NSEvent) {
        mode = .pan(screen: location(event), origin: origin)
    }

    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mode = .none }

    // MARK: перетаскивание, размеры, ластик

    /// Направляющие: края и центры выделения прилипают к краям и центрам других предметов.
    private func snap(_ delta: CGPoint, originals: [String: BoardItem], disabled: Bool) -> CGPoint {
        guides = []
        guard !disabled, let first = originals.values.first else { return delta }
        var moving = originals.values.dropFirst().reduce(first.bounds(in: board)) { $0.union($1.bounds(in: board)) }
        moving = moving.offsetBy(dx: delta.x, dy: delta.y)
        let others = board.items.filter { originals[$0.id] == nil && !$0.isConnector }.map { $0.bounds(in: board) }
        let threshold = 6 / zoom
        var result = delta
        var bestX: (CGFloat, CGFloat, CGRect)?
        var bestY: (CGFloat, CGFloat, CGRect)?
        for other in others {
            for mx in [moving.minX, moving.midX, moving.maxX] {
                for ox in [other.minX, other.midX, other.maxX] where abs(ox - mx) < threshold && abs(ox - mx) < abs(bestX?.0 ?? .infinity) {
                    bestX = (ox - mx, ox, other)
                }
            }
            for my in [moving.minY, moving.midY, moving.maxY] {
                for oy in [other.minY, other.midY, other.maxY] where abs(oy - my) < threshold && abs(oy - my) < abs(bestY?.0 ?? .infinity) {
                    bestY = (oy - my, oy, other)
                }
            }
        }
        if let (dx, x, other) = bestX {
            result.x += dx
            let moved = moving.offsetBy(dx: dx, dy: 0)
            guides.append((CGPoint(x: x, y: min(moved.minY, other.minY) - 20), CGPoint(x: x, y: max(moved.maxY, other.maxY) + 20)))
        }
        if let (dy, y, other) = bestY {
            result.y += dy
            let moved = moving.offsetBy(dx: 0, dy: dy)
            guides.append((CGPoint(x: min(moved.minX, other.minX) - 20, y: y), CGPoint(x: max(moved.maxX, other.maxX) + 20, y: y)))
        }
        return result
    }

    private func resized(_ original: BoardItem, handle: Handle, to p: CGPoint, keepAspect: Bool) -> BoardItem {
        var item = original
        let r = original.isStroke ? original.strokeBounds : original.rect.standardized
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch handle {
        case .topLeft: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        }
        let minimum: CGFloat = original.isStroke ? 4 : 24
        var nr = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: max(abs(maxX - minX), minimum), height: max(abs(maxY - minY), minimum))
        let corner = [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle)
        if keepAspect, corner, r.width > 0, r.height > 0 {
            let scale = max(nr.width / r.width, nr.height / r.height)
            let size = CGSize(width: r.width * scale, height: r.height * scale)
            let anchorX = handle == .topLeft || handle == .bottomLeft ? r.maxX : r.minX
            let anchorY = handle == .topLeft || handle == .topRight ? r.maxY : r.minY
            nr = CGRect(x: anchorX == r.maxX ? anchorX - size.width : anchorX, y: anchorY == r.maxY ? anchorY - size.height : anchorY,
                        width: size.width, height: size.height)
        }
        if original.isStroke {
            let sx = r.width > 0 ? nr.width / r.width : 1, sy = r.height > 0 ? nr.height / r.height : 1
            item.points = original.points.map { CGPoint(x: nr.minX + ($0.x - r.minX) * sx, y: nr.minY + ($0.y - r.minY) * sy) }
        } else {
            item.rect = nr
            if item.kind == .text {
                item.fixedWidth = true
                item.fitText()
            }
            if item.kind == .sticky { item.fitText() }
        }
        return item
    }

    /// Отпустили конец над предметом: у края - закрепляем в этой точке (у середины стороны - на ней),
    /// в глубине предмета - «плавающий» конец, сам выбирает лучшую сторону.
    private func anchorForDrop(on item: BoardItem, at p: CGPoint) -> CGPoint? {
        let r = item.rect.standardized
        let edgeZone = min(28 / zoom, min(r.width, r.height) / 3)
        let inner = r.insetBy(dx: edgeZone, dy: edgeZone)
        if !inner.isEmpty, inner.contains(p) { return nil }
        return BoardItem.anchor(of: item, near: p, snap: 18 / zoom)
    }

    private func updateDropPreview(at p: CGPoint) {
        guard let id = dropTarget, let item = board.item(id) else { dropAnchor = nil; return }
        dropAnchor = anchorForDrop(on: item, at: p).map { BoardItem.anchoredPoint(item, $0, gap: 0) }
    }

    /// Старая стрелка без запомненных мест касания: запоминаем текущие, чтобы концы больше не ездили.
    private func freezeAnchors(_ id: String) {
        guard let i = board.index(id), board.items[i].isConnector else { return }
        let shape = board.items[i].connectorPath(in: board)
        if board.items[i].startAnchor == nil, let s = board.items[i].start, let item = board.item(s) {
            board.items[i].startAnchor = BoardItem.anchor(of: item, near: shape.a, snap: 0)
        }
        if board.items[i].endAnchor == nil, let e = board.items[i].end, let item = board.item(e) {
            board.items[i].endAnchor = BoardItem.anchor(of: item, near: shape.b, snap: 0)
        }
    }

    private func erase(at p: CGPoint) {
        let tolerance = 10 / zoom
        let hit = Set(board.items.filter { $0.hit(p, tolerance: tolerance, in: board) }.map(\.id))
        if !hit.isEmpty { remove(hit) }
    }

    /// Удалить предметы. Стрелки, привязанные к ним, остаются - их концы становятся свободными.
    private func remove(_ ids: Set<String>) {
        for i in board.items.indices where board.items[i].isConnector && !ids.contains(board.items[i].id) {
            let (a, b) = board.items[i].endpoints(in: board)
            if let s = board.items[i].start, ids.contains(s) { board.items[i].points[0] = a; board.items[i].start = nil; board.items[i].startAnchor = nil }
            if let e = board.items[i].end, ids.contains(e) { board.items[i].points[1] = b; board.items[i].end = nil; board.items[i].endAnchor = nil }
        }
        board.items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        needsDisplay = true
    }

    // MARK: выделение

    func select(_ ids: Set<String>) {
        selection = ids
        notifySelection()
    }

    /// Изменить выделенные предметы (из панели свойств) - одним шагом отмены.
    func updateSelection(_ body: (inout BoardItem) -> Void) {
        guard !selection.isEmpty else { return }
        beginChange()
        for i in board.items.indices where selection.contains(board.items[i].id) {
            body(&board.items[i])
            board.items[i].fitText()
        }
        positionEditor()
        endChange()
    }

    // MARK: команды

    func undo() {
        endEditing()
        guard let last = undoStack.popLast() else { return }
        redoStack.append(board)
        board = last
        changed()
    }

    func redo() {
        endEditing()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(board)
        board = next
        changed()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        beginChange()
        remove(selection)
        endChange()
    }

    func clearAll() {
        guard !board.items.isEmpty else { return }
        endEditing()
        beginChange()
        board.items.removeAll()
        selection = []
        endChange()
    }

    func bringToFront() { reorder(front: true) }
    func sendToBack() { reorder(front: false) }

    private func reorder(front: Bool) {
        guard !selection.isEmpty else { return }
        beginChange()
        let moving = board.items.filter { selection.contains($0.id) }
        let rest = board.items.filter { !selection.contains($0.id) }
        board.items = front ? rest + moving : moving + rest
        endChange()
    }

    /// Копии выделенного; связи между копиями сохраняются.
    @discardableResult
    func duplicateSelection(offset: CGPoint = CGPoint(x: 24, y: 24)) -> Set<String> {
        let items = board.items.filter { selection.contains($0.id) }
        guard !items.isEmpty else { return [] }
        let copies = Self.cloned(items, offset: offset)
        board.items += copies
        let ids = Set(copies.map(\.id))
        selection = ids
        return ids
    }

    private static func cloned(_ items: [BoardItem], offset: CGPoint) -> [BoardItem] {
        var map: [String: String] = [:]
        for item in items { map[item.id] = Board.newID() }
        return items.map { item in
            var copy = item
            copy.id = map[item.id]!
            copy.move(by: offset)
            if copy.isConnector {
                // Привязка к предмету вне копии - конец становится свободным.
                copy.start = item.start.flatMap { map[$0] }
                copy.end = item.end.flatMap { map[$0] }
            }
            return copy
        }
    }

    func selectAll() { select(Set(board.items.map(\.id))) }

    func copySelection() {
        var items = board.items.filter { selection.contains($0.id) }
        guard !items.isEmpty else { return }
        // Свободные концы для стрелок, чей предмет не копируется.
        let ids = Set(items.map(\.id))
        for i in items.indices where items[i].isConnector {
            let (a, b) = items[i].endpoints(in: board)
            if let s = items[i].start, !ids.contains(s) { items[i].points[0] = a; items[i].start = nil }
            if let e = items[i].end, !ids.contains(e) { items[i].points[1] = b; items[i].end = nil }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let data = try? JSONEncoder().encode(items) { pasteboard.setData(data, forType: Self.pasteType) }
        let texts = items.map(\.text).filter { !$0.isEmpty }
        if !texts.isEmpty { pasteboard.setString(texts.joined(separator: "\n"), forType: .string) }
    }

    func paste() {
        let pasteboard = NSPasteboard.general
        let center = world(CGPoint(x: bounds.midX, y: bounds.midY))
        beginChange()
        defer { endChange() }
        if let data = pasteboard.data(forType: Self.pasteType), let items = try? JSONDecoder().decode([BoardItem].self, from: data), !items.isEmpty {
            let box = items.dropFirst().reduce(items[0].bounds(in: board)) { $0.union($1.bounds(in: board)) }
            let copies = Self.cloned(items, offset: CGPoint(x: center.x - box.midX + 20, y: center.y - box.midY + 20))
            board.items += copies
            select(Set(copies.map(\.id)))
            return
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL], !urls.isEmpty {
            addImages(urls, at: center)
            return
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Картинка.png")
            if (try? png.write(to: temp)) != nil { addImages([temp], at: center) }
            return
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            var item = BoardItem(kind: .text, rect: CGRect(x: center.x - 100, y: center.y - 20, width: 200, height: 40), color: color, text: string)
            item.fitText()
            board.items.append(item)
            select([item.id])
        }
    }

    @objc private func cutAction() { copySelection(); deleteSelection() }
    @objc private func copyAction() { copySelection() }
    @objc private func pasteAction() { paste() }
    @objc private func duplicateAction() { duplicate() }

    func duplicate() {
        beginChange()
        duplicateSelection()
        endChange()
    }
    @objc private func frontAction() { bringToFront() }
    @objc private func backAction() { sendToBack() }
    @objc private func selectAllAction() { selectAll() }
    @objc private func deleteAction() { deleteSelection() }

    // MARK: картинки

    private func insertImagesFromPicker(at p: CGPoint) {
        let urls = Assets.pick(images: true, multiple: true)
        guard !urls.isEmpty else { snapshot = nil; return }
        addImages(urls, at: p)
        endChange()
        finishPlacing()
    }

    /// Поставили фигуру, стрелку, стикер или картинку - обратно к выбору, чтобы сразу двигать и тянуть.
    /// С замочком инструмент остаётся (ставить много одинаковых подряд).
    private func finishPlacing() {
        guard controller?.toolLocked != true else { return }
        controller?.tool = .select
    }

    private func addImages(_ urls: [URL], at p: CGPoint) {
        var ids: Set<String> = []
        for (n, url) in urls.enumerated() {
            guard let name = Assets.store(url), let picture = Assets.image(name) else { continue }
            let longest = max(picture.size.width, picture.size.height, 1)
            let scale = min(1, 420 / longest)
            let size = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
            var item = BoardItem(kind: .image, rect: CGRect(x: p.x - size.width / 2 + CGFloat(n) * 30, y: p.y - size.height / 2 + CGFloat(n) * 30,
                                                           width: size.width, height: size.height))
            item.image = name
            board.items.append(item)
            ids.insert(item.id)
        }
        if !ids.isEmpty { select(ids) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]])
            || NSImage.canInit(with: sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let p = world(convert(sender.draggingLocation, from: nil))
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        beginChange()
        addImages(urls, at: p)
        endChange()
        return true
    }

    // MARK: клавиатура

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 6: shift ? redo() : undo()                       // Z
        case 16: redo()                                       // Y
        case 0: selectAll()                                   // A
        case 2: duplicateAction()                             // D
        case 8: copySelection()                               // C
        case 7: cutAction()                                   // X
        case 9: paste()                                       // V
        case 24, 69: setZoom(zoom * 1.25)                     // =
        case 27, 78: setZoom(zoom / 1.25)                     // -
        case 29: fitContent()                                 // 0
        case 18: setZoom(1)                                   // 1
        case 30: bringToFront()                               // ]
        case 33: sendToBack()                                 // [
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 51, 117:
            deleteSelection()
            return
        case 53:
            if !selection.isEmpty { select([]) } else { controller?.tool = .select }
            return
        case 49:
            if !spaceHeld { spaceHeld = true; window?.invalidateCursorRects(for: self); NSCursor.openHand.set() }
            return
        case 36, 76:
            if selection.count == 1, let id = selection.first, board.item(id)?.holdsText == true { beginEditing(id) }
            return
        case 123, 124, 125, 126:
            guard !selection.isEmpty else { return }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let d: CGPoint = switch event.keyCode {
            case 123: CGPoint(x: -step, y: 0)
            case 124: CGPoint(x: step, y: 0)
            case 125: CGPoint(x: 0, y: step)
            default: CGPoint(x: 0, y: -step)
            }
            beginChange()
            for i in board.items.indices where selection.contains(board.items[i].id) { board.items[i].move(by: d) }
            endChange()
            return
        default:
            break
        }
        if flags.isEmpty, event.keyCode == 12 { // Q - замочек инструмента
            controller?.toolLocked.toggle()
            return
        }
        if flags.isEmpty, let tool = BoardTool.allCases.first(where: { $0.keyCode == event.keyCode }) {
            controller?.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = false
            window?.invalidateCursorRects(for: self)
            return
        }
        super.keyUp(with: event)
    }

    // MARK: текст в стикерах, фигурах и надписях

    func beginEditing(_ id: String) {
        guard let item = board.item(id), item.holdsText else { return }
        endEditing()
        if snapshot == nil { beginChange() }
        editingID = id
        let text = NSTextView(frame: .zero)
        text.drawsBackground = false
        text.isRichText = false
        text.allowsUndo = true
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.delegate = self
        let attrs = item.textAttributes(scale: zoom)
        text.typingAttributes = attrs
        text.defaultParagraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        text.textStorage?.setAttributedString(NSAttributedString(string: item.text, attributes: attrs))
        text.insertionPointColor = item.textColor
        addSubview(text)
        editor = text
        positionEditor()
        window?.makeFirstResponder(text)
        text.selectAll(nil)
        needsDisplay = true
    }

    private func positionEditor() {
        guard let editor, let id = editingID, let item = board.item(id) else { return }
        let box = item.kind == .text && item.fixedWidth != true
            ? CGRect(x: item.textBox.minX, y: item.textBox.minY, width: 700, height: item.textBox.height)
            : item.isShape ? item.textFrame : item.textBox
        let r = screen(box)
        editor.frame = NSRect(x: r.minX, y: r.minY, width: max(r.width, 20), height: max(r.height, 24 * zoom))
        editor.textContainer?.containerSize = NSSize(width: max(r.width, 20), height: .greatestFiniteMagnitude)
        let attrs = item.textAttributes(scale: zoom)
        if let font = attrs[.font] as? NSFont, editor.font?.pointSize != font.pointSize {
            editor.textStorage?.addAttributes(attrs, range: NSRange(location: 0, length: editor.textStorage?.length ?? 0))
            editor.typingAttributes = attrs
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let editor, let id = editingID, let i = board.index(id) else { return }
        board.items[i].text = editor.string
        board.items[i].fitText()
        positionEditor()
        needsDisplay = true
        controller?.boardChanged(board)
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // Esc в поле текста приходит как «дополнить слово» - считаем это «готово».
        if selector == #selector(cancelOperation(_:)) || selector == #selector(NSResponder.complete(_:)) {
            endEditing()
            return true
        }
        return false
    }

    func textDidEndEditing(_ notification: Notification) { endEditing() }

    func endEditing() {
        guard let editor, let id = editingID else { return }
        self.editor = nil
        editingID = nil
        editor.removeFromSuperview()
        if let i = board.index(id) {
            board.items[i].text = editor.string
            board.items[i].fitText()
            // Пустая надпись не нужна; пустой стикер или фигура остаются.
            if board.items[i].kind == .text, editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                remove([id])
            }
        }
        endChange()
        window?.makeFirstResponder(self)
        needsDisplay = true
        if backToSelect {
            backToSelect = false
            finishPlacing()
        }
    }

    /// Закрытие окна: дописанный текст сохраняется.
    func finish() -> Board {
        endEditing()
        return board
    }
}

private extension Board {
    init(id: String, items: [BoardItem]) {
        self.init()
        self.id = id
        self.items = items
    }
}
