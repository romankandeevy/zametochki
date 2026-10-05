import AppKit

/// Иконка в Dock: та же белая «з», а фон - как у стиля по умолчанию (цвет, градиент или картинка).
/// Перерисовывается при запуске и когда меняется стиль по умолчанию.
enum DockIcon {
    static func update(_ style: PageStyle = .saved) {
        let size: CGFloat = 1024
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            // Сетка иконок macOS: тело 824×824 с отступом 100, скругление ~185.
            let body = rect.insetBy(dx: 100, dy: 100)
            let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.set()
            NSColor(cgColor: style.baseColor.cgColor)?.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            switch style.background {
            case .color:
                style.baseColor.setFill()
                body.fill()
            case .gradient(let id):
                let g = PageStyle.gradients.first { $0.id == id } ?? PageStyle.gradients[0]
                NSGradient(starting: g.top, ending: g.bottom)?.draw(in: body, angle: -90)
            case .image(let name):
                style.baseColor.setFill()
                body.fill()
                if let picture = Assets.image(name), picture.size.width > 0, picture.size.height > 0 {
                    let scale = max(body.width / picture.size.width, body.height / picture.size.height)
                    let w = picture.size.width * scale, h = picture.size.height * scale
                    picture.draw(in: NSRect(x: body.midX - w / 2, y: body.midY - h / 2, width: w, height: h))
                    NSColor.black.withAlphaComponent(0.3).setFill()
                    body.fill(using: .sourceOver)
                }
            }
            NSGraphicsContext.restoreGraphicsState()

            // «з» почерком Caveat, как в собранной иконке; по центру контура самой буквы.
            let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([
                kCTFontNameAttribute: "Caveat-Regular",
                kCTFontVariationAttribute: [0x7767_6874: 600],
            ] as CFDictionary), body.width * 0.62, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "з", attributes: [
                .font: font, .foregroundColor: NSColor.white,
            ]))
            cg.textMatrix = .identity
            let bounds = CTLineGetImageBounds(line, cg)
            cg.textPosition = CGPoint(x: body.midX - bounds.width / 2 - bounds.minX,
                                      y: body.midY - bounds.height / 2 - bounds.minY)
            CTLineDraw(line, cg)
            return true
        }
        NSApp.applicationIconImage = image
    }
}
