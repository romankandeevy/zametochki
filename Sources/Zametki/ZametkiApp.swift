import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@main
struct ZametkiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: Store
    @AppStorage("sidebarShown") private var showList = true
    @AppStorage("inspectorShown") private var showInspector = false
    @AppStorage("typingSound") private var typingSound = true
    @AppStorage("autoCapitalize") private var autoCapitalize = true
    @AppStorage("focusMode") private var focusMode = false

    init() {
        Style.registerFont()
        let store = Store()
        _store = State(initialValue: store)
        AppDelegate.store = store
    }

    var body: some Scene {
        Window("Заметочки", id: "main") {
            RootView(store: store, showList: $showList, showInspector: $showInspector)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // ⌘, открывает те же настройки внутри окна, что и шестерёнка.
            CommandGroup(replacing: .appSettings) {
                Button("Настройки…") { NotificationCenter.default.post(name: .openSettings, object: nil) }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                NoteFileCommands(store: store, shortcuts: true)
            }
            CommandGroup(after: .textEditing) {
                Toggle("Звук печати", isOn: $typingSound)
                Toggle("Заглавные буквы автоматически", isOn: $autoCapitalize)
                Divider()
                Button("Голосовой ввод") { Dictation.shared.toggle() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Голосовая заметка") { Editor.Coordinator.active?.insert(.audio) }
                    .keyboardShortcut("d", modifiers: [.command, .shift, .option])
            }
            CommandMenu("Формат") {
                format("Заголовок", .block(.title), "1", [.command, .option])
                format("Подзаголовок", .block(.heading), "2", [.command, .option])
                format("Маленький заголовок", .block(.subheading), "3", [.command, .option])
                Divider()
                format("Жирный", .bold, "b", .command)
                format("Курсив", .italic, "i", .command)
                format("Подчёркнутый", .underline, "u", .command)
                format("Зачёркнутый", .strike, "x", [.command, .shift])
                format("Маркер", .highlight, "m", [.command, .shift])
                Divider()
                format("Список", .block(.bullet), "7", [.command, .shift])
                format("Нумерованный список", .block(.numbered), "9", [.command, .shift])
                format("Чеклист", .block(.todo), "l", [.command, .shift])
                format("Цитата", .block(.quote), "'", [.command, .shift])
                format("Страница", .block(.page), "p", [.command, .option])
                Divider()
                Button("Доска") { Editor.Coordinator.active?.insert(.board) }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                Menu("Шаблон") {
                    ForEach(Template.all) { template in
                        Button(template.name) {
                            guard let editor = Editor.Coordinator.active, let text = editor.textView else { return }
                            editor.insertTemplate(template, at: text.selectedRange().location)
                        }
                    }
                }
            }
            CommandGroup(after: .sidebar) {
                Button(showInspector ? "Скрыть панель справа" : "Показать панель справа") {
                    withAnimation(.smooth(duration: 0.3)) { showInspector.toggle() }
                }
                .keyboardShortcut("\\", modifiers: [.command, .option])
                Button(showList ? "Скрыть список" : "Показать список") {
                    withAnimation(.snappy(duration: 0.25)) { showList.toggle() }
                }
                .keyboardShortcut("\\")
                Toggle("Режим фокуса", isOn: Binding(get: { focusMode }, set: { on in
                    focusMode = on
                    Editor.Coordinator.active?.applyFocus()
                }))
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Поиск по заметкам") { NotificationCenter.default.post(name: .openSearch, object: nil) }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Ссылка на заметку…") { Editor.Coordinator.active?.beginLink() }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Заметка за сегодня") { store.openToday() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Button("Быстрая заметка") { QuickNote.shared.show() }
                    .keyboardShortcut("n", modifiers: [.control, .option])
                Button("Предыдущая") { store.step(-1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Следующая") { store.step(1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }
        }
    }
}

/// Пункт меню «Формат»: сочетания как в Apple Notes.
private func format(_ title: String, _ command: Editor.Command,
                    _ key: KeyEquivalent, _ modifiers: EventModifiers) -> some View {
    Button(title) { Editor.Coordinator.active?.run(command) }.keyboardShortcut(key, modifiers: modifiers)
}

extension Notification.Name {
    static let openSettings = Notification.Name("zametki.openSettings")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var store: Store?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIcon.update()
        UNUserNotificationCenter.current().delegate = self
        QuickNote.shared.updateHotKey()
    }

    /// Напоминание видно, даже когда Заметочки открыты.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Нажал на напоминание - открывается заметка с этой задачей.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["note"] as? String
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let id { Self.store?.select(id) }
            completionHandler()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        Self.store?.flush()
        Dictation.shared.shutdown()
    }
    private var resignedAt: Date?
    func applicationDidResignActive(_ notification: Notification) {
        Self.store?.flush()
        resignedAt = Date()
    }
    /// Вернулся не сразу - открытые закрытые заметки закрываются снова.
    func applicationDidBecomeActive(_ notification: Notification) {
        if let resignedAt, Date().timeIntervalSince(resignedAt) > 60 { Self.store?.relockOthers(than: nil) }
        resignedAt = nil
    }
}

struct RootView: View {
    let store: Store
    @Binding var showList: Bool
    @Binding var showInspector: Bool
    @AppStorage(UILayout.key) private var layout = UILayout.quiet.rawValue
    @State private var settingsOpen = false
    @State private var searchOpen = false
    @State private var linkOpen = false
    @State private var transfer: TransferMode?

    var body: some View {
        Group {
            switch UILayout(rawValue: layout) ?? .quiet {
            case .quiet: QuietLayout(store: store, showList: $showList)
            case .craft: CraftLayout(store: store, showList: $showList, showInspector: $showInspector)
            case .notebook: NotebookLayout(store: store, showList: $showList)
            }
        }
        .background(PageBackground(style: store.style(of: store.selectedID)).ignoresSafeArea())
        // Короткие сообщения («глубже нельзя») - плашкой сверху по центру.
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(Color(nsColor: store.currentStyle.panelColor)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    .padding(.top, 62)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(.smooth(duration: 0.25), value: store.toast)
        // Настройки - в левом нижнем углу при любом варианте.
        .overlay(alignment: .bottomLeading) {
            SettingsButton(open: $settingsOpen).padding(.leading, 12).padding(.bottom, 10)
        }
        // Счётчик слов и режим фокуса - в правом нижнем углу, левее панели справа, если она открыта.
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                BacklinksBadge(store: store)
                StatsBadge()
            }
                .padding(.trailing, layout == UILayout.craft.rawValue && showInspector ? 276 + 12 : 14)
                .padding(.bottom, layout == UILayout.notebook.rawValue ? 24 : 10)
        }
        .sheet(isPresented: $settingsOpen) {
            SettingsView { settingsOpen = false }
                .frame(width: 640, height: 450)
                .presentationBackground(Color(nsColor: store.currentStyle.panelColor))
                .preferredColorScheme(.dark)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            settingsOpen.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSearch)) { _ in
            withAnimation(.smooth(duration: 0.18)) { searchOpen.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTransfer)) { note in
            transfer = note.object as? TransferMode
        }
        .sheet(item: $transfer) { mode in
            TransferSheet(store: store, mode: mode) { transfer = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pickLink)) { _ in
            withAnimation(.smooth(duration: 0.18)) { linkOpen = true }
        }
        // Окно выбора заметки для ссылки: то же окно поиска, но выбор вставляет ссылку.
        .overlay {
            if linkOpen {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.35).ignoresSafeArea()
                        .onTapGesture { withAnimation(.smooth(duration: 0.18)) { linkOpen = false } }
                    SearchPalette(store: store, pick: { note in
                        Editor.Coordinator.active?.insertLink(to: note.id, title: note.title)
                    }) { withAnimation(.smooth(duration: 0.18)) { linkOpen = false } }
                    .padding(.top, 90)
                }
                .transition(.opacity)
            }
        }
        // Окно поиска ⌘K: тёмная вуаль, закрывается нажатием мимо или Esc.
        .overlay {
            if searchOpen {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.35).ignoresSafeArea()
                        .onTapGesture { withAnimation(.smooth(duration: 0.18)) { searchOpen = false } }
                    SearchPalette(store: store) { withAnimation(.smooth(duration: 0.18)) { searchOpen = false } }
                        .padding(.top, 90)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 420, minHeight: 280)
        .background(WindowTweaks())
    }
}

/// Маленькая иконка в верхней полосе: тихая, ярче при наведении.
struct BarIcon: View {
    let symbol: String
    var isOn = false
    @State private var hover = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(hover || isOn ? 0.85 : 0.45))
            .frame(width: 26, height: 22)
            .contentShape(Rectangle())
            .onHover { hover in withAnimation(.easeOut(duration: 0.15)) { self.hover = hover } }
    }
}

/// Крошки над вложенной страницей: «Покупки › Продукты». Нажал на родителя - вернулся к нему.
struct Breadcrumbs: View {
    let store: Store
    /// Показывать и одну заметку без родителей (варианты B и C - название в полосе сверху).
    var showSingle = false
    /// По центру полосы (вариант C), а не от левого края.
    var centered = false

    var body: some View {
        let path = store.path(to: store.selectedID)
        if path.count > 1 || (showSingle && !path.isEmpty) {
            // Длинный путь сворачивается: первая › … › две последние - чтобы крошки не налезали на кнопки.
            let shown: [Note?] = path.count > 4 ? [path[0], nil] + path.suffix(2).map { $0 } : path.map { $0 }
            HStack(spacing: 5) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, note in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    if let note {
                        Crumb(title: note.title, current: note.id == path.last?.id) { store.select(note.id) }
                    } else {
                        Text("…").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .frame(maxWidth: 460, alignment: centered ? .center : .leading)
            .clipped()
            .transition(.opacity)
        }
    }

    private struct Crumb: View {
        let title: String
        let current: Bool
        let action: () -> Void
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 140)
                    .foregroundStyle(.white.opacity(current ? 0.75 : hover ? 0.8 : 0.45))
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .disabled(current)
            .onHover { hover = $0 }
        }
    }
}

/// Микрофон: нажал - говоришь, слова сразу в тексте; нажал ещё раз - встаёт готовый текст. Esc - отмена.
struct MicButton: View {
    /// Крупный белый круг - для полоски варианта C.
    var prominent = false
    private var dictation = Dictation.shared
    @State private var pulse = false

    init(prominent: Bool = false) { self.prominent = prominent }

    var body: some View {
        Button { dictation.toggle() } label: {
            ZStack {
                if prominent {
                    Circle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                        .scaleEffect(dictation.state == .listening && pulse ? 1.08 : 1)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                        .onAppear { pulse = dictation.state == .listening }
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(nsColor: Style.background))
                } else if dictation.state == .listening {
                    Circle()
                        .fill(.white.opacity(0.16))
                        .frame(width: 22, height: 22)
                        .scaleEffect(pulse ? 1.15 : 0.85)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                        .onAppear { pulse = true }
                        .onDisappear { pulse = false }
                }
                if !prominent {
                    BarIcon(symbol: symbol, isOn: dictation.isActive)
                        .opacity(dictation.state == .finishing || dictation.warming ? 0.5 : 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Голосовой ввод")
        .help(help)
    }

    private var symbol: String {
        switch dictation.state {
        case .listening: "mic.fill"
        case .finishing: "ellipsis"
        case .failed: "mic.slash"
        case .idle: "mic"
        }
    }

    private var help: String {
        switch dictation.state {
        case .listening: dictation.warming ? "Загружаю распознавание… можно уже говорить" : "Говорите. Нажмите ещё раз - вставить, Esc - отмена"
        case .finishing: "Расставляю знаки…"
        case .failed(let message): message
        case .idle: "Голосовой ввод (⇧⌘D)"
        }
    }
}

/// «⋯» справа сверху: всё, что делается с заметкой как с файлом.
struct NoteMenu: View {
    let store: Store

    var body: some View {
        Menu {
            NoteFileCommands(store: store)
        } label: {
            BarIcon(symbol: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Действия с заметкой")
        .help("Копировать, экспорт, импорт")
    }
}

/// Одни и те же пункты в «⋯» и в меню «Файл».
struct NoteFileCommands: View {
    let store: Store
    var shortcuts = false

    var body: some View {
        Button("Новая заметка") { store.create() }
            .keyboardShortcut(shortcuts ? KeyboardShortcut("n", modifiers: .command) : nil)
        Divider()
        Button("Скопировать заметку") { if let note = store.selected { Transfer.copy(note.doc) } }
            .keyboardShortcut(shortcuts ? KeyboardShortcut("c", modifiers: [.command, .shift]) : nil)
        Menu("Новая из шаблона") {
            ForEach(Template.all) { template in
                Button(template.name) { store.create(doc: template.doc()) }
            }
        }
        Divider()
        Menu("Экспорт") {
            ForEach(Transfer.Format.allCases, id: \.self) { format in
                Button(format.name) { if let note = store.selected { Transfer.export(note, as: format) } }
            }
            Divider()
            Button("PDF - как выглядит страница") { if let note = store.selected { PageExport.save(note, as: .pdf) } }
            Button("Картинка PNG") { if let note = store.selected { PageExport.save(note, as: .png) } }
        }
        Button("Скопировать как картинку") {
            if let note = store.selected, PageExport.copyImage(note) { store.say("Картинка в буфере - вставляй куда угодно") }
        }
        Menu("iPhone") {
            Button("Отправить на iPhone…") { NotificationCenter.default.post(name: .openTransfer, object: TransferMode.send) }
            Button("Принять с iPhone…") { NotificationCenter.default.post(name: .openTransfer, object: TransferMode.receive) }
        }
        Button("Импорт…") { store.add(Transfer.pickFiles()) }
            .keyboardShortcut(shortcuts ? KeyboardShortcut("o", modifiers: .command) : nil)
        Divider()
        if let note = store.selected, note.doc.locked != true {
            Button("Закрыть заметку (Touch ID)") { store.lock(note.id) }
        } else if let note = store.selected, note.unlocked {
            Button("Закрыть заметку") { store.lock(note.id) }
            Button("Снять защиту") { store.removeLock(note.id) }
        }
        Button("Показать в Finder") {
            if let id = store.selectedID { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(id)]) }
        }
        Button("Удалить заметку") { if let id = store.selectedID { store.delete(id) } }
            // Не ⌘⌫: в тексте это «стереть до начала строки», и заметка улетала бы целиком.
            .keyboardShortcut(shortcuts ? KeyboardShortcut(.delete, modifiers: [.command, .shift]) : nil)
    }
}

/// Список слева - дерево страниц, как в Craft. Страницы перетаскиваются: на строку - внутрь неё,
/// на верхний или нижний край строки - перед ней или после.
struct NoteList: View {
    /// quiet - вариант A: название почерком, под ним дата и начало текста; craft - вариант B: дерево со значками.
    enum Variant { case quiet, craft }

    let store: Store
    var variant: Variant = .craft
    var query = ""
    var topPadding: CGFloat = 24
    @Namespace private var selection
    @State private var dragged: String?
    @State private var target: (id: String, zone: DropZone)?

    enum DropZone { case before, inside, after }

    static let noteType = UTType(exportedAs: "com.romankandeevy.zametki.note", conformingTo: .data)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.note.id) { row in
                    rowView(row.note, depth: row.depth)
                }
                // Пустое место под списком: бросил сюда - страница уходит наверх, в конец.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .contentShape(Rectangle())
                    .onDrop(of: [NoteList.noteType], delegate: TailDrop(store: store, dragged: $dragged))
            }
            // Новые, удалённые и переехавшие заметки двигаются плавно.
            .animation(.smooth(duration: 0.3), value: rows.map(\.note.id))
            .animation(.smooth(duration: 0.28), value: store.selectedID)
            .padding(.leading, variant == .quiet ? 8 : 10)
            .padding(.trailing, variant == .quiet ? 8 : 12)
            .padding(.top, topPadding)
        }
    }

    /// Поиск показывает подходящие заметки плоским списком, без дерева.
    private var rows: [(note: Note, depth: Int)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.rows }
        return store.notes.filter { $0.text.lowercased().contains(q) }.map { ($0, 0) }
    }

    private func rowHeight(_ depth: Int) -> CGFloat { variant == .quiet && depth == 0 ? 52 : 30 }

    /// «Сейчас», «Сегодня, 14:05», «Вчера», «2 окт».
    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if Date().timeIntervalSince(date) < 60 { return "Сейчас" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        if calendar.isDateInToday(date) { formatter.dateFormat = "HH:mm"; return "Сегодня, " + formatter.string(from: date) }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func label(_ note: Note, depth: Int, selected: Bool) -> some View {
        switch variant {
        case .quiet:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if store.isPinned(note.id) { Image(systemName: "pin.fill").font(.system(size: 8.5)).opacity(0.45) }
                    NoteLabel(text: note.title, alpha: selected ? 1 : depth == 0 ? 0.88 : 0.62, style: store.style(of: note.id))
                }
                if depth == 0 {
                    let preview = note.preview.isEmpty ? "" : " · " + note.preview
                    Text(Self.when(note.modified) + preview)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: store.currentStyle.text.color).opacity(selected ? 0.6 : 0.45))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .craft:
            HStack(spacing: 7) {
                if !store.hasChildren(note.id) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(note.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color(nsColor: store.currentStyle.text.color).opacity(selected ? 1 : 0.78))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rowView(_ note: Note, depth: Int) -> some View {
        let selected = note.id == store.selectedID
        let isTarget = target?.id == note.id
        return HStack(spacing: 2) {
            // Стрелка раскрытия - только у страниц с вложенными страницами.
            Group {
                if store.hasChildren(note.id) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .rotationEffect(.degrees(store.expanded.contains(note.id) ? 90 : 0))
                        .frame(width: 16, height: 22)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.smooth(duration: 0.25)) {
                                if store.expanded.contains(note.id) { store.expanded.remove(note.id) } else { store.expanded.insert(note.id) }
                            }
                        }
                } else {
                    Color.clear.frame(width: 16, height: 22)
                }
            }
            label(note, depth: depth, selected: selected)
        }
        .padding(.leading, CGFloat(min(depth, Store.maxDepth)) * 14)
        .padding(.vertical, variant == .quiet && depth == 0 ? 7 : 4)
        .padding(.trailing, 8)
        .frame(minHeight: rowHeight(depth))
        .background {
            ZStack {
                // Подсветка открытой заметки переезжает от строки к строке.
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(variant == .quiet ? 0.11 : 0.12))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
                if isTarget, target?.zone == .inside {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
        .overlay(alignment: target?.zone == .before ? .top : .bottom) {
            // Куда встанет страница - линия над или под строкой.
            if isTarget, target?.zone != .inside {
                Capsule().fill(.white.opacity(0.85)).frame(height: 2.5)
                    .padding(.leading, CGFloat(depth) * 14 + 16)
                    .offset(y: target?.zone == .before ? -1.5 : 1.5)
            }
        }
        .opacity(dragged == note.id ? 0.4 : 1)
        .contentShape(Rectangle())
        .transition(.opacity.combined(with: .offset(y: -6)))
        .onTapGesture { store.select(note.id) }
        .onDrag {
            dragged = note.id
            // Свой тип, а не текст: иначе список принимал бы и текст, вытащенный из заметки.
            let provider = NSItemProvider()
            let id = note.id
            provider.registerDataRepresentation(forTypeIdentifier: NoteList.noteType.identifier, visibility: .ownProcess) { done in
                done(Data(id.utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(of: [NoteList.noteType], delegate: RowDrop(note: note, store: store, height: rowHeight(depth), dragged: $dragged, target: $target))
        .contextMenu {
            if note.parent == nil {
                Button(store.isPinned(note.id) ? "Открепить" : "Закрепить") { store.togglePin(note.id) }
            }
            if note.doc.locked == true {
                if note.unlocked { Button("Снять защиту") { store.removeLock(note.id) } }
            } else {
                Button("Закрыть (Touch ID)") { store.lock(note.id) }
            }
            Button("Новая страница внутри") {
                if let page = store.createPage(in: note.id, title: "") {
                    store.edit(note.id) { Formatting.appendCard(page, to: $0) }
                    store.select(page)
                }
            }
            Divider()
            Button("Удалить") { store.delete(note.id) }
        }
    }

    private struct RowDrop: DropDelegate {
        let note: Note
        let store: Store
        let height: CGFloat
        @Binding var dragged: String?
        @Binding var target: (id: String, zone: DropZone)?

        private func zone(_ info: DropInfo) -> DropZone {
            // Верхняя и нижняя четверть строки - между строками, середина - внутрь.
            let y = info.location.y
            if y < height * 0.27 { return .before }
            if y > height * 0.73 { return .after }
            return .inside
        }

        private func allowed() -> Bool {
            guard let dragged, dragged != note.id else { return false }
            return !store.isDescendant(note.id, of: dragged)
        }

        func validateDrop(info: DropInfo) -> Bool { allowed() && info.hasItemsConforming(to: [NoteList.noteType]) }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            guard allowed() else { return DropProposal(operation: .forbidden) }
            let z = zone(info)
            if target?.id != note.id || target?.zone != z {
                withAnimation(.easeOut(duration: 0.12)) { target = (note.id, z) }
            }
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            if target?.id == note.id { withAnimation(.easeOut(duration: 0.12)) { target = nil } }
        }

        func performDrop(info: DropInfo) -> Bool {
            defer { target = nil; dragged = nil }
            guard let id = dragged, allowed() else { return false }
            withAnimation(.smooth(duration: 0.3)) {
                switch zone(info) {
                case .inside:
                    store.move(id, into: note.id)
                case .before:
                    store.move(id, into: note.parent, before: note.id)
                case .after:
                    let siblings = store.children(of: note.parent).filter { $0.id != id }
                    let next = siblings.firstIndex { $0.id == note.id }.flatMap { $0 + 1 < siblings.count ? siblings[$0 + 1].id : nil }
                    store.move(id, into: note.parent, before: next)
                }
            }
            return true
        }
    }

    private struct TailDrop: DropDelegate {
        let store: Store
        @Binding var dragged: String?

        func validateDrop(info: DropInfo) -> Bool { dragged != nil && info.hasItemsConforming(to: [NoteList.noteType]) }
        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
        func performDrop(info: DropInfo) -> Bool {
            defer { dragged = nil }
            guard let id = dragged else { return false }
            withAnimation(.smooth(duration: 0.3)) { store.move(id, into: nil) }
            return true
        }
    }
}

/// Окно целиком синее: без полосы заголовка, но со светофором и перетаскиванием за фон.
struct WindowTweaks: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            // Пустая панель инструментов делает полосу заголовка выше (52pt): светофор и кнопки
            // встают с воздухом сверху, а не впритык к краю окна.
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "main")
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = Style.background
            window.appearance = NSAppearance(named: .darkAqua)
            if UserDefaults.standard.bool(forKey: "floatOnTop") { window.level = .floating }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
