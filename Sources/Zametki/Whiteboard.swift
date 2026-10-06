import AppKit

// MARK: - доска: модель

/// Доска (whiteboard): бесконечный холст с рисунками, фигурами, стикерами, надписями, картинками
/// и стрелками-связями. Хранится в тексте заметки JSON-строкой; координаты - мировые, без границ.
struct Whiteboard: Codable, Equatable {
    /// Пропорции превью в тексте заметки.
    static let previewAspect: CGFloat = 16.0 / 9.0

    /// Постоянный номер доски: по нему окно доски находит её в заметке, даже если текст вокруг поменялся.
    var id: String = Whiteboard.newID()
    var items: [BoardItem] = []

    static func newID() -> String { String(UUID().uuidString.prefix(8)).lowercased() }

    var json: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "{\"items\":[]}"
    }

    init() {}

    init(json: String) {
        self = (try? JSONDecoder().decode(Whiteboard.self, from: Data(json.utf8))) ?? Whiteboard()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Whiteboard.newID()
        // Испорченный предмет пропускаем, а не теряем всю доску.
        var items: [BoardItem] = []
        if var list = try? c.nestedUnkeyedContainer(forKey: .items) {
            while !list.isAtEnd {
                if let item = try? list.decode(BoardItem.self) {
                    items.append(item)
                } else if (try? list.decode(Skip.self)) == nil {
                    break
                }
            }
        }
        self.items = items
    }

    private struct Skip: Decodable {}

    func item(_ id: String) -> BoardItem? { items.first { $0.id == id } }
    func index(_ id: String) -> Int? { items.firstIndex { $0.id == id } }

    /// Рамка всего нарисованного; nil - доска пустая.
    var contentBounds: CGRect? {
        guard let first = items.first else { return nil }
        return items.dropFirst().reduce(first.bounds(in: self)) { $0.union($1.bounds(in: self)) }
    }

    /// Что показать в превью: всё нарисованное с полями, в пропорциях превью.
    var previewViewport: CGRect {
        let aspect = Whiteboard.previewAspect
        guard var box = contentBounds else { return CGRect(x: 0, y: 0, width: 1600, height: 900) }
        box = box.insetBy(dx: -60, dy: -60)
        // Одна маленькая закорючка не должна раздуться на весь блок.
        let width = max(box.width, box.height * aspect, 900)
        let height = width / aspect
        return CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }

    /// Нарисовать часть доски (viewport, мировые координаты) в прямоугольник на экране. Контекст перевёрнут (y вниз).
    func draw(viewport: CGRect, in rect: NSRect, hiding hidden: String? = nil) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let scale = rect.width / viewport.width
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX - viewport.minX * scale, yBy: rect.minY - viewport.minY * scale)
        transform.scale(by: scale)
        transform.concat()
        for item in items { item.draw(in: self, hidingText: item.id == hidden) }
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct BoardItem: Codable, Equatable {
    enum Kind: String, Codable { case pen, marker, line, arrow, rect, ellipse, diamond, sticky, text, image }
    enum Dash: String, Codable, CaseIterable { case solid, dashed, dotted }
    enum Heads: String, Codable, CaseIterable { case none, end, both }
    /// Форма стрелки: прямая, кривая (с изгибом) или угловая - под прямым углом, как в блок-схемах.
    enum Route: String, Codable, CaseIterable { case straight, curved, elbow }

    var id: String = Whiteboard.newID()
    var kind: Kind
    /// Точки: штрих карандаша или два конца линии/стрелки (если конец не привязан к предмету).
    var points: [CGPoint] = []
    /// Рамка фигуры, стикера, надписи, картинки.
    var rect: CGRect = .zero
    /// Цвет линии и текста (id из TextColor).
    var color: String = "white"
    /// Заливка фигуры или цвет стикера; nil у фигуры - без заливки.
    var fill: String?
    var width: CGFloat = 4
    var dash: Dash = .solid
    var heads: Heads?
    var route: Route?
    /// Изгиб кривой стрелки: насколько середина отходит в сторону от прямой (мировые единицы, со знаком).
    var bend: CGFloat?
    /// Где середина кривой стрелки - в долях её длины: x - вдоль стрелки, y - поперёк.
    /// Так изгиб тянется в любую сторону и растягивается вместе со стрелкой.
    var curve: CGPoint?
    /// Дополнительные точки стрелки (изломы и изгибы) - относительно самой стрелки:
    /// x - доля пути от начала к концу, y - отход в сторону в долях длины. Так точки едут вместе со стрелкой.
    var waypoints: [CGPoint]?
    var text: String = ""
    var fontSize: CGFloat?
    /// Стрелка-связь: к каким предметам привязаны начало и конец.
    var start: String?
    var end: String?
    /// Где именно на краю предмета сидит конец стрелки - доля ширины и высоты его рамки (0…1).
    /// Задаётся, когда стрелку прицепили, и дальше не меняется: изгиб и перемещение его не трогают.
    var startAnchor: CGPoint?
    var endAnchor: CGPoint?
    /// Картинка - имя файла в папке вложений.
    var image: String?
    /// Ширину надписи задали руками - текст переносится по ней.
    var fixedWidth: Bool?

    init(kind: Kind, points: [CGPoint] = [], rect: CGRect = .zero, color: String = "white", fill: String? = nil,
         width: CGFloat = 4, text: String = "") {
        self.kind = kind
        self.points = points
        self.rect = rect
        self.color = color
        self.fill = fill
        self.width = width
        self.text = text
    }

    /// Чтение с запасом: отсутствующие поля - по умолчанию (старые доски, будущие версии).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Whiteboard.newID()
        points = try c.decodeIfPresent([CGPoint].self, forKey: .points) ?? []
        rect = try c.decodeIfPresent(CGRect.self, forKey: .rect) ?? .zero
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "white"
        fill = try c.decodeIfPresent(String.self, forKey: .fill)
        width = try c.decodeIfPresent(CGFloat.self, forKey: .width) ?? 4
        dash = (try? c.decodeIfPresent(Dash.self, forKey: .dash)) ?? .solid
        heads = (try? c.decodeIfPresent(Heads.self, forKey: .heads)) ?? nil
        route = (try? c.decodeIfPresent(Route.self, forKey: .route)) ?? nil
        bend = try c.decodeIfPresent(CGFloat.self, forKey: .bend)
        curve = try c.decodeIfPresent(CGPoint.self, forKey: .curve)
        waypoints = try c.decodeIfPresent([CGPoint].self, forKey: .waypoints)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize)
        start = try c.decodeIfPresent(String.self, forKey: .start)
        end = try c.decodeIfPresent(String.self, forKey: .end)
        startAnchor = try c.decodeIfPresent(CGPoint.self, forKey: .startAnchor)
        endAnchor = try c.decodeIfPresent(CGPoint.self, forKey: .endAnchor)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        fixedWidth = try c.decodeIfPresent(Bool.self, forKey: .fixedWidth)
        // Первые доски хранили цвет стикера в color.
        if kind == .sticky, fill == nil { fill = color }
        if isConnector {
            while points.count < 2 { points.append(points.last ?? .zero) }
        }
        fitText()
    }

    static let stickySize = CGSize(width: 240, height: 180)

    // MARK: что это за предмет

    var isStroke: Bool { kind == .pen || kind == .marker }
    var isConnector: Bool { kind == .line || kind == .arrow }
    var isShape: Bool { [.rect, .ellipse, .diamond].contains(kind) }
    /// Предметы с рамкой: их можно растягивать и связывать стрелками.
    var isBox: Bool { !isStroke && !isConnector }
    var holdsText: Bool { isShape || kind == .sticky || kind == .text }
    var hasStroke: Bool { isStroke || isConnector || isShape }

    var effectiveHeads: Heads { heads ?? (kind == .arrow ? .end : .none) }

    var defaultFontSize: CGFloat { kind == .text ? 32 : 22 }
    var effectiveFontSize: CGFloat { fontSize ?? defaultFontSize }

    var ink: NSColor { (TextColor(rawValue: color) ?? .white).color }

    static func pastel(_ id: String?) -> NSColor {
        switch id {
        case "pink", "coral", "peach": NSColor(srgbRed: 1, green: 0.76, blue: 0.86, alpha: 1)
        case "green", "mint": NSColor(srgbRed: 0.74, green: 0.94, blue: 0.78, alpha: 1)
        case "sky", "blue": NSColor(srgbRed: 0.72, green: 0.86, blue: 1, alpha: 1)
        case "lavender": NSColor(srgbRed: 0.86, green: 0.80, blue: 1, alpha: 1)
        case "orange": NSColor(srgbRed: 1, green: 0.83, blue: 0.64, alpha: 1)
        case "white", "gray": NSColor(white: 0.95, alpha: 1)
        default: NSColor(srgbRed: 1, green: 0.92, blue: 0.55, alpha: 1)
        }
    }

    var fillColor: NSColor? {
        if kind == .sticky { return Self.pastel(fill) }
        guard let fill, let color = TextColor(rawValue: fill)?.color else { return nil }
        return color.withAlphaComponent(0.32)
    }

    var textColor: NSColor { kind == .sticky ? NSColor(white: 0.12, alpha: 1) : ink }

    var center: CGPoint { CGPoint(x: rect.standardized.midX, y: rect.standardized.midY) }

    // MARK: текст

    static func font(_ size: CGFloat) -> NSFont {
        let style = PageStyle.current
        return style.font(style.font == .hand ? size * 1.3 : size, weight: 600)
    }

    func textAttributes(scale: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        if isShape { paragraph.alignment = .center }
        return [.font: Self.font(effectiveFontSize * scale), .foregroundColor: textColor, .paragraphStyle: paragraph]
    }

    /// Где внутри рамки живёт текст.
    var textBox: CGRect {
        let r = rect.standardized
        switch kind {
        case .sticky: return r.insetBy(dx: 16, dy: 14)
        case .text: return r.insetBy(dx: 4, dy: 2)
        case .diamond: return r.insetBy(dx: r.width * 0.2, dy: r.height * 0.2)
        case .ellipse: return r.insetBy(dx: r.width * 0.12, dy: r.height * 0.12)
        default: return r.insetBy(dx: 12, dy: 10)
        }
    }

    func textSize(width: CGFloat) -> CGSize {
        let measured = NSAttributedString(string: text.isEmpty ? "Текст" : text, attributes: textAttributes())
            .boundingRect(with: NSSize(width: width, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(measured.width), height: ceil(measured.height))
    }

    /// Надпись подстраивается под свой текст; стикер растёт вниз, если текст не влезает.
    mutating func fitText() {
        switch kind {
        case .text:
            if fixedWidth == true {
                rect.size.height = textSize(width: max(rect.width - 8, 20)).height + 6
            } else {
                let size = textSize(width: 700)
                rect.size = CGSize(width: max(size.width + 10, 40), height: size.height + 6)
            }
        case .sticky:
            let needed = textSize(width: max(rect.width - 32, 20)).height + 30
            if needed > rect.height { rect.size.height = needed }
        default:
            break
        }
    }

    // MARK: геометрия

    /// Концы линии: привязанный конец сидит на краю своего предмета.
    func endpoints(in board: Whiteboard) -> (CGPoint, CGPoint) {
        let path = connectorPath(in: board)
        return (path.a, path.b)
    }

    var effectiveRoute: Route { route ?? .straight }

    /// Центры (или свободные концы), между которыми идёт стрелка, - от них считается изгиб.
    func connectorRefs(in board: Whiteboard) -> (CGPoint, CGPoint) {
        let a0 = points.first ?? .zero
        let b0 = points.count > 1 ? points[1] : a0
        let from = start.flatMap { board.item($0) }, to = end.flatMap { board.item($0) }
        let a = from.map { item in startAnchor.map { Self.anchoredPoint(item, $0) } ?? item.center } ?? a0
        let b = to.map { item in endAnchor.map { Self.anchoredPoint(item, $0) } ?? item.center } ?? b0
        return (a, b)
    }

    /// Точка на краю предмета по сохранённой доле, чуть наружу - чтобы наконечник не утыкался в край.
    static func anchoredPoint(_ item: BoardItem, _ anchor: CGPoint, gap: CGFloat = 7) -> CGPoint {
        let r = item.rect.standardized
        let p = CGPoint(x: r.minX + anchor.x * r.width, y: r.minY + anchor.y * r.height)
        let c = item.center
        // Наружу - по нормали к стороне (у прямоугольников) или от центра (у овала и ромба).
        var n: CGPoint
        if item.kind == .ellipse || item.kind == .diamond {
            n = CGPoint(x: p.x - c.x, y: p.y - c.y)
        } else {
            let dl = abs(anchor.x), dr = abs(1 - anchor.x), dt = abs(anchor.y), db = abs(1 - anchor.y)
            let m = min(dl, dr, dt, db)
            n = m == dl ? CGPoint(x: -1, y: 0) : m == dr ? CGPoint(x: 1, y: 0) : m == dt ? CGPoint(x: 0, y: -1) : CGPoint(x: 0, y: 1)
        }
        let length = max(hypot(n.x, n.y), 0.001)
        return CGPoint(x: p.x + n.x / length * gap, y: p.y + n.y / length * gap)
    }

    /// Ближайшая к точке p точка края предмета (доля рамки). У серединок сторон - прилипает к ним.
    static func anchor(of item: BoardItem, near p: CGPoint, snap: CGFloat) -> CGPoint {
        let r = item.rect.standardized
        guard r.width > 0, r.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        var q: CGPoint
        if item.kind == .ellipse || item.kind == .diamond {
            q = edgePoint(of: item, toward: p, gap: 0)
        } else {
            let cx = min(max(p.x, r.minX), r.maxX), cy = min(max(p.y, r.minY), r.maxY)
            let dl = cx - r.minX, dr = r.maxX - cx, dt = cy - r.minY, db = r.maxY - cy
            let m = min(dl, dr, dt, db)
            q = m == dl ? CGPoint(x: r.minX, y: cy) : m == dr ? CGPoint(x: r.maxX, y: cy) : m == dt ? CGPoint(x: cx, y: r.minY) : CGPoint(x: cx, y: r.maxY)
        }
        let mids = [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
        if let mid = mids.min(by: { hypot($0.x - q.x, $0.y - q.y) < hypot($1.x - q.x, $1.y - q.y) }), hypot(mid.x - q.x, mid.y - q.y) < snap {
            q = mid
        }
        return CGPoint(x: (q.x - r.minX) / r.width, y: (q.y - r.minY) / r.height)
    }

    /// Форма стрелки: концы, изломы или кривые через дополнительные точки.
    func connectorPath(in board: Whiteboard) -> ConnectorPath {
        let a0 = points.first ?? .zero
        let b0 = points.count > 1 ? points[1] : a0
        let from = start.flatMap { board.item($0) }
        let to = end.flatMap { board.item($0) }
        let (aRef, bRef) = connectorRefs(in: board)
        let via = waypointPositions(aRef: aRef, bRef: bRef)
        // Прицепленные концы с сохранённым местом стоят ровно там, что бы ни происходило с точками.
        let fixedA = from.flatMap { item in startAnchor.map { Self.anchoredPoint(item, $0) } }
        let fixedB = to.flatMap { item in endAnchor.map { Self.anchoredPoint(item, $0) } }

        switch effectiveRoute {
        case .elbow:
            // Угловая: каждый конец выходит наружу из своей стороны; маршрут обходит оба предмета и идёт через точки.
            let otherA = via.first ?? to.map { item in endAnchor.map { Self.anchoredPoint(item, $0, gap: 0) } ?? item.center } ?? b0
            let otherB = via.last ?? from.map { item in startAnchor.map { Self.anchoredPoint(item, $0, gap: 0) } ?? item.center } ?? a0
            let anchorA = from.map { startAnchor ?? Self.autoSide(of: $0, toward: otherA) }
            let anchorB = to.map { endAnchor ?? Self.autoSide(of: $0, toward: otherB) }
            let a = from.flatMap { item in anchorA.map { Self.anchoredPoint(item, $0, gap: 2) } } ?? a0
            let b = to.flatMap { item in anchorB.map { Self.anchoredPoint(item, $0, gap: 7) } } ?? b0
            let dirA = anchorA.map(Self.sideNormal), dirB = anchorB.map(Self.sideNormal)
            let rectA = from?.rect.standardized, rectB = to?.rect.standardized
            guard !via.isEmpty else {
                let route = Self.orthogonalRoute(a: a, dirA: dirA, rectA: rectA, b: b, dirB: dirB, rectB: rectB)
                return ConnectorPath(a: a, b: b, bends: route, ghosts: [Self.polylineMiddle([a] + route + [b])])
            }
            // Участки: от начала к первой точке, между точками, от последней к концу.
            var legs: [[CGPoint]] = []
            let firstBends = Self.orthogonalRoute(a: a, dirA: dirA, rectA: rectA, b: via[0], dirB: nil, rectB: nil)
            legs.append([a] + firstBends + [via[0]])
            for k in 1..<max(via.count, 1) where via.count > 1 {
                let p = via[k - 1], q = via[k]
                // Продолжаем в ту же сторону, куда шли - угол получается один.
                let prev = legs.last.map { $0.count > 1 ? $0[$0.count - 2] : p } ?? p
                let horizontal = abs(p.y - prev.y) < 0.5 ? true : abs(p.x - prev.x) < 0.5 ? false : abs(q.x - p.x) >= abs(q.y - p.y)
                let corner = horizontal ? CGPoint(x: q.x, y: p.y) : CGPoint(x: p.x, y: q.y)
                legs.append([p, corner, q])
            }
            let lastBends = Self.orthogonalRoute(a: via[via.count - 1], dirA: nil, rectA: nil, b: b, dirB: dirB, rectB: rectB)
            legs.append([via[via.count - 1]] + lastBends + [b])
            var all: [CGPoint] = []
            for leg in legs { all += all.isEmpty ? leg : Array(leg.dropFirst()) }
            let clean = Self.simplify(all)
            return ConnectorPath(a: a, b: b, bends: Array(clean.dropFirst().dropLast()), ghosts: legs.map { Self.polylineMiddle(Self.simplify($0)) })
        case .curved where !via.isEmpty:
            let a = fixedA ?? from.map { Self.edgePoint(of: $0, toward: via[0]) } ?? a0
            let b = fixedB ?? to.map { Self.edgePoint(of: $0, toward: via[via.count - 1]) } ?? b0
            // Плавная кривая через все точки; у предметов выходит из стороны под прямым углом.
            let nA = from.map { Self.outward(of: $0, at: a) } ?? .zero
            let nB = to.map { Self.outward(of: $0, at: b) } ?? .zero
            let all = [a] + via + [b]
            var tangents: [CGPoint] = []
            for k in all.indices {
                if k == 0 {
                    let d = hypot(all[1].x - all[0].x, all[1].y - all[0].y)
                    tangents.append(nA != .zero ? CGPoint(x: nA.x * d, y: nA.y * d) : CGPoint(x: all[1].x - all[0].x, y: all[1].y - all[0].y))
                } else if k == all.count - 1 {
                    let d = hypot(all[k].x - all[k - 1].x, all[k].y - all[k - 1].y)
                    tangents.append(nB != .zero ? CGPoint(x: -nB.x * d, y: -nB.y * d) : CGPoint(x: all[k].x - all[k - 1].x, y: all[k].y - all[k - 1].y))
                } else {
                    tangents.append(CGPoint(x: (all[k + 1].x - all[k - 1].x) / 2, y: (all[k + 1].y - all[k - 1].y) / 2))
                }
            }
            var segments: [CurveSegment] = []
            for k in 0..<all.count - 1 {
                let c1 = CGPoint(x: all[k].x + tangents[k].x / 3, y: all[k].y + tangents[k].y / 3)
                let c2 = CGPoint(x: all[k + 1].x - tangents[k + 1].x / 3, y: all[k + 1].y - tangents[k + 1].y / 3)
                segments.append(CurveSegment(start: all[k], c1: c1, c2: c2, end: all[k + 1]))
            }
            return ConnectorPath(a: a, b: b, curves: segments, ghosts: segments.map { $0.point(0.5) })
        default:
            if via.isEmpty {
                let a = fixedA ?? from.map { Self.edgePoint(of: $0, toward: bRef) } ?? a0
                let b = fixedB ?? to.map { Self.edgePoint(of: $0, toward: aRef) } ?? b0
                return ConnectorPath(a: a, b: b, ghosts: [CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)])
            }
            // Прямая с точками - ломаная.
            let a = fixedA ?? from.map { Self.edgePoint(of: $0, toward: via[0]) } ?? a0
            let b = fixedB ?? to.map { Self.edgePoint(of: $0, toward: via[via.count - 1]) } ?? b0
            let all = [a] + via + [b]
            let ghosts = (0..<all.count - 1).map { CGPoint(x: (all[$0].x + all[$0 + 1].x) / 2, y: (all[$0].y + all[$0 + 1].y) / 2) }
            return ConnectorPath(a: a, b: b, bends: via, ghosts: ghosts)
        }
    }

    /// Точки стрелки в мире. Первые кривые хранили один изгиб (curve или bend) - он становится точкой.
    func waypointPositions(aRef: CGPoint, bRef: CGPoint) -> [CGPoint] {
        let d = CGPoint(x: bRef.x - aRef.x, y: bRef.y - aRef.y)
        let length = max(hypot(d.x, d.y), 1)
        var relative = waypoints ?? []
        if waypoints == nil, effectiveRoute == .curved {
            if let curve { relative = [CGPoint(x: 0.5 + curve.x, y: curve.y)] } else if let bend { relative = [CGPoint(x: 0.5, y: bend / length)] }
        }
        return relative.map { Self.world($0, aRef: aRef, bRef: bRef) }
    }

    static func world(_ r: CGPoint, aRef: CGPoint, bRef: CGPoint) -> CGPoint {
        let d = CGPoint(x: bRef.x - aRef.x, y: bRef.y - aRef.y)
        let length = max(hypot(d.x, d.y), 1)
        let normal = CGPoint(x: -d.y / length, y: d.x / length)
        return CGPoint(x: aRef.x + d.x * r.x + normal.x * r.y * length, y: aRef.y + d.y * r.x + normal.y * r.y * length)
    }

    static func relative(_ p: CGPoint, aRef: CGPoint, bRef: CGPoint) -> CGPoint {
        let d = CGPoint(x: bRef.x - aRef.x, y: bRef.y - aRef.y)
        let length2 = max(d.x * d.x + d.y * d.y, 1)
        let length = sqrt(length2)
        let normal = CGPoint(x: -d.y / length, y: d.x / length)
        let v = CGPoint(x: p.x - aRef.x, y: p.y - aRef.y)
        return CGPoint(x: (v.x * d.x + v.y * d.y) / length2, y: (v.x * normal.x + v.y * normal.y) / length)
    }

    /// Перевести старый одиночный изгиб в точки - дальше работаем только с точками.
    mutating func adoptWaypoints(in board: Whiteboard) {
        guard waypoints == nil else { return }
        let (aRef, bRef) = connectorRefs(in: board)
        waypoints = waypointPositions(aRef: aRef, bRef: bRef).map { Self.relative($0, aRef: aRef, bRef: bRef) }
        curve = nil
        bend = nil
    }

    /// Середина ломаной по её длине.
    static func polylineMiddle(_ pts: [CGPoint]) -> CGPoint {
        let total = zip(pts, pts.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        var left = total / 2
        for (p, q) in zip(pts, pts.dropFirst()) {
            let d = hypot(q.x - p.x, q.y - p.y)
            if d >= left, d > 0 { return CGPoint(x: p.x + (q.x - p.x) * left / d, y: p.y + (q.y - p.y) * left / d) }
            left -= d
        }
        return pts.first ?? .zero
    }

    /// Направление «наружу» из предмета в точке на его краю: по нормали стороны (у прямоугольников)
    /// или от центра (у овала и ромба).
    static func outward(of item: BoardItem, at p: CGPoint) -> CGPoint {
        let r = item.rect.standardized
        guard r.width > 0, r.height > 0 else { return .zero }
        if item.kind == .ellipse || item.kind == .diamond {
            let d = CGPoint(x: p.x - r.midX, y: p.y - r.midY)
            let l = max(hypot(d.x, d.y), 0.001)
            return CGPoint(x: d.x / l, y: d.y / l)
        }
        return sideNormal(CGPoint(x: (p.x - r.minX) / r.width, y: (p.y - r.minY) / r.height))
    }

    /// Нормаль стороны, на которой лежит точка крепления (наружу, вдоль оси).
    static func sideNormal(_ anchor: CGPoint) -> CGPoint {
        let dl = anchor.x, dr = 1 - anchor.x, dt = anchor.y, db = 1 - anchor.y
        let m = min(dl, dr, dt, db)
        return m == dl ? CGPoint(x: -1, y: 0) : m == dr ? CGPoint(x: 1, y: 0) : m == dt ? CGPoint(x: 0, y: -1) : CGPoint(x: 0, y: 1)
    }

    /// «Плавающий» конец: середина той стороны, что смотрит на другой конец.
    static func autoSide(of item: BoardItem, toward target: CGPoint) -> CGPoint {
        let r = item.rect.standardized
        let dx = (target.x - r.midX) / max(r.width, 1), dy = (target.y - r.midY) / max(r.height, 1)
        if abs(dx) >= abs(dy) { return dx >= 0 ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0, y: 0.5) }
        return dy >= 0 ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 0.5, y: 0)
    }

    /// Маршрут угловой стрелки: изломы между концами. Перебираем несколько вариантов
    /// и берём самый короткий с наименьшим числом поворотов, который не режет предметы и не разворачивается назад.
    static func orthogonalRoute(a: CGPoint, dirA: CGPoint?, rectA: CGRect?, b: CGPoint, dirB: CGPoint?, rectB: CGRect?) -> [CGPoint] {
        let margin: CGFloat = 26
        let pA = dirA.map { CGPoint(x: a.x + $0.x * margin, y: a.y + $0.y * margin) } ?? a
        let pB = dirB.map { CGPoint(x: b.x + $0.x * margin, y: b.y + $0.y * margin) } ?? b
        let midX = (pA.x + pB.x) / 2, midY = (pA.y + pB.y) / 2
        var candidates: [[CGPoint]] = [
            [pA, CGPoint(x: pB.x, y: pA.y), pB],
            [pA, CGPoint(x: pA.x, y: pB.y), pB],
            [pA, CGPoint(x: midX, y: pA.y), CGPoint(x: midX, y: pB.y), pB],
            [pA, CGPoint(x: pA.x, y: midY), CGPoint(x: pB.x, y: midY), pB],
        ]
        // Обходы вокруг предметов - сверху, снизу, слева, справа.
        let boxes = [rectA, rectB].compactMap { $0 }
        if let first = boxes.first {
            let all = boxes.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -margin, dy: -margin)
            for y in [all.minY, all.maxY] { candidates.append([pA, CGPoint(x: pA.x, y: y), CGPoint(x: pB.x, y: y), pB]) }
            for x in [all.minX, all.maxX] { candidates.append([pA, CGPoint(x: x, y: pA.y), CGPoint(x: x, y: pB.y), pB]) }
        }
        var best: (score: CGFloat, points: [CGPoint])?
        for candidate in candidates {
            let full = simplify([a] + candidate + [b])
            var score: CGFloat = 0
            for i in 1..<full.count {
                let p = full[i - 1], q = full[i]
                score += abs(q.x - p.x) + abs(q.y - p.y)
                // Отрезок сквозь предмет - почти запрещён.
                let segment = CGRect(x: min(p.x, q.x), y: min(p.y, q.y), width: abs(q.x - p.x), height: abs(q.y - p.y)).insetBy(dx: -0.5, dy: -0.5)
                for box in boxes where segment.intersects(box.insetBy(dx: 3, dy: 3)) { score += 100_000 }
            }
            score += CGFloat(max(full.count - 2, 0)) * 40
            // Первый шаг - наружу из своей стороны, последний - внутрь к своей.
            if let dirA, full.count > 1 {
                let d = CGPoint(x: full[1].x - full[0].x, y: full[1].y - full[0].y)
                if d.x * dirA.x + d.y * dirA.y < -0.5 { score += 50_000 }
            }
            if let dirB, full.count > 1 {
                let n = full.count
                let d = CGPoint(x: full[n - 2].x - full[n - 1].x, y: full[n - 2].y - full[n - 1].y)
                if d.x * dirB.x + d.y * dirB.y < -0.5 { score += 50_000 }
            }
            if best == nil || score < best!.score { best = (score, full) }
        }
        guard let points = best?.points, points.count > 2 else { return [] }
        return Array(points.dropFirst().dropLast())
    }

    /// Без повторов и точек посреди прямого участка.
    static func simplify(_ points: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in points {
            if let last = out.last, abs(last.x - p.x) < 0.5, abs(last.y - p.y) < 0.5 { continue }
            if out.count >= 2 {
                let a = out[out.count - 2], b = out[out.count - 1]
                let cross = (b.x - a.x) * (p.y - b.y) - (b.y - a.y) * (p.x - b.x)
                let dot = (b.x - a.x) * (p.x - b.x) + (b.y - a.y) * (p.y - b.y)
                if abs(cross) < 0.5, dot >= 0 { out.removeLast() }
            }
            out.append(p)
        }
        return out
    }

    /// Точка на краю предмета по направлению к target (с маленьким зазором).
    static func edgePoint(of item: BoardItem, toward target: CGPoint, gap: CGFloat = 7) -> CGPoint {
        let r = item.rect.standardized.insetBy(dx: -gap, dy: -gap)
        let c = CGPoint(x: r.midX, y: r.midY)
        let dx = target.x - c.x, dy = target.y - c.y
        guard abs(dx) > 0.01 || abs(dy) > 0.01, r.width > 0, r.height > 0 else { return c }
        let a = r.width / 2, b = r.height / 2
        let t: CGFloat
        switch item.kind {
        case .ellipse: t = 1 / sqrt(dx * dx / (a * a) + dy * dy / (b * b))
        case .diamond: t = 1 / (abs(dx) / a + abs(dy) / b)
        default: t = min(abs(dx) > 0.01 ? a / abs(dx) : .infinity, abs(dy) > 0.01 ? b / abs(dy) : .infinity)
        }
        return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
    }

    func bounds(in board: Whiteboard) -> CGRect {
        if isConnector {
            let samples = connectorPath(in: board).samples
            let box = samples.dropFirst().reduce(CGRect(origin: samples[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
            return box.insetBy(dx: -width - 8, dy: -width - 8)
        }
        if isStroke {
            let pad = kind == .marker ? width * 2 : width
            return strokeBounds.insetBy(dx: -pad, dy: -pad)
        }
        return rect.standardized
    }

    /// Рамка самих точек штриха - без толщины.
    var strokeBounds: CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    func hit(_ p: CGPoint, tolerance: CGFloat, in board: Whiteboard) -> Bool {
        switch kind {
        case .pen, .marker:
            let reach = tolerance + (kind == .marker ? width * 2 : width / 2)
            guard points.count > 1 else { return points.first.map { hypot($0.x - p.x, $0.y - p.y) < reach } ?? false }
            for i in 1..<points.count where Self.distance(p, points[i - 1], points[i]) < reach { return true }
            return false
        case .line, .arrow:
            let samples = connectorPath(in: board).samples
            for i in 1..<samples.count where Self.distance(p, samples[i - 1], samples[i]) < tolerance + width / 2 { return true }
            return false
        case .rect, .ellipse, .diamond:
            let r = rect.standardized
            // С заливкой или текстом - попадание по всей фигуре; пустая - только по контуру.
            if fill != nil || !text.isEmpty { return r.insetBy(dx: -tolerance, dy: -tolerance).contains(p) }
            let outer = r.insetBy(dx: -tolerance, dy: -tolerance), inner = r.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(p) && (inner.isEmpty || !inner.contains(p))
        case .sticky, .text, .image:
            return rect.standardized.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(p)
        }
    }

    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = dx * dx + dy * dy
        guard len > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    mutating func move(by d: CGPoint) {
        points = points.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
        rect = rect.offsetBy(dx: d.x, dy: d.y)
    }

    // MARK: рисование

    private func stroked(_ path: NSBezierPath) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch dash {
        case .solid: break
        case .dashed: path.setLineDash([width * 3, width * 2.2], count: 2, phase: 0)
        case .dotted: path.setLineDash([0.01, width * 2.2], count: 2, phase: 0)
        }
        ink.setStroke()
        path.stroke()
    }

    func draw(in board: Whiteboard, hidingText: Bool = false) {
        switch kind {
        case .pen, .marker:
            if points.count == 1, let p = points.first {
                let d = kind == .marker ? width * 4 : width
                (kind == .marker ? ink.withAlphaComponent(0.5) : ink).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)).fill()
                return
            }
            let path = Self.smoothPath(points)
            if kind == .marker {
                path.lineWidth = width * 4
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                ink.withAlphaComponent(0.5).setStroke()
                path.stroke()
            } else {
                stroked(path)
            }
        case .line, .arrow:
            let shape = connectorPath(in: board)
            stroked(shape.bezier())
            // Наконечник смотрит по касательной к линии в её конце.
            let heads = effectiveHeads
            if heads != .none { drawHead(at: shape.b, from: shape.curves.last?.c2 ?? shape.bends.last ?? shape.a) }
            if heads == .both { drawHead(at: shape.a, from: shape.curves.first?.c1 ?? shape.bends.first ?? shape.b) }
        case .rect, .ellipse, .diamond:
            let path = shapePath()
            if let fillColor {
                fillColor.setFill()
                path.fill()
            }
            stroked(path)
            if !hidingText { drawText() }
        case .sticky:
            let r = rect.standardized
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = NSSize(width: 0, height: -5)
            shadow.set()
            (fillColor ?? Self.pastel(nil)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
            NSGraphicsContext.restoreGraphicsState()
            if !hidingText { drawText() }
        case .text:
            if !hidingText { drawText() }
        case .image:
            let r = rect.standardized
            let clip = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            if let name = image, let picture = Assets.image(name) {
                NSGraphicsContext.saveGraphicsState()
                clip.addClip()
                picture.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                             hints: [.interpolation: NSImageInterpolation.high.rawValue])
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor.white.withAlphaComponent(0.08).setFill()
                clip.fill()
            }
        }
    }

    func shapePath() -> NSBezierPath {
        let r = rect.standardized
        switch kind {
        case .ellipse:
            return NSBezierPath(ovalIn: r)
        case .diamond:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.midX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.midY))
            path.line(to: CGPoint(x: r.midX, y: r.maxY))
            path.line(to: CGPoint(x: r.minX, y: r.midY))
            path.close()
            return path
        default:
            let radius = min(14, min(r.width, r.height) / 4)
            return NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        }
    }

    private func drawHead(at tip: CGPoint, from tail: CGPoint) {
        guard hypot(tip.x - tail.x, tip.y - tail.y) > 2 else { return }
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let length = max(14, width * 3.6)
        let spread: CGFloat = .pi / 7.5
        let head = NSBezierPath()
        head.move(to: CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)))
        head.line(to: tip)
        head.line(to: CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
        head.lineWidth = width
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        ink.setStroke()
        head.stroke()
    }

    /// Где рисуется текст (у фигур - по центру по вертикали).
    var textFrame: CGRect {
        let box = textBox
        guard isShape else { return box }
        let height = min(textSize(width: box.width).height, box.height)
        return CGRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height + 2)
    }

    private func drawText() {
        guard !text.isEmpty else { return }
        let target = textFrame
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: (isShape ? rect.standardized : target).insetBy(dx: -4, dy: -4)).addClip()
        NSAttributedString(string: text, attributes: textAttributes())
            .draw(with: CGRect(x: target.minX, y: target.minY, width: target.width + (kind == .text ? 6 : 0), height: target.height + 4),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Плавная линия через точки: кривые через середины соседних отрезков.
    static func smoothPath(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count < 3 {
            for p in points.dropFirst() { path.line(to: p) }
            return path
        }
        for i in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.curve(to: mid, controlPoint1: points[i], controlPoint2: points[i])
        }
        path.line(to: points[points.count - 1])
        return path
    }
}

// MARK: - доска в тексте заметки

/// Превью доски прямо в заметке: показывает всё нарисованное; клик - открыть доску.
final class WhiteboardCell: NSTextAttachmentCell {
    let board: Whiteboard

    init(json: String) {
        board = Whiteboard(json: json)
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("не используется") }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let width = Objects.width(textContainer, lineFrag)
        return NSRect(x: 0, y: -10, width: width, height: width / Whiteboard.previewAspect + 8)
    }

    override func cellSize() -> NSSize { NSSize(width: 320, height: 188) }
    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let rect = frame.insetBy(dx: 0.5, dy: 4)
        let outline = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSColor.white.withAlphaComponent(0.05).setFill()
        outline.fill()
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let viewport = board.previewViewport
        BoardGrid.draw(in: rect, origin: viewport.origin, zoom: rect.width / viewport.width)
        board.draw(viewport: viewport, in: rect)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        if board.items.isEmpty {
            let style = PageStyle.current
            let hint = NSAttributedString(string: "Доска - нажми, чтобы рисовать", attributes: [
                .font: style.font(style.font == .hand ? 24 : 15, weight: 500),
                .foregroundColor: style.text.color.withAlphaComponent(0.45),
            ])
            let size = hint.size()
            hint.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        } else {
            let label = NSAttributedString(string: "ДОСКА", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.4),
                .kern: 0.6,
            ])
            label.draw(at: NSPoint(x: rect.minX + 12, y: rect.minY + 10))
        }
    }
}

/// Сетка из точек, как на доске для маркеров. Шаг растёт при отдалении, чтобы точки не сливались.
enum BoardGrid {
    static func draw(in rect: NSRect, origin: CGPoint, zoom: CGFloat) {
        var step: CGFloat = 40
        while step * zoom < 16 { step *= 2 }
        NSColor.white.withAlphaComponent(0.1).setFill()
        let worldWidth = rect.width / zoom, worldHeight = rect.height / zoom
        let dot: CGFloat = 2
        var x = floor(origin.x / step) * step
        while x <= origin.x + worldWidth {
            let sx = rect.minX + (x - origin.x) * zoom
            var y = floor(origin.y / step) * step
            while y <= origin.y + worldHeight {
                let sy = rect.minY + (y - origin.y) * zoom
                NSRect(x: sx - dot / 2, y: sy - dot / 2, width: dot, height: dot).fill()
                y += step
            }
            x += step
        }
    }
}


/// Кусок кривой стрелки (кубическая кривая).
struct CurveSegment {
    var start: CGPoint
    var c1: CGPoint
    var c2: CGPoint
    var end: CGPoint

    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
        return CGPoint(x: w0 * start.x + w1 * c1.x + w2 * c2.x + w3 * end.x, y: w0 * start.y + w1 * c1.y + w2 * c2.y + w3 * end.y)
    }
}

/// Геометрия стрелки: концы, кривые или изломы, и места, где можно добавить точку.
struct ConnectorPath {
    var a: CGPoint
    var b: CGPoint
    var curves: [CurveSegment] = []
    var bends: [CGPoint] = []
    /// Полупрозрачные точки на каждом участке: потянул - появилась новая точка (номер участка = куда вставить).
    var ghosts: [CGPoint] = []

    func bezier() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: a)
        if !curves.isEmpty {
            for segment in curves { path.curve(to: segment.end, controlPoint1: segment.c1, controlPoint2: segment.c2) }
        } else if !bends.isEmpty {
            // Изломы со скруглёнными углами.
            let all = [a] + bends + [b]
            for i in 1..<all.count - 1 {
                let prev = all[i - 1], corner = all[i], next = all[i + 1]
                let radius = min(14, hypot(corner.x - prev.x, corner.y - prev.y) / 2, hypot(next.x - corner.x, next.y - corner.y) / 2)
                if radius > 1 { path.appendArc(from: corner, to: next, radius: radius) } else { path.line(to: corner) }
            }
            path.line(to: b)
        } else {
            path.line(to: b)
        }
        return path
    }

    /// Точки вдоль линии - для попадания мышью, рамки и подсветки.
    var samples: [CGPoint] {
        if !curves.isEmpty {
            var out = [a]
            for segment in curves { out += (1...16).map { segment.point(CGFloat($0) / 16) } }
            return out
        }
        return [a] + bends + [b]
    }
}
