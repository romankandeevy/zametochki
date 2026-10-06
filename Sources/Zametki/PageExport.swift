import AppKit
import UniformTypeIdentifiers

/// Страница целиком - в PDF или картинку, такой, какой её видно в приложении: фон, почерк, маркеры, предметы.
/// Текст рисует тот же NotesTextView, что и в редакторе, только вне окна и на всю высоту.
enum PageExport {
    /// Ширина страницы при выводе. Колонка текста внутри - как в окне при обычной ширине.
    static let width: CGFloat = 820

    enum Kind { case pdf, png }

    /// Готовая к печати «бумага»: фон страницы и текст поверх.
    private static func sheet(for note: Note) -> PageSheet {
        let style = note.doc.style ?? PageStyle.saved
        let previous = PageStyle.current
        PageStyle.current = style
        defer { PageStyle.current = previous }

        let text = NotesTextView(usingTextLayoutManager: false)
        text.textContainer?.replaceLayoutManager(NotesLayoutManager())
        text.isRichText = false
        text.drawsBackground = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.frame = NSRect(x: 0, y: 0, width: width, height: 100)
        text.updateInsets()
        let storage = NSTextStorage(attributedString: Formatting.attributed(note.doc))
        Formatting.render(storage)
        text.textStorage?.setAttributedString(storage)
        if let layout = text.layoutManager, let container = text.textContainer {
            layout.ensureLayout(for: container)
            let height = layout.usedRect(for: container).height + text.textContainerInset.height * 2 + 40
            text.frame.size.height = ceil(height)
        }
        let sheet = PageSheet(frame: NSRect(x: 0, y: 0, width: width, height: text.frame.height), style: style)
        sheet.addSubview(text)
        return sheet
    }

    /// Рисует лист, пока на время рисования стиль открытой страницы подменён стилем этой заметки.
    private static func render<T>(_ note: Note, _ body: (PageSheet) -> T) -> T {
        let sheet = sheet(for: note)
        let previous = PageStyle.current
        PageStyle.current = sheet.style
        defer { PageStyle.current = previous }
        sheet.layoutSubtreeIfNeeded()
        return body(sheet)
    }

    static func pdf(_ note: Note) -> Data {
        render(note) { $0.dataWithPDF(inside: $0.bounds) }
    }

    /// Картинка в двойном разрешении - чётко и на Retina, и в мессенджерах.
    static func png(_ note: Note, scale: CGFloat = 2) -> Data? {
        render(note) { sheet in
            let size = sheet.bounds.size
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
            rep.size = size
            sheet.cacheDisplay(in: sheet.bounds, to: rep)
            return rep.representation(using: .png, properties: [:])
        }
    }

    /// Сохранить через окно «Сохранить как».
    static func save(_ note: Note, as kind: Kind) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind == .pdf ? .pdf : .png]
        panel.nameFieldStringValue = String(note.title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-").prefix(60))
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = kind == .pdf ? pdf(note) : png(note)
        try? data?.write(to: url, options: .atomic)
    }

    /// Картинкой в буфер обмена - сразу вставить в мессенджер.
    static func copyImage(_ note: Note) -> Bool {
        guard let data = png(note) else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: .png)
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation { board.setData(tiff, forType: .tiff) }
        return true
    }
}

/// Лист с фоном страницы: цвет, градиент или картинка с затемнением - как окно в приложении.
final class PageSheet: NSView {
    let style: PageStyle

    init(frame: NSRect, style: PageStyle) {
        self.style = style
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        switch style.background {
        case .color:
            style.baseColor.setFill()
            bounds.fill()
        case .gradient(let id):
            let g = PageStyle.gradients.first { $0.id == id } ?? PageStyle.gradients[0]
            // Вид перевёрнут: угол 90 - сверху вниз, как в окне.
            NSGradient(starting: g.top, ending: g.bottom)?.draw(in: bounds, angle: 90)
        case .image(let name):
            style.baseColor.setFill()
            bounds.fill()
            if let image = Assets.image(name), image.size.width > 0 {
                // Картинка заполняет первый экран, ниже - цвет; сверху затемнение, чтобы текст читался.
                let screen = NSRect(x: 0, y: 0, width: bounds.width, height: min(bounds.height, bounds.width * 0.75))
                let scale = max(screen.width / image.size.width, screen.height / image.size.height)
                let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: screen).addClip()
                image.draw(in: NSRect(x: (screen.width - drawn.width) / 2, y: (screen.height - drawn.height) / 2, width: drawn.width, height: drawn.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
                NSGradient(colors: [NSColor.black.withAlphaComponent(0.45), style.baseColor])?
                    .draw(in: screen, angle: 90)
            }
        }
    }
}
