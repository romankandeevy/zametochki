import AppKit
import UniformTypeIdentifiers

/// Копирование, экспорт и импорт. Всё через локальные файлы и буфер обмена.
enum Transfer {
    // MARK: из заметки наружу

    /// Текст с маркерами списков, как его увидит человек в любом другом приложении.
    static func plainText(_ doc: Formatting.Doc) -> String {
        exportParagraphs(doc).map { $0.prefix + $0.text }.joined(separator: "\n")
    }

    static func markdown(_ doc: Formatting.Doc) -> String {
        let storage = Formatting.attributed(doc)
        var lines: [String] = []
        var number = 0
        let ns = storage.string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, range, enclosing, _ in
            let attrs = enclosing.length > 0 ? storage.attributes(at: NSMaxRange(enclosing) - 1, effectiveRange: nil) : [:]
            let block = Formatting.block(of: attrs)
            number = block == .numbered ? number + 1 : 0
            var line = ""
            storage.enumerateAttributes(in: range) { attrs, sub, _ in
                var piece = ns.substring(with: sub)
                let core = piece.trimmingCharacters(in: .whitespaces)
                guard !core.isEmpty else { line += piece; return }
                var wrapped = core
                if attrs[.zStrike] != nil { wrapped = "~~\(wrapped)~~" }
                if attrs[.zItalic] != nil { wrapped = "_\(wrapped)_" }
                if attrs[.zBold] != nil { wrapped = "**\(wrapped)**" }
                if attrs[.zHighlight] != nil { wrapped = "==\(wrapped)==" }
                piece = piece.replacingOccurrences(of: core, with: wrapped)
                line += piece
            }
            let prefix: String = switch block {
            case .title: "# "
            case .heading: "## "
            case .subheading: "### "
            case .bullet: "- "
            case .numbered: "\(number). "
            case .todo: "- [ ] "
            case .done: "- [x] "
            case .quote: "> "
            case .toggle: "- "
            case .toggleItem: "  - "
            case .code: "    "
            case .text, .page, .divider, .image, .file, .table, .board: ""
            }
            if block.isObject {
                lines.append(objectText(block, storage, range, markdown: true))
            } else {
                lines.append(prefix + line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Оформленный текст для RTF и буфера обмена: маркеры списков становятся символами.
    static func richText(_ doc: Formatting.Doc) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let source = Formatting.attributed(doc)
        let storage = NSTextStorage(attributedString: source)
        Formatting.render(storage)
        let paragraphs = exportParagraphs(doc)
        for (i, p) in paragraphs.enumerated() {
            let base = p.range.length > 0 ? storage.attributes(at: p.range.location, effectiveRange: nil) : Formatting.visual([:])
            if !p.prefix.isEmpty { out.append(NSAttributedString(string: p.prefix, attributes: base)) }
            if p.text.contains("\u{FFFC}") || p.isObject {
                out.append(NSAttributedString(string: p.text, attributes: [.font: NSFont.systemFont(ofSize: 14)]))
            } else {
                out.append(storage.attributedSubstring(from: p.range))
            }
            if i < paragraphs.count - 1 { out.append(NSAttributedString(string: "\n", attributes: base)) }
        }
        // Цвета у нас светлые под синий фон - в чужом белом документе их не видно, поэтому делаем текст тёмным.
        out.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: out.length)) { _, range, _ in
            out.addAttribute(.foregroundColor, value: NSColor.black, range: range)
        }
        out.removeAttribute(.strokeColor, range: NSRange(location: 0, length: out.length))
        out.addAttribute(.strokeColor, value: NSColor.black, range: NSRange(location: 0, length: out.length))
        return out
    }

    private struct ExportParagraph { let prefix: String; let text: String; let range: NSRange; var isObject = false }

    private static func exportParagraphs(_ doc: Formatting.Doc) -> [ExportParagraph] {
        let storage = Formatting.attributed(doc)
        let ns = storage.string as NSString
        var result: [ExportParagraph] = []
        var number = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { text, range, enclosing, _ in
            let attrs = enclosing.length > 0 ? storage.attributes(at: NSMaxRange(enclosing) - 1, effectiveRange: nil) : [:]
            let block = Formatting.block(of: attrs)
            number = block == .numbered ? number + 1 : 0
            let prefix: String = switch block {
            case .bullet: PageStyle.current.bulletStyle == .dash ? "– " : "• "
            case .numbered: "\(number). "
            case .todo: "☐ "
            case .done: "☑ "
            case .quote: "│ "
            case .toggle: "▸ "
            case .toggleItem, .code: "    "
            default: ""
            }
            let line = block.isObject ? objectText(block, storage, range, markdown: false) : text ?? ""
            result.append(ExportParagraph(prefix: prefix, text: line, range: range, isObject: block.isObject))
        }
        return result
    }

    /// Предметы в тексте - символы-вложения; наружу они уходят текстом: страница - названием,
    /// картинка и файл - именем, таблица - строками через «|».
    private static func objectText(_ block: Block, _ storage: NSAttributedString, _ range: NSRange, markdown: Bool) -> String {
        guard range.length > 0 else { return "" }
        let attrs = storage.attributes(at: range.location, effectiveRange: nil)
        switch block {
        case .page:
            let title = AppDelegate.store?.note(attrs[.zPage] as? String)?.title ?? "Страница"
            return "📄 " + title
        case .divider:
            return markdown ? "---" : "———"
        case .image:
            let name = attrs[.zImage] as? String ?? ""
            return markdown ? "![](\(Assets.url(name).absoluteString))" : "[картинка: \(Assets.displayName(name))]"
        case .file:
            let name = attrs[.zFile] as? String ?? ""
            return markdown ? "[\(Assets.displayName(name))](\(Assets.url(name).absoluteString))" : "[файл: \(Assets.displayName(name))]"
        case .table:
            let table = Table(json: attrs[.zTable] as? String ?? "")
            var rows = table.cells.map { "| " + $0.joined(separator: " | ") + " |" }
            if markdown, table.columns > 0 {
                rows.insert("|" + Array(repeating: " --- |", count: table.columns).joined(), at: min(1, rows.count))
            }
            return rows.joined(separator: "\n")
        case .board:
            let board = Board(json: attrs[.zBoard] as? String ?? "")
            let texts = board.items.filter { $0.holdsText }.map(\.text).filter { !$0.isEmpty }
            return (markdown ? "*Доска*" : "[доска]") + (texts.isEmpty ? "" : ": " + texts.joined(separator: " · "))
        default:
            return ""
        }
    }

    static func copy(_ doc: Formatting.Doc) {
        let board = NSPasteboard.general
        board.clearContents()
        let rich = richText(doc)
        if let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length),
                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            board.setData(rtf, forType: .rtf)
        }
        board.setString(plainText(doc), forType: .string)
    }

    enum Format: String, CaseIterable {
        case markdown, text, rtf

        var name: String {
            switch self {
            case .markdown: "Markdown (.md)"
            case .text: "Текст (.txt)"
            case .rtf: "RTF (.rtf) - для Pages и Word"
            }
        }

        var type: UTType {
            switch self {
            case .markdown: UTType(filenameExtension: "md") ?? .plainText
            case .text: .plainText
            case .rtf: .rtf
            }
        }
    }

    static func export(_ note: Note, as format: Format) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = safeFileName(note.title)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data?
        switch format {
        case .markdown: data = markdown(note.doc).data(using: .utf8)
        case .text: data = plainText(note.doc).data(using: .utf8)
        case .rtf:
            let rich = richText(note.doc)
            data = try? rich.data(from: NSRange(location: 0, length: rich.length),
                                  documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        }
        try? data?.write(to: url, options: .atomic)
    }

    /// Все заметки разом - в выбранную папку, Markdown-файлами. Вложенные страницы - в папке своей заметки.
    /// Вернёт, сколько файлов записано (nil - отменили).
    static func exportAll(_ store: Store) -> Int? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Сохранить сюда"
        panel.message = "Куда сохранить все заметки (Markdown)"
        guard panel.runModal() == .OK, let base = panel.url else { return nil }
        let root = base.appendingPathComponent("Заметочки", isDirectory: true)
        var written = 0
        func write(_ parent: String?, into folder: URL) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var used: Set<String> = []
            for note in store.children(of: parent) {
                var name = safeFileName(note.title.isEmpty ? "Без названия" : note.title)
                var n = 2
                while used.contains(name.lowercased()) { name = safeFileName(note.title) + " \(n)"; n += 1 }
                used.insert(name.lowercased())
                if (try? markdown(note.doc).data(using: .utf8)?.write(to: folder.appendingPathComponent(name + ".md"), options: .atomic)) != nil {
                    written += 1
                }
                if store.hasChildren(note.id) { write(note.id, into: folder.appendingPathComponent(name, isDirectory: true)) }
            }
        }
        write(nil, into: root)
        NSWorkspace.shared.activateFileViewerSelecting([root])
        return written
    }

    private static func safeFileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        return String(cleaned.prefix(60))
    }

    // MARK: снаружи в заметку

    /// Выбор файлов (.txt, .md, .rtf) - каждый становится новой заметкой.
    static func pickFiles() -> [Formatting.Doc] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .rtf, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap(read)
    }

    static func read(_ url: URL) -> Formatting.Doc? {
        switch url.pathExtension.lowercased() {
        case "rtf":
            guard let rich = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                     documentAttributes: nil) else { return nil }
            return fromRich(rich)
        default:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Formatting.fromMarkdown(text)
        }
    }

    /// Из чужого оформленного текста берём смысл: жирный, курсив, подчёркнутый, зачёркнутый.
    static func fromRich(_ rich: NSAttributedString) -> Formatting.Doc {
        let out = NSMutableAttributedString(string: rich.string)
        rich.enumerateAttributes(in: NSRange(location: 0, length: rich.length)) { attrs, range, _ in
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) { out.addAttribute(.zBold, value: true, range: range) }
                if traits.contains(.italic) { out.addAttribute(.zItalic, value: true, range: range) }
            }
            if (attrs[.underlineStyle] as? Int ?? 0) != 0 { out.addAttribute(.zUnderline, value: true, range: range) }
            if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 { out.addAttribute(.zStrike, value: true, range: range) }
        }
        return Formatting.doc(from: out)
    }
}
