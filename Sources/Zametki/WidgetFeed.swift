import Foundation
import WidgetKit

/// Снимок «Входящих» для виджета: последние строки в маленьком файле рядом с заметками.
/// Виджет работает в песочнице и читает только этот файл; всё остальное ему недоступно.
enum WidgetFeed {
    static let fileName = "widget-inbox.json"
    static let maxLines = 6

    struct Snapshot: Codable, Equatable {
        var lines: [String]
        var closed: Bool
        var count: Int
    }

    /// Пишет снимок, только если он изменился, и просит систему обновить виджет.
    static func publish(_ store: Store) {
        let id = store.inboxID(createIfMissing: false)
        var snapshot = Snapshot(lines: [], closed: false, count: 0)
        if let id, let note = store.note(id) {
            // Закрытая под Touch ID заметка никогда не отдаёт текст виджету, даже пока открыта.
            if note.doc.locked == true || note.isClosed {
                snapshot.closed = true
            } else {
                let lines = note.doc.text.replacingOccurrences(of: "\u{FFFC}", with: "")
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .dropFirst() // первая строка - заголовок «Входящие»
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                snapshot.count = lines.count
                snapshot.lines = Array(lines.suffix(maxLines))
            }
        }
        let url = store.folder.appendingPathComponent(fileName)
        if let old = try? Data(contentsOf: url), let prev = try? JSONDecoder().decode(Snapshot.self, from: old), prev == snapshot { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
