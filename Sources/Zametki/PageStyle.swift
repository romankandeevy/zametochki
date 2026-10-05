import AppKit
import SwiftUI

/// Стиль страницы, как вкладка «Стиль» в Craft: шрифт, ширина, фон, обложка, цвет текста,
/// вид разделителей и карточек. Хранится в заметке; у новых заметок - стиль по умолчанию.
struct PageStyle: Codable, Equatable {
    enum Font: String, Codable, CaseIterable {
        case hand, system, serif, mono, rounded

        var name: String {
            switch self {
            case .hand: "От руки"
            case .system: "Обычный"
            case .serif: "С засечками"
            case .mono: "Моно"
            case .rounded: "Округлый"
            }
        }
    }

    enum Width: String, Codable, CaseIterable {
        case regular, wide
        var name: String { self == .regular ? "Обычная" : "Широкая" }
    }

    enum Background: Codable, Equatable {
        case color(String)
        case gradient(String)
        case image(String)   // файл в папке вложений
    }

    enum Divider: String, Codable, CaseIterable {
        case line, dots, washi
        var name: String {
            switch self {
            case .line: "Линия"
            case .dots: "Точки"
            case .washi: "Лента"
            }
        }
    }

    enum Card: String, Codable, CaseIterable {
        case plain, outline, filled
        var name: String {
            switch self {
            case .plain: "Простые"
            case .outline: "С рамкой"
            case .filled: "Яркие"
            }
        }
    }

    var font: Font = .hand
    var width: Width = .regular
    var background: Background = .color("blue")
    var cover: String?
    /// Какая часть обложки видна: 0 - верх картинки, 1 - низ.
    var coverPosition: Double = 0.5
    var text: TextColor = .white
    var divider: Divider = .line
    var card: Card = .plain
    /// Маркер списка. Необязательное поле: у старых заметок его нет в файле, а без «?» они бы не прочитались.
    var bullet: Bullet?

    enum Bullet: String, Codable, CaseIterable {
        case dot, dash
        var name: String { self == .dot ? "Точка" : "Тире" }
    }

    var bulletStyle: Bullet { bullet ?? .dot }

    // MARK: текущий и по умолчанию

    /// Стиль открытой страницы - по нему рисуется всё: текст, маркеры, карточки, окно.
    static var current = PageStyle.saved

    static var saved: PageStyle {
        guard let data = UserDefaults.standard.data(forKey: "defaultPageStyle"),
              let style = try? JSONDecoder().decode(PageStyle.self, from: data) else { return PageStyle() }
        return style
    }

    func makeDefault() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "defaultPageStyle") }
        DockIcon.update(self)
    }

    // MARK: цвета

    static let colors: [(id: String, name: String, color: NSColor)] = [
        ("blue", "Синий", NSColor(srgbRed: 0x1D / 255.0, green: 0x35 / 255.0, blue: 0x94 / 255.0, alpha: 1)),
        ("navy", "Ночь", NSColor(srgbRed: 0.07, green: 0.10, blue: 0.27, alpha: 1)),
        ("violet", "Фиолетовый", NSColor(srgbRed: 0.27, green: 0.18, blue: 0.52, alpha: 1)),
        ("forest", "Лес", NSColor(srgbRed: 0.09, green: 0.27, blue: 0.22, alpha: 1)),
        ("wine", "Вино", NSColor(srgbRed: 0.33, green: 0.12, blue: 0.20, alpha: 1)),
        ("graphite", "Графит", NSColor(srgbRed: 0.15, green: 0.16, blue: 0.18, alpha: 1)),
        ("clay", "Глина", NSColor(srgbRed: 0.47, green: 0.24, blue: 0.16, alpha: 1)),
        ("teal", "Бирюза", NSColor(srgbRed: 0.04, green: 0.30, blue: 0.33, alpha: 1)),
        ("plum", "Слива", NSColor(srgbRed: 0.33, green: 0.13, blue: 0.38, alpha: 1)),
        ("rose", "Роза", NSColor(srgbRed: 0.47, green: 0.16, blue: 0.28, alpha: 1)),
        ("olive", "Олива", NSColor(srgbRed: 0.25, green: 0.27, blue: 0.12, alpha: 1)),
        ("slate", "Сланец", NSColor(srgbRed: 0.16, green: 0.22, blue: 0.31, alpha: 1)),
        ("cocoa", "Какао", NSColor(srgbRed: 0.27, green: 0.18, blue: 0.14, alpha: 1)),
        ("ink", "Чернила", NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)),
    ]

    static let gradients: [(id: String, name: String, top: NSColor, bottom: NSColor)] = [
        ("ocean", "Океан", NSColor(srgbRed: 0.11, green: 0.21, blue: 0.58, alpha: 1), NSColor(srgbRed: 0.04, green: 0.42, blue: 0.52, alpha: 1)),
        ("sunset", "Закат", NSColor(srgbRed: 0.33, green: 0.16, blue: 0.55, alpha: 1), NSColor(srgbRed: 0.62, green: 0.22, blue: 0.33, alpha: 1)),
        ("night", "Полночь", NSColor(srgbRed: 0.10, green: 0.14, blue: 0.38, alpha: 1), NSColor(srgbRed: 0.03, green: 0.04, blue: 0.10, alpha: 1)),
        ("aurora", "Сияние", NSColor(srgbRed: 0.06, green: 0.33, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.14, green: 0.18, blue: 0.52, alpha: 1)),
        ("dawn", "Рассвет", NSColor(srgbRed: 0.55, green: 0.28, blue: 0.18, alpha: 1), NSColor(srgbRed: 0.24, green: 0.14, blue: 0.42, alpha: 1)),
        ("lagoon", "Лагуна", NSColor(srgbRed: 0.03, green: 0.36, blue: 0.40, alpha: 1), NSColor(srgbRed: 0.05, green: 0.15, blue: 0.33, alpha: 1)),
    ]

    /// Фон всплывающих панелей (стиль, настройки, панель над выделением) - темнее страницы, в её тон.
    /// Чуть светлее самой страницы - панель читается как слой над ней, но остаётся в её цвете.
    var panelColor: NSColor { baseColor.blended(withFraction: 0.09, of: .white) ?? baseColor }

    /// Основной цвет фона - для окна, панелей и всего, что рисуется «в цвет страницы».
    var baseColor: NSColor {
        switch background {
        case .color(let id): Self.colors.first { $0.id == id }?.color ?? Self.colors[0].color
        case .gradient(let id): Self.gradients.first { $0.id == id }?.top ?? Self.colors[0].color
        case .image: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.14, alpha: 1)
        }
    }

    // MARK: шрифт

    /// Caveat мелкий, ему нужен кегль крупнее, чем системным шрифтам.
    var bodySize: CGFloat { (font == .hand ? 27 : 17.5) * Self.textScale }

    /// Размер текста из настроек: 0.88 - мелкий ... 1.3 - огромный.
    static var textScale: CGFloat {
        let value = UserDefaults.standard.double(forKey: "textScale")
        return value > 0 ? value : 1
    }
    var listSize: CGFloat { font == .hand ? 20 : 14 }

    private static var cache: [String: NSFont] = [:]

    func font(_ size: CGFloat, weight: CGFloat = 500) -> NSFont {
        let key = "\(font.rawValue)-\(size)-\(weight)"
        if let cached = Self.cache[key] { return cached }
        let made: NSFont
        if font == .hand {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .name: "Caveat-Regular",
                NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [0x7767_6874: weight],
            ])
            made = NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
        } else {
            let w: NSFont.Weight = weight >= 690 ? .bold : weight >= 620 ? .semibold : weight >= 480 ? .regular : .light
            let base = NSFont.systemFont(ofSize: size, weight: w)
            let design: NSFontDescriptor.SystemDesign = switch font {
            case .serif: .serif
            case .mono: .monospaced
            case .rounded: .rounded
            default: .default
            }
            made = base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
        Self.cache[key] = made
        return made
    }
}

// MARK: - вложения

/// Картинки, файлы и фоны лежат рядом с заметками - в папке Assets. Только локально.
enum Assets {
    static let folder: URL = {
        let url = Store.dataFolder.appendingPathComponent("Assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    /// Копия файла в папку вложений; вернёт имя копии.
    static func store(_ source: URL) -> String? {
        let ext = source.pathExtension.isEmpty ? "" : "." + source.pathExtension.lowercased()
        let name = UUID().uuidString.prefix(8) + "-" + source.deletingPathExtension().lastPathComponent.prefix(40) + ext
        let target = url(String(name))
        do {
            try FileManager.default.copyItem(at: source, to: target)
            return String(name)
        } catch {
            return nil
        }
    }

    /// Показать имя без служебного префикса.
    static func displayName(_ name: String) -> String {
        name.count > 9 && name.dropFirst(8).first == "-" ? String(name.dropFirst(9)) : name
    }

    private static var images: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        let image = NSImage(contentsOf: url(name))
        images[name] = image
        return image
    }

    static func pick(images only: Bool, multiple: Bool = false) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        if only { panel.allowedContentTypes = [.image] }
        return panel.runModal() == .OK ? panel.urls : []
    }
}

// MARK: - фон страницы в SwiftUI

/// Фон окна по стилю страницы: цвет, градиент или картинка с размытием и затемнением.
struct PageBackground: View {
    let style: PageStyle

    var body: some View {
        switch style.background {
        case .color:
            Color(nsColor: style.baseColor)
        case .gradient(let id):
            let g = PageStyle.gradients.first { $0.id == id } ?? PageStyle.gradients[0]
            LinearGradient(colors: [Color(nsColor: g.top), Color(nsColor: g.bottom)], startPoint: .top, endPoint: .bottom)
        case .image(let name):
            ZStack {
                Color(nsColor: style.baseColor)
                if let image = Assets.image(name) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 30)
                        .overlay(Color.black.opacity(0.35))
                }
            }
            .clipped()
        }
    }
}
