import AppKit
import SwiftUI

/// Три варианта интерфейса из мокапов. Сейчас включён A; выбор появится в настройках.
/// Редактор, хранилище, стиль и блоки у всех общие - отличается только «обвес» вокруг текста.
enum UILayout: String, CaseIterable {
    case quiet      // A · Тихий: список с датами, «+» слева от строки, стиль в «Аа»
    case craft      // B · Craft: дерево страниц, крошки, панель «Блоки | Стиль» справа
    case notebook   // C · Тетрадь: колонка по центру, плавающая полоска снизу с микрофоном

    static let key = "uiLayout"

    var name: String {
        switch self {
        case .quiet: "A · Тихий"
        case .craft: "B · Craft"
        case .notebook: "C · Тетрадь"
        }
    }
}

// MARK: - A · Тихий

struct QuietLayout: View {
    let store: Store
    @Binding var showList: Bool
    @State private var query = ""

    var body: some View {
        HStack(spacing: 0) {
            if showList {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 52) // под светофор и кнопки
                    SearchField(text: $query).padding(.horizontal, 12).padding(.bottom, 8)
                    NoteList(store: store, variant: .quiet, query: query, topPadding: 2)
                }
                .frame(width: 232)
                .background(Color.black.opacity(0.14))
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                Color.clear.frame(height: 52)
                Editor(store: store)
            }
        }
        // Кнопки там же, где были всегда: у светофора - список, новая заметка, микрофон; справа - стиль и «···».
        .overlay(alignment: .topLeading) {
            HStack(spacing: 2) {
                SidebarToggle(shown: $showList)
                Button { store.create() } label: { BarIcon(symbol: "plus") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Новая заметка")
                    .help("Новая заметка (⌘N)")
                MicButton()
                Breadcrumbs(store: store).padding(.leading, 8)
            }
            .padding(.leading, 84)
            .padding(.top, 15)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                FocusButton()
                StyleButton(store: store)
                NoteMenu(store: store)
            }
            .padding(.trailing, 12)
            .padding(.top, 15)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - B · Craft

struct CraftLayout: View {
    let store: Store
    @Binding var showList: Bool
    @Binding var showInspector: Bool

    var body: some View {
        HStack(spacing: 0) {
            if showList {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        SidebarToggle(shown: $showList)
                    }
                    .frame(height: 52)
                    .padding(.horizontal, 10)
                    HStack {
                        SectionTitle("ЗАМЕТКИ")
                        Spacer()
                        Button { store.create() } label: { BarIcon(symbol: "plus") }
                            .buttonStyle(.plain)
                            .help("Новая заметка (⌘N)")
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 8)
                    NoteList(store: store, variant: .craft, topPadding: 4)
                }
                .frame(width: 210)
                .background(Color.black.opacity(0.14))
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if !showList { SidebarToggle(shown: $showList).padding(.leading, 76) }
                    Breadcrumbs(store: store, showSingle: true)
                    Spacer()
                    FocusButton()
                    MicButton()
                    if !showInspector { InspectorToggle(shown: $showInspector) }
                    if !showInspector { NoteMenu(store: store) }
                }
                .frame(height: 52)
                .padding(.leading, 16)
                .padding(.trailing, 12)
                Editor(store: store)
            }
            if showInspector {
                Inspector(store: store)
                    .frame(width: 276)
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 2) {
                            InspectorToggle(shown: $showInspector)
                            NoteMenu(store: store)
                        }
                        .frame(height: 52)
                        .padding(.trailing, 12)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - C · Тетрадь

struct NotebookLayout: View {
    let store: Store
    @Binding var showList: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ZStack {
                    Breadcrumbs(store: store, showSingle: true, centered: true)
                    HStack(spacing: 2) {
                        SidebarToggle(shown: $showList).padding(.leading, 84)
                        Spacer()
                        NoteMenu(store: store).padding(.trailing, 12)
                    }
                }
                .frame(height: 52)
                Editor(store: store)
                    .padding(.bottom, 64) // место под плавающую полоску
            }
            NotebookToolbar(store: store)
                .padding(.bottom, 18)
        }
        // Список заметок - выезжающая шторка поверх текста.
        .overlay(alignment: .leading) {
            if showList {
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.25)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.smooth(duration: 0.3)) { showList = false } }
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            SidebarToggle(shown: $showList)
                        }
                        .frame(height: 52)
                        .padding(.horizontal, 10)
                        NoteList(store: store, variant: .quiet, topPadding: 2)
                        Button { store.create() } label: {
                            Label("Новая заметка", systemImage: "plus")
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.08)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .padding(.bottom, 32) // ниже - шестерёнка настроек, не налезаем на неё
                    }
                    .frame(width: 260)
                    .background(Color(nsColor: store.currentStyle.panelColor))
                    .shadow(color: .black.opacity(0.35), radius: 20)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
    }
}

/// Плавающая полоска варианта C: стиль, частые блоки, остальные блоки и большой микрофон.
struct NotebookToolbar: View {
    let store: Store
    @State private var styleOpen = false

    var body: some View {
        HStack(spacing: 3) {
            Button { styleOpen.toggle() } label: {
                Text("Аа")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 40, height: 36)
                    .background(Capsule().fill(.white.opacity(styleOpen ? 0.24 : 0.14)))
            }
            .buttonStyle(.plain)
            .help("Стиль страницы")
            .popover(isPresented: $styleOpen, arrowEdge: .top) {
                ScrollView { StylePanel(store: store).padding(16) }
                    .frame(width: 300, height: 460)
                    .foregroundStyle(.white)
                    .background(Color(nsColor: store.currentStyle.panelColor))
            }
            divider
            ForEach([Block.title, .todo, .image, .table, .page], id: \.self) { block in
                ToolbarBlock(block: block)
            }
            Button { Editor.Coordinator.active?.openPlusAtCaret() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 36)
                    .opacity(0.75)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Все блоки")
            FocusButton().frame(width: 38, height: 36)
            divider
            MicButton(prominent: true)
        }
        .padding(.horizontal, 7)
        .frame(height: 50)
        .background(
            Capsule().fill(Color(nsColor: store.currentStyle.panelColor))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 22).padding(.horizontal, 4)
    }

    private struct ToolbarBlock: View {
        let block: Block
        @State private var hover = false

        var body: some View {
            Button { Editor.Coordinator.active?.insert(block) } label: {
                Group {
                    if block == .title {
                        Text("H").font(.system(size: 14, weight: .bold))
                    } else {
                        Image(systemName: block.symbol).font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(width: 38, height: 36)
                .background(Capsule().fill(.white.opacity(hover ? 0.12 : 0)))
                .opacity(hover ? 1 : 0.75)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help(block.name)
        }
    }
}

// MARK: - общие кнопки

struct SidebarToggle: View {
    @Binding var shown: Bool

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { shown.toggle() }
        } label: { BarIcon(symbol: "sidebar.left", isOn: shown) }
            .buttonStyle(.plain)
            .accessibilityLabel("Список заметок")
            .help(shown ? "Спрятать список (⌘\\)" : "Показать список (⌘\\)")
    }
}

struct InspectorToggle: View {
    @Binding var shown: Bool

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { shown.toggle() }
        } label: { BarIcon(symbol: "sidebar.right", isOn: shown) }
            .buttonStyle(.plain)
            .accessibilityLabel("Панель справа")
            .help("Блоки и стиль страницы (⌥⌘\\)")
    }
}

/// Режим фокуса: всё, кроме строки с курсором, приглушено. То же, что ⇧⌘F и нажатие на счётчик слов.
struct FocusButton: View {
    @AppStorage("focusMode") private var focus = false

    var body: some View {
        Button {
            focus.toggle()
            Editor.Coordinator.active?.applyFocus()
        } label: { BarIcon(symbol: "scope", isOn: focus) }
            .buttonStyle(.plain)
            .accessibilityLabel("Режим фокуса")
            .help(focus ? "Режим фокуса включён - нажми, чтобы выключить (⇧⌘F)" : "Режим фокуса: видно только строку, которую пишешь (⇧⌘F)")
    }
}

/// «Аа» варианта A: стиль страницы во всплывающей карточке.
struct StyleButton: View {
    let store: Store
    @State private var open = false
    @State private var hover = false

    var body: some View {
        Button { open.toggle() } label: {
            Text("Аа")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(open || hover ? 0.85 : 0.5))
                .frame(width: 30, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Стиль страницы")
        .help("Стиль страницы")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView { StylePanel(store: store).padding(16) }
                .frame(width: 300, height: 430)
                .foregroundStyle(.white)
                .background(Color(nsColor: store.currentStyle.panelColor))
        }
    }
}

/// Поиск по заметкам: по названию и тексту.
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11.5, weight: .semibold)).opacity(0.5)
            TextField("Поиск", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").opacity(0.5) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.07)))
    }
}
