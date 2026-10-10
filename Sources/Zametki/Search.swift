import AppKit
import SwiftUI

extension Notification.Name {
    static let openSearch = Notification.Name("zametki.openSearch")
    static let pickLink = Notification.Name("zametki.pickLink")
}

/// Поиск по всем заметкам (⌘K): окно поверх редактора. Пустой запрос - недавние заметки.
/// Всё ищется локально, по тексту заметок в памяти.
enum NoteSearch {
    struct Hit: Identifiable {
        let note: Note
        /// Фрагмент вокруг первого совпадения; у недавних - начало текста.
        let snippet: String
        let inTitle: Bool
        var id: String { note.id }
    }

    /// Слова запроса должны встретиться все, в любом порядке. Название выше текста, свежие выше старых.
    static func search(_ query: String, in notes: [Note], limit: Int = 30) -> [Hit] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var hits: [(Hit, Int)] = []
        for note in notes {
            let text = clean(note.text)
            let lower = text.lowercased()
            guard words.allSatisfy({ lower.contains($0) }) else { continue }
            let title = note.title.lowercased()
            let inTitle = words.allSatisfy { title.contains($0) }
            hits.append((Hit(note: note, snippet: snippet(text, around: words[0]), inTitle: inTitle),
                         (inTitle ? 2 : 0) + (title.hasPrefix(words[0]) ? 1 : 0)))
        }
        return hits.sorted { ($0.1, $0.0.note.modified) > ($1.1, $1.0.note.modified) }.prefix(limit).map(\.0)
    }

    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    static func snippet(_ text: String, around word: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " · ")
        guard let range = flat.lowercased().range(of: word) else { return String(flat.prefix(90)) }
        let start = flat.index(range.lowerBound, offsetBy: -30, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: 60, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }

    /// Открыть заметку и поставить курсор на первое совпадение.
    static func open(_ note: Note, query: String, in store: Store) {
        store.select(note.id)
        let word = query.lowercased().split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard !word.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let view = Editor.Coordinator.active?.textView else { return }
            let range = (view.string as NSString).range(of: word, options: [.caseInsensitive, .diacriticInsensitive])
            guard range.location != NSNotFound else { return }
            view.setSelectedRange(range)
            view.scrollRangeToVisible(range)
            view.showFindIndicator(for: range)
        }
    }
}

struct SearchPalette: View {
    let store: Store
    /// Выбор заметки для ссылки вместо перехода к ней.
    var pick: ((Note) -> Void)?
    let close: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var hits: [NoteSearch.Hit] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return store.recent().map { NoteSearch.Hit(note: $0, snippet: NoteSearch.snippet(NoteSearch.clean($0.text), around: "\u{0}"), inTitle: false) }
        }
        return NoteSearch.search(query, in: store.notes)
    }

    var body: some View {
        let hits = hits
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).opacity(0.5)
                TextField(pick == nil ? "Искать по всем заметкам" : "Ссылка на заметку…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { open(hits) }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            Divider().opacity(0.2)
            if hits.isEmpty {
                Text(query.isEmpty ? "Заметок пока нет" : "Ничего не нашлось")
                    .font(.system(size: 13)).opacity(0.5)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            if query.isEmpty {
                                Text("Недавние").font(.system(size: 11, weight: .semibold)).opacity(0.4)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 6)
                            }
                            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                                row(hit, active: index == selected)
                                    .id(index)
                                    .onTapGesture { selected = index; open(hits) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selected) { _, new in proxy.scrollTo(new) }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: store.currentStyle.panelColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selected = 0 }
        .onKeyPress(.downArrow) { selected = min(selected + 1, max(hits.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
    }

    private func row(_ hit: NoteSearch.Hit, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if store.isPinned(hit.note.id) { Image(systemName: "pin.fill").font(.system(size: 9)).opacity(0.5) }
                Text(hit.note.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if hit.note.parent != nil {
                    Text("в «\(store.path(to: hit.note.id).dropLast().last?.title ?? "")»")
                        .font(.system(size: 11)).opacity(0.4).lineLimit(1)
                }
            }
            if !hit.snippet.isEmpty {
                Text(hit.snippet).font(.system(size: 12)).opacity(0.55).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(active ? 0.13 : 0)))
        .contentShape(Rectangle())
    }

    private func open(_ hits: [NoteSearch.Hit]) {
        guard hits.indices.contains(selected) else { return }
        let note = hits[selected].note
        close()
        if let pick { pick(note); return }
        NoteSearch.open(note, query: query, in: store)
    }
}
