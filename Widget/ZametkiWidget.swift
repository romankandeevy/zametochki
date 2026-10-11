import SwiftUI
import WidgetKit

/// Виджет «Входящие»: последние мысли из заметки «Входящие» и кнопка новой. Данные - файл widget-inbox.json,
/// который пишет приложение (WidgetFeed); в сеть виджет не ходит.
private struct Snapshot: Codable {
    var lines: [String]
    var closed: Bool
    var count: Int
}

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

private enum Feed {
    /// Настоящий домашний каталог: в песочнице HOME указывает в контейнер расширения.
    static var url: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Zametki/widget-inbox.json")
    }

    static func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: Snapshot(lines: ["Позвонить маме", "Идея для ролика", "Купить хлеб"], closed: false, count: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Entry(date: Date(), snapshot: Feed.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Приложение само просит обновить виджет при каждой правке «Входящих»; раз в час - страховка.
        completion(Timeline(entries: [Entry(date: Date(), snapshot: Feed.read())],
                            policy: .after(Date().addingTimeInterval(3600))))
    }
}

private let blue = Color(red: 0x1D / 255, green: 0x35 / 255, blue: 0x94 / 255)

private struct InboxView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var limit: Int { family == .systemLarge ? 6 : family == .systemMedium ? 3 : 2 }

    var body: some View {
        let lines = Array((entry.snapshot?.lines ?? []).suffix(limit).reversed())
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 11, weight: .semibold))
                Text("Входящие").font(.system(size: 12, weight: .semibold))
                Spacer()
                if let count = entry.snapshot?.count, count > 0, !(entry.snapshot?.closed ?? false) {
                    Text("\(count)").font(.system(size: 11, weight: .medium)).opacity(0.6)
                }
            }
            .opacity(0.7)

            if entry.snapshot?.closed == true {
                Label("Закрыты", systemImage: "lock").font(.system(size: 13)).opacity(0.7)
            } else if lines.isEmpty {
                Text(entry.snapshot == nil ? "Откройте Заметочки один раз" : "Пусто. Новая мысль?")
                    .font(.system(size: 13)).opacity(0.6)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.custom("Caveat", size: 19)).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            if family != .systemSmall {
                Link(destination: URL(string: "zametki://quick")!) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("Новая мысль").font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.18)))
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: family == .systemSmall ? "zametki://quick" : "zametki://inbox"))
        .containerBackground(blue, for: .widget)
    }
}

@main
struct ZametkiWidgetBundle: WidgetBundle {
    init() {
        // Почерк Заметочек: шрифт лежит рядом с расширением.
        if let url = Bundle.main.url(forResource: "Caveat", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Widget { InboxWidget() }
}

struct InboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZametkiInbox", provider: Provider()) { entry in
            InboxView(entry: entry)
        }
        .configurationDisplayName("Входящие")
        .description("Последние мысли из «Входящих» и кнопка новой.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
