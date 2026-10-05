import AppKit
import SwiftUI

/// Внешний вид - из стиля открытой страницы (PageStyle.current): цвета, шрифт, размеры.
enum Style {
    static var background: NSColor { PageStyle.current.baseColor }
    static var text: NSColor { PageStyle.current.text.color }
    /// Caveat - вариативный шрифт; 500 чуть плотнее обычного и лучше держится на тёмном фоне.
    static let weight: CGFloat = 500
    static var editorSize: CGFloat { PageStyle.current.bodySize }
    static var listSize: CGFloat { PageStyle.current.listSize }

    /// Caveat лежит в бандле и регистрируется только для этого процесса - в систему ничего не ставится.
    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "Caveat", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(_ size: CGFloat, weight: CGFloat = Style.weight) -> NSFont {
        PageStyle.current.font(size, weight: weight)
    }

    static func attributes(size: CGFloat, alpha: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = size * 0.12
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: font(size),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: paragraph,
        ]
    }
}
