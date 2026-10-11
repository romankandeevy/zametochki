import AppKit
import Observation

struct Note: Identifiable, Equatable {
    let id: String          // имя файла без расширения
    var doc: Formatting.Doc
    var modified: Date
    /// Растёт, когда заметку поменяли не из редактора (карточки, перенос блоков): редактор перечитает её.
    var revision = 0
    /// Закрытая заметка открыта в этом запуске: текст в памяти настоящий.
    var unlocked = false

    var text: String { doc.text }
    var parent: String? { doc.parent }
    /// Закрытая заметка, которую ещё не открыли: текста в памяти нет.
    var isClosed: Bool { doc.locked == true && !unlocked }

    var title: String {
        if isClosed { return "Закрытая заметка" }
        let first = text.split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return first ?? "Без названия"
    }

    /// Первая строка после названия - для превью на карточке.
    var preview: String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .dropFirst().first ?? ""
    }
}

/// Каждая заметка - отдельный .json в ~/Library/Application Support/Zametki: текст, куски с оформлением,
/// родитель и место в списке. Заметки складываются в дерево, как страницы в Craft. Никакой сети, никакой базы.
@Observable
final class Store {
    private(set) var notes: [Note] = []
    var selectedID: String?
    /// Короткое сообщение сверху окна (например, «глубже нельзя») - само исчезает.
    var toast: String?
    /// Раскрытые в списке слева страницы.
    var expanded: Set<String> = [] {
        didSet { UserDefaults.standard.set(Array(expanded), forKey: "expanded") }
    }

    let folder: URL
    @ObservationIgnored private var pendingSave: [String: DispatchWorkItem] = [:]

    /// Папка с заметками. У демо-сборки (для скриншотов и ролика) - своя, чтобы не трогать настоящие заметки.
    static let dataFolder: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let demo = Bundle.main.bundleIdentifier?.hasSuffix(".demo") == true
        return support.appendingPathComponent(demo ? "ZametkiDemo" : "Zametki", isDirectory: true)
    }()

    init() {
        folder = Store.dataFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        expanded = Set(UserDefaults.standard.stringArray(forKey: "expanded") ?? [])
        load()
        if notes.isEmpty { create() } else { selectedID = children(of: nil).first?.id ?? notes.first?.id }
        // Запуск с «-openNote <id>» сразу открывает эту заметку (для скриншотов и ролика).
        if let id = UserDefaults.standard.string(forKey: "openNote"), note(id) != nil { select(id) }
        Reminders.sync(self)
    }

    var selected: Note? { note(selectedID) }

    func note(_ id: String?) -> Note? { id.flatMap { id in notes.first { $0.id == id } } }

    private func index(_ id: String) -> Int? { notes.firstIndex { $0.id == id } }

    private func url(_ id: String) -> URL { folder.appendingPathComponent(id).appendingPathExtension("json") }

    func fileURL(_ id: String) -> URL { url(id) }

    // MARK: стиль

    /// Стиль страницы: свой или стиль по умолчанию.
    func style(of id: String?) -> PageStyle { note(id)?.doc.style ?? PageStyle.saved }

    /// Стиль открытой заметки - по нему подстраиваются список, панели и кнопки.
    var currentStyle: PageStyle { style(of: selectedID) }

    func setStyle(_ style: PageStyle, for id: String) {
        guard let i = index(id) else { return }
        notes[i].doc.style = style
        notes[i].revision += 1
        scheduleSave(id)
    }

    /// Один стиль на все заметки сразу.
    func setStyleForAll(_ style: PageStyle) {
        for note in notes { setStyle(style, for: note.id) }
    }

    // MARK: дерево

    /// Сколько уровней страниц можно вкладывать друг в друга.
    static let maxDepth = 5

    /// Уровень заметки: 0 - верхняя, 1 - страница внутри неё и т.д.
    func depth(_ id: String?) -> Int { max(path(to: id).count - 1, 0) }

    /// Можно ли положить страницу (вместе с её вложенными) внутрь parent.
    func canNest(_ id: String? = nil, under parent: String?) -> Bool {
        guard let parent else { return true }
        let below = id.map { subtreeHeight($0) } ?? 0
        if depth(parent) + 1 + below <= Self.maxDepth { return true }
        say("Глубже \(Self.maxDepth) уровней вкладывать нельзя")
        return false
    }

    /// Высота поддерева: 0 - без вложенных страниц.
    private func subtreeHeight(_ id: String) -> Int {
        let kids = children(of: id)
        return kids.isEmpty ? 0 : 1 + (kids.map { subtreeHeight($0.id) }.max() ?? 0)
    }

    func say(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }

    func children(of parent: String?) -> [Note] {
        notes.filter { $0.parent == parent }.sorted { ($0.doc.order ?? 0) < ($1.doc.order ?? 0) }
    }

    func hasChildren(_ id: String) -> Bool { notes.contains { $0.parent == id } }

    /// Строки списка слева: дерево, развёрнутое по раскрытым страницам.
    var rows: [(note: Note, depth: Int)] {
        var out: [(Note, Int)] = []
        func walk(_ parent: String?, _ depth: Int) {
            var kids = children(of: parent)
            // Закреплённые заметки верхнего уровня - выше остальных, порядок среди них прежний.
            if parent == nil { kids = kids.filter { $0.doc.pinned == true } + kids.filter { $0.doc.pinned != true } }
            for note in kids {
                out.append((note, depth))
                if expanded.contains(note.id) { walk(note.id, depth + 1) }
            }
        }
        walk(nil, 0)
        return out
    }

    /// Путь от верхней заметки до этой - для крошек.
    func path(to id: String?) -> [Note] {
        var out: [Note] = []
        var current = note(id)
        while let n = current, !out.contains(where: { $0.id == n.id }) {
            out.insert(n, at: 0)
            current = note(n.parent)
        }
        return out
    }

    func isDescendant(_ id: String, of ancestor: String) -> Bool {
        var current = note(id)?.parent
        while let p = current {
            if p == ancestor { return true }
            current = note(p)?.parent
        }
        return false
    }

    // MARK: загрузка

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func date(_ file: URL) -> Date {
            (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        var loaded: [Note] = files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let doc = try? JSONDecoder().decode(Formatting.Doc.self, from: data) else { return nil }
            return Note(id: file.deletingPathExtension().lastPathComponent, doc: doc, modified: date(file))
        }
        // Старые .txt с разметкой переводим в новый формат один раз; исходник - в Корзину.
        for file in files where file.pathExtension == "txt" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let note = Note(id: file.deletingPathExtension().lastPathComponent, doc: Formatting.fromMarkdown(text), modified: date(file))
            loaded.append(note)
            notes = loaded
            write(note.id)
            try? FileManager.default.setAttributes([.modificationDate: note.modified], ofItemAtPath: url(note.id).path)
            try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
        }
        // Родитель пропал - страница поднимается наверх, а не теряется.
        let ids = Set(loaded.map(\.id))
        for i in loaded.indices where loaded[i].doc.parent.map({ !ids.contains($0) }) ?? false {
            loaded[i].doc.parent = nil
        }
        // У старых заметок нет места в списке - раздаём по дате, свежие выше.
        let unordered = loaded.indices.filter { loaded[$0].doc.order == nil }.sorted { loaded[$0].modified > loaded[$1].modified }
        for (n, i) in unordered.enumerated() { loaded[i].doc.order = Double(n) }
        notes = loaded
    }

    // MARK: создание

    private func newID(offset: Double = 0) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        var id = formatter.string(from: Date().addingTimeInterval(offset))
        while index(id) != nil { id += "-1" }
        return id
    }

    /// Новая заметка наверху списка (или первой среди страниц родителя).
    @discardableResult
    func create(parent: String? = nil, doc: Formatting.Doc = .init(text: ""), open: Bool = true) -> String {
        dropEmpty(except: nil)
        var doc = doc
        doc.parent = parent
        doc.order = (children(of: parent).map { $0.doc.order ?? 0 }.min() ?? 1) - 1
        if doc.style == nil { doc.style = PageStyle.saved }
        let note = Note(id: newID(), doc: doc, modified: Date())
        notes.append(note)
        write(note.id)
        if open { reveal(note.id); selectedID = note.id }
        return note.id
    }

    /// Новая вложенная страница: в конце списка страниц родителя. Карточку в текст родителя ставит редактор.
    func createPage(in parent: String, title: String) -> String? {
        guard !isClosed(parent) else { say("Сначала откройте закрытую заметку"); return nil }
        guard canNest(under: parent) else { return nil }
        var doc = Formatting.Doc(text: title)
        if !title.isEmpty { doc.runs = [Formatting.Run(from: 0, length: (title as NSString).length, block: Block.title.rawValue)] }
        doc.parent = parent
        doc.order = (children(of: parent).map { $0.doc.order ?? 0 }.max() ?? -1) + 1
        // Страница наследует стиль родителя - как в Craft.
        doc.style = style(of: parent)
        let note = Note(id: newID(), doc: doc, modified: Date())
        notes.append(note)
        write(note.id)
        expanded.insert(parent)
        return note.id
    }

    /// Импорт: каждый документ - новая заметка, первая из них открывается.
    func add(_ docs: [Formatting.Doc]) {
        guard !docs.isEmpty else { return }
        var first: String?
        for doc in docs.reversed() { first = create(doc: doc, open: false) }
        if let first { selectedID = first }
    }

    func select(_ id: String) {
        guard id != selectedID, index(id) != nil else { return }
        dropEmpty(except: id)
        reveal(id)
        selectedID = id
        relockOthers(than: id)
    }

    /// Раскрыть в списке всех предков, чтобы открытая страница была видна.
    private func reveal(_ id: String) {
        for ancestor in path(to: id).dropLast() where !expanded.contains(ancestor.id) { expanded.insert(ancestor.id) }
    }

    // MARK: правка

    func update(_ id: String, doc: Formatting.Doc) {
        guard let i = index(id) else { return }
        var doc = doc
        doc.parent = notes[i].doc.parent
        doc.order = notes[i].doc.order
        doc.style = notes[i].doc.style
        doc.pinned = notes[i].doc.pinned
        doc.daily = notes[i].doc.daily
        doc.locked = notes[i].doc.locked
        doc.sealed = notes[i].doc.sealed
        // Пока закрытая заметка не открыта, её текст не трогаем.
        guard !notes[i].isClosed else { return }
        guard notes[i].doc != doc else { return }
        notes[i].doc = doc
        notes[i].modified = Date()
        scheduleSave(id)
    }

    /// Правка заметки не из её редактора: редактор, если она открыта, перечитает её.
    func edit(_ id: String, _ body: (NSMutableAttributedString) -> Void) {
        guard let i = index(id), !notes[i].isClosed else { return }
        let text = NSMutableAttributedString(attributedString: Formatting.attributed(notes[i].doc))
        body(text)
        var doc = Formatting.doc(from: text)
        doc.parent = notes[i].doc.parent
        doc.order = notes[i].doc.order
        doc.style = notes[i].doc.style
        doc.pinned = notes[i].doc.pinned
        doc.daily = notes[i].doc.daily
        doc.locked = notes[i].doc.locked
        doc.sealed = notes[i].doc.sealed
        notes[i].doc = doc
        notes[i].modified = Date()
        notes[i].revision += 1
        scheduleSave(id)
    }

    /// Блоки, перетащенные на карточку, переезжают в конец страницы.
    func append(_ paragraphs: NSAttributedString, to id: String) {
        edit(id) { text in
            if text.length > 0, !text.string.hasSuffix("\n") {
                // Перенос закрывает последнюю строку и несёт её тип - иначе задача или заголовок стали бы текстом.
                let last = text.attributes(at: text.length - 1, effectiveRange: nil).filter { $0.key != .attachment }
                text.append(NSAttributedString(string: "\n", attributes: last))
            }
            text.append(paragraphs)
        }
    }

    // MARK: входящие

    /// Заметка «Входящие» - сюда падают быстрые заметки. Нет - создаётся.
    func inboxID() -> String {
        if let id = UserDefaults.standard.string(forKey: "inboxNote"), note(id) != nil { return id }
        if let found = notes.first(where: { $0.parent == nil && $0.title == "Входящие" }) {
            UserDefaults.standard.set(found.id, forKey: "inboxNote")
            return found.id
        }
        var doc = Formatting.Doc(text: "Входящие")
        doc.runs = [Formatting.Run(from: 0, length: ("Входящие" as NSString).length, block: Block.title.rawValue)]
        let id = create(doc: doc, open: false)
        UserDefaults.standard.set(id, forKey: "inboxNote")
        return id
    }

    /// Быстрая заметка - в конец «Входящих». Разметка в начале строки работает: «[] » - задача, «- » - список.
    func appendToInbox(_ text: String) {
        let source = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            line.hasPrefix("[] ") ? "[ ] " + line.dropFirst(3) : String(line)
        }.joined(separator: "\n")
        let id = inboxID()
        if isClosed(id) { say("«Входящие» закрыты - откройте их, чтобы дописать"); return }
        append(Formatting.attributed(Formatting.fromMarkdown(source)), to: id)
        say("Сохранено во «Входящие»")
    }

    // MARK: заметки, полученные по коду

    /// Полученные заметки встают в список. Та же заметка (id и текст) не дублируется; изменённая приходит копией.
    /// Страницы остаются внутри своих родителей, карточки в тексте ведут на новые id. Возвращает, сколько добавлено.
    @discardableResult
    func importReceived(_ items: [TransferLink.Item]) -> Int {
        var idMap: [String: String] = [:]
        var fresh: [(item: TransferLink.Item, doc: Formatting.Doc, id: String)] = []
        for item in items {
            let doc = item.doc ?? Formatting.fromMarkdown(item.md ?? "")
            if let existing = note(item.id), existing.doc.text == doc.text, existing.doc.runs == doc.runs, !existing.isClosed {
                idMap[item.id] = item.id
                continue
            }
            let id = note(item.id) == nil && idMap[item.id] == nil ? item.id : newID(offset: Double(fresh.count) * 0.001)
            idMap[item.id] = id
            fresh.append((item, doc, id))
        }
        guard !fresh.isEmpty else { return 0 }
        var roots = 0.0
        let top = (children(of: nil).map { $0.doc.order ?? 0 }.min() ?? 1) - Double(fresh.count) - 1
        for entry in fresh {
            var doc = entry.doc
            doc.locked = nil
            doc.sealed = nil
            doc.pinned = nil
            doc.daily = nil
            doc.runs = doc.runs.map { var run = $0; run.page = run.page.flatMap { idMap[$0] ?? $0 }; run.link = run.link.flatMap { idMap[$0] ?? $0 }; return run }
            if let parent = entry.item.parent, let mapped = idMap[parent] {
                doc.parent = mapped
                doc.order = entry.item.order ?? 0
            } else {
                doc.parent = nil
                roots += 1
                doc.order = top + roots
            }
            if doc.style == nil { doc.style = PageStyle.saved }
            notes.append(Note(id: entry.id, doc: doc, modified: Date()))
            write(entry.id)
        }
        // Переехавшая страница без карточки в родителе: ставим карточку в конец.
        for entry in fresh where entry.doc.parent != nil || entry.item.parent != nil {
            guard let parent = idMap[entry.item.parent ?? ""], let child = idMap[entry.item.id],
                  let p = note(parent), !p.doc.runs.contains(where: { $0.page == child }) else { continue }
            edit(parent) { Formatting.appendCard(child, to: $0) }
        }
        if let first = fresh.first(where: { $0.doc.parent == nil || idMap[$0.item.parent ?? ""] == nil }) { select(first.id) }
        Reminders.sync(self)
        return fresh.count
    }

    // MARK: закрытые заметки

    func isClosed(_ id: String?) -> Bool { note(id)?.isClosed == true }

    private func subtree(_ id: String) -> [String] { [id] + children(of: id).flatMap { subtree($0.id) } }

    /// Закрыть заметку и все её страницы: текст шифруется ключом из связки ключей.
    func lock(_ id: String) {
        guard let key = Vault.key(create: true) else { say("Нет доступа к связке ключей"); return }
        for sub in subtree(id) {
            guard let i = index(sub) else { continue }
            if notes[i].doc.locked == true, !notes[i].unlocked { continue }
            guard let sealed = Vault.seal(.init(text: notes[i].doc.text, runs: notes[i].doc.runs), key: key) else {
                say("Не удалось зашифровать заметку")
                return
            }
            pendingSave[sub]?.cancel()
            pendingSave[sub] = nil
            notes[i].doc.locked = true
            notes[i].doc.sealed = sealed
            close(i)
            // Старые копии были открытым текстом - им на диске не место.
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("Backups/\(sub)", isDirectory: true))
        }
        say("Заметка закрыта")
    }

    /// Убрать из памяти открытый текст закрытой заметки (на диске он уже зашифрован).
    private func close(_ i: Int) {
        notes[i].doc.text = ""
        notes[i].doc.runs = []
        notes[i].unlocked = false
        notes[i].revision += 1
        write(notes[i].id)
    }

    /// Открыть закрытую заметку: Touch ID или пароль, затем расшифровка.
    func unlock(_ id: String, completion: ((Bool) -> Void)? = nil) {
        guard let i = index(id), notes[i].isClosed else { completion?(true); return }
        Vault.authenticate(reason: "Открыть закрытую заметку") { [weak self] ok in
            guard let self, ok, let i = self.index(id), let sealed = self.notes[i].doc.sealed else { completion?(false); return }
            guard let key = Vault.key(create: false), let content = Vault.open(sealed, key: key) else {
                self.say("Не удалось расшифровать - ключ не найден")
                completion?(false)
                return
            }
            self.notes[i].doc.text = content.text
            self.notes[i].doc.runs = content.runs
            self.notes[i].unlocked = true
            self.notes[i].revision += 1
            completion?(true)
        }
    }

    /// Закрыть снова все открытые закрытые заметки, кроме выбранной (или все, если other == nil).
    func relockOthers(than keep: String?) {
        for i in notes.indices where notes[i].doc.locked == true && notes[i].unlocked && notes[i].id != keep { close(i) }
    }

    /// Снять защиту: заметка снова обычная. Только у открытой.
    func removeLock(_ id: String) {
        guard let i = index(id), notes[i].doc.locked == true, notes[i].unlocked else { return }
        notes[i].doc.locked = nil
        notes[i].doc.sealed = nil
        notes[i].unlocked = false
        write(id)
        say("Защита снята")
    }

    // MARK: ссылки между заметками

    /// Заметки, в которых есть ссылка на эту.
    func backlinks(to id: String) -> [Note] {
        notes.filter { $0.id != id && $0.doc.runs.contains { $0.link == id } }
            .sorted { $0.modified > $1.modified }
    }

    // MARK: закрепление и недавние

    func isPinned(_ id: String) -> Bool { note(id)?.doc.pinned == true }

    func togglePin(_ id: String) {
        guard let i = index(id), notes[i].parent == nil else { return }
        notes[i].doc.pinned = notes[i].doc.pinned == true ? nil : true
        scheduleSave(id)
    }

    /// Последние изменённые заметки - для пустого окна поиска.
    func recent(_ count: Int = 8) -> [Note] {
        notes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.modified > $1.modified }.prefix(count).map { $0 }
    }

    // MARK: сегодня

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Заметка за день, если она есть.
    func dailyNote(_ date: Date) -> Note? {
        let key = Self.dayKey(date)
        return notes.first { $0.doc.daily == key }
    }

    /// Открыть заметку за сегодня: нет - создаётся из шаблона «Дневник дня», а невыполненные задачи
    /// с последнего дня переезжают в конец.
    @discardableResult
    func openToday(now: Date = Date()) -> String {
        if let today = dailyNote(now) { select(today.id); return today.id }
        var doc = Template.all.first { $0.id == "diary" }?.doc(on: now) ?? Formatting.Doc(text: "")
        doc.daily = Self.dayKey(now)
        let carried = unfinishedTasks(before: now)
        let id = create(doc: doc)
        if carried.length > 0 {
            edit(id) { text in
                if !text.string.hasSuffix("\n") { text.append(NSAttributedString(string: "\n")) }
                text.append(carried)
            }
            say("Невыполненные задачи со вчера - внизу")
        }
        return id
    }

    /// Невыполненные задачи из самой свежей заметки-дня, что раньше этой даты.
    func unfinishedTasks(before date: Date) -> NSAttributedString {
        let key = Self.dayKey(date)
        guard let last = notes.filter({ ($0.doc.daily ?? "") < key && $0.doc.daily != nil })
            .max(by: { ($0.doc.daily ?? "") < ($1.doc.daily ?? "") }) else { return NSAttributedString() }
        let text = Formatting.attributed(last.doc)
        let ns = text.string as NSString
        let out = NSMutableAttributedString()
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, _, full, _ in
            let end = max(full.location, NSMaxRange(full) - 1)
            guard full.length > 0,
                  Formatting.block(of: text.attributes(at: min(end, ns.length - 1), effectiveRange: nil)) == .todo else { return }
            let line = text.attributedSubstring(from: full)
            let body = line.string.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FFFC}")))
            guard !body.isEmpty else { return }
            out.append(line.string.hasSuffix("\n") ? line : {
                let m = NSMutableAttributedString(attributedString: line)
                m.append(NSAttributedString(string: "\n", attributes: line.attributes(at: line.length - 1, effectiveRange: nil)))
                return m
            }())
        }
        return out
    }

    // MARK: перенос в списке слева

    /// Положить заметку внутрь parent (nil - наверх) перед before (nil - в конец).
    func move(_ id: String, into parent: String?, before: String? = nil) {
        guard let i = index(id), id != parent, parent.map({ !isDescendant($0, of: id) }) ?? true else { return }
        if isClosed(parent) { say("Сначала откройте закрытую заметку"); return }
        if parent != notes[i].parent, !canNest(id, under: parent) { return }
        let oldParent = notes[i].parent
        let siblings = children(of: parent).filter { $0.id != id }
        let order: Double
        if let before, let at = siblings.firstIndex(where: { $0.id == before }) {
            let next = siblings[at].doc.order ?? 0
            let prev = at > 0 ? (siblings[at - 1].doc.order ?? 0) : next - 2
            order = (prev + next) / 2
        } else {
            order = (siblings.last?.doc.order ?? -1) + 1
        }
        notes[i].doc.parent = parent
        notes[i].doc.order = order
        notes[i].revision += 1
        scheduleSave(id)
        // Карточки в тексте идут за деревом: убираем из старого родителя, добавляем в новый.
        if oldParent != parent {
            if let oldParent { edit(oldParent) { Formatting.removeCards(of: id, in: $0) } }
            if let parent {
                edit(parent) { Formatting.appendCard(id, to: $0) }
                expanded.insert(parent)
            }
        }
    }

    /// Карточку уже перенесли руками (в тексте) - меняем только родителя.
    func reparent(_ id: String, to parent: String) {
        guard let i = index(id), id != parent, !isDescendant(parent, of: id), canNest(id, under: parent) else { return }
        notes[i].doc.parent = parent
        notes[i].doc.order = (children(of: parent).map { $0.doc.order ?? 0 }.max() ?? -1) + 1
        scheduleSave(id)
        expanded.insert(parent)
    }

    // MARK: удаление

    /// Заметка и все её страницы уходят в Корзину - случайное удаление можно вернуть.
    func delete(_ id: String) {
        guard let note = note(id) else { return }
        let rowsBefore = rows.map(\.note.id)
        for child in children(of: id) { delete(child.id) }
        pendingSave[id]?.cancel()
        notes.removeAll { $0.id == id }
        try? FileManager.default.trashItem(at: url(id), resultingItemURL: nil)
        if let parent = note.parent { edit(parent) { Formatting.removeCards(of: id, in: $0) } }
        if selectedID == id || selectedID.map({ self.note($0) == nil }) ?? true {
            // Открываем соседа по списку или родителя.
            let at = rowsBefore.firstIndex(of: id) ?? 0
            let candidates = rowsBefore[at...].dropFirst() + rowsBefore[..<at].reversed()
            selectedID = note.parent ?? candidates.first { self.note($0) != nil }
        }
        if notes.isEmpty { create() }
    }

    func step(_ delta: Int) {
        let ids = rows.map(\.note.id)
        guard let i = ids.firstIndex(where: { $0 == selectedID }) else { return }
        let j = i + delta
        if ids.indices.contains(j) { select(ids[j]) }
    }

    func flush() {
        for (id, work) in pendingSave { work.cancel(); write(id) }
        pendingSave.removeAll()
    }

    /// Пустые заметки верхнего уровня не плодим: уходя с пустой, удаляем её.
    /// Пустые страницы не трогаем - на них стоит карточка в родителе.
    private func dropEmpty(except keep: String?) {
        for note in notes where note.id != keep && note.parent == nil && !hasChildren(note.id) && note.doc.locked != true
            && note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingSave[note.id]?.cancel()
            pendingSave[note.id] = nil
            // Пустая - терять нечего, в Корзину не кладём.
            try? FileManager.default.removeItem(at: url(note.id))
            notes.removeAll { $0.id == note.id }
        }
    }

    /// Сохраняем сразу, на каждую правку: заметки маленькие, запись - миллисекунды, а потерять текст нельзя.
    private func scheduleSave(_ id: String) {
        pendingSave[id]?.cancel()
        pendingSave[id] = nil
        write(id)
        Reminders.sync(self)
    }

    private func write(_ id: String) {
        guard let note = note(id) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        var doc = note.doc
        if doc.locked == true {
            // Закрытая заметка лежит на диске только зашифрованной.
            if note.unlocked {
                guard let key = Vault.key(create: false),
                      let sealed = Vault.seal(.init(text: doc.text, runs: doc.runs), key: key) else {
                    say("Не удалось зашифровать заметку - она не сохранена")
                    return
                }
                doc.sealed = sealed
            }
            doc.text = ""
            doc.runs = []
        }
        guard let data = try? encoder.encode(doc) else { return }
        if doc.locked != true { backupIfShrinking(id, newText: note.doc.text, newSize: data.count) }
        try? data.write(to: url(id), options: .atomic)
    }

    /// Страховка: если заметка разом потеряла заметную часть текста, предмет (доску, таблицу, картинку)
    /// или файл резко похудел - прошлая версия сначала кладётся в Backups/<заметка>/<время>.json.
    private func backupIfShrinking(_ id: String, newText: String, newSize: Int) {
        let file = url(id)
        guard let old = try? Data(contentsOf: file),
              let oldDoc = try? JSONDecoder().decode(Formatting.Doc.self, from: old) else { return }
        let lost = oldDoc.text.count - newText.count
        let lostText = lost >= 40 || (lost >= 12 && Double(newText.count) < Double(oldDoc.text.count) * 0.5)
        // Доска или таблица в тексте - один символ, но внутри может быть много работы.
        let objects = { (text: String) in text.unicodeScalars.filter { $0 == "\u{FFFC}" }.count }
        let lostObject = objects(newText) < objects(oldDoc.text)
        let lostData = old.count - newSize >= 1500 && Double(newSize) < Double(old.count) * 0.6
        guard lostText || lostObject || lostData else { return }
        let folder = self.folder.appendingPathComponent("Backups/\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        try? old.write(to: folder.appendingPathComponent(formatter.string(from: Date()) + ".json"), options: .atomic)
    }
}
