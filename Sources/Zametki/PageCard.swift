import AppKit

/// Карточка вложенной страницы в тексте, как в Craft: один символ-вложение, который рисуется плашкой
/// с названием и первой строкой страницы. Нажал - провалился внутрь.
enum PageCard {
    static let height: CGFloat = 60
}

final class PageCardCell: NSTextAttachmentCell {
    let pageID: String
    /// Над карточкой тащат блок - подсвечиваем: отпустишь, и блок уедет внутрь страницы.
    var isDropTarget = false

    init(pageID: String) {
        self.pageID = pageID
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("не используется") }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let width = min(lineFrag.width - textContainer.lineFragmentPadding * 2 - 4, 560)
        return NSRect(x: 0, y: -14, width: max(width, 160), height: PageCard.height)
    }

    override func cellSize() -> NSSize { NSSize(width: 320, height: PageCard.height) }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -14) }
    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = cellFrame.insetBy(dx: 0.5, dy: 4)
        let card = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        // Вид карточек - из стиля страницы: простые, с рамкой или яркие.
        let look = PageStyle.current.card
        let fill: CGFloat = isDropTarget ? 0.16 : look == .filled ? 0.16 : look == .outline ? 0.02 : 0.07
        let border: CGFloat = isDropTarget ? 0.55 : look == .outline ? 0.5 : 0.14
        NSColor.white.withAlphaComponent(fill).setFill()
        card.fill()
        NSColor.white.withAlphaComponent(border).setStroke()
        card.lineWidth = isDropTarget || look == .outline ? 1.5 : 1
        card.stroke()

        let note = AppDelegate.store?.note(pageID)
        let title = note?.title ?? "Страница удалена"
        let preview = note?.preview ?? ""

        // Значок страницы.
        if let icon = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) {
            let tinted = icon.tinted(PageStyle.current.text.color.withAlphaComponent(0.7))
            let size = tinted.size
            tinted.draw(in: NSRect(x: rect.minX + 16, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        // Стрелка «внутрь».
        if let chevron = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) {
            let tinted = chevron.tinted(PageStyle.current.text.color.withAlphaComponent(0.4))
            let size = tinted.size
            tinted.draw(in: NSRect(x: rect.maxX - 18 - size.width, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        let textX = rect.minX + 44
        let textWidth = rect.maxX - 40 - textX
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: Style.font(Style.editorSize * 0.78, weight: 650),
            .foregroundColor: PageStyle.current.text.color.withAlphaComponent(note == nil ? 0.4 : 1),
            .paragraphStyle: paragraph,
        ]
        if preview.isEmpty {
            let titleHeight = Style.font(Style.editorSize * 0.78, weight: 650).boundingRectForFont.height
            NSAttributedString(string: title, attributes: titleAttrs)
                .draw(in: NSRect(x: textX, y: rect.midY - titleHeight / 2 + 1, width: textWidth, height: titleHeight))
        } else {
            NSAttributedString(string: title, attributes: titleAttrs)
                .draw(in: NSRect(x: textX, y: rect.minY + 6, width: textWidth, height: 26))
            NSAttributedString(string: preview, attributes: [
                .font: Style.font(Style.editorSize * 0.57), .foregroundColor: PageStyle.current.text.color.withAlphaComponent(0.5), .paragraphStyle: paragraph,
            ]).draw(in: NSRect(x: textX, y: rect.minY + 29, width: textWidth, height: 20))
        }
    }
}

private extension NSImage {
    /// Значок SF Symbols нужного цвета: шаблонные картинки сами по себе рисуются чёрным.
    func tinted(_ color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return image
    }
}
