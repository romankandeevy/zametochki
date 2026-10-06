import AppKit

/// Форматирование как в Notion и Craft: никаких символов разметки в тексте.
/// Стили - это свойства букв (жирный, курсив, цвет...), а тип строки (заголовок, список, код, картинка...) -
/// свойство абзаца. Маркеры, галочки, фон кода, картинки и карточки рисует редактор.

extension NSAttributedString.Key {
    static let zBold = NSAttributedString.Key("z.bold")
    static let zItalic = NSAttributedString.Key("z.italic")
    static let zUnderline = NSAttributedString.Key("z.underline")
    static let zStrike = NSAttributedString.Key("z.strike")
    static let zHighlight = NSAttributedString.Key("z.highlight")
    static let zColor = NSAttributedString.Key("z.color")
    static let zBlock = NSAttributedString.Key("z.block")
    /// Карточка вложенной страницы: id заметки-страницы. Сама карточка - один символ-вложение.
    static let zPage = NSAttributedString.Key("z.page")
    /// Картинка и файл - имя копии в папке вложений.
    static let zImage = NSAttributedString.Key("z.image")
    static let zFile = NSAttributedString.Key("z.file")
    /// Ширина картинки - доля ширины колонки (0.2…1).
    static let zImageWidth = NSAttributedString.Key("z.imageWidth")
    /// Язык блока кода (rawValue CodeLanguage); нет - «Авто».
    static let zLang = NSAttributedString.Key("z.lang")
    /// Таблица - ячейки JSON-строкой.
    static let zTable = NSAttributedString.Key("z.table")
    /// Сворачиваемый список свёрнут (ставится на строку-заголовок).
    static let zCollapsed = NSAttributedString.Key("z.collapsed")
    /// Строка внутри свёрнутого списка - не рисуется. Вычисляется при отрисовке, в файл не идёт.
    static let zHidden = NSAttributedString.Key("z.hidden")

    static let inlineStyles: [NSAttributedString.Key] = [.zBold, .zItalic, .zUnderline, .zStrike, .zHighlight]
    /// Всё смысловое, что живёт рядом с внешним видом и переживает перерисовку.
    static let semantic: [NSAttributedString.Key] = inlineStyles + [.zColor, .zBlock, .zPage, .zImage, .zImageWidth, .zFile, .zTable, .zLang,
                                                                  .zCollapsed, .zHidden, .attachment]
}

/// Тип абзаца.
enum Block: String, CaseIterable {
    case text, title, heading, subheading, bullet, numbered, todo, done, toggle, toggleItem, quote, code
    case page, divider, image, file, table

    var name: String {
        switch self {
        case .text: "Текст"
        case .title: "Заголовок"
        case .heading: "Подзаголовок"
        case .subheading: "Маленький заголовок"
        case .bullet: "Список"
        case .numbered: "Нумерованный список"
        case .todo, .done: "Чеклист"
        case .toggle: "Сворачиваемый список"
        case .toggleItem: "Внутри сворачиваемого"
        case .quote: "Цитата"
        case .code: "Код"
        case .page: "Страница"
        case .divider: "Разделитель"
        case .image: "Картинка"
        case .file: "Файл"
        case .table: "Таблица"
        }
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .title: "textformat.size.larger"
        case .heading: "textformat.size"
        case .subheading: "textformat.size.smaller"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .todo, .done: "checklist"
        case .toggle, .toggleItem: "chevron.right.square"
        case .quote: "text.quote"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .page: "doc.text"
        case .divider: "minus"
        case .image: "photo"
        case .file: "paperclip"
        case .table: "tablecells"
        }
    }

    /// Слова для поиска в меню «/»: «/h1», «/заг», «/код», «/табл»…
    var keywords: [String] {
        switch self {
        case .text: ["текст", "text", "обычн"]
        case .title: ["h1", "заголовок", "title", "heading"]
        case .heading: ["h2", "подзаголовок", "subtitle"]
        case .subheading: ["h3", "маленький", "малый"]
        case .bullet: ["список", "bullet", "list", "точк", "-"]
        case .numbered: ["нумер", "1.", "number", "ol"]
        case .todo, .done: ["чек", "задач", "todo", "check", "[]"]
        case .toggle, .toggleItem: ["свор", "toggle", "скрыт"]
        case .quote: ["цитат", "quote", ">"]
        case .code: ["код", "code", "```"]
        case .page: ["страниц", "page", "вложен"]
        case .divider: ["раздел", "линия", "divider", "---"]
        case .image: ["картин", "фото", "image", "img", "изображ"]
        case .file: ["файл", "file"]
        case .table: ["табл", "table"]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return q.isEmpty || name.lowercased().contains(q) || keywords.contains { $0.hasPrefix(q) || q.hasPrefix($0) && $0.count >= 2 }
    }

    var isList: Bool { [.bullet, .numbered, .todo, .done].contains(self) }
    var isHeading: Bool { [.title, .heading, .subheading].contains(self) }
    /// Строка-предмет: один символ-вложение (карточка, картинка, файл, таблица, разделитель).
    var isObject: Bool { [.page, .divider, .image, .file, .table].contains(self) }
    /// Тип, который продолжается на следующей строке после Enter.
    var continues: Bool { isList || [.quote, .code, .toggleItem].contains(self) }

    /// Пункты меню «Превратить в» (done - это тот же чеклист, только отмеченный).
    static let menu: [Block] = [.text, .title, .heading, .subheading, .bullet, .numbered, .todo, .toggle, .quote, .code, .page]
}

/// Цвета маркера (фон под словами) - полупрозрачные, чтобы текст читался на любой странице.
enum MarkColor: String, CaseIterable {
    case yellow, green, blue, pink, purple, orange, red, gray

    /// Значение атрибута: имя цвета, а у старых заметок просто true - это жёлтый.
    static func of(_ value: Any?) -> MarkColor {
        (value as? String).flatMap(MarkColor.init) ?? .yellow
    }

    var name: String {
        switch self {
        case .yellow: "Жёлтый"
        case .green: "Зелёный"
        case .blue: "Синий"
        case .pink: "Розовый"
        case .purple: "Фиолетовый"
        case .orange: "Оранжевый"
        case .red: "Красный"
        case .gray: "Серый"
        }
    }

    var color: NSColor {
        switch self {
        case .yellow: NSColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 0.32)
        case .green: NSColor(srgbRed: 0.35, green: 0.9, blue: 0.5, alpha: 0.3)
        case .blue: NSColor(srgbRed: 0.35, green: 0.65, blue: 1, alpha: 0.35)
        case .pink: NSColor(srgbRed: 1, green: 0.45, blue: 0.75, alpha: 0.32)
        case .purple: NSColor(srgbRed: 0.65, green: 0.45, blue: 1, alpha: 0.35)
        case .orange: NSColor(srgbRed: 1, green: 0.6, blue: 0.25, alpha: 0.34)
        case .red: NSColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 0.34)
        case .gray: NSColor(white: 1, alpha: 0.18)
        }
    }

    /// Последний выбранный - его ставит кнопка-маркер и ⇧⌘M.
    static var last: MarkColor {
        get { UserDefaults.standard.string(forKey: "lastMark").flatMap(MarkColor.init) ?? .yellow }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lastMark") }
    }
}

/// Цвета текста - мягкие, чтобы жить на тёмном фоне.
enum TextColor: String, CaseIterable, Codable {
    case white, yellow, pink, green, sky, gray, orange, lavender, mint, peach, lemon, coral, blue

    var name: String {
        switch self {
        case .white: "Белый"
        case .yellow: "Жёлтый"
        case .pink: "Розовый"
        case .green: "Зелёный"
        case .sky: "Голубой"
        case .gray: "Серый"
        case .orange: "Оранжевый"
        case .lavender: "Лавандовый"
        case .mint: "Мятный"
        case .peach: "Персиковый"
        case .lemon: "Лимонный"
        case .coral: "Коралловый"
        case .blue: "Синий"
        }
    }

    var color: NSColor {
        switch self {
        case .white: .white
        case .yellow: NSColor(srgbRed: 1, green: 0.88, blue: 0.48, alpha: 1)
        case .pink: NSColor(srgbRed: 1, green: 0.66, blue: 0.80, alpha: 1)
        case .green: NSColor(srgbRed: 0.64, green: 0.94, blue: 0.72, alpha: 1)
        case .sky: NSColor(srgbRed: 0.64, green: 0.86, blue: 1, alpha: 1)
        case .gray: NSColor(white: 1, alpha: 0.6)
        case .orange: NSColor(srgbRed: 1, green: 0.72, blue: 0.45, alpha: 1)
        case .lavender: NSColor(srgbRed: 0.80, green: 0.73, blue: 1, alpha: 1)
        case .mint: NSColor(srgbRed: 0.60, green: 1, blue: 0.88, alpha: 1)
        case .peach: NSColor(srgbRed: 1, green: 0.80, blue: 0.72, alpha: 1)
        case .lemon: NSColor(srgbRed: 1, green: 0.97, blue: 0.62, alpha: 1)
        case .coral: NSColor(srgbRed: 1, green: 0.56, blue: 0.56, alpha: 1)
        case .blue: NSColor(srgbRed: 0.58, green: 0.72, blue: 1, alpha: 1)
        }
    }
}

enum Formatting {
    static let listIndent: CGFloat = 30
    static let quoteIndent: CGFloat = 20
    static let codeIndent: CGFloat = 16

    static func block(of attrs: [NSAttributedString.Key: Any]) -> Block {
        (attrs[.zBlock] as? String).flatMap(Block.init) ?? .text
    }

    // MARK: внешний вид из смысла

    /// Атрибуты для отрисовки: шрифт, цвет, отступы - из смысловых (жирный, тип абзаца...).
    static func visual(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let style = PageStyle.current
        let block = block(of: attrs)
        let base = style.bodySize
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        // Свёрнутая строка сворачиваемого списка: нулевая высота, ничего не видно.
        if attrs[.zHidden] != nil {
            paragraph.minimumLineHeight = 0.01
            paragraph.maximumLineHeight = 0.01
            var out: [NSAttributedString.Key: Any] = [
                .font: style.font(1), .foregroundColor: NSColor.clear, .paragraphStyle: paragraph,
            ]
            for key in NSAttributedString.Key.semantic where attrs[key] != nil { out[key] = attrs[key] }
            return out
        }

        let size: CGFloat = switch block {
        case .title: base * 1.55
        case .heading: base * 1.3
        case .subheading: base * 1.12
        case .code: base * (style.font == .hand ? 0.55 : 0.85)
        default: base
        }
        let bold = attrs[.zBold] != nil
        let italic = attrs[.zItalic] != nil
        let weight: CGFloat = bold || block.isHeading ? 700 : italic ? 400 : Style.weight
        var color = (attrs[.zColor] as? String).flatMap(TextColor.init)?.color ?? style.text.color
        if block == .done { color = color.withAlphaComponent(color.alphaComponent * 0.45) }
        if block == .quote { color = color.withAlphaComponent(color.alphaComponent * 0.85) }

        // Caveat сам по себе с большим воздухом; системным шрифтам межстрочный нужен больше.
        let hand = style.font == .hand
        paragraph.lineSpacing = size * (hand ? 0.1 : 0.32)
        if !hand { paragraph.paragraphSpacing = size * 0.18 }
        if block.isHeading { paragraph.paragraphSpacingBefore = size * (hand ? 0.3 : 0.5) }
        if block.isList || block == .toggle || block == .toggleItem {
            paragraph.firstLineHeadIndent = listIndent
            paragraph.headIndent = listIndent
        }
        if block == .quote { paragraph.firstLineHeadIndent = quoteIndent; paragraph.headIndent = quoteIndent }
        if block == .code {
            paragraph.firstLineHeadIndent = codeIndent
            paragraph.headIndent = codeIndent
            paragraph.tailIndent = -codeIndent
            paragraph.lineSpacing = 3
        }
        if block.isObject { paragraph.paragraphSpacingBefore = 6; paragraph.paragraphSpacing = 6; paragraph.lineSpacing = 0 }
        // Картинка - по центру колонки.
        if block == .image { paragraph.alignment = .center; paragraph.paragraphSpacingBefore = 10; paragraph.paragraphSpacing = 10 }

        let font: NSFont = block == .code
            ? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
            : style.font(size, weight: weight)
        var out: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        // У Caveat максимум 700 - мало отличается от обычного 500, жирный дотягиваем тонкой обводкой.
        if bold, style.font == .hand, block != .code { out[.strokeWidth] = -1.8; out[.strokeColor] = color }
        // Caveat и так с наклоном: курсиву нужен заметно сильнее наклон.
        if italic { out[.obliqueness] = style.font == .hand ? 0.3 : 0.2 }
        if attrs[.zUnderline] != nil { out[.underlineStyle] = NSUnderlineStyle.single.rawValue; out[.underlineColor] = color }
        if attrs[.zStrike] != nil || block == .done {
            out[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            out[.strikethroughColor] = color
        }
        if let mark = attrs[.zHighlight] { out[.backgroundColor] = MarkColor.of(mark).color }
        // Смысловые атрибуты живут рядом с внешними.
        for key in NSAttributedString.Key.semantic where key != .zHidden && attrs[key] != nil { out[key] = attrs[key] }
        return out
    }

    /// Пересчитать внешний вид всего текста. Тип абзаца выравнивается по его последней букве
    /// (обычно это перенос строки): она не меняется, когда печатаешь в начале или середине строки.
    /// Строки внутри свёрнутого списка помечаются скрытыми.
    static func render(_ storage: NSTextStorage) {
        let ns = storage.string as NSString
        let all = NSRange(location: 0, length: ns.length)
        var collapsed = false
        ns.enumerateSubstrings(in: all, options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            guard enclosing.length > 0 else { return }
            var block = storage.attribute(.zBlock, at: NSMaxRange(enclosing) - 1, effectiveRange: nil) as? String
            // Символ-предмет в строке задаёт её тип сам: строка с картинкой - картинка.
            let objectAt = ns.range(of: "\u{FFFC}", options: [], range: enclosing).location
            if objectAt != NSNotFound, let own = storage.attribute(.zBlock, at: objectAt, effectiveRange: nil) as? String,
               Block(rawValue: own)?.isObject == true {
                block = own
            } else if let b = block.flatMap(Block.init), b.isObject {
                // Строка-предмет без своего символа (его стёрли) - обычный текст.
                block = nil
            }
            if let block {
                storage.addAttribute(.zBlock, value: block, range: enclosing)
            } else {
                storage.removeAttribute(.zBlock, range: enclosing)
            }
            let kind = block.flatMap(Block.init) ?? .text
            if kind == .toggle {
                collapsed = storage.attribute(.zCollapsed, at: NSMaxRange(enclosing) - 1, effectiveRange: nil) != nil
                if collapsed { storage.addAttribute(.zCollapsed, value: true, range: enclosing) } else { storage.removeAttribute(.zCollapsed, range: enclosing) }
                storage.removeAttribute(.zHidden, range: enclosing)
            } else if kind == .toggleItem, collapsed {
                storage.addAttribute(.zHidden, value: true, range: enclosing)
            } else {
                if kind != .toggleItem { collapsed = false }
                storage.removeAttribute(.zHidden, range: enclosing)
                storage.removeAttribute(.zCollapsed, range: enclosing)
            }
        }
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: all) { attrs, range, _ in runs.append((range, visual(attrs))) }
        for (range, attrs) in runs { storage.setAttributes(attrs, range: range) }
        padCodeGroups(storage)
    }

    /// Блоки кода: отступ сверху под шапку («КОД», язык, «Скопировать»), снизу - воздух; язык у всего блока
    /// один (берётся с первой строки), текст раскрашивается.
    private static func padCodeGroups(_ storage: NSTextStorage) {
        for group in codeGroups(in: storage) {
            let ns = storage.string as NSString
            let first = ns.paragraphRange(for: NSRange(location: group.location, length: 0))
            let last = ns.paragraphRange(for: NSRange(location: max(NSMaxRange(group) - 1, group.location), length: 0))
            for (range, isFirst) in [(first, true), (last, false)] {
                guard range.length > 0,
                      let style = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?
                        .mutableCopy() as? NSMutableParagraphStyle else { continue }
                if isFirst { style.paragraphSpacingBefore = 44 } else { style.paragraphSpacing = 18 }
                if first == last { style.paragraphSpacingBefore = 44; style.paragraphSpacing = 18 }
                storage.addAttribute(.paragraphStyle, value: style, range: range)
            }
            let lang = storage.attribute(.zLang, at: group.location, effectiveRange: nil) as? String
            if let lang { storage.addAttribute(.zLang, value: lang, range: group) } else { storage.removeAttribute(.zLang, range: group) }
            CodeHighlight.apply(storage, range: group, language: language(of: group, in: storage))
        }
    }

    /// Подряд идущие строки кода - один блок.
    static func codeGroups(in storage: NSAttributedString) -> [NSRange] {
        let ns = storage.string as NSString
        var groups: [NSRange] = []
        var current: NSRange?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
            let code = enclosing.length > 0 && storage.attribute(.zBlock, at: enclosing.location, effectiveRange: nil) as? String == Block.code.rawValue
            if code {
                current = current.map { NSUnionRange($0, enclosing) } ?? enclosing
            } else if let c = current {
                groups.append(c)
                current = nil
            }
        }
        if let c = current { groups.append(c) }
        return groups
    }

    /// Язык блока: выбранный вручную или угаданный по тексту.
    static func language(of group: NSRange, in storage: NSAttributedString) -> CodeLanguage {
        if group.length > 0, let raw = storage.attribute(.zLang, at: group.location, effectiveRange: nil) as? String,
           let lang = CodeLanguage(rawValue: raw) { return lang }
        return CodeLanguage.detect((storage.string as NSString).substring(with: group))
    }

    // MARK: файл

    struct Doc: Codable, Equatable {
        var text: String
        var runs: [Run] = []
        /// Страница внутри другой заметки - id родителя; nil - заметка верхнего уровня.
        var parent: String?
        /// Место среди соседей в списке слева (меньше - выше). nil у старых заметок - по дате.
        var order: Double?
        /// Стиль страницы; nil у старых заметок - стиль по умолчанию.
        var style: PageStyle?
        ///Tags
        var tags: [String]? = nil
    }

    /// Кусок текста с одинаковым оформлением. Позиции - в UTF-16, как в NSString.
    struct Run: Codable, Equatable {
        var from: Int
        var length: Int
        var bold: Bool?
        var italic: Bool?
        var underline: Bool?
        var strike: Bool?
        var highlight: Bool?
        /// Цвет маркера; nil - жёлтый (так было у всех старых заметок).
        var mark: String?
        var color: String?
        var block: String?
        var page: String?
        var image: String?
        var imageWidth: Double?
        var file: String?
        var table: String?
        var collapsed: Bool?
        var lang: String?

        /// То же оформление, без учёта места.
        func sameLook(_ other: Run) -> Bool {
            var a = self, b = other
            a.from = 0; a.length = 0; b.from = 0; b.length = 0
            return a == b
        }
    }

    static func attributed(_ doc: Doc) -> NSAttributedString {
        let out = NSMutableAttributedString(string: doc.text)
        let length = out.length
        for run in doc.runs {
            let range = NSIntersectionRange(NSRange(location: run.from, length: run.length), NSRange(location: 0, length: length))
            guard range.length > 0 else { continue }
            var attrs: [NSAttributedString.Key: Any] = [:]
            if run.bold == true { attrs[.zBold] = true }
            if run.italic == true { attrs[.zItalic] = true }
            if run.underline == true { attrs[.zUnderline] = true }
            if run.strike == true { attrs[.zStrike] = true }
            if run.highlight == true { attrs[.zHighlight] = run.mark ?? MarkColor.yellow.rawValue }
            if let color = run.color { attrs[.zColor] = color }
            if let block = run.block { attrs[.zBlock] = block }
            if run.collapsed == true { attrs[.zCollapsed] = true }
            if let lang = run.lang { attrs[.zLang] = lang }
            if let page = run.page { attrs[.zPage] = page }
            if let image = run.image { attrs[.zImage] = image }
            if let width = run.imageWidth { attrs[.zImageWidth] = width }
            if let file = run.file { attrs[.zFile] = file }
            if let table = run.table { attrs[.zTable] = table }
            if let attachment = Objects.attachment(for: attrs) { attrs[.attachment] = attachment }
            out.addAttributes(attrs, range: range)
        }
        return out
    }

    static func doc(from storage: NSAttributedString) -> Doc {
        var runs: [Run] = []
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, _ in
            var run = Run(from: range.location, length: range.length)
            if attrs[.zBold] != nil { run.bold = true }
            if attrs[.zItalic] != nil { run.italic = true }
            if attrs[.zUnderline] != nil { run.underline = true }
            if attrs[.zStrike] != nil { run.strike = true }
            if let mark = attrs[.zHighlight] {
                run.highlight = true
                let color = MarkColor.of(mark)
                if color != .yellow { run.mark = color.rawValue }
            }
            run.color = attrs[.zColor] as? String
            run.block = attrs[.zBlock] as? String
            run.page = attrs[.zPage] as? String
            run.image = attrs[.zImage] as? String
            run.imageWidth = attrs[.zImageWidth] as? Double
            run.file = attrs[.zFile] as? String
            run.table = attrs[.zTable] as? String
            if attrs[.zCollapsed] != nil { run.collapsed = true }
            run.lang = attrs[.zLang] as? String
            let empty = Run(from: run.from, length: run.length)
            guard run != empty else { return }
            // Соседние куски с одинаковым оформлением склеиваем.
            if var last = runs.last, last.from + last.length == run.from, last.sameLook(run) {
                last.length += run.length
                runs[runs.count - 1] = last
            } else {
                runs.append(run)
            }
        }
        return Doc(text: storage.string, runs: runs)
    }

    // MARK: карточки страниц

    /// Строка-карточка: один символ-вложение, тип абзаца «страница».
    static func card(_ id: String) -> NSAttributedString {
        object([.zPage: id, .zBlock: Block.page.rawValue])
    }

    /// Строка-предмет: символ-вложение со своим типом абзаца и данными (картинка, файл, таблица...).
    static func object(_ attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attrs = attrs
        attrs[.attachment] = Objects.attachment(for: attrs)
        return NSAttributedString(string: "\u{FFFC}", attributes: attrs)
    }

    static func appendCard(_ id: String, to text: NSMutableAttributedString) {
        if text.length > 0, !text.string.hasSuffix("\n") {
            text.append(NSAttributedString(string: "\n"))
        }
        text.append(card(id))
    }

    /// Убрать строки-карточки этой страницы вместе с их переносом строки.
    static func removeCards(of id: String, in text: NSMutableAttributedString) {
        var ranges: [NSRange] = []
        text.enumerateAttribute(.zPage, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value as? String == id { ranges.append(range) }
        }
        let ns = text.string as NSString
        for range in ranges.reversed() {
            var paragraph = ns.paragraphRange(for: range)
            // Последняя строка без своего переноса - забираем перенос перед ней.
            if NSMaxRange(paragraph) == ns.length, !ns.substring(with: paragraph).hasSuffix("\n"), paragraph.location > 0 {
                paragraph = NSRange(location: paragraph.location - 1, length: paragraph.length + 1)
            }
            text.deleteCharacters(in: paragraph)
        }
    }

    // MARK: старые заметки с разметкой

    /// Переводит старый .txt со звёздочками и решётками в новый формат: разметка убирается, оформление остаётся.
    static func fromMarkdown(_ text: String) -> Doc {
        let out = NSMutableAttributedString(string: text)
        // Типы строк по префиксам.
        // Длинные префиксы раньше коротких: «- [ ] » - это чеклист, а не список.
        let prefixes: [(String, Block)] = [
            ("### ", .subheading), ("## ", .heading), ("# ", .title),
            ("- [ ] ", .todo), ("- [x] ", .done), ("- [X] ", .done), ("[ ] ", .todo), ("[x] ", .done),
            ("- ", .bullet), ("* ", .bullet), ("• ", .bullet), ("☐ ", .todo), ("☑ ", .done), ("> ", .quote),
        ]
        let numbered = try! NSRegularExpression(pattern: #"^\d+[.)] "#)
        var location = 0
        while location < out.length {
            let ns = out.string as NSString
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let content = ns.substring(with: line)
            var lineLength = line.length
            var found = prefixes.first(where: { content.hasPrefix($0.0) })
            if found == nil, let m = numbered.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) {
                found = ((content as NSString).substring(with: m.range), .numbered)
            }
            if let (prefix, block) = found {
                let p = (prefix as NSString).length
                out.deleteCharacters(in: NSRange(location: line.location, length: p))
                lineLength -= p
                out.addAttribute(.zBlock, value: block.rawValue, range: NSRange(location: line.location, length: lineLength))
            }
            location = line.location + max(lineLength, 1)
        }
        // Стили внутри строк: убираем пары символов, помечаем текст между ними.
        let inline: [(String, [NSAttributedString.Key])] = [
            (#"(?<!\*)\*\*\*(?=[^\s*])(.+?)(?<=[^\s*])\*\*\*(?!\*)"#, [.zBold, .zItalic]),
            (#"(?<!\*)\*\*(?=[^\s*])(.+?)(?<=[^\s*])\*\*(?!\*)"#, [.zBold]),
            (#"(?<!\w)_(?![\s_])(.+?)(?<![\s_])_(?!\w)"#, [.zItalic]),
            (#"(?<![*\w])\*(?![*\s])(.+?)(?<![*\s])\*(?![*\w])"#, [.zItalic]),
            (#"~~(?=\S)(.+?)(?<=\S)~~"#, [.zStrike]),
            (#"==(?=\S)(.+?)(?<=\S)=="#, [.zHighlight]),
        ]
        for (pattern, keys) in inline {
            let re = try! NSRegularExpression(pattern: pattern)
            let matches = re.matches(in: out.string, range: NSRange(location: 0, length: out.length))
            for m in matches.reversed() {
                let inner = m.range(at: 1)
                for key in keys { out.addAttribute(key, value: key == .zHighlight ? MarkColor.yellow.rawValue as Any : true, range: inner) }
                let closing = NSRange(location: NSMaxRange(inner), length: NSMaxRange(m.range) - NSMaxRange(inner))
                let opening = NSRange(location: m.range.location, length: inner.location - m.range.location)
                out.deleteCharacters(in: closing)
                out.deleteCharacters(in: opening)
            }
        }
        // Оборванные хвосты старой разметки (одинокие ~~ и т.п.) просто убираем.
        for junk in ["~~", "**"] {
            while let r = out.string.range(of: junk) {
                out.deleteCharacters(in: NSRange(r, in: out.string))
            }
        }
        return doc(from: out)
    }
}
