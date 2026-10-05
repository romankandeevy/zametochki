import AppKit
import Observation

struct Note: Identifiable, Equatable {
    let id: String          // имя файла без расширения
    var doc: Formatting.Doc
    var modified: Date
    /// Растёт, когда заметку поменяли не из редактора (карточки, перенос блоков): редактор перечитает её.
    var revision = 0

    var text: String { doc.text }
    var parent: String? { doc.parent }

    var title: String {
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
            for note in children(of: parent) {
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
        guard notes[i].doc != doc else { return }
        notes[i].doc = doc
        notes[i].modified = Date()
        scheduleSave(id)
    }

    /// Правка заметки не из её редактора: редактор, если она открыта, перечитает её.
    func edit(_ id: String, _ body: (NSMutableAttributedString) -> Void) {
        guard let i = index(id) else { return }
        let text = NSMutableAttributedString(attributedString: Formatting.attributed(notes[i].doc))
        body(text)
        var doc = Formatting.doc(from: text)
        doc.parent = notes[i].doc.parent
        doc.order = notes[i].doc.order
        doc.style = notes[i].doc.style
        notes[i].doc = doc
        notes[i].modified = Date()
        notes[i].revision += 1
        scheduleSave(id)
    }

    /// Блоки, перетащенные на карточку, переезжают в конец страницы.
    func append(_ paragraphs: NSAttributedString, to id: String) {
        edit(id) { text in
            if text.length > 0, !text.string.hasSuffix("\n") {
                text.append(NSAttributedString(string: "\n"))
            }
            text.append(paragraphs)
        }
    }

    // MARK: перенос в списке слева

    /// Положить заметку внутрь parent (nil - наверх) перед before (nil - в конец).
    func move(_ id: String, into parent: String?, before: String? = nil) {
        guard let i = index(id), id != parent, parent.map({ !isDescendant($0, of: id) }) ?? true else { return }
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
        for note in notes where note.id != keep && note.parent == nil && !hasChildren(note.id)
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
    }

    private func write(_ id: String) {
        guard let note = note(id) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(note.doc) else { return }
        backupIfShrinking(id, newText: note.doc.text)
        try? data.write(to: url(id), options: .atomic)
    }

    /// Страховка: если заметка разом потеряла заметную часть текста, прошлая версия сначала кладётся
    /// в Backups/<заметка>/<время>.json - её можно вернуть руками.
    private func backupIfShrinking(_ id: String, newText: String) {
        let file = url(id)
        guard let old = try? Data(contentsOf: file),
              let oldDoc = try? JSONDecoder().decode(Formatting.Doc.self, from: old) else { return }
        let lost = oldDoc.text.count - newText.count
        guard lost >= 40 || (lost >= 12 && Double(newText.count) < Double(oldDoc.text.count) * 0.5) else { return }
        let folder = self.folder.appendingPathComponent("Backups/\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        try? old.write(to: folder.appendingPathComponent(formatter.string(from: Date()) + ".json"), options: .atomic)
    }
}
