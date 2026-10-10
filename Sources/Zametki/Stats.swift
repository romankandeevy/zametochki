import AppKit
import Observation
import SwiftUI

/// Сколько слов в открытой заметке и в выделении - редактор обновляет, плашка в углу показывает.
@Observable
final class EditorStats {
    static let shared = EditorStats()
    var words = 0
    var selectedWords = 0

    /// Слова - куски между пробелами; предметы (картинки, карточки) словами не считаются.
    static func count(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for ch in text.unicodeScalars {
            let letter = ch != "\u{FFFC}" && !CharacterSet.whitespacesAndNewlines.contains(ch)
            if letter, !inWord { count += 1 }
            inWord = letter
        }
        return count
    }

    /// Читают в среднем около 180 слов в минуту.
    static func readingTime(_ words: Int) -> String {
        guard words > 0 else { return "" }
        let minutes = Int((Double(words) / 180).rounded(.up))
        return minutes <= 1 ? "1 мин чтения" : "\(minutes) мин чтения"
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = n % 100, b = n % 10
        if (11...14).contains(a) { return many }
        if b == 1 { return one }
        if (2...4).contains(b) { return few }
        return many
    }
}

/// Тихая плашка в правом нижнем углу: «245 слов · 2 мин чтения», с выделением - «выделено 12 слов».
/// Нажатие включает и выключает режим фокуса.
struct StatsBadge: View {
    private var stats = EditorStats.shared
    @AppStorage("showStats") private var shown = true
    @AppStorage("focusMode") private var focus = false
    @State private var hover = false

    var body: some View {
        if shown, stats.words > 0 || focus {
            Button {
                focus.toggle()
                Editor.Coordinator.active?.applyFocus()
            } label: {
                HStack(spacing: 6) {
                    if focus {
                        Image(systemName: "scope").font(.system(size: 10, weight: .semibold))
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white.opacity(hover ? 0.85 : 0.55))
                .padding(.horizontal, 10)
                .frame(height: 24)
                // Своя подложка в тон страницы: плашка не смешивается с текстом, когда он доходит до угла.
                .background(Capsule().fill(Color(nsColor: PageStyle.current.panelColor).opacity(hover ? 1 : 0.92)))
                .overlay(Capsule().strokeBorder(.white.opacity(hover ? 0.16 : 0.08)))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(.smooth(duration: 0.2), value: stats.words)
            .animation(.smooth(duration: 0.2), value: stats.selectedWords)
            .help(focus ? "Режим фокуса включён - нажми, чтобы выключить (⇧⌘F)" : "Режим фокуса (⇧⌘F)")
        }
    }

    private var label: String {
        if stats.selectedWords > 0 {
            let n = stats.selectedWords
            return "выделено \(n) " + EditorStats.plural(n, "слово", "слова", "слов")
        }
        let n = stats.words
        let words = "\(n) " + EditorStats.plural(n, "слово", "слова", "слов")
        let time = EditorStats.readingTime(n)
        return time.isEmpty ? words : words + " · " + time
    }
}

/// «Упоминается в 2»: заметки, которые ссылаются на открытую. Нажал - выбрал, куда перейти.
struct BacklinksBadge: View {
    let store: Store
    @State private var hover = false

    var body: some View {
        let links = store.selectedID.map { store.backlinks(to: $0) } ?? []
        if !links.isEmpty {
            Menu {
                Text("Упоминается в")
                ForEach(links) { note in Button(note.title) { store.select(note.id) } }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "link").font(.system(size: 10, weight: .semibold))
                    Text("\(links.count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                }
                .foregroundStyle(.white.opacity(hover ? 0.85 : 0.55))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color(nsColor: PageStyle.current.panelColor).opacity(hover ? 1 : 0.92)))
                .overlay(Capsule().strokeBorder(.white.opacity(hover ? 0.16 : 0.08)))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { hover = $0 }
            .help("Упоминается в других заметках")
        }
    }
}
