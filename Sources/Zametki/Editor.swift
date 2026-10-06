import AppKit
import SwiftUI

/// NSTextView на TextKit 1: через его временные атрибуты плавно проявляются новые буквы,
/// а свой NSLayoutManager красит выделение в наш цвет.
struct Editor: NSViewRepresentable {
    let store: Store

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.wantsLayer = true

        let text = NotesTextView(usingTextLayoutManager: false)
        text.textContainer?.replaceLayoutManager(NotesLayoutManager())
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text

        text.delegate = context.coordinator
        text.drawsBackground = false
        // Rich text выключен: вставка приносит только буквы, оформление ставим сами.
        text.isRichText = false
        text.allowsUndo = true
        text.isAutomaticTextReplacementEnabled = false
        Coordinator.applySettings(to: text)
        text.textContainerInset = NSSize(width: 28, height: 20)
        text.insertionPointColor = Style.text
        text.selectedTextAttributes = [.backgroundColor: NotesLayoutManager.selection]
        // Блоки из панели «Вставить» и файлы из Finder можно бросать прямо в текст.
        text.registerForDraggedTypes([NotesTextView.blockType, .fileURL])
        text.typingAttributes = Formatting.visual([:])
        context.coordinator.textView = text
        context.coordinator.scrollView = scroll
        Coordinator.active = context.coordinator
        text.layoutManager?.delegate = context.coordinator
        context.coordinator.connectDictation()
        AudioPlayer.shared.onChange = { [weak text] in text?.needsDisplay = true }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.show(store.selected)
    }

    enum Command: Hashable {
        case bold, italic, underline, strike, highlight
        case color(TextColor)
        /// Маркер выбранного цвета; nil - снять маркер.
        case mark(MarkColor?)
        case block(Block)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        /// Редактор, в который идут команды меню «Формат».
        static weak var active: Coordinator?

        let store: Store
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var shownID: String?
        private var shownRevision = 0
        private var pendingFade: NSRange?
        private var fades: [(range: NSRange, start: CFTimeInterval)] = []
        private var fadeTimer: Timer?
        private var editingSelf = false
        private var barMode = FormatBar.Mode.main
        /// Где стоит «/», открывший меню типа строки, и какой пункт подсвечен стрелками.
        private(set) var slashAt: Int?
        private var slashCandidate: Int?
        private var slashIndex = 0
        /// Меню «+» слева от строки: для какого абзаца открыто.
        private(set) var plusParagraph: NSRange?
        /// Пункты меню «+» и «/»: сначала типы строки, потом предметы.
        static let menuBlocks = Block.basic + Block.objects
        var menuOpen: Bool { slashAt != nil || plusParagraph != nil }
        /// Что напечатано после «/» - по нему фильтруется меню («/h1», «/код»).
        private var slashQuery = ""
        /// Пункты открытого меню: у «/» - отфильтрованные, у «+» - все.
        private var menuItems: [Block] {
            slashAt != nil ? Self.menuBlocks.filter { $0.matches(slashQuery) } : Self.menuBlocks
        }

        static let fadeDuration: CFTimeInterval = 0.22

        init(store: Store) { self.store = store }

        func show(_ note: Note?) {
            guard let textView, let scrollView else { return }
            if let note, note.id == shownID {
                // Ту же заметку поменяли снаружи (карточки, перенесённые блоки) - перечитываем на месте.
                if note.revision != shownRevision, live == nil {
                    shownRevision = note.revision
                    applyStyle(note.doc.style ?? PageStyle.saved)
                    let selection = textView.selectedRange()
                    textView.textStorage?.setAttributedString(Formatting.attributed(note.doc))
                    render()
                    let length = (textView.string as NSString).length
                    textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
                    textView.needsDisplay = true
                }
                return
            }
            guard note?.id != shownID else { return }
            shownRevision = note?.revision ?? 0
            let first = shownID == nil
            shownID = note?.id
            fades.removeAll()
            hideBar()
            let swap = {
                self.applyStyle(note?.doc.style ?? PageStyle.saved)
                textView.textStorage?.setAttributedString(Formatting.attributed(note?.doc ?? .init(text: "")))
                self.render()
                textView.undoManager?.removeAllActions()
                textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
                textView.typingAttributes = self.attributesForTyping()
                textView.window?.makeFirstResponder(textView)
                self.applyFocus()
                self.updateStats()
                self.runDemoScript()
            }
            // Текст новой заметки ставим сразу: иначе первая буква, набранная во время анимации,
            // попала бы в старый текст и пропала при подмене.
            swap()
            if first { return }
            // Смена заметки: новая проявляется, чуть всплывая снизу.
            scrollView.alphaValue = 0
            do {
                guard let layer = scrollView.layer else { scrollView.alphaValue = 1; return }
                let rise = CABasicAnimation(keyPath: "transform.translation.y")
                rise.fromValue = -8
                rise.toValue = 0
                rise.duration = 0.28
                rise.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                layer.add(rise, forKey: "rise")
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.animator().alphaValue = 1
                }
            }
        }

        // MARK: ввод

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard let text else { return true }
            // «/» в начале пустой строки - откроется меню типа строки.
            if !editingSelf, text == "/", range.length == 0 {
                let paragraph = paragraphRange(at: range.location)
                let content = (textView.string as NSString).substring(with: paragraph).trimmingCharacters(in: .newlines)
                if content.isEmpty { slashCandidate = range.location }
            }
            if !editingSelf, let handled = capitalize(textView, range: range, typing: text) {
                return handled
            }
            if !editingSelf, let handled = blockKeys(textView, range: range, typing: text) {
                playSound(for: text)
                return handled
            }
            let length = (text as NSString).length
            pendingFade = length > 0 && length < 200 ? NSRange(location: range.location, length: length) : nil
            if !editingSelf, length <= 2 { playSound(for: text) }
            return true
        }

        /// Заглавная в начале строки и после конца предложения (. ! ? … и пробел).
        private func capitalize(_ textView: NSTextView, range: NSRange, typing text: String) -> Bool? {
            guard UserDefaults.standard.object(forKey: "autoCapitalize") as? Bool ?? true,
                  text.count == 1, let letter = text.first, letter.isLetter, letter.isLowercase else { return nil }
            // В коде регистр - часть смысла; на строке-предмете буква уйдёт на новую строку (blockKeys).
            let here = block(at: range.location)
            guard here != .code, !here.isObject else { return nil }
            let ns = textView.string as NSString
            let paragraph = paragraphRange(at: range.location)
            let before = ns.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location))
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            let sentenceStart: Bool
            if trimmed.isEmpty {
                sentenceStart = true
            } else {
                // После знака обязательно пробел: «file.txt» и «3.14» не трогаем.
                sentenceStart = before.last?.isWhitespace == true && ".!?…".contains(trimmed.last!)
            }
            guard sentenceStart else { return nil }
            let upper = String(letter).uppercased()
            pendingFade = NSRange(location: range.location, length: (upper as NSString).length)
            playSound(for: text)
            replace(range, with: NSAttributedString(string: upper, attributes: textView.typingAttributes))
            return false
        }

        private func playSound(for text: String) {
            guard UserDefaults.standard.object(forKey: "typingSound") as? Bool ?? true else { return }
            switch text {
            case "": TypingSound.shared.play(.delete)
            case " ": TypingSound.shared.play(.space)
            case "\n": TypingSound.shared.play(.enter)
            default: TypingSound.shared.play(.letter)
            }
        }

        private func paragraphRange(at location: Int) -> NSRange {
            let text = (textView?.string ?? "") as NSString
            return text.paragraphRange(for: NSRange(location: min(location, text.length), length: 0))
        }

        /// Тип абзаца, в котором стоит курсор. Пустая последняя строка своих букв не имеет - берём из набора.
        private func block(at location: Int) -> Block {
            guard let storage = textView?.textStorage else { return .text }
            let paragraph = paragraphRange(at: location)
            if paragraph.length > 0, paragraph.location < storage.length {
                return Formatting.block(of: storage.attributes(at: paragraph.location, effectiveRange: nil))
            }
            return Formatting.block(of: textView?.typingAttributes ?? [:])
        }

        /// Поведение как в Notion: Enter в списке продолжает список, на пустом пункте - выходит из него,
        /// после заголовка начинается обычный текст; Backspace в начале строки снимает её тип;
        /// «- », «1. », «[] », «# », «> » в начале строки превращают её в нужный тип. nil - обычный ввод.
        private func blockKeys(_ textView: NSTextView, range: NSRange, typing text: String) -> Bool? {
            let ns = textView.string as NSString
            let paragraph = paragraphRange(at: range.location)
            let current = block(at: range.location)
            let content = ns.substring(with: paragraph).trimmingCharacters(in: .newlines)

            // На строке-предмете (карточка, картинка, таблица...) печатать некуда: буквы уходят на новую строку под ней.
            if current.isObject, !text.isEmpty, text != "\n" {
                let end = ns.substring(with: paragraph).hasSuffix("\n") ? NSMaxRange(paragraph) - 1 : NSMaxRange(paragraph)
                replace(NSRange(location: end, length: 0), with: NSAttributedString(string: "\n" + text, attributes: Formatting.visual([:])))
                setBlock(.text, paragraphsIn: NSRange(location: end + 1, length: 0))
                return false
            }
            if text == "\n", range.length == 0 {
                if current.continues, content.isEmpty {
                    setBlock(.text, paragraphsIn: NSRange(location: range.location, length: 0))
                    return false
                }
                // После сворачиваемого заголовка - строка внутри него, после списков, кода, цитаты - их продолжение.
                let next: Block = current == .toggle ? .toggleItem : current == .done ? .todo : current.continues ? current : .text
                // Сам перенос строки - последняя буква верхнего абзаца, у него остаётся прежний тип.
                var attrs = textView.typingAttributes
                attrs[.zBlock] = current == .text ? nil : current.rawValue
                replace(range, with: NSAttributedString(string: "\n", attributes: attrs))
                // Хвост строки (если Enter нажали посередине) уходит в новый абзац с новым типом.
                setBlock(next, paragraphsIn: NSRange(location: range.location + 1, length: 0))
                return false
            }
            // Backspace в самом начале абзаца.
            let caret = textView.selectedRange()
            if text.isEmpty, caret.length == 0, caret.location == paragraphRange(at: caret.location).location {
                let here = block(at: caret.location)
                if here.isObject {
                    // Перед карточкой: убираем пустую строку над ней, а саму карточку не трогаем.
                    if caret.location > 0, paragraphRange(at: caret.location - 1).length == 1 {
                        replace(NSRange(location: caret.location - 1, length: 1), with: NSAttributedString(string: ""))
                    }
                    return false
                }
                // Внутри кода (и сворачиваемого списка) Backspace в начале строки просто склеивает её с предыдущей -
                // как в любом редакторе кода, без превращения строки в обычный текст.
                if (here == .code || here == .toggleItem), caret.location > 0, block(at: caret.location - 1) == here {
                    return nil
                }
                if here != .text {
                    // Сначала строка становится обычным текстом, следующий Backspace склеит её с предыдущей.
                    setBlock(.text, paragraphsIn: NSRange(location: caret.location, length: 0))
                    return false
                }
                if caret.location > 0 {
                    // Склейка: строка вливается в предыдущую и берёт её тип.
                    let previous = block(at: caret.location - 1)
                    // Текст в карточку не вливается: пустую строку под ней убираем, непустую не трогаем.
                    if previous.isObject, !content.isEmpty { return false }
                    replace(NSRange(location: caret.location - 1, length: 1), with: NSAttributedString(string: ""))
                    setBlock(previous, paragraphsIn: NSRange(location: caret.location - 1, length: 0))
                    return false
                }
            }
            // «---» - разделитель.
            if text == "-", range.length == 0, current == .text,
               ns.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location)) == "--",
               content == "--" {
                replace(NSRange(location: paragraph.location, length: 2), with: Formatting.object([.zBlock: Block.divider.rawValue]))
                return false
            }
            if text == " ", range.length == 0, current == .text {
                let before = ns.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location))
                let shortcuts: [String: Block] = ["-": .bullet, "*": .bullet, "1.": .numbered, "[]": .todo, "[ ]": .todo,
                                                  "#": .title, "##": .heading, "###": .subheading, ">": .quote,
                                                  "+": .toggle, "```": .code]
                if let block = shortcuts[before] {
                    replace(NSRange(location: paragraph.location, length: (before as NSString).length), with: NSAttributedString(string: ""))
                    setBlock(block, paragraphsIn: NSRange(location: paragraph.location, length: 0))
                    return false
                }
            }
            return nil
        }

        // MARK: правка из кода (с отменой через ⌘Z)

        private func replace(_ range: NSRange, with string: NSAttributedString) {
            guard let textView, let storage = textView.textStorage else { return }
            editingSelf = true
            defer { editingSelf = false }
            guard textView.shouldChangeText(in: range, replacementString: string.string) else { return }
            storage.replaceCharacters(in: range, with: string)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + string.length, length: 0))
        }

        /// Меняет только оформление: отмена через ⌘Z работает и для него.
        private func changeAttributes(in range: NSRange, _ body: (NSTextStorage) -> Void) {
            guard let textView, let storage = textView.textStorage else { return }
            editingSelf = true
            defer { editingSelf = false }
            let selection = textView.selectedRange()
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.beginEditing()
            body(storage)
            storage.endEditing()
            textView.didChangeText()
            textView.setSelectedRange(selection)
        }

        private func setBlock(_ block: Block, paragraphsIn range: NSRange) {
            guard let textView else { return }
            // Блок кода на пустой последней строке: даём ему настоящую строку, чтобы рамка и шапка встали на место.
            if block == .code, range.location >= (textView.string as NSString).length {
                let at = (textView.string as NSString).length
                var attrs = textView.typingAttributes
                attrs[.zBlock] = Block.code.rawValue
                replace(NSRange(location: at, length: 0), with: NSAttributedString(string: "\n", attributes: Formatting.visual(attrs)))
                textView.setSelectedRange(NSRange(location: at, length: 0))
                var typing = textView.typingAttributes
                typing[.zBlock] = Block.code.rawValue
                textView.typingAttributes = Formatting.visual(typing)
                render()
                textView.needsDisplay = true
                return
            }
            let ns = textView.string as NSString
            let paragraphs = ns.paragraphRange(for: NSRange(location: min(range.location, ns.length), length: range.length))
            if paragraphs.length > 0 {
                changeAttributes(in: paragraphs) { storage in
                    if block == .text {
                        storage.removeAttribute(.zBlock, range: paragraphs)
                    } else {
                        storage.addAttribute(.zBlock, value: block.rawValue, range: paragraphs)
                    }
                }
            }
            // Пустая последняя строка - тип живёт в атрибутах набора.
            if paragraphs.location >= ns.length || paragraphs.length == 0 || textView.selectedRange().location == ns.length {
                var typing = textView.typingAttributes
                typing[.zBlock] = block == .text ? nil : block.rawValue
                textView.typingAttributes = Formatting.visual(typing)
            }
            textView.needsDisplay = true
        }

        // MARK: команды

        func run(_ command: Command) {
            guard let textView else { return }
            let selection = textView.selectedRange()
            switch command {
            case .bold: toggle(.zBold, in: selection)
            case .italic: toggle(.zItalic, in: selection)
            case .underline: toggle(.zUnderline, in: selection)
            case .strike: toggle(.zStrike, in: selection)
            case .highlight: toggle(.zHighlight, in: selection, value: MarkColor.last.rawValue)
            case .mark(let mark):
                if let mark { MarkColor.last = mark }
                if selection.length == 0 {
                    var typing = textView.typingAttributes
                    typing[.zHighlight] = mark?.rawValue
                    textView.typingAttributes = Formatting.visual(typing)
                } else {
                    changeAttributes(in: selection) { storage in
                        if let mark {
                            storage.addAttribute(.zHighlight, value: mark.rawValue, range: selection)
                        } else {
                            storage.removeAttribute(.zHighlight, range: selection)
                        }
                    }
                }
            case .color(let color):
                if selection.length == 0 {
                    var typing = textView.typingAttributes
                    typing[.zColor] = color == .white ? nil : color.rawValue
                    textView.typingAttributes = Formatting.visual(typing)
                } else {
                    changeAttributes(in: selection) { storage in
                        if color == .white {
                            storage.removeAttribute(.zColor, range: selection)
                        } else {
                            storage.addAttribute(.zColor, value: color.rawValue, range: selection)
                        }
                    }
                }
            case .block(let block) where slashAt != nil:
                // Выбор из меню «/»: сам «/» убираем, строке ставим тип (или ставим на неё предмет).
                let at = slashAt!
                let typed = 1 + (slashQuery as NSString).length
                closeSlash()
                replace(NSRange(location: at, length: typed), with: NSAttributedString(string: ""))
                if block == .page {
                    makePage(at: at)
                } else if block == .template {
                    pickTemplate(at: at)
                } else if block.isObject {
                    textView.setSelectedRange(NSRange(location: at, length: 0))
                    insert(block)
                } else {
                    setBlock(block, paragraphsIn: NSRange(location: at, length: 0))
                }
            case .block(let block) where plusParagraph != nil:
                // Выбор из меню «+»: пустая строка сама становится блоком, под непустой появляется новый.
                let paragraph = plusParagraph!
                closePlus()
                let ns = textView.string as NSString
                let safe = NSIntersectionRange(paragraph, NSRange(location: 0, length: ns.length))
                let empty = ns.substring(with: safe).trimmingCharacters(in: .newlines).isEmpty
                if block == .template {
                    pickTemplate(at: min(paragraph.location, ns.length))
                } else if empty, self.block(at: paragraph.location) == .text {
                    textView.setSelectedRange(NSRange(location: min(paragraph.location, ns.length), length: 0))
                    insert(block)
                } else {
                    insert(block, at: NSMaxRange(safe))
                }
            case .block(.page):
                makePage(at: selection.location)
            case .block(let block):
                let current = self.block(at: selection.location)
                let same = current == block || (block == .todo && current == .done)
                setBlock(same ? .text : block, paragraphsIn: selection)
            }
        }

        // MARK: вставка блоков (панель «Вставить», перетаскивание файлов)

        /// Вставить блок: на границу абзацев (его перетащили туда) или под строку с курсором (нажали в панели).
        /// Пустая строка под курсором сама становится этим блоком.
        func insert(_ kind: Block, at boundary: Int? = nil) {
            switch kind {
            case .image, .file:
                let urls = Assets.pick(images: kind == .image, multiple: true)
                insertFiles(urls, at: boundary, asImages: kind == .image)
            case .page:
                guard let parent = shownID else { return }
                guard let page = store.createPage(in: parent, title: "") else { return }
                insertParagraphs([Formatting.object([.zPage: page, .zBlock: Block.page.rawValue])], at: boundary)
            case .table:
                insertParagraphs([Formatting.object([.zTable: Table.empty.json, .zBlock: Block.table.rawValue])], at: boundary)
            case .divider:
                insertParagraphs([Formatting.object([.zBlock: Block.divider.rawValue])], at: boundary)
            case .board:
                insertParagraphs([Formatting.object([.zBoard: Board.empty.json, .zBlock: Block.board.rawValue])], at: boundary)
            case .audio:
                // Голосовая заметка: запись начинается сразу, плашка встанет, когда договоришь.
                if let boundary { textView?.setSelectedRange(NSRange(location: boundary, length: 0)) }
                Dictation.shared.toggleVoiceNote()
            case .template:
                pickTemplate(at: boundary ?? textView?.selectedRange().location ?? 0)
            default:
                var attrs: [NSAttributedString.Key: Any] = [:]
                if kind != .text { attrs[.zBlock] = kind.rawValue }
                insertParagraphs([NSAttributedString(string: "", attributes: Formatting.visual(attrs))], at: boundary, textBlock: kind)
            }
        }

        /// Файлы с диска: картинки - картинками, остальное - карточками файлов. Копии ложатся в папку вложений.
        func insertFiles(_ urls: [URL], at boundary: Int?, asImages: Bool? = nil) {
            let imageTypes = Set(["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "webp", "bmp"])
            let pieces: [NSAttributedString] = urls.compactMap { url in
                guard let name = Assets.store(url) else { return nil }
                let isImage = asImages ?? imageTypes.contains(url.pathExtension.lowercased())
                return isImage
                    ? Formatting.object([.zImage: name, .zBlock: Block.image.rawValue])
                    : Formatting.object([.zFile: name, .zBlock: Block.file.rawValue])
            }
            guard !pieces.isEmpty else { return }
            insertParagraphs(pieces, at: boundary)
        }

        /// Вставить готовые абзацы одним шагом отмены. textBlock - пустая строка нужного типа, курсор встаёт в неё.
        private func insertParagraphs(_ pieces: [NSAttributedString], at boundary: Int?, textBlock: Block? = nil) {
            guard let textView, let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            var location: Int
            if let boundary {
                location = min(boundary, ns.length)
            } else {
                let paragraph = paragraphRange(at: textView.selectedRange().location)
                let content = ns.substring(with: paragraph).trimmingCharacters(in: .newlines)
                if content.isEmpty, block(at: paragraph.location) == .text {
                    // Пустая строка под курсором - сюда и ставим.
                    if let textBlock {
                        setBlock(textBlock, paragraphsIn: NSRange(location: paragraph.location, length: 0))
                        textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
                        return
                    }
                    location = paragraph.location
                    let removing = NSRange(location: paragraph.location, length: paragraph.length)
                    if removing.length > 0 { replace(removing, with: NSAttributedString(string: "")) }
                } else {
                    location = NSMaxRange(paragraph)
                }
            }
            let text = NSMutableAttributedString()
            for piece in pieces {
                text.append(piece)
                // Перенос строки несёт тип абзаца (по нему абзац и опознаётся).
                var newline: [NSAttributedString.Key: Any] = piece.length > 0 ? piece.attributes(at: piece.length - 1, effectiveRange: nil) : [:]
                if piece.length == 0, let textBlock, textBlock != .text { newline[.zBlock] = textBlock.rawValue }
                newline.removeValue(forKey: .attachment)
                text.append(NSAttributedString(string: "\n", attributes: Formatting.visual(newline)))
            }
            let current = (textView.string as NSString)
            // В самый конец без переноса: перенос нужен перед вставкой.
            if location == current.length, current.length > 0, !current.substring(from: current.length - 1).hasSuffix("\n") {
                text.insert(NSAttributedString(string: "\n", attributes: Formatting.visual([:])), at: 0)
            }
            replace(NSRange(location: location, length: 0), with: text)
            let caret = textBlock != nil ? location + (text.string.hasPrefix("\n") ? 1 : 0) : location + text.length
            textView.setSelectedRange(NSRange(location: min(caret, (textView.string as NSString).length), length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
            textView.window?.makeFirstResponder(textView)
        }

        // MARK: таблица, картинка, файл - клики

        func openObject(at index: Int) {
            guard let storage = textView?.textStorage, index < storage.length else { return }
            let attrs = storage.attributes(at: index, effectiveRange: nil)
            switch Formatting.block(of: attrs) {
            case .page: (attrs[.zPage] as? String).map(openPage)
            case .image, .file:
                if let name = (attrs[.zImage] ?? attrs[.zFile]) as? String { NSWorkspace.shared.open(Assets.url(name)) }
            case .table: editTable(at: index)
            case .board: editBoard(at: index)
            case .audio: (attrs[.zAudio] as? String).map { AudioPlayer.shared.toggle($0) }
            default: break
            }
        }

        /// Язык блока кода: rawValue CodeLanguage или nil - «Авто».
        func setCodeLanguage(_ lang: String?, in range: NSRange) {
            guard let storage = textView?.textStorage, range.length > 0, NSMaxRange(range) <= storage.length else { return }
            changeAttributes(in: range) { storage in
                if let lang { storage.addAttribute(.zLang, value: lang, range: range) } else { storage.removeAttribute(.zLang, range: range) }
            }
            render()
            textView?.needsDisplay = true
        }

        /// Новая ширина картинки (доля колонки) - одним шагом отмены.
        func setImageWidth(at index: Int, ratio: Double) {
            guard let storage = textView?.textStorage, index < storage.length else { return }
            let range = NSRange(location: index, length: 1)
            changeAttributes(in: range) { storage in
                var attrs = storage.attributes(at: index, effectiveRange: nil)
                attrs[.zImageWidth] = ratio
                storage.addAttribute(.zImageWidth, value: ratio, range: range)
                if let attachment = Objects.attachment(for: attrs) { storage.addAttribute(.attachment, value: attachment, range: range) }
            }
            render()
        }

        private func editTable(at index: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let table = Table(json: storage.attribute(.zTable, at: index, effectiveRange: nil) as? String ?? "")
            TableEditor.present(table, over: textView.window) { [weak self] edited in
                guard let self, let storage = self.textView?.textStorage, index < storage.length else { return }
                let range = NSRange(location: index, length: 1)
                self.changeAttributes(in: range) { storage in
                    storage.addAttribute(.zTable, value: edited.json, range: range)
                    var attrs = storage.attributes(at: index, effectiveRange: nil)
                    attrs[.zTable] = edited.json
                    if let attachment = Objects.attachment(for: attrs) { storage.addAttribute(.attachment, value: attachment, range: range) }
                }
            }
        }

        private func editBoard(at index: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let board = Board(json: storage.attribute(.zBoard, at: index, effectiveRange: nil) as? String ?? "")
            BoardEditor.present(board, over: textView.window) { [weak self] edited in
                guard let self, let storage = self.textView?.textStorage, index < storage.length,
                      storage.attribute(.zBoard, at: index, effectiveRange: nil) != nil else { return }
                let range = NSRange(location: index, length: 1)
                self.changeAttributes(in: range) { storage in
                    storage.addAttribute(.zBoard, value: edited.json, range: range)
                    var attrs = storage.attributes(at: index, effectiveRange: nil)
                    attrs[.zBoard] = edited.json
                    if let attachment = Objects.attachment(for: attrs) { storage.addAttribute(.attachment, value: attachment, range: range) }
                }
                self.render()
                self.textView?.needsDisplay = true
            }
        }

        // MARK: шаблоны

        /// Меню шаблонов у строки: выбранный шаблон встаёт на пустую строку или под непустую.
        func pickTemplate(at location: Int) {
            guard let textView, let layout = textView.layoutManager else { return }
            let length = (textView.string as NSString).length
            var line: NSRect
            if location >= length {
                line = layout.extraLineFragmentRect
                if line.height == 0, length > 0 {
                    line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: length - 1), effectiveRange: nil)
                }
            } else {
                line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: location), effectiveRange: nil)
            }
            line = line.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            let menu = NSMenu()
            for template in Template.all {
                let item = NSMenuItem(title: template.name, action: #selector(templatePicked(_:)), keyEquivalent: "")
                item.target = self
                item.image = NSImage(systemSymbolName: template.symbol, accessibilityDescription: nil)
                item.representedObject = [template.id, location] as [Any]
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: line.minX, y: line.maxY + 4), in: textView)
        }

        @objc private func templatePicked(_ item: NSMenuItem) {
            guard let info = item.representedObject as? [Any], let id = info.first as? String,
                  let location = info.last as? Int, let template = Template.all.first(where: { $0.id == id }) else { return }
            insertTemplate(template, at: location)
        }

        func insertTemplate(_ template: Template, at location: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let body = NSMutableAttributedString(attributedString: Formatting.attributed(template.doc()))
            let ns = storage.string as NSString
            let paragraph = paragraphRange(at: min(location, ns.length))
            let content = ns.substring(with: paragraph).trimmingCharacters(in: .newlines)
            let start: Int
            if content.isEmpty, block(at: paragraph.location) == .text {
                // Пустая строка - шаблон встаёт прямо на неё.
                let ownNewline = ns.substring(with: paragraph).hasSuffix("\n")
                if ownNewline, !body.string.hasSuffix("\n") { body.append(NSAttributedString(string: "\n", attributes: Self.lineEnd(of: body))) }
                start = paragraph.location
                replace(paragraph, with: body)
            } else {
                // Под непустой строкой. Перенос несёт тип строки, поэтому у каждого - атрибуты своей строки.
                start = NSMaxRange(paragraph)
                if start == ns.length, !ns.substring(with: paragraph).hasSuffix("\n") {
                    let previous = ns.length > 0 ? storage.attributes(at: ns.length - 1, effectiveRange: nil) : [:]
                    body.insert(NSAttributedString(string: "\n", attributes: previous.filter { $0.key != .attachment }), at: 0)
                } else if !body.string.hasSuffix("\n") {
                    body.append(NSAttributedString(string: "\n", attributes: Self.lineEnd(of: body)))
                }
                replace(NSRange(location: start, length: 0), with: body)
            }
            // Курсор - в конец первой строки шаблона (обычно это заголовок, его хочется дописать).
            let inserted = (textView.string as NSString)
            let first = inserted.paragraphRange(for: NSRange(location: min(start + (body.string.hasPrefix("\n") ? 1 : 0), inserted.length), length: 0))
            let end = inserted.substring(with: first).hasSuffix("\n") ? NSMaxRange(first) - 1 : NSMaxRange(first)
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(first)
            textView.window?.makeFirstResponder(textView)
        }

        /// Смысловые атрибуты последней буквы - для переноса строки, который её закрывает.
        private static func lineEnd(of text: NSAttributedString) -> [NSAttributedString.Key: Any] {
            guard text.length > 0 else { return [:] }
            return text.attributes(at: text.length - 1, effectiveRange: nil).filter { $0.key != .attachment }
        }

        /// Если стиль уже у всего выделения - снимаем, иначе ставим. Без выделения - для того, что будет набрано.
        private func toggle(_ key: NSAttributedString.Key, in selection: NSRange, value: Any = true) {
            guard let textView else { return }
            if selection.length == 0 {
                var typing = textView.typingAttributes
                typing[key] = typing[key] == nil ? value : nil
                textView.typingAttributes = Formatting.visual(typing)
                return
            }
            let on = has(key, everywhereIn: selection)
            changeAttributes(in: selection) { storage in
                if on { storage.removeAttribute(key, range: selection) } else { storage.addAttribute(key, value: value, range: selection) }
            }
        }

        private func has(_ key: NSAttributedString.Key, everywhereIn range: NSRange) -> Bool {
            guard let storage = textView?.textStorage, range.length > 0 else { return false }
            var all = true
            storage.enumerateAttribute(key, in: range) { value, _, stop in
                if value == nil { all = false; stop.pointee = true }
            }
            return all
        }

        // MARK: страницы

        /// Строка становится карточкой новой страницы. Её текст - название страницы.
        /// Пустая строка - сразу открываем новую страницу, чтобы писать в ней.
        private func makePage(at location: Int) {
            guard let textView, let parent = shownID else { return }
            let ns = textView.string as NSString
            let paragraph = paragraphRange(at: location)
            let content = ns.substring(with: paragraph).trimmingCharacters(in: .newlines)
            let body = NSRange(location: paragraph.location, length: (content as NSString).length)
            guard let page = store.createPage(in: parent, title: content.replacingOccurrences(of: "\u{FFFC}", with: "")) else { return }
            replace(body, with: Formatting.card(page))
            textView.setSelectedRange(NSRange(location: paragraph.location + 1, length: 0))
            if content.isEmpty { openPage(page) }
        }

        func openPage(_ id: String) {
            guard store.note(id) != nil else { return }
            store.select(id)
        }

        /// Перетаскивание блока за ручку: абзац переезжает на границу boundary (индекс начала абзаца).
        func moveParagraph(_ range: NSRange, to boundary: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            guard boundary < range.location || boundary > NSMaxRange(range) else { return }
            let ns = storage.string as NSString
            var piece = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            var cut = range
            if !piece.string.hasSuffix("\n") {
                // Последняя строка без переноса: забираем перенос перед ней, а себе ставим свой.
                let newlineAttrs = piece.length > 0 ? piece.attributes(at: piece.length - 1, effectiveRange: nil) : [:]
                piece.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                if range.location > 0 { cut = NSRange(location: range.location - 1, length: range.length + 1) }
            }
            var target = boundary > range.location ? boundary - cut.length : boundary
            textView.undoManager?.beginUndoGrouping()
            replace(cut, with: NSAttributedString(string: ""))
            let length = (textView.string as NSString).length
            target = min(target, length)
            if target == length, length > 0, !(textView.string as NSString).substring(from: length - 1).hasSuffix("\n") {
                // В самый конец, где нет переноса: перенос ставим перед блоком, а не после.
                piece = NSMutableAttributedString(attributedString: piece.attributedSubstring(from: NSRange(location: 0, length: piece.length - 1)))
                piece.insert(NSAttributedString(string: "\n", attributes: piece.length > 0 ? piece.attributes(at: 0, effectiveRange: nil) : [:]), at: 0)
                target = length
            }
            replace(NSRange(location: target, length: 0), with: piece)
            textView.undoManager?.endUndoGrouping()
            _ = ns
            textView.setSelectedRange(NSRange(location: min(target + (piece.string.hasPrefix("\n") ? 1 : 0), (textView.string as NSString).length), length: 0))
        }

        /// Блок брошен на карточку: он уезжает в конец той страницы. Карточка внутри блока - страница переезжает тоже.
        func moveParagraph(_ range: NSRange, intoPage page: String) {
            guard let textView, let storage = textView.textStorage else { return }
            var piece = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            var cut = range
            if !piece.string.hasSuffix("\n"), range.location > 0 {
                cut = NSRange(location: range.location - 1, length: range.length + 1)
            }
            if piece.string.hasSuffix("\n") {
                piece = NSMutableAttributedString(attributedString: piece.attributedSubstring(from: NSRange(location: 0, length: piece.length - 1)))
            }
            var moved: [String] = []
            piece.enumerateAttribute(.zPage, in: NSRange(location: 0, length: piece.length)) { value, _, _ in
                if let id = value as? String, id != page { moved.append(id) }
            }
            replace(cut, with: NSAttributedString(string: ""))
            for id in moved { store.reparent(id, to: page) }
            store.append(piece, to: page)
        }

        /// Для скриншотов и ролика: «-demoSelect 30,14» выделяет текст (появляется панель стилей),
        /// «-demoType /» печатает в конце текста (открывается меню блоков). Срабатывает один раз при запуске.
        private static var demoDone = false
        private func runDemoScript() {
            guard !Self.demoDone else { return }
            Self.demoDone = true
            let defaults = UserDefaults.standard
            let select = defaults.string(forKey: "demoSelect")
            let type = defaults.string(forKey: "demoType")
            guard select != nil || type != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let textView = self?.textView else { return }
                if let parts = select?.split(separator: ",").compactMap({ Int($0) }), parts.count == 2 {
                    textView.setSelectedRange(NSRange(location: parts[0], length: parts[1]))
                }
                if let type {
                    let end = (textView.string as NSString).length
                    textView.setSelectedRange(NSRange(location: end, length: 0))
                    for ch in type { textView.insertText(String(ch), replacementRange: textView.selectedRange()) }
                }
            }
        }

        /// Настройки, которые касаются самого поля ввода: орфография, тире и кавычки.
        static func applySettings(to text: NSTextView) {
            let defaults = UserDefaults.standard
            text.isContinuousSpellCheckingEnabled = defaults.bool(forKey: "spellCheck")
            let smart = defaults.bool(forKey: "smartPunctuation")
            text.isAutomaticDashSubstitutionEnabled = smart
            text.isAutomaticQuoteSubstitutionEnabled = smart
            // Т9: исправление опечаток на лету и серая подсказка, как дописать слово (Tab - принять).
            let t9 = defaults.object(forKey: "t9") as? Bool ?? true
            text.isAutomaticSpellingCorrectionEnabled = t9
            text.isAutomaticTextCompletionEnabled = t9
            text.inlinePredictionType = t9 ? .yes : .no
        }

        /// Настройки поменялись: перечитать их и перерисовать текст (размер шрифта мог измениться).
        func refreshSettings() {
            guard let textView else { return }
            Self.applySettings(to: textView)
            applyStyle(PageStyle.current)
            render()
            textView.needsDisplay = true
        }

        /// Стиль страницы: шрифт, цвета, ширина, обложка. Всё рисуется от PageStyle.current.
        private func applyStyle(_ style: PageStyle) {
            PageStyle.current = style
            (textView as? NotesTextView)?.updateInsets()
            textView?.insertionPointColor = style.text.color
            textView?.window?.backgroundColor = style.baseColor
            textView?.typingAttributes = Formatting.visual(textView?.typingAttributes.filter { NSAttributedString.Key.semantic.contains($0.key) } ?? [:])
        }

        /// Клик по стрелке сворачиваемого списка.
        func toggleCollapsed(paragraphAt location: Int) {
            guard let storage = textView?.textStorage else { return }
            let paragraph = paragraphRange(at: location)
            guard paragraph.length > 0 else { return }
            let collapsed = storage.attribute(.zCollapsed, at: paragraph.location, effectiveRange: nil) != nil
            changeAttributes(in: paragraph) { storage in
                if collapsed { storage.removeAttribute(.zCollapsed, range: paragraph) } else { storage.addAttribute(.zCollapsed, value: true, range: paragraph) }
            }
            render()
            textView?.needsDisplay = true
        }

        // MARK: скрытые строки свёрнутого списка

        /// Глифы строк внутри свёрнутого списка не рисуются (у них ещё и нулевая высота строки).
        func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                           properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                           characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
            guard let storage = layoutManager.textStorage else { return 0 }
            var changed = false
            var newProps = [NSLayoutManager.GlyphProperty]()
            newProps.reserveCapacity(range.length)
            for i in 0..<range.length {
                var prop = props[i]
                let index = characterIndexes[i]
                if index < storage.length, storage.attribute(.zHidden, at: index, effectiveRange: nil) != nil {
                    prop.insert(.null)
                    changed = true
                }
                newProps.append(prop)
            }
            guard changed else { return 0 }
            layoutManager.setGlyphs(glyphs, properties: newProps, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
            return range.length
        }

        /// Курсор не заходит в свёрнутые строки - перескакивает их.
        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange,
                      toCharacterRange new: NSRange) -> NSRange {
            guard new.length == 0, let storage = textView.textStorage, new.location < storage.length else { return new }
            var run = NSRange()
            guard storage.attribute(.zHidden, at: new.location, longestEffectiveRange: &run,
                                    in: NSRange(location: 0, length: storage.length)) != nil else { return new }
            let forward = new.location >= old.location
            let target = forward ? NSMaxRange(run) : max(run.location - 1, 0)
            return NSRange(location: min(target, storage.length), length: 0)
        }

        /// Клик по квадратику чеклиста отмечает пункт.
        func toggleCheckbox(paragraphAt location: Int) {
            let current = block(at: location)
            guard current == .todo || current == .done else { return }
            setBlock(current == .todo ? .done : .todo, paragraphsIn: NSRange(location: location, length: 0))
            if UserDefaults.standard.object(forKey: "typingSound") as? Bool ?? true { TypingSound.shared.play(.space) }
        }

        // MARK: изменения

        func textDidChange(_ notification: Notification) {
            guard let textView, let id = shownID, let storage = textView.textStorage else { return }
            render()
            if let range = pendingFade { startFade(range) }
            pendingFade = nil
            // Живой текст диктовки не сохраняем - в файл попадёт только окончательный.
            if live == nil { store.update(id, doc: Formatting.doc(from: storage)) }
            textView.needsDisplay = true
            applyFocus()
            updateStats()
            if let candidate = slashCandidate {
                slashCandidate = nil
                slashAt = candidate
                slashIndex = 0
            } else if !editingSelf {
                checkSlash()
            }
            if !editingSelf { updateBar() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !editingSelf else { return }
            textView?.needsDisplay = true // подсказка на пустой строке ходит за курсором
            if textView?.selectedRange().length == 0 { barMode = .main }
            checkSlash()
            if plusParagraph != nil { closePlus() }
            updateBar()
            applyFocus()
            updateStats()
        }

        // MARK: счётчик слов и режим фокуса

        /// Слова во всей заметке и в выделении - для плашки в углу.
        private func updateStats() {
            guard let textView else { return }
            let text = textView.string
            EditorStats.shared.words = EditorStats.count(text)
            let selection = textView.selectedRange()
            EditorStats.shared.selectedWords = selection.length > 0 && NSMaxRange(selection) <= (text as NSString).length
                ? EditorStats.count((text as NSString).substring(with: selection)) : 0
        }

        /// Есть ли сейчас приглушённые строки - чтобы снять их, когда фокус выключат.
        private var focusDimmed = false

        /// Режим фокуса: всё, кроме абзаца с курсором, приглушено.
        func applyFocus() {
            guard let textView, let layout = textView.layoutManager, let storage = textView.textStorage else { return }
            let all = NSRange(location: 0, length: storage.length)
            let on = UserDefaults.standard.bool(forKey: "focusMode") && live == nil
            guard on else {
                if focusDimmed {
                    layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
                    focusDimmed = false
                    textView.needsDisplay = true
                }
                return
            }
            let current = NSIntersectionRange(paragraphRange(at: textView.selectedRange().location), all)
            let dim = Style.text.withAlphaComponent(0.22)
            let before = NSRange(location: 0, length: current.location)
            let after = NSRange(location: NSMaxRange(current), length: storage.length - NSMaxRange(current))
            if current.length > 0 { layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: current) }
            for range in [before, after] where range.length > 0 {
                layout.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: range)
            }
            focusDimmed = true
            textView.needsDisplay = true
        }

        // MARK: меню «/»

        /// Меню живёт, пока курсор стоит за «/» и словом после него («/h1», «/заг»): это слово фильтрует пункты.
        /// Пробел, ушёл курсором или ничего не подходит - закрывается, текст остаётся как есть.
        private func checkSlash() {
            guard let at = slashAt, let textView else { return }
            let ns = textView.string as NSString
            let caret = textView.selectedRange()
            guard at < ns.length, ns.character(at: at) == 47 /* / */, caret.length == 0,
                  caret.location > at, caret.location - at <= 20 else { return closeSlash() }
            let query = ns.substring(with: NSRange(location: at + 1, length: caret.location - at - 1))
            guard !query.contains(where: { $0.isWhitespace }) else { return closeSlash() }
            if query != slashQuery { slashIndex = 0 }
            slashQuery = query
            if menuItems.isEmpty { closeSlash() }
        }

        private func closeSlash() {
            slashAt = nil
            slashQuery = ""
            textView?.needsDisplay = true
        }

        /// «+» слева от строки: меню блоков для неё.
        func openPlus(paragraph: NSRange) {
            closeSlash()
            plusParagraph = paragraph
            slashIndex = 0
            textView?.window?.makeFirstResponder(textView)
            updateBar()
            textView?.needsDisplay = true
        }

        /// «···» в полоске варианта C: меню блоков для строки с курсором.
        func openPlusAtCaret() {
            guard let textView else { return }
            openPlus(paragraph: paragraphRange(at: textView.selectedRange().location))
        }

        private func closePlus() {
            plusParagraph = nil
            textView?.needsDisplay = true
        }

        /// Стрелки, Enter и Esc, пока открыто меню «/» или «+».
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard menuOpen else { return false }
            let items = menuItems
            let count = max(items.count, 1)
            switch selector {
            case #selector(NSResponder.moveDown(_:)): slashIndex = (slashIndex + 1) % count
            case #selector(NSResponder.moveUp(_:)): slashIndex = (slashIndex + count - 1) % count
            case #selector(NSResponder.insertNewline(_:)):
                guard items.indices.contains(slashIndex) else { closeSlash(); return true }
                run(.block(items[slashIndex]))
            case #selector(NSResponder.cancelOperation(_:)): closeSlash(); closePlus()
            default: return false
            }
            updateBar()
            return true
        }

        private func render() {
            guard let textView, let storage = textView.textStorage else { return }
            storage.beginEditing()
            Formatting.render(storage)
            storage.endEditing()
        }

        /// Набор продолжает оформление буквы слева от курсора (как везде), а тип строки - тип абзаца.
        private func attributesForTyping() -> [NSAttributedString.Key: Any] {
            guard let textView, let storage = textView.textStorage else { return Formatting.visual([:]) }
            let location = textView.selectedRange().location
            guard location > 0, location <= storage.length else { return Formatting.visual([:]) }
            return storage.attributes(at: location - 1, effectiveRange: nil)
        }

        // MARK: диктовка

        /// Где идёт живой текст диктовки: начало и то, что сейчас стоит в тексте.
        private var live: (start: Int, text: String, lead: String, attrs: [NSAttributedString.Key: Any])?

        func connectDictation() {
            let dictation = Dictation.shared
            dictation.onLive = { [weak self] text in self?.showLive(text) }
            dictation.onFinal = { [weak self] text in self?.commitLive(text) }
            dictation.onCancel = { [weak self] in self?.dropLive() }
            dictation.onVoiceNote = { [weak self] name, text in self?.commitVoice(name, text) }
        }

        /// Пока человек говорит: слова сразу в тексте, строчными и без знаков - так они не прыгают,
        /// когда движок уточняет пунктуацию.
        private func showLive(_ raw: String) {
            guard let textView, let storage = textView.textStorage else { return }
            if live == nil {
                let selection = textView.selectedRange()
                let ns = storage.string as NSString
                let start = selection.location + selection.length
                let before: unichar? = start > 0 ? ns.character(at: start - 1) : nil
                let needsSpace = before.map { !(CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar($0) ?? " ")) } ?? false
                live = (start, "", needsSpace ? " " : "", textView.typingAttributes)
                textView.isEditable = false
                hideBar()
            }
            guard var current = live else { return }
            let words = raw.lowercased()
                .components(separatedBy: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-'")))
                .joined()
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            let shown = words.isEmpty ? "" : current.lead + words
            guard shown != current.text else { return }
            // Меняем только хвост, который отличается: уже стоящие слова не мигают.
            let old = current.text as NSString, new = shown as NSString
            var common = 0
            while common < old.length, common < new.length, old.character(at: common) == new.character(at: common) { common += 1 }
            let replaced = NSRange(location: current.start + common, length: old.length - common)
            let added = new.substring(from: common)
            storage.beginEditing()
            storage.replaceCharacters(in: replaced, with: NSAttributedString(string: added, attributes: current.attrs))
            storage.endEditing()
            current.text = shown
            live = current
            afterProgrammaticChange()
            let end = current.start + new.length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            if !added.isEmpty { startFade(NSRange(location: current.start + common, length: (added as NSString).length)) }
        }

        /// Договорил: живой текст в один кадр заменяется готовым - без видимого стирания и перепечатывания.
        private func commitLive(_ final: String) {
            guard let textView, let storage = textView.textStorage else { return }
            let current = live ?? (textView.selectedRange().location, "", "", textView.typingAttributes)
            let ns = storage.string as NSString
            let before: unichar? = current.start > 0 ? ns.character(at: current.start - 1) : nil
            var text = final.trimmingCharacters(in: .whitespacesAndNewlines)
            textView.isEditable = true
            guard !text.isEmpty else { return dropLive() }
            // Посреди предложения первая буква строчная (если это не аббревиатура вроде «МКС»).
            let prefix = ns.substring(to: current.start).trimmingCharacters(in: .whitespacesAndNewlines)
            let sentenceStart = prefix.isEmpty || ".!?…\n".contains(prefix.last!) || before == 10
            if !sentenceStart, let first = text.first, first.isUppercase,
               text.dropFirst().first.map({ $0.isLowercase }) ?? true {
                text = first.lowercased() + text.dropFirst()
            }
            let lead = before.map { !(CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar($0) ?? " ")) } ?? false ? " " : ""
            // Живой текст убираем без записи в отмену, готовый вставляем с ней: ⌘Z уберёт всю диктовку разом.
            textView.undoManager?.disableUndoRegistration()
            storage.replaceCharacters(in: NSRange(location: current.start, length: (current.text as NSString).length), with: "")
            textView.undoManager?.enableUndoRegistration()
            live = nil
            textView.setSelectedRange(NSRange(location: current.start, length: 0))
            textView.typingAttributes = current.attrs
            replace(NSRange(location: current.start, length: 0), with: NSAttributedString(string: lead + text, attributes: current.attrs))
            textView.window?.makeFirstResponder(textView)
        }

        /// Голосовая заметка готова: живой текст убираем, вместо него - плашка с записью и расшифровка под ней.
        private func commitVoice(_ name: String, _ text: String) {
            guard let textView, let storage = textView.textStorage else { return }
            textView.isEditable = true
            if let current = live {
                textView.undoManager?.disableUndoRegistration()
                storage.replaceCharacters(in: NSRange(location: current.start, length: (current.text as NSString).length), with: "")
                textView.undoManager?.enableUndoRegistration()
                live = nil
                textView.setSelectedRange(NSRange(location: current.start, length: 0))
                afterProgrammaticChange()
            }
            var pieces = [Formatting.object([.zAudio: name, .zBlock: Block.audio.rawValue])]
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty { pieces.append(NSAttributedString(string: spoken, attributes: Formatting.visual([:]))) }
            insertParagraphs(pieces, at: nil)
        }

        private func dropLive() {
            guard let textView, let storage = textView.textStorage else { return }
            textView.isEditable = true
            guard let current = live else { return }
            live = nil
            storage.replaceCharacters(in: NSRange(location: current.start, length: (current.text as NSString).length), with: "")
            afterProgrammaticChange()
            textView.setSelectedRange(NSRange(location: current.start, length: 0))
        }

        private func afterProgrammaticChange() {
            render()
            textView?.needsDisplay = true
        }

        // MARK: панель форматирования

        private lazy var bar = FormatBarHost(rootView: FormatBar(state: .init(), mode: .main, run: { _ in }, setMode: { _ in }))

        private func updateBar() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
            let selection = textView.selectedRange()
            if let at = slashAt { return showSlashMenu(at: at) }
            if let paragraph = plusParagraph { return showSlashMenu(at: paragraph.location) }
            guard selection.length > 0, !textView.hasMarkedText() else { return hideBar() }

            bar.rootView = FormatBar(state: barState(selection), mode: barMode, run: { [weak self] command in
                self?.run(command)
                if case .block = command { self?.barMode = .main }
                if case .color = command { self?.barMode = .main }
                self?.textView?.window?.makeFirstResponder(self?.textView)
                self?.updateBar()
            }, setMode: { [weak self] mode in
                self?.barMode = mode
                self?.updateBar()
            })
            let size = bar.fittingSize
            let glyphs = layout.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
            let origin = textView.textContainerOrigin
            let first = layout.boundingRect(forGlyphRange: NSRange(location: glyphs.location, length: 1), in: container)
                .offsetBy(dx: origin.x, dy: origin.y)
            let all = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            // Панель (12 - прозрачные поля под тень) стоит над выделением; меню раскрывается вниз, поэтому
            // ряд кнопок всегда остаётся на одном месте, а не прыгает при открытии меню.
            let rowHeight = FormatBar.rowHeight + 24
            var x = first.minX - 12
            x = min(max(x, textView.visibleRect.minX), textView.visibleRect.maxX - size.width)
            var y = first.minY - rowHeight + 4
            if y < textView.visibleRect.minY { y = all.maxY - 8 } // сверху нет места - под выделением
            place(NSRect(x: x, y: y, width: size.width, height: size.height))
        }

        private func showSlashMenu(at location: Int) {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
            bar.rootView = FormatBar(state: .init(), mode: .slash, highlighted: slashIndex, menuItems: menuItems, run: { [weak self] command in
                self?.run(command)
                self?.textView?.window?.makeFirstResponder(self?.textView)
                self?.updateBar()
            }, setMode: { _ in })
            let size = bar.fittingSize
            let length = (textView.string as NSString).length
            var rect: NSRect
            if location >= length {
                // Пустая строка в самом конце - у неё свой «лишний» фрагмент.
                rect = layout.extraLineFragmentRect
                if rect.height == 0, length > 0 {
                    rect = layout.lineFragmentUsedRect(forGlyphAt: layout.glyphIndexForCharacter(at: length - 1), effectiveRange: nil)
                }
                rect = rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            } else {
                let glyph = layout.glyphIndexForCharacter(at: location)
                rect = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
                    .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            }
            // Под строкой или над ней - где больше места; и целиком внутри видимой части.
            let visible = textView.visibleRect
            let below = visible.maxY - rect.maxY, above = rect.minY - visible.minY
            var y = below >= size.height - 12 || below >= above ? rect.maxY - 6 : rect.minY - size.height + 6
            y = min(max(y, visible.minY), visible.maxY - size.height)
            let x = min(max(rect.minX - 12, textView.visibleRect.minX), textView.visibleRect.maxX - size.width)
            place(NSRect(x: x, y: y, width: size.width, height: size.height))
        }

        private func place(_ frame: NSRect) {
            guard let textView else { return }
            if bar.superview == nil {
                bar.frame = frame
                bar.alphaValue = 0
                textView.addSubview(bar)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    bar.animator().alphaValue = 1
                }
            } else {
                bar.frame = frame
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    bar.animator().alphaValue = 1 // если панель как раз гасла - возвращаем
                }
            }
        }

        private func hideBar() {
            barMode = .main
            guard bar.superview != nil else { return }
            let bar = self.bar
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                bar.animator().alphaValue = 0
            }, completionHandler: {
                if bar.alphaValue == 0 { bar.removeFromSuperview() }
            })
        }

        /// Что уже включено у выделения - эти кнопки на панели подсвечены.
        private func barState(_ selection: NSRange) -> FormatBar.State {
            var state = FormatBar.State()
            state.block = block(at: selection.location)
            if has(.zBold, everywhereIn: selection) { state.on.insert(.bold) }
            if has(.zItalic, everywhereIn: selection) { state.on.insert(.italic) }
            if has(.zUnderline, everywhereIn: selection) { state.on.insert(.underline) }
            if has(.zStrike, everywhereIn: selection) { state.on.insert(.strike) }
            if has(.zHighlight, everywhereIn: selection) { state.on.insert(.highlight) }
            if let storage = textView?.textStorage, selection.location < storage.length {
                state.color = (storage.attribute(.zColor, at: selection.location, effectiveRange: nil) as? String)
                    .flatMap(TextColor.init) ?? .white
                if state.on.contains(.highlight) {
                    state.mark = MarkColor.of(storage.attribute(.zHighlight, at: selection.location, effectiveRange: nil))
                }
            }
            return state
        }

        // MARK: проявление новых букв

        private func startFade(_ range: NSRange) {
            fades.append((range, CACurrentMediaTime()))
            tickFades()
            guard fadeTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tickFades() }
            RunLoop.main.add(timer, forMode: .common)
            fadeTimer = timer
        }

        private func tickFades() {
            guard let layout = textView?.layoutManager, let storage = textView?.textStorage else { return }
            let now = CACurrentMediaTime()
            for fade in fades {
                let range = NSIntersectionRange(fade.range, NSRange(location: 0, length: storage.length))
                guard range.length > 0 else { continue }
                let p = min(1, (now - fade.start) / Self.fadeDuration)
                if p >= 1 {
                    layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
                } else {
                    let eased = 1 - pow(1 - p, 3)
                    // Проявляем до настоящего цвета буквы, а не до белого.
                    let target = storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor ?? Style.text
                    let color = target.withAlphaComponent(target.alphaComponent * (0.15 + 0.85 * eased))
                    layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
                }
            }
            fades.removeAll { now - $0.start >= Self.fadeDuration }
            if fades.isEmpty {
                fadeTimer?.invalidate()
                fadeTimer = nil
            }
        }
    }
}

/// Выделение - тёмное и полупрозрачное, и в активном окне, и в неактивном (а не системное цветное).
final class NotesLayoutManager: NSLayoutManager {
    static let selection = NSColor.black.withAlphaComponent(0.32)

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        let isSelection = color == NSColor.selectedTextBackgroundColor
            || color == NSColor.unemphasizedSelectedTextBackgroundColor
            || color == Self.selection
        guard isSelection else {
            return super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
        }
        Self.selection.setFill()
        for i in 0..<rectCount {
            NSBezierPath(roundedRect: rectArray[i], xRadius: 4, yRadius: 4).fill()
        }
    }
}

/// Свой NSTextView: курсор чуть правее (у Caveat буквы наклонены и палочка налезала на них),
/// маркеры списков, галочки и полоска цитаты рисуются здесь, а не буквами в тексте.
final class NotesTextView: NSTextView {
    static let caretShift: CGFloat = 2

    /// Текст, вытащенный мышью из заметки куда-то ещё, только копируется - из заметки он не пропадает никогда.
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    /// Курсор стоит на строке-предмете (картинка, файл, таблица, карточка): вместо палочки - рамка вокруг предмета.
    private var caretObjectRect: NSRect? {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return nil }
        let caret = selectedRange()
        guard caret.length == 0, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: min(caret.location, ns.length), length: 0))
        guard paragraph.length > 0, paragraph.location < storage.length,
              Formatting.block(of: storage.attributes(at: paragraph.location, effectiveRange: nil)).isObject else { return nil }
        let object = ns.range(of: "\u{FFFC}", options: [], range: paragraph)
        guard object.location != NSNotFound else { return nil }
        let glyph = layout.glyphIndexForCharacter(at: object.location)
        var rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        if storage.attribute(.zImage, at: object.location, effectiveRange: nil) != nil {
            rect = rect.insetBy(dx: ImageCell.pad, dy: ImageCell.pad)
        } else {
            rect = rect.insetBy(dx: 0, dy: 4)
        }
        return rect
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        if caretObjectRect != nil { return }
        var rect = rect
        rect.origin.x += Self.caretShift
        rect.size.width = 2
        // Палочка - высотой со строку текста, а не со всю строку с межстрочным отступом
        // (на пустой строке иначе она тянулась далеко вниз).
        let font = typingAttributes[.font] as? NSFont ?? Style.font(Style.editorSize)
        let height = ceil(font.ascender - font.descender)
        if rect.height > height + 2 { rect.size.height = height }
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
    }

    /// Мигающий курсор стирается по старому прямоугольнику - расширяем его, чтобы не оставалось следов.
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var rect = rect
        rect.size.width += Self.caretShift + 2
        super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
    }

    // MARK: маркеры

    private struct Marker {
        let block: Block
        let number: Int
        let line: NSRect      // первая строка абзаца
        let baseline: CGFloat
        let height: CGFloat   // весь абзац - для полоски цитаты
        let color: NSColor
        let charIndex: Int
        let xHeight: CGFloat
        var collapsed = false
        /// Середина строчных букв - по ней выравниваются точки, галочки и стрелки.
        var mid: CGFloat { baseline - xHeight / 2 }
    }

    private func markers() -> [Marker] {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return [] }
        let ns = storage.string as NSString
        let origin = textContainerOrigin
        var result: [Marker] = []
        var number = 0

        func add(_ block: Block, paragraph: NSRange, attrs: [NSAttributedString.Key: Any]) {
            number = block == .numbered ? number + 1 : 0
            guard block.isList || block == .quote || block == .toggle, attrs[.zHidden] == nil else { return }
            let color = attrs[.foregroundColor] as? NSColor ?? .white
            let xHeight = (attrs[.font] as? NSFont ?? Style.font(Style.editorSize)).xHeight
            let collapsed = attrs[.zCollapsed] != nil
            // Пустая строка посреди текста: у неё есть только перенос - по нему и рисуем маркер.
            var paragraph = paragraph
            if paragraph.length == 0, paragraph.location < storage.length { paragraph.length = 1 }
            if paragraph.length == 0 || paragraph.location >= storage.length {
                // Пустая последняя строка: у неё свой «лишний» фрагмент.
                let rect = layout.extraLineFragmentRect.offsetBy(dx: origin.x, dy: origin.y)
                guard rect.height > 0 else { return }
                let font = attrs[.font] as? NSFont ?? Style.font(Style.editorSize)
                result.append(Marker(block: block, number: number, line: rect, baseline: rect.minY + font.ascender + 2,
                                     height: rect.height, color: color, charIndex: paragraph.location, xHeight: xHeight, collapsed: collapsed))
                return
            }
            let glyphs = layout.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            var lineRect = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let glyphPos = layout.location(forGlyphAt: glyphs.location)
            // Высота абзаца - по его строкам (без межстрочного хвоста последней) - для полоски цитаты.
            var whole = NSRect.zero
            layout.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in whole = whole == .zero ? used : whole.union(used) }
            _ = container
            lineRect = lineRect.offsetBy(dx: origin.x, dy: origin.y)
            result.append(Marker(block: block, number: number, line: lineRect, baseline: lineRect.minY + glyphPos.y,
                                 height: whole.height, color: color, charIndex: paragraph.location, xHeight: xHeight, collapsed: collapsed))
        }

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) {
            _, range, enclosing, _ in
            let attrs = enclosing.length > 0 ? storage.attributes(at: enclosing.location, effectiveRange: nil) : [:]
            add(Formatting.block(of: attrs), paragraph: range, attrs: attrs)
        }
        // Курсор на новой пустой строке в конце - маркер нужен и ей.
        if ns.length == 0 || ns.character(at: ns.length - 1) == 10 {
            add(Formatting.block(of: typingAttributes), paragraph: NSRange(location: ns.length, length: 0), attrs: typingAttributes)
        }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHint()
        drawImageUI()
        gutter.needsDisplay = true
        if let object = caretObjectRect, window?.firstResponder === self {
            let ring = NSBezierPath(roundedRect: object.insetBy(dx: -3, dy: -3), xRadius: 14, yRadius: 14)
            ring.lineWidth = 2
            NSColor.white.withAlphaComponent(0.55).setStroke()
            ring.stroke()
        }
        let left = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 5)
        for m in markers() where m.line.intersects(dirtyRect) || m.block == .quote {
            switch m.block {
            case .bullet:
                m.color.withAlphaComponent(0.8).setFill()
                if PageStyle.current.bulletStyle == .dash {
                    // Тире: короткая скруглённая чёрточка.
                    NSBezierPath(roundedRect: NSRect(x: left + 6, y: m.mid - 1, width: 11, height: 2), xRadius: 1, yRadius: 1).fill()
                } else {
                    let d: CGFloat = 6.5
                    NSBezierPath(ovalIn: NSRect(x: left + 9, y: m.mid - d / 2, width: d, height: d)).fill()
                }
            case .numbered:
                let label = NSAttributedString(string: "\(m.number).", attributes: [
                    .font: Style.font(Style.editorSize), .foregroundColor: m.color.withAlphaComponent(0.75),
                ])
                let font = Style.font(Style.editorSize)
                label.draw(at: NSPoint(x: left + 2, y: m.baseline - font.ascender))
            case .todo, .done:
                let s: CGFloat = 15
                let rect = checkboxRect(m.mid, left: left)
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                path.lineWidth = 1.6
                if m.block == .done {
                    Style.text.withAlphaComponent(0.85).setFill()
                    path.fill()
                    let tick = NSBezierPath()
                    tick.move(to: NSPoint(x: rect.minX + s * 0.24, y: rect.midY + s * 0.02))
                    tick.line(to: NSPoint(x: rect.minX + s * 0.43, y: rect.maxY - s * 0.26))
                    tick.line(to: NSPoint(x: rect.maxX - s * 0.22, y: rect.minY + s * 0.27))
                    tick.lineWidth = 2
                    tick.lineCapStyle = .round
                    tick.lineJoinStyle = .round
                    Style.background.setStroke()
                    tick.stroke()
                } else {
                    Style.text.withAlphaComponent(0.75).setStroke()
                    path.stroke()
                }
            case .quote:
                let bar = NSRect(x: left + 2, y: m.line.minY + 2, width: 2.5, height: max(m.height - 4, 10))
                Style.text.withAlphaComponent(0.55).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.25, yRadius: 1.25).fill()
            case .toggle:
                // Треугольник: вправо - свёрнуто, вниз - раскрыто.
                let r = toggleRect(m.mid, left: left)
                let tri = NSBezierPath()
                if m.collapsed {
                    tri.move(to: NSPoint(x: r.minX + 4, y: r.minY + 3))
                    tri.line(to: NSPoint(x: r.maxX - 3, y: r.midY))
                    tri.line(to: NSPoint(x: r.minX + 4, y: r.maxY - 3))
                } else {
                    tri.move(to: NSPoint(x: r.minX + 3, y: r.minY + 4))
                    tri.line(to: NSPoint(x: r.maxX - 3, y: r.minY + 4))
                    tri.line(to: NSPoint(x: r.midX, y: r.maxY - 3))
                }
                tri.close()
                m.color.withAlphaComponent(0.75).setFill()
                tri.fill()
            default:
                break
            }
        }
    }

    /// Бледная подсказка на пустой строке под курсором - как в Notion.
    private func drawHint() {
        guard let storage = textStorage, let layout = layoutManager else { return }
        // Без фокуса подсказка видна только в совсем пустой заметке - как приглашение начать.
        guard window?.firstResponder === self || storage.length == 0 else { return }
        let caret = selectedRange()
        guard caret.length == 0, (delegate as? Editor.Coordinator)?.menuOpen == false else { return }
        let ns = storage.string as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: min(caret.location, ns.length), length: 0))
        let content = ns.substring(with: paragraph).trimmingCharacters(in: .newlines)
        guard content.isEmpty else { return }
        let attrs = paragraph.length > 0 && paragraph.location < storage.length
            ? storage.attributes(at: paragraph.location, effectiveRange: nil) : typingAttributes
        let block = Formatting.block(of: attrs)
        let line: NSRect
        if paragraph.location >= ns.length || paragraph.length == 0 {
            line = layout.extraLineFragmentRect
        } else {
            line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: paragraph.location), effectiveRange: nil)
        }
        guard line.height > 0 else { return }
        let hint: String = switch block {
        case .text: ns.length == 0 ? "Пиши… или нажми + слева" : "Нажми + или напиши /"
        case .title, .heading, .subheading: block.name
        case .bullet, .numbered: "Пункт списка"
        case .todo, .done: "Задача"
        case .quote: "Цитата"
        case .toggle: "Сворачиваемый список"
        case .toggleItem: "Внутри списка"
        case .code: "Код"
        case .page, .divider, .image, .file, .table, .board, .audio, .template: ""
        }
        var hintAttrs = Formatting.visual(attrs)
        hintAttrs[.foregroundColor] = Style.text.withAlphaComponent(0.28)
        hintAttrs.removeValue(forKey: .strokeWidth)
        hintAttrs.removeValue(forKey: .backgroundColor)
        let paragraphStyle = hintAttrs[.paragraphStyle] as? NSParagraphStyle
        let x = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 5) + (paragraphStyle?.firstLineHeadIndent ?? 0)
        let y = textContainerOrigin.y + line.minY + (paragraphStyle?.paragraphSpacingBefore ?? 0)
        NSAttributedString(string: hint, attributes: hintAttrs).draw(at: NSPoint(x: x, y: y))
    }

    private func checkboxRect(_ mid: CGFloat, left: CGFloat) -> NSRect {
        let s: CGFloat = 15
        return NSRect(x: left + 4, y: mid - s / 2, width: s, height: s)
    }

    private func toggleRect(_ mid: CGFloat, left: CGFloat) -> NSRect {
        NSRect(x: left + 5, y: mid - 7, width: 14, height: 14)
    }

    // MARK: фон: обложка и подложка кода

    /// Высота обложки страницы - на неё же сдвинут текст.
    static let coverHeight: CGFloat = 190

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCover()
        drawCodeBackgrounds(in: rect)
    }

    private func drawCover() {
        guard let name = PageStyle.current.cover, let image = Assets.image(name), image.size.width > 0 else { return }
        let frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.coverHeight)
        guard needsToDraw(frame) else { return }
        // Картинка заполняет полосу; какая её часть видна - решает «положение обложки».
        let scale = max(frame.width / image.size.width, frame.height / image.size.height)
        let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let y = -(drawn.height - frame.height) * CGFloat(PageStyle.current.coverPosition)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: frame).addClip()
        image.draw(in: NSRect(x: (frame.width - drawn.width) / 2, y: y, width: drawn.width, height: drawn.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        // Низ обложки плавно растворяется - под ним виден фон страницы, какой бы он ни был.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSGradient(colors: [NSColor.black.withAlphaComponent(0), NSColor.black])?
            .draw(in: NSRect(x: 0, y: frame.maxY - 70, width: frame.width, height: 70), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Блок кода на экране: рамка, места кнопок в шапке и сам текст блока.
    private struct CodeBox { let range: NSRange; let rect: NSRect; let language: NSRect; let copy: NSRect }
    private var codeBoxes: [CodeBox] = []
    /// Блок, текст которого только что скопировали - на кнопке на секунду «Скопировано».
    private var copiedBox: Int?

    /// Блок кода - тёмная подложка в тон страницы, тонкая рамка и шапка: «КОД», язык (авто или выбранный) и «Скопировать».
    private func drawCodeBackgrounds(in dirty: NSRect) {
        guard let storage = textStorage, let layout = layoutManager else { codeBoxes = []; return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let x = textContainerOrigin.x + padding - 2
        let width = (textContainer?.size.width ?? bounds.width) - 2 * padding + 4
        var boxes: [CodeBox] = []

        func used(_ range: NSRange) -> NSRect {
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = NSRect.zero
            // По занятой части строк, без отступов абзаца - иначе подложка наезжает на соседей.
            layout.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in rect = rect == .zero ? used : rect.union(used) }
            return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        }
        var groups = Formatting.codeGroups(in: storage).map { ($0, used($0)) }
        // Пустой блок кода в самом конце (строк ещё нет): рамка вокруг «лишней» строки, чтобы блок было видно сразу.
        let ns = storage.string as NSString
        if Formatting.block(of: typingAttributes) == .code, ns.length == 0 || ns.hasSuffix("\n") {
            let extra = layout.extraLineFragmentUsedRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            if extra.height > 0 {
                if let last = groups.last, NSMaxRange(last.0) == ns.length {
                    groups[groups.count - 1].1 = last.1.union(extra)
                } else {
                    groups.append((NSRange(location: ns.length, length: 0), extra))
                }
            }
        }
        for (index, (range, lines)) in groups.enumerated() {
            let rect = NSRect(x: x, y: lines.minY - 34, width: width, height: lines.height + 34 + 12)
            let header = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 30)
            let language = range.length > 0 ? Formatting.language(of: range, in: storage) : .plain
            let manual = range.length > 0 && storage.attribute(.zLang, at: range.location, effectiveRange: nil) != nil
            let label = (manual ? "" : "Авто · ") + language.name + "  ▾"
            let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                                         .foregroundColor: Style.text.withAlphaComponent(0.55)]
            let languageSize = (label as NSString).size(withAttributes: small)
            let copyText = copiedBox == index ? "Скопировано" : "Скопировать"
            let copySize = (copyText as NSString).size(withAttributes: small)
            let copyRect = NSRect(x: header.maxX - copySize.width - 14, y: header.midY - copySize.height / 2, width: copySize.width, height: copySize.height)
            let languageRect = NSRect(x: copyRect.minX - languageSize.width - 18, y: copyRect.minY, width: languageSize.width, height: languageSize.height)
            boxes.append(CodeBox(range: range, rect: rect, language: languageRect.insetBy(dx: -6, dy: -4), copy: copyRect.insetBy(dx: -6, dy: -4)))
            guard rect.intersects(dirty) else { continue }

            let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            NSColor.black.withAlphaComponent(0.38).setFill()
            shape.fill()
            Style.text.withAlphaComponent(0.13).setStroke()
            shape.lineWidth = 1
            shape.stroke()
            // Шапка отделена тонкой линией.
            Style.text.withAlphaComponent(0.08).setFill()
            NSRect(x: rect.minX + 1, y: header.maxY, width: rect.width - 2, height: 1).fill()
            NSAttributedString(string: "КОД", attributes: small).draw(at: NSPoint(x: rect.minX + 14, y: languageRect.minY))
            NSAttributedString(string: label, attributes: small).draw(at: languageRect.origin)
            NSAttributedString(string: copyText, attributes: small).draw(at: copyRect.origin)
        }
        codeBoxes = boxes
    }

    /// Клик по шапке блока кода: меню языка или копирование.
    private func handleCodeHeaderClick(at point: NSPoint) -> Bool {
        guard let index = codeBoxes.firstIndex(where: { $0.language.contains(point) || $0.copy.contains(point) }) else { return false }
        let box = codeBoxes[index]
        if box.copy.contains(point) {
            let text = (string as NSString).substring(with: box.range)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedBox = index
            needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.copiedBox = nil
                self?.needsDisplay = true
            }
            return true
        }
        let menu = NSMenu()
        let auto = NSMenuItem(title: "Авто", action: #selector(pickLanguage(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = ["range": NSValue(range: box.range)] as [String: Any]
        menu.addItem(auto)
        menu.addItem(.separator())
        for language in CodeLanguage.allCases {
            let item = NSMenuItem(title: language.name, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["range": NSValue(range: box.range), "lang": language.rawValue] as [String: Any]
            if box.range.length > 0, textStorage?.attribute(.zLang, at: box.range.location, effectiveRange: nil) as? String == language.rawValue {
                item.state = .on
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: box.language.minX, y: box.language.maxY + 4), in: self)
        return true
    }

    @objc private func pickLanguage(_ item: NSMenuItem) {
        guard let info = item.representedObject as? [String: Any], let range = (info["range"] as? NSValue)?.rangeValue else { return }
        coordinator?.setCodeLanguage(info["lang"] as? String, in: range)
    }

    // MARK: ширина страницы и место под обложку

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
        gutter.frame = bounds
    }

    /// Обычная ширина - текст колонкой по центру, широкая - во всё окно. Обложка сдвигает текст вниз.
    func updateInsets() {
        let style = PageStyle.current
        // Слева место под «+» и ручку ⠿.
        let side = style.width == .regular ? max(56, (bounds.width - 700) / 2) : 56
        let top: CGFloat = style.cover != nil ? Self.coverHeight + 16 : 20
        let inset = NSSize(width: side, height: top)
        if textContainerInset != inset {
            textContainerInset = inset
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let left = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 5)
        // Шапка блока кода: язык и «Скопировать».
        if handleCodeHeaderClick(at: point) { return }
        // Ручка у правого края картинки: меняем её ширину.
        if let image = hoveredImage, imageHandleRect(image.rect).insetBy(dx: -5, dy: -5).contains(point) {
            resizing = (image.index, image.rect.midX, columnWidth)
            resizeWidth = image.rect.width
            return
        }
        // «+» слева: меню блоков для строки.
        for paragraph in [gutterParagraph].compactMap({ $0 })
            where plusRect(for: paragraph).insetBy(dx: -3, dy: -3).contains(point) {
            coordinator?.openPlus(paragraph: paragraph)
            return
        }
        // Ручка блока (на строке под мышью или с курсором): тащим абзац.
        if let grabbed = handleParagraphs.first(where: { handleRect(for: $0).insetBy(dx: -4, dy: -4).contains(point) }) {
            dragging = grabbed
            dimDragged(true)
            return
        }
        for m in markers() where m.block == .todo || m.block == .done || m.block == .toggle {
            let hit = m.block == .toggle ? toggleRect(m.mid, left: left) : checkboxRect(m.mid, left: left)
            if hit.insetBy(dx: -6, dy: -6).contains(point) {
                if m.block == .toggle {
                    coordinator?.toggleCollapsed(paragraphAt: m.charIndex)
                } else {
                    coordinator?.toggleCheckbox(paragraphAt: m.charIndex)
                }
                return
            }
        }
        // Клик по предмету: страница открывается, картинка и файл - в своей программе, таблица - на правку.
        if let index = object(at: point) {
            // Картинку открываем двойным кликом: одиночный - чтобы не мешать тянуть за край.
            let isImage = textStorage?.attribute(.zImage, at: index, effectiveRange: nil) != nil
            if !isImage || event.clickCount >= 2 { coordinator?.openObject(at: index) }
            return
        }
        super.mouseDown(with: event)
    }

    private var coordinator: Editor.Coordinator? { delegate as? Editor.Coordinator }

    /// Символ-предмет (картинка, файл, таблица, карточка) под точкой.
    private func object(at point: NSPoint) -> Int? {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        let char = layout.characterIndexForGlyph(at: glyph)
        guard char < storage.length, storage.attribute(.attachment, at: char, effectiveRange: nil) != nil,
              Formatting.block(of: storage.attributes(at: char, effectiveRange: nil)) != .divider else { return nil }
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return rect.contains(point) ? char : nil
    }

    /// Карточка страницы под точкой: id страницы и её рамка.
    private func card(at point: NSPoint) -> (String, NSRect)? {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        let char = layout.characterIndexForGlyph(at: glyph)
        guard char < storage.length, let page = storage.attribute(.zPage, at: char, effectiveRange: nil) as? String else { return nil }
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return rect.contains(point) ? (page, rect) : nil
    }

    // MARK: бросок из панели «Вставить» и из Finder

    static let blockType = NSPasteboard.PasteboardType("com.romankandeevy.zametki.block")
    private var externalBoundary: Int?

    private func handlesDrop(_ info: NSDraggingInfo) -> Bool {
        let types = info.draggingPasteboard.types ?? []
        return types.contains(Self.blockType) || types.contains(.fileURL)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard handlesDrop(sender) else { return super.draggingEntered(sender) }
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard handlesDrop(sender) else { return super.draggingUpdated(sender) }
        externalBoundary = boundary(near: convert(sender.draggingLocation, from: nil))
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if externalBoundary != nil {
            externalBoundary = nil
            needsDisplay = true
        }
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        handlesDrop(sender) ? true : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard handlesDrop(sender) else { return super.performDragOperation(sender) }
        let boundary = externalBoundary ?? self.boundary(near: convert(sender.draggingLocation, from: nil))
        externalBoundary = nil
        needsDisplay = true
        let board = sender.draggingPasteboard
        if let raw = board.string(forType: Self.blockType) ?? board.data(forType: Self.blockType).map({ String(decoding: $0, as: UTF8.self) }),
           let kind = Block(rawValue: raw) {
            coordinator?.insert(kind, at: boundary)
            return true
        }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            coordinator?.insertFiles(urls, at: boundary)
            return true
        }
        return false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if let sender, handlesDrop(sender) { return }
        super.concludeDragOperation(sender)
    }

    // MARK: размер картинки

    private var hoveredImage: (index: Int, rect: NSRect)?
    private var resizing: (index: Int, center: CGFloat, column: CGFloat)?
    private var resizeWidth: CGFloat = 0

    private var columnWidth: CGFloat {
        let padding = textContainer?.lineFragmentPadding ?? 5
        return (textContainer?.size.width ?? bounds.width) - padding * 2 - 4
    }

    /// Картинка под точкой: её индекс и рамка самой картинки (без полей под тень).
    private func imageRect(at point: NSPoint) -> (index: Int, rect: NSRect)? {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        let char = layout.characterIndexForGlyph(at: glyph)
        guard char < storage.length, storage.attribute(.zImage, at: char, effectiveRange: nil) != nil else { return nil }
        let box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            .insetBy(dx: ImageCell.pad, dy: ImageCell.pad)
        return box.insetBy(dx: -12, dy: -4).contains(point) ? (char, box) : nil
    }

    private func imageHandleRect(_ image: NSRect) -> NSRect {
        NSRect(x: image.maxX - 4, y: image.midY - 20, width: 8, height: 40)
    }

    private func drawImageUI() {
        if let resizing {
            // Пока тянешь - рамка будущего размера.
            let current = hoveredImage?.rect ?? .zero
            let rect = NSRect(x: resizing.center - resizeWidth / 2, y: current.minY,
                              width: resizeWidth, height: current.width > 0 ? current.height * resizeWidth / current.width : 0)
            let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            path.lineWidth = 2
            NSColor.white.withAlphaComponent(0.85).setStroke()
            path.stroke()
            return
        }
        guard let image = hoveredImage, window?.isKeyWindow == true else { return }
        let handle = imageHandleRect(image.rect)
        let pill = NSBezierPath(roundedRect: handle, xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowBlurRadius = 4
        shadow.set()
        NSColor.white.withAlphaComponent(0.92).setFill()
        pill.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: перетаскивание блоков

    /// Абзац под мышью - у него слева появляется ручка ⋮⋮.
    private var hovered: NSRange?
    private var dragging: NSRange?
    private var dropBoundary: Int?
    private var dropCard: PageCardCell?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self && area.userInfo?["handles"] != nil { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: ["handles": true]))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard dragging == nil, resizing == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        // Картинка под мышью - у неё появляется ручка размера.
        let image = imageRect(at: point)
        if image?.index != hoveredImage?.index || image?.rect != hoveredImage?.rect {
            hoveredImage = image
            needsDisplay = true
        }
        if let image, imageHandleRect(image.rect).insetBy(dx: -5, dy: -5).contains(point) {
            NSCursor.resizeLeftRight.set()
            return
        }
        let paragraph = paragraph(at: point)
        let overPlus = [paragraph, caretEmptyParagraph].compactMap { $0 }
            .contains { plusRect(for: $0).insetBy(dx: -3, dy: -3).contains(point) }
        if paragraph != hovered || overPlus != plusHovered {
            hovered = paragraph
            plusHovered = overPlus
            needsDisplay = true
        }
        updateCursor(at: point)
    }

    /// Над тем, что нажимается (квадратик, стрелка, «+», карточка, файл, таблица) - рука, над ручкой ⠿ - хватающая рука.
    /// Текстовое поле само ставит текстовый курсор, поэтому ставим свой после него.
    /// Строки, у которых сейчас видна ручка ⠿: под мышью и с курсором (пустые не таскаем).
    private var handleParagraphs: [NSRange] {
        guard let line = gutterParagraph, !isEmpty(line) else { return [] }
        return [line]
    }

    /// Одна строка с «+» и ⠿: под мышью, а если мышь не над текстом - с курсором.
    private var gutterParagraph: NSRange? { hovered ?? caretEmptyParagraph }

    private func updateCursor(at point: NSPoint) {
        if handleParagraphs.contains(where: { handleRect(for: $0).insetBy(dx: -4, dy: -4).contains(point) }) {
            NSCursor.openHand.set()
        } else if isClickable(point) {
            NSCursor.pointingHand.set()
        }
    }

    private func isClickable(_ point: NSPoint) -> Bool {
        if [gutterParagraph].compactMap({ $0 }).contains(where: { plusRect(for: $0).insetBy(dx: -3, dy: -3).contains(point) }) {
            return true
        }
        let left = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 5)
        for m in markers() where m.block == .todo || m.block == .done || m.block == .toggle {
            let hit = m.block == .toggle ? toggleRect(m.mid, left: left) : checkboxRect(m.mid, left: left)
            if hit.insetBy(dx: -6, dy: -6).contains(point) { return true }
        }
        if codeBoxes.contains(where: { $0.language.contains(point) || $0.copy.contains(point) }) { return true }
        return object(at: point) != nil
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isClickable(point) || handleParagraphs.contains(where: { handleRect(for: $0).insetBy(dx: -4, dy: -4).contains(point) }) {
            updateCursor(at: point)
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard dragging == nil else { return }
        hovered = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if let resizing {
            // Картинка по центру: ширина = двойное расстояние от центра до мыши.
            let point = convert(event.locationInWindow, from: nil)
            resizeWidth = min(max(2 * (point.x - resizing.center), resizing.column * 0.2), resizing.column)
            NSCursor.resizeLeftRight.set()
            needsDisplay = true
            return
        }
        guard let dragging else { return super.mouseDragged(with: event) }
        NSCursor.closedHand.set()
        let point = convert(event.locationInWindow, from: nil)
        autoscroll(with: event)
        // Над карточкой чужой страницы - блок уедет внутрь неё.
        var target: PageCardCell?
        if let (page, _) = card(at: point), let storage = textStorage,
           NSIntersectionRange(dragging, NSRange(location: 0, length: storage.length)).length > 0 {
            let draggedPages = Set((0..<dragging.length).compactMap {
                storage.attribute(.zPage, at: dragging.location + $0, effectiveRange: nil) as? String
            })
            if !draggedPages.contains(page) {
                target = (attachmentCell(for: page))
            }
        }
        if target !== dropCard {
            dropCard?.isDropTarget = false
            target?.isDropTarget = true
            dropCard = target
        }
        dropBoundary = target == nil ? boundary(near: point) : nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let resizing {
            self.resizing = nil
            let ratio = Double(resizeWidth / max(resizing.column, 1))
            coordinator?.setImageWidth(at: resizing.index, ratio: min(max(ratio, 0.2), 1))
            hoveredImage = nil
            needsDisplay = true
            return
        }
        guard let dragged = dragging else { return super.mouseUp(with: event) }
        dimDragged(false)
        dragging = nil
        let boundary = dropBoundary
        let card = dropCard
        dropBoundary = nil
        dropCard?.isDropTarget = false
        dropCard = nil
        hovered = nil
        NSCursor.arrow.set()
        if let card {
            coordinator?.moveParagraph(dragged, intoPage: card.pageID)
        } else if let boundary {
            coordinator?.moveParagraph(dragged, to: boundary)
        }
        needsDisplay = true
    }

    private func attachmentCell(for page: String) -> PageCardCell? {
        guard let storage = textStorage else { return nil }
        var found: PageCardCell?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if let cell = (value as? NSTextAttachment)?.attachmentCell as? PageCardCell, cell.pageID == page {
                found = cell
                stop.pointee = true
            }
        }
        return found
    }

    /// Пока блок тащат, он на своём месте полупрозрачный.
    private func dimDragged(_ on: Bool) {
        guard let dragging, let layout = layoutManager else { return }
        if on {
            layout.addTemporaryAttribute(.foregroundColor, value: Style.text.withAlphaComponent(0.3), forCharacterRange: dragging)
        } else {
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: dragging)
        }
    }

    private func paragraph(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, storage.length > 0, let layout = layoutManager, let container = textContainer else { return nil }
        let local = NSPoint(x: max(point.x, textContainerOrigin.x + 1) - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard local.y >= 0, local.y <= layout.usedRect(for: container).maxY else { return nil }
        // Пустая строка в самом конце - отдельный «лишний» фрагмент. Без этой проверки мышь над ней
        // попадала в последний абзац, и «+» с ручкой прыгали к его первой строке.
        let extra = layout.extraLineFragmentRect
        if extra.height > 0, local.y >= extra.minY, local.y <= extra.maxY {
            return NSRange(location: storage.length, length: 0)
        }
        let glyph = layout.glyphIndex(for: local, in: container)
        let char = min(layout.characterIndexForGlyph(at: glyph), storage.length - 1)
        return (storage.string as NSString).paragraphRange(for: NSRange(location: char, length: 0))
    }

    private func isEmpty(_ paragraph: NSRange) -> Bool {
        guard let storage = textStorage else { return true }
        let safe = NSIntersectionRange(paragraph, NSRange(location: 0, length: storage.length))
        return (storage.string as NSString).substring(with: safe).trimmingCharacters(in: .newlines).isEmpty
    }

    /// «+» слева от ручки: меню блоков для этой строки.
    private func plusRect(for paragraph: NSRange) -> NSRect {
        let mid = lineMid(of: paragraph)
        return NSRect(x: textContainerOrigin.x - 40, y: mid - 10, width: 20, height: 20)
    }

    /// Середина самой строки (без межстрочного отступа) - по ней стоят «+» и ручка.
    private func lineMid(of paragraph: NSRange) -> CGFloat {
        guard let layout = layoutManager, let storage = textStorage else { return 0 }
        if paragraph.location >= storage.length {
            let rect = layout.extraLineFragmentRect
            let font = typingAttributes[.font] as? NSFont ?? Style.font(Style.editorSize)
            return textContainerOrigin.y + rect.minY + font.ascender - font.xHeight / 2 + 1
        }
        let glyph = layout.glyphIndexForCharacter(at: paragraph.location)
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let font = storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont ?? Style.font(Style.editorSize)
        let baseline = line.minY + layout.location(forGlyphAt: glyph).y
        return textContainerOrigin.y + baseline - font.xHeight / 2
    }

    /// Мышь над самим «+» - он ярче и с подложкой.
    private var plusHovered = false

    /// Строка с курсором - на ней «+» виден всегда, пустая она или нет.
    private var caretEmptyParagraph: NSRange? {
        guard window?.firstResponder === self, let storage = textStorage else { return nil }
        let caret = selectedRange()
        guard caret.length == 0 else { return nil }
        let ns = storage.string as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: min(caret.location, ns.length), length: 0))
        // Строку внутри свёрнутого списка не показываем - её не видно.
        if paragraph.length > 0, paragraph.location < ns.length,
           storage.attribute(.zHidden, at: paragraph.location, effectiveRange: nil) != nil { return nil }
        return paragraph
    }

    private func firstLineRect(of paragraph: NSRange) -> NSRect {
        guard let layout = layoutManager else { return .zero }
        if paragraph.location >= (textStorage?.length ?? 0) {
            // Пустая строка в самом конце: её «лишний» фрагмент.
            return layout.extraLineFragmentRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        }
        let glyph = layout.glyphIndexForCharacter(at: paragraph.location)
        return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    private func handleRect(for paragraph: NSRange) -> NSRect {
        let mid = lineMid(of: paragraph)
        return NSRect(x: textContainerOrigin.x - 18, y: mid - 9, width: 14, height: 18)
    }

    /// Ближайшая к точке граница между абзацами - индекс начала абзаца (или конец текста).
    private func boundary(near point: NSPoint) -> Int? {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return nil }
        let ns = storage.string as NSString
        var best: (Int, CGFloat)?
        var location = 0
        while location <= ns.length {
            let y: CGFloat
            if location == ns.length {
                y = layout.usedRect(for: container).maxY + textContainerOrigin.y
            } else {
                y = firstLineRect(of: NSRange(location: location, length: 0)).minY
            }
            let d = abs(y - point.y)
            if best == nil || d < best!.1 { best = (location, d) }
            if location == ns.length { break }
            location = NSMaxRange(ns.paragraphRange(for: NSRange(location: location, length: 0)))
        }
        return best?.0
    }

    private func boundaryY(_ boundary: Int) -> CGFloat {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return 0 }
        if boundary >= storage.length { return layout.usedRect(for: container).maxY + textContainerOrigin.y }
        return firstLineRect(of: NSRange(location: boundary, length: 0)).minY
    }

    /// «+», ручка ⠿ и линия вставки рисуются на прозрачном слое поверх текста:
    /// само текстовое поле обрезает всё, что рисуется левее текста, и там их не было видно.
    private lazy var gutter: GutterOverlay = {
        let view = GutterOverlay(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.owner = self
        addSubview(view)
        return view
    }()

    fileprivate func drawGutter() { drawDragUI() }

    private func drawDragUI() {
        // «+» на строке под мышью и на пустой строке с курсором.
        if dragging == nil {
            // Тонкий плюс без плашки, как в Notion; подложка - только когда мышь над ним.
            for location in [gutterParagraph].compactMap({ $0?.location }) {
                let rect = plusRect(for: NSRange(location: location, length: 0))
                let underMouse = plusHovered && hovered?.location == location
                if underMouse {
                    NSColor.white.withAlphaComponent(0.1).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                }
                let arm: CGFloat = 5
                let plus = NSBezierPath()
                plus.move(to: NSPoint(x: rect.midX - arm, y: rect.midY))
                plus.line(to: NSPoint(x: rect.midX + arm, y: rect.midY))
                plus.move(to: NSPoint(x: rect.midX, y: rect.midY - arm))
                plus.line(to: NSPoint(x: rect.midX, y: rect.midY + arm))
                plus.lineWidth = 1.4
                plus.lineCapStyle = .round
                let isHoveredLine = hovered?.location == location
                Style.text.withAlphaComponent(underMouse ? 0.9 : isHoveredLine ? 0.5 : 0.35).setStroke()
                plus.stroke()
            }
        }
        if dragging == nil {
            // Ручка ⠿ - шесть точек справа от «+»: на строке под мышью и на строке с курсором.
            for paragraph in handleParagraphs {
                let rect = handleRect(for: paragraph)
                Style.text.withAlphaComponent(paragraph.location == hovered?.location ? 0.55 : 0.4).setFill()
                for row in 0..<3 {
                    for col in 0..<2 {
                        let dot = NSRect(x: rect.minX + 3 + CGFloat(col) * 5, y: rect.minY + 3 + CGFloat(row) * 5, width: 2.6, height: 2.6)
                        NSBezierPath(ovalIn: dot).fill()
                    }
                }
            }
        }
        if let dropBoundary = dragging != nil ? dropBoundary : externalBoundary {
            // Куда встанет блок - тонкая линия со скруглёнными краями.
            let y = boundaryY(dropBoundary)
            let left = textContainerOrigin.x
            let width = (textContainer?.size.width ?? bounds.width) - 4
            Style.text.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: NSRect(x: left, y: y - 1.25, width: width, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
        }
    }
}

/// Прозрачный слой над текстом для «+», ручки ⠿ и линии вставки. Мышь проходит сквозь него.
final class GutterOverlay: NSView {
    weak var owner: NotesTextView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { owner?.drawGutter() }
}

/// Одна строчка тем же почерком - для списка заметок.
struct NoteLabel: NSViewRepresentable {
    let text: String
    let alpha: CGFloat
    /// Стиль открытой заметки: список пишется её шрифтом и цветом.
    var style = PageStyle.current

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.wantsLayer = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Список подстраивается под открытую заметку: её шрифт и цвет текста (как «стиль приложения» в Craft).
        let paragraphStyle = NSMutableParagraphStyle()
        var attrs: [NSAttributedString.Key: Any] = [
            .font: style.font(style.listSize, weight: style.font == .hand ? 500 : 500),
            .foregroundColor: style.text.color, .paragraphStyle: paragraphStyle,
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        attrs[.paragraphStyle] = paragraph
        field.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
        // Яркость меняется плавно, когда выбираешь другую заметку.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            field.animator().alphaValue = alpha
        }
    }
}
