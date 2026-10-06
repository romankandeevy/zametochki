import AppKit

/// Строки-предметы: картинка, файл, таблица, разделитель, карточка страницы.
/// В тексте каждый - один символ-вложение, а рисует его своя ячейка.
enum Objects {
    static func attachment(for attrs: [NSAttributedString.Key: Any]) -> NSTextAttachment? {
        let cell: NSTextAttachmentCell?
        switch Formatting.block(of: attrs) {
        case .page: cell = (attrs[.zPage] as? String).map { PageCardCell(pageID: $0) }
        case .image: cell = (attrs[.zImage] as? String).map { ImageCell(name: $0, ratio: attrs[.zImageWidth] as? Double ?? ImageCell.defaultRatio) }
        case .file: cell = (attrs[.zFile] as? String).map { FileCell(name: $0) }
        case .table: cell = TableCell(json: attrs[.zTable] as? String ?? Table.empty.json)
        case .board: cell = BoardCell(json: attrs[.zBoard] as? String ?? Board().json)
        case .divider: cell = DividerCell()
        default: cell = nil
        }
        guard let cell else { return nil }
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell
        return attachment
    }

    /// Ширина предмета - во всю строку, с учётом отступов контейнера.
    static func width(_ container: NSTextContainer, _ lineFrag: NSRect) -> CGFloat {
        max(lineFrag.width - container.lineFragmentPadding * 2 - 4, 120)
    }
}

/// Таблица: ячейки строками; первая строка - шапка.
struct Table: Codable, Equatable {
    var cells: [[String]]

    static let empty = Table(cells: Array(repeating: Array(repeating: "", count: 3), count: 3))

    var rows: Int { cells.count }
    var columns: Int { cells.map(\.count).max() ?? 0 }

    var json: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "{\"cells\":[]}"
    }

    init(cells: [[String]]) { self.cells = cells }

    init(json: String) {
        self = (try? JSONDecoder().decode(Table.self, from: Data(json.utf8))) ?? .empty
    }
}

// MARK: - разделитель

final class DividerCell: NSTextAttachmentCell {
    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: 0, y: -8, width: Objects.width(textContainer, lineFrag), height: 26)
    }

    override func cellSize() -> NSSize { NSSize(width: 200, height: 26) }
    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let y = frame.midY
        switch PageStyle.current.divider {
        case .line:
            PageStyle.current.text.color.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: NSRect(x: frame.minX, y: y - 0.75, width: frame.width, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
        case .dots:
            PageStyle.current.text.color.withAlphaComponent(0.45).setFill()
            for i in -1...1 {
                let d: CGFloat = 4.5
                NSBezierPath(ovalIn: NSRect(x: frame.midX + CGFloat(i) * 16 - d / 2, y: y - d / 2, width: d, height: d)).fill()
            }
        case .washi:
            // «Лента»: полупрозрачная полоса с косой штриховкой, чуть повёрнутая - как приклеенный кусок washi.
            let band = NSRect(x: frame.minX + frame.width * 0.2, y: y - 7, width: frame.width * 0.6, height: 14)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: band.midX, yBy: band.midY)
            transform.rotate(byDegrees: -1.2)
            transform.translateX(by: -band.midX, yBy: -band.midY)
            transform.concat()
            let path = NSBezierPath(rect: band)
            NSColor(srgbRed: 1, green: 0.85, blue: 0.5, alpha: 0.28).setFill()
            path.fill()
            path.addClip()
            NSColor.white.withAlphaComponent(0.16).setStroke()
            var x = band.minX - band.height
            while x < band.maxX {
                let stripe = NSBezierPath()
                stripe.move(to: NSPoint(x: x, y: band.maxY))
                stripe.line(to: NSPoint(x: x + band.height, y: band.minY))
                stripe.lineWidth = 3
                stripe.stroke()
                x += 9
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

// MARK: - картинка

/// Картинка в тексте: по центру, со скруглением, тонкой рамкой и мягкой тенью.
/// Ширина - доля колонки; тянешь за правый край - меняется (редактор сохраняет её в zImageWidth).
final class ImageCell: NSTextAttachmentCell {
    let name: String
    let ratio: Double
    static let defaultRatio = 0.6
    static let maxHeight: CGFloat = 460
    /// Поля вокруг картинки под тень.
    static let pad: CGFloat = 10

    init(name: String, ratio: Double) {
        self.name = name
        self.ratio = min(max(ratio, 0.2), 1)
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("не используется") }

    /// Размер самой картинки при ширине колонки column.
    func imageSize(column: CGFloat) -> NSSize {
        let maxWidth = max(column * CGFloat(ratio), 80)
        guard let image = Assets.image(name), image.size.width > 0 else { return NSSize(width: maxWidth, height: 80) }
        var width = min(maxWidth, image.size.width)
        var height = width * image.size.height / image.size.width
        if height > Self.maxHeight {
            height = Self.maxHeight
            width = height * image.size.width / image.size.height
        }
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let size = imageSize(column: Objects.width(textContainer, lineFrag))
        return NSRect(x: 0, y: -Self.pad, width: size.width + Self.pad * 2, height: size.height + Self.pad * 2)
    }

    override func cellSize() -> NSSize { NSSize(width: 200, height: 120) }
    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let rect = frame.insetBy(dx: Self.pad, dy: Self.pad)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        guard let image = Assets.image(name) else {
            NSColor.white.withAlphaComponent(0.07).setFill()
            shape.fill()
            NSAttributedString(string: "Картинка не найдена", attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white.withAlphaComponent(0.5),
            ]).draw(at: NSPoint(x: rect.minX + 16, y: rect.midY - 8))
            return
        }
        // Мягкая тень под картинкой.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        NSColor.black.withAlphaComponent(0.2).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        // Тонкая светлая рамка - картинка не «вклеена», а лежит на странице.
        NSColor.white.withAlphaComponent(0.14).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
}

// MARK: - файл

final class FileCell: NSTextAttachmentCell {
    let name: String

    init(name: String) {
        self.name = name
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("не используется") }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: 0, y: -12, width: min(Objects.width(textContainer, lineFrag), 420), height: 56)
    }

    override func cellSize() -> NSSize { NSSize(width: 300, height: 56) }
    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let rect = frame.insetBy(dx: 0.5, dy: 4)
        let card = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)
        NSColor.white.withAlphaComponent(0.07).setFill()
        card.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        card.stroke()

        let url = Assets.url(name)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.draw(in: NSRect(x: rect.minX + 10, y: rect.midY - 16, width: 32, height: 32),
                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        NSAttributedString(string: Assets.displayName(name), attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium), .foregroundColor: PageStyle.current.text.color, .paragraphStyle: paragraph,
        ]).draw(in: NSRect(x: rect.minX + 52, y: rect.minY + 8, width: rect.width - 64, height: 18))
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        let detail = bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Файл не найден"
        NSAttributedString(string: detail + " · открыть", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: PageStyle.current.text.color.withAlphaComponent(0.55),
        ]).draw(at: NSPoint(x: rect.minX + 52, y: rect.minY + 27))
    }
}

// MARK: - таблица

final class TableCell: NSTextAttachmentCell {
    let table: Table
    static let rowHeight: CGFloat = 34

    init(json: String) {
        table = Table(json: json)
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("не используется") }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: 0, y: -10, width: Objects.width(textContainer, lineFrag), height: CGFloat(table.rows) * Self.rowHeight + 8)
    }

    override func cellSize() -> NSSize { NSSize(width: 300, height: CGFloat(table.rows) * Self.rowHeight + 8) }
    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let rect = frame.insetBy(dx: 0.5, dy: 4)
        let columns = max(table.columns, 1)
        let colWidth = rect.width / CGFloat(columns)
        let outline = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        NSColor.white.withAlphaComponent(0.04).setFill()
        outline.fill()
        // Шапка чуть светлее.
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: Self.rowHeight).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.16).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        let grid = NSBezierPath()
        for r in 1..<max(table.rows, 1) {
            let y = rect.minY + CGFloat(r) * Self.rowHeight
            grid.move(to: NSPoint(x: rect.minX, y: y))
            grid.line(to: NSPoint(x: rect.maxX, y: y))
        }
        for c in 1..<columns {
            let x = rect.minX + CGFloat(c) * colWidth
            grid.move(to: NSPoint(x: x, y: rect.minY))
            grid.line(to: NSPoint(x: x, y: rect.maxY))
        }
        grid.lineWidth = 1
        grid.stroke()

        let style = PageStyle.current
        let size = style.font == .hand ? 20 : 14
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        for (r, row) in table.cells.enumerated() {
            for (c, value) in row.enumerated() where !value.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: style.font(CGFloat(size), weight: r == 0 ? 700 : 500),
                    .foregroundColor: style.text.color.withAlphaComponent(r == 0 ? 1 : 0.9),
                    .paragraphStyle: paragraph,
                ]
                let text = NSAttributedString(string: value, attributes: attrs)
                let h = text.size().height
                text.draw(in: NSRect(x: rect.minX + CGFloat(c) * colWidth + 10,
                                     y: rect.minY + CGFloat(r) * Self.rowHeight + (Self.rowHeight - h) / 2,
                                     width: colWidth - 20, height: h))
            }
        }
    }
}
