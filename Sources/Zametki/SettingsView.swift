import AppKit
import SwiftUI

/// Настройки - шестерёнка в левом нижнем углу (и ⌘,). Окно по центру: разделы слева, содержимое справа.
/// Цвета не задаются - всё из белого с прозрачностью поверх цвета панели, так что подходит к любому стилю.
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case look, typing, voice, data, keys
        var id: String { rawValue }
        var name: String {
            switch self {
            case .look: "Вид"
            case .typing: "Текст и печать"
            case .voice: "Голосовой ввод"
            case .data: "Данные"
            case .keys: "Горячие клавиши"
            }
        }
        var symbol: String {
            switch self {
            case .look: "macwindow"
            case .typing: "textformat"
            case .voice: "mic"
            case .data: "externaldrive"
            case .keys: "command"
            }
        }
    }

    var close: (() -> Void)? = nil
    @AppStorage("settingsSection") private var sectionRaw = Section.look.rawValue
    @AppStorage(UILayout.key) private var layout = UILayout.quiet.rawValue
    @AppStorage("typingSound") private var typingSound = true
    @AppStorage("autoCapitalize") private var autoCapitalize = true
    @AppStorage("textScale") private var textScale = 1.0
    @AppStorage("spellCheck") private var spellCheck = false
    @AppStorage("t9") private var t9 = true
    @AppStorage("smartPunctuation") private var smartPunctuation = false
    @AppStorage("floatOnTop") private var floatOnTop = false
    @AppStorage("showStats") private var showStats = true
    @AppStorage(QuickNote.settingKey) private var quickNote = true

    private var section: Section { Section(rawValue: sectionRaw) ?? .look }

    private static let sizes: [(name: String, scale: Double)] = [("Мелкий", 0.88), ("Обычный", 1), ("Крупный", 1.15), ("Огромный", 1.3)]

    var body: some View {
        HStack(spacing: 0) {
            nav
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text(section.name).font(.system(size: 17, weight: .semibold))
                    content
                }
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(section)
                .transition(.opacity)
            }
            .animation(.easeOut(duration: 0.15), value: section)
        }
        .frame(maxWidth: 640, maxHeight: 450)
        .foregroundStyle(.white)
        .overlay(alignment: .topTrailing) {
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Закрыть настройки")
                .help("Закрыть (Esc)")
                .padding(14)
            }
        }
        .onChange(of: textScale) { _, _ in Editor.Coordinator.active?.refreshSettings() }
        .onChange(of: t9) { _, _ in Editor.Coordinator.active?.refreshSettings() }
        .onChange(of: spellCheck) { _, _ in Editor.Coordinator.active?.refreshSettings() }
        .onChange(of: smartPunctuation) { _, _ in Editor.Coordinator.active?.refreshSettings() }
        .onChange(of: quickNote) { _, _ in QuickNote.shared.updateHotKey() }
        .onChange(of: floatOnTop) { _, on in
            for window in NSApp.windows where window.canBecomeMain {
                window.level = on ? .floating : .normal
            }
        }
    }

    // MARK: разделы слева

    private var nav: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Настройки")
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.45)
                .padding(.horizontal, 10)
                .padding(.top, 22)
                .padding(.bottom, 10)
            ForEach(Section.allCases) { item in
                NavRow(title: item.name, symbol: item.symbol, isOn: item == section) { sectionRaw = item.rawValue }
            }
            Spacer()
            Text("Заметочки · всё хранится на этом Mac")
                .font(.system(size: 10.5))
                .opacity(0.35)
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .frame(width: 190)
        .background(Color.black.opacity(0.12))
    }

    // MARK: содержимое

    @ViewBuilder
    private var content: some View {
        switch section {
        case .look:
            SettingsGroup(title: "Интерфейс", note: "Кнопки, список и панели - по-разному; заметки и стили общие.") {
                HStack(spacing: 10) {
                    ForEach(UILayout.allCases, id: \.self) { option in
                        LayoutChoice(option: option, isOn: layout == option.rawValue) {
                            withAnimation(.smooth(duration: 0.3)) { layout = option.rawValue }
                        }
                    }
                }
            }
            SettingsGroup(title: "Окно") {
                Card {
                    SettingToggle(title: "Поверх всех окон", detail: "Заметки не прячутся за другими окнами", isOn: $floatOnTop)
                    CardDivider()
                    SettingToggle(title: "Счётчик слов", detail: "Слова и время чтения в правом нижнем углу. Нажми на него - режим фокуса", isOn: $showStats)
                }
            }
            SettingsGroup(title: "Быстрая заметка", note: "Окошко поверх любой программы. Enter - и мысль уже в заметке «Входящие».") {
                Card {
                    SettingToggle(title: "\(QuickNote.shortcut) из любой программы", detail: "Работает, даже когда Заметочки в фоне", isOn: $quickNote)
                }
            }
            SettingsGroup(title: "Стиль страниц", note: "Шрифт, фон и цвета меняются в «Аа» сверху справа. Там же - стиль по умолчанию и «ко всем заметкам».") { EmptyView() }
        case .typing:
            SettingsGroup(title: "Размер текста") {
                HStack(spacing: 8) {
                    ForEach(Self.sizes, id: \.scale) { size in
                        SizeChoice(name: size.name, scale: size.scale, isOn: abs(textScale - size.scale) < 0.01) {
                            textScale = size.scale
                        }
                    }
                }
            }
            SettingsGroup(title: "Печать") {
                Card {
                    SettingToggle(title: "Звук печати", detail: "Мягкий щелчок на каждую клавишу", isOn: $typingSound)
                    CardDivider()
                    SettingToggle(title: "Заглавные буквы сами", detail: "В начале строки и после точки", isOn: $autoCapitalize)
                    CardDivider()
                    SettingToggle(title: "Т9", detail: "Исправляет опечатки и подсказывает конец слова - Tab, чтобы принять", isOn: $t9)
                    CardDivider()
                    SettingToggle(title: "Проверка орфографии", detail: "Подчёркивать слова с ошибками", isOn: $spellCheck)
                    CardDivider()
                    SettingToggle(title: "Тире и кавычки", detail: "«--» становится «—», кавычки - типографскими", isOn: $smartPunctuation)
                }
            }
            SettingsGroup(title: "Напоминания", note: "Допиши к задаче время - в этот момент придёт уведомление. Отметил задачу - напоминание снимается.") {
                Card {
                    KeyRow(key: "@завтра 10:00", title: "Завтра в 10 утра")
                    CardDivider()
                    KeyRow(key: "@18:30", title: "Сегодня (или завтра, если уже поздно)")
                    CardDivider()
                    KeyRow(key: "@пт", title: "В ближайшую пятницу в 9:00")
                    CardDivider()
                    KeyRow(key: "@15.10 9:00", title: "В конкретный день")
                }
            }
        case .voice:
            SettingsGroup(title: "Движок") {
                Card {
                    HStack(spacing: 10) {
                        Image(systemName: FlowBackend.missing() == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .opacity(0.85)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(FlowBackend.missing() == nil ? "Готов к работе" : "Не найден")
                                .font(.system(size: 13, weight: .medium))
                            Text(FlowBackend.missing() ?? "FlowLocal на этом Mac, без интернета")
                                .font(.system(size: 11.5))
                                .opacity(0.5)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
            }
            SettingsGroup(title: "Как пользоваться") {
                Card {
                    KeyRow(key: "⇧⌘D", title: "Начать и закончить")
                    CardDivider()
                    KeyRow(key: "Esc", title: "Отменить")
                    CardDivider()
                    KeyRow(key: "🎙", title: "Или кнопка микрофона сверху")
                    CardDivider()
                    KeyRow(key: "⌥⇧⌘D", title: "Голосовая заметка: запись с расшифровкой")
                }
            }
        case .data:
            if let store = AppDelegate.store {
                HStack(spacing: 10) {
                    Stat(value: "\(store.notes.count)", label: Self.plural(store.notes.count, "заметка", "заметки", "заметок"))
                    Stat(value: "\(Self.words(store))", label: Self.plural(Self.words(store), "слово", "слова", "слов"))
                }
                SettingsGroup(title: "Файлы", note: "Перед тем как заметка сильно уменьшится, её прошлая версия кладётся в резервные копии.") {
                    Card {
                        ActionRow(title: "Открыть папку заметок", symbol: "folder") { NSWorkspace.shared.open(store.folder) }
                        CardDivider()
                        ActionRow(title: "Резервные копии", symbol: "clock.arrow.circlepath") {
                            let backups = store.folder.appendingPathComponent("Backups", isDirectory: true)
                            try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(backups)
                        }
                        CardDivider()
                        ActionRow(title: "Сохранить все заметки в Markdown…", symbol: "square.and.arrow.up") {
                            if let count = Transfer.exportAll(store) { store.say("Сохранено заметок: \(count)") }
                        }
                    }
                }
            }
        case .keys:
            Card {
                ForEach(Array(Self.keys.enumerated()), id: \.offset) { index, item in
                    if index > 0 { CardDivider() }
                    KeyRow(key: item.0, title: item.1)
                }
            }
        }
    }

    private static let keys: [(String, String)] = [
        ("⌘N", "Новая заметка"),
        ("/", "Меню блоков"),
        ("⌘B  ⌘I  ⌘U", "Жирный, курсив, подчёркнутый"),
        ("⇧⌘X", "Зачёркнутый"),
        ("⇧⌘M", "Маркер"),
        ("⌥⌘1  2  3", "Заголовки"),
        ("⇧⌘7  ⇧⌘9", "Список, нумерованный"),
        ("⇧⌘L", "Чеклист"),
        ("⌥⌘P", "Страница внутри"),
        ("⇧⌘D", "Голосовой ввод"),
        ("⌥⇧⌘D", "Голосовая заметка"),
        ("⌃⌥N", "Быстрая заметка из любой программы"),
        ("⇧⌘F", "Режим фокуса"),
        ("⌥⌘K", "Канбан-доска"),
        ("⌘\\", "Список заметок"),
        ("⌥⌘↑  ⌥⌘↓", "Предыдущая, следующая"),
        ("⇧⌘C", "Скопировать заметку"),
        ("⇧⌘⌫", "Удалить заметку"),
    ]

    private static func words(_ store: Store) -> Int {
        store.notes.reduce(0) { sum, note in sum + note.doc.text.split { $0.isWhitespace || $0.isNewline }.count }
    }

    private static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = n % 100, b = n % 10
        if (11...14).contains(a) { return many }
        if b == 1 { return one }
        if (2...4).contains(b) { return few }
        return many
    }
}

// MARK: - детали настроек

/// Раздел: заголовок, содержимое и, если есть, пояснение мелко под ним.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(title.uppercased())
            content
            if let note {
                Text(note).font(.system(size: 11.5)).opacity(0.45).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Подложка для строк настроек, как в Системных настройках.
private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.07)))
    }
}

private struct CardDivider: View {
    var body: some View { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
}

private struct NavRow: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .opacity(isOn ? 1 : 0.6)
                Text(title).font(.system(size: 13, weight: isOn ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(isOn ? 0.13 : hover ? 0.06 : 0)))
            .opacity(isOn || hover ? 1 : 0.8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct KeyRow: View {
    let key: String
    let title: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13)).opacity(0.85)
            Spacer()
            Text(key)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.09)))
        }
        .frame(height: 38)
    }
}

private struct ActionRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12.5, weight: .medium)).frame(width: 18).opacity(0.75)
                Text(title).font(.system(size: 13))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).opacity(hover ? 0.6 : 0.3)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 12)).opacity(0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.07)))
    }
}

private struct SizeChoice: View {
    let name: String
    let scale: Double
    let isOn: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("Аа").font(.system(size: 10 + 8 * scale, weight: .semibold))
                    .frame(height: 26)
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1).opacity(isOn ? 1 : 0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(isOn ? 0.14 : hover ? 0.09 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(isOn ? 0.55 : 0.07), lineWidth: isOn ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Размер текста: " + name)
    }
}

private struct LayoutChoice: View {
    let option: UILayout
    let isOn: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                LayoutSketch(option: option)
                    .frame(height: 50)
                Text(option.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(isOn ? 0.16 : hover ? 0.09 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(isOn ? 0.6 : 0.08), lineWidth: isOn ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Маленький набросок варианта: где список, где панель, где полоска.
private struct LayoutSketch: View {
    let option: UILayout

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: AppDelegate.store?.currentStyle.baseColor ?? Style.background))
                switch option {
                case .quiet:
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.14)).frame(width: w * 0.3, height: h - 6).offset(x: 3, y: 3)
                    lines(x: w * 0.42, y: 10, width: w * 0.48)
                case .craft:
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.14)).frame(width: w * 0.24, height: h - 6).offset(x: 3, y: 3)
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.14)).frame(width: w * 0.24, height: h - 6).offset(x: w * 0.76 - 3, y: 3)
                    lines(x: w * 0.32, y: 10, width: w * 0.38)
                case .notebook:
                    lines(x: w * 0.25, y: 8, width: w * 0.5)
                    Capsule().fill(.white.opacity(0.3)).frame(width: w * 0.5, height: 6).offset(x: w * 0.25, y: h - 11)
                }
            }
        }
    }

    private func lines(x: CGFloat, y: CGFloat, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(.white.opacity(0.7)).frame(width: width * 0.7, height: 3)
            Capsule().fill(.white.opacity(0.35)).frame(width: width, height: 2)
            Capsule().fill(.white.opacity(0.35)).frame(width: width * 0.85, height: 2)
            Capsule().fill(.white.opacity(0.35)).frame(width: width * 0.6, height: 2)
        }
        .offset(x: x, y: y)
    }
}

private struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11.5)).opacity(0.45)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// Шестерёнка в левом нижнем углу окна. Открывает настройки окном по центру - ничего не уезжает за край.
struct SettingsButton: View {
    @Binding var open: Bool

    var body: some View {
        Button { open.toggle() } label: { BarIcon(symbol: "gearshape", isOn: open) }
            .buttonStyle(.plain)
            .accessibilityLabel("Настройки")
            .help("Настройки (⌘,)")
    }
}

