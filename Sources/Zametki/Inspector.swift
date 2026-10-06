import AppKit
import SwiftUI

/// Правая панель, как у Craft: «Вставить» - блоки, которые тащишь в текст (или жмёшь - встанут под курсор),
/// и «Стиль» - оформление всей страницы.
struct Inspector: View {
    let store: Store
    @AppStorage("inspectorTab") private var tab = "insert"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                tabButton("insert", "Блоки", "square.stack")
                tabButton("style", "Стиль", "paintbrush")
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.2)))
            .padding(.leading, 12)
            .padding(.trailing, 70) // место под кнопки окна справа сверху
            .frame(height: 52)
            .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if tab == "insert" { InsertTab() } else { StylePanel(store: store) }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1) }
    }

    private func tabButton(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) { tab = id }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(tab == id ? 0.16 : 0)))
            .opacity(tab == id ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - «Блоки»

/// Короткое пояснение к блоку - в списке панели и в меню «+».
extension Block {
    var hint: String {
        switch self {
        case .text: "Обычный текст"
        case .title: "Большой, для раздела"
        case .heading: "Поменьше"
        case .subheading: "Совсем небольшой"
        case .bullet: "Пункты с точками"
        case .numbered: "Пункты по порядку"
        case .todo, .done: "Задачи с галочками"
        case .toggle, .toggleItem: "Прячет текст под стрелку"
        case .quote: "Выделенная мысль"
        case .code: "Моноширинный, на подложке"
        case .image: "С диска или перетащи файл"
        case .file: "Любой файл, лежит рядом"
        case .table: "Строки и столбцы"
        case .divider: "Линия, точки или лента"
        case .page: "Карточка вложенной страницы"
        case .board: "Канбан: колонки и карточки"
        case .whiteboard: "Рисунки, фигуры и стикеры"
        case .audio: "Запись с расшифровкой"
        case .template: "Встреча, план недели, идея…"
        }
    }

    /// Что напечатать в начале строки, чтобы получить этот блок.
    var shortcut: String? {
        switch self {
        case .title: "#"
        case .heading: "##"
        case .subheading: "###"
        case .bullet: "-"
        case .numbered: "1."
        case .todo: "[]"
        case .toggle: "+"
        case .quote: ">"
        case .code: "```"
        case .divider: "---"
        default: nil
        }
    }

    static let basic: [Block] = [.text, .title, .heading, .subheading, .bullet, .numbered, .todo, .toggle, .quote, .code]
    static let objects: [Block] = [.image, .file, .table, .whiteboard, .board, .audio, .divider, .page, .template]
}

private struct InsertTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionTitle("ТЕКСТ").padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
            ForEach(Block.basic, id: \.self) { BlockRow(block: $0) }
            SectionTitle("ПРЕДМЕТЫ").padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
            ForEach(Block.objects, id: \.self) { BlockRow(block: $0) }
        }
    }
}

/// Строка блока: значок, название, пояснение и ручка ⠿. Тащи в текст или нажми - встанет под курсор.
private struct BlockRow: View {
    let block: Block
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            BlockIcon(block: block)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.name).font(.system(size: 13))
                Text(block.hint).font(.system(size: 11)).opacity(0.45)
            }
            Spacer(minLength: 4)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .opacity(hover ? 0.55 : 0.22)
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hover ? 0.09 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { Editor.Coordinator.active?.insert(block) }
        .onDrag {
            let provider = NSItemProvider()
            let raw = block.rawValue
            provider.registerDataRepresentation(forTypeIdentifier: NotesTextView.blockType.rawValue, visibility: .ownProcess) { done in
                done(Data(raw.utf8), nil)
                return nil
            }
            return provider
        } preview: {
            HStack(spacing: 8) {
                Image(systemName: block.symbol)
                Text(block.name)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: PageStyle.current.panelColor)))
        }
        .help(block.shortcut.map { "\(block.name) - или напечатай «\($0) » в начале строки" } ?? block.name)
    }
}

/// Значок блока в скруглённом квадратике - одинаковый в панели, меню «+» и меню «/».
struct BlockIcon: View {
    let block: Block

    var body: some View {
        Group {
            switch block {
            case .title: Text("H").font(.system(size: 13, weight: .bold))
            case .heading: Text("H2").font(.system(size: 10.5, weight: .bold))
            case .subheading: Text("H3").font(.system(size: 10, weight: .bold))
            case .text: Text("Аа").font(.system(size: 11.5, weight: .semibold))
            default: Image(systemName: block.symbol).font(.system(size: 12.5, weight: .medium))
            }
        }
        .frame(width: 28, height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.1)))
    }
}

// MARK: - «Стиль»

/// Стиль страницы: в панели B, в кнопке «Аа» варианта A и в полоске варианта C.
/// Ряды ровные: в каждом столько вариантов, сколько влезает в одну строку, без «хвостов».
struct StylePanel: View {
    let store: Store

    private var style: PageStyle { store.style(of: store.selectedID) }

    private func change(_ body: (inout PageStyle) -> Void) {
        guard let id = store.selectedID else { return }
        var style = self.style
        body(&style)
        withAnimation(.smooth(duration: 0.25)) { store.setStyle(style, for: id) }
    }

    private var isImageBackground: Bool {
        if case .image = style.background { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            group("Шрифт") {
                HStack(spacing: 6) {
                    ForEach(PageStyle.Font.allCases, id: \.self) { font in
                        Choice(isOn: style.font == font, action: { change { $0.font = font } }) {
                            Text("Аа")
                                .font(Font(PageStyle(font: font).font(font == .hand ? 23 : 16, weight: 600)))
                                .frame(height: 40)
                        }
                        .help(font.name)
                    }
                }
                Text(style.font.name).font(.system(size: 11)).opacity(0.5)
                    .transaction { $0.animation = nil } // без наплыва старой подписи на новую
            }

            group("Ширина страницы") {
                HStack(spacing: 6) {
                    ForEach(PageStyle.Width.allCases, id: \.self) { width in
                        Choice(isOn: style.width == width, action: { change { $0.width = width } }) {
                            HStack(spacing: 7) {
                                Image(systemName: width == .regular ? "rectangle.portrait" : "rectangle")
                                    .font(.system(size: 12, weight: .medium))
                                Text(width.name).font(.system(size: 12, weight: .medium))
                            }
                            .frame(height: 32)
                        }
                    }
                }
            }

            group("Фон") {
                // Цвета сеткой по 7 - ровные ряды без хвостов.
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(29), spacing: 7), count: 7), alignment: .leading, spacing: 7) {
                    ForEach(PageStyle.colors, id: \.id) { item in
                        Swatch(isOn: style.background == .color(item.id), help: item.name) {
                            Circle().fill(Color(nsColor: item.color))
                        } action: { change { $0.background = .color(item.id) } }
                    }
                }
                HStack(spacing: 7) {
                    ForEach(PageStyle.gradients, id: \.id) { item in
                        Swatch(isOn: style.background == .gradient(item.id), help: item.name) {
                            Circle().fill(LinearGradient(colors: [Color(nsColor: item.top), Color(nsColor: item.bottom)],
                                                         startPoint: .top, endPoint: .bottom))
                        } action: { change { $0.background = .gradient(item.id) } }
                    }
                    Swatch(isOn: isImageBackground, help: "Картинка с размытием…") {
                        Image(systemName: "photo").font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Circle().fill(.white.opacity(0.1)))
                    } action: {
                        if let url = Assets.pick(images: true).first, let name = Assets.store(url) {
                            change { $0.background = .image(name) }
                        }
                    }
                }
            }

            group("Обложка") {
                if let cover = style.cover, let image = Assets.image(cover) {
                    GeometryReader { geo in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: 64, alignment: .center)
                            .clipped()
                    }
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    HStack(spacing: 8) {
                        Text("Верх").font(.system(size: 10.5)).opacity(0.5)
                        Slider(value: Binding(get: { style.coverPosition }, set: { v in change { $0.coverPosition = v } }), in: 0...1)
                            .controlSize(.mini)
                        Text("Низ").font(.system(size: 10.5)).opacity(0.5)
                    }
                    HStack(spacing: 6) {
                        SmallButton(title: "Сменить…", symbol: "photo") { pickCover() }
                        SmallButton(title: "Убрать", symbol: "xmark") { change { $0.cover = nil } }
                    }
                } else {
                    SmallButton(title: "Добавить обложку…", symbol: "photo.on.rectangle") { pickCover() }
                }
            }

            group("Цвет текста") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(29), spacing: 7), count: 7), alignment: .leading, spacing: 7) {
                    ForEach(TextColor.allCases, id: \.self) { color in
                        Swatch(isOn: style.text == color, help: color.name) {
                            Circle().fill(Color(nsColor: color.color))
                        } action: { change { $0.text = color } }
                    }
                }
            }

            group("Маркер списка") {
                HStack(spacing: 6) {
                    ForEach(PageStyle.Bullet.allCases, id: \.self) { bullet in
                        Choice(isOn: style.bulletStyle == bullet, action: { change { $0.bullet = bullet } }) {
                            HStack(spacing: 8) {
                                if bullet == .dot {
                                    Circle().fill(.white.opacity(0.85)).frame(width: 6, height: 6)
                                } else {
                                    Capsule().fill(.white.opacity(0.85)).frame(width: 11, height: 2)
                                }
                                Text(bullet.name).font(.system(size: 12, weight: .medium))
                            }
                            .frame(height: 32)
                        }
                    }
                }
            }

            group("Разделители") {
                HStack(spacing: 6) {
                    ForEach(PageStyle.Divider.allCases, id: \.self) { divider in
                        Choice(isOn: style.divider == divider, action: { change { $0.divider = divider } }) {
                            VStack(spacing: 6) {
                                DividerSketch(kind: divider).frame(height: 10).padding(.horizontal, 10)
                                Text(divider.name).font(.system(size: 11, weight: .medium))
                            }
                            .frame(height: 46)
                        }
                    }
                }
            }

            group("Карточки страниц") {
                HStack(spacing: 6) {
                    ForEach(PageStyle.Card.allCases, id: \.self) { card in
                        Choice(isOn: style.card == card, action: { change { $0.card = card } }) {
                            VStack(spacing: 6) {
                                CardSketch(kind: card).frame(height: 14).padding(.horizontal, 10)
                                Text(card.name).font(.system(size: 11, weight: .medium))
                            }
                            .frame(height: 46)
                        }
                    }
                }
            }

            DefaultStyleRow(store: store, style: style)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title.uppercased())
            content()
        }
    }

    private func pickCover() {
        if let url = Assets.pick(images: true).first, let name = Assets.store(url) {
            change { $0.cover = name }
        }
    }
}

/// «Стиль по умолчанию»: кнопка гаснет, когда этот стиль уже по умолчанию, и сообщает, что сработала.
/// Отдельно - применить стиль ко всем заметкам (со своим подтверждением: это меняет все страницы).
private struct DefaultStyleRow: View {
    let store: Store
    let style: PageStyle
    @AppStorage("defaultPageStyle") private var saved: Data?
    @State private var confirmAll = false
    @State private var justSaved = false

    private var isDefault: Bool {
        (saved.flatMap { try? JSONDecoder().decode(PageStyle.self, from: $0) } ?? PageStyle()) == style
    }

    private var allSame: Bool { store.notes.allSatisfy { store.style(of: $0.id) == style } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("ДЛЯ ВСЕХ ЗАМЕТОК")
            if isDefault {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold))
                    Text(justSaved ? "Готово - это стиль по умолчанию" : "Это стиль по умолчанию")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.18)))
                .opacity(0.75)
                .transition(.opacity)
            } else {
                SmallButton(title: "Сделать стилем по умолчанию", symbol: "star") {
                    withAnimation(.smooth(duration: 0.25)) {
                        style.makeDefault()
                        saved = UserDefaults.standard.data(forKey: "defaultPageStyle")
                        justSaved = true
                    }
                    store.say("Новые заметки будут в этом стиле")
                }
                .transition(.opacity)
            }
            SmallButton(title: allSame ? "Все заметки уже в этом стиле" : "Применить ко всем заметкам", symbol: "square.stack") {
                confirmAll = true
            }
            .disabled(allSame)
            .opacity(allSame ? 0.45 : 1)
            Text("По умолчанию - для новых заметок и иконки в Dock. «Ко всем» - перекрасит и уже созданные.")
                .font(.system(size: 11))
                .opacity(0.45)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("Применить этот стиль ко всем заметкам?", isPresented: $confirmAll) {
            Button("Применить") {
                store.setStyleForAll(style)
                store.say("Стиль применён ко всем \(store.notes.count) заметкам")
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Шрифт, фон, обложка и цвета у всех страниц станут как у этой.")
        }
        .onChange(of: style) { _, _ in justSaved = false }
    }
}

/// Мини-рисунок разделителя для выбора.
private struct DividerSketch: View {
    let kind: PageStyle.Divider

    var body: some View {
        switch kind {
        case .line: Capsule().fill(.white.opacity(0.5)).frame(height: 1.5)
        case .dots:
            HStack(spacing: 6) { ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.6)).frame(width: 3.5, height: 3.5) } }
        case .washi:
            Rectangle().fill(Color(nsColor: NSColor(srgbRed: 1, green: 0.85, blue: 0.5, alpha: 0.45)))
                .frame(height: 8).rotationEffect(.degrees(-2))
        }
    }
}

/// Мини-рисунок карточки страницы для выбора.
private struct CardSketch: View {
    let kind: PageStyle.Card

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.white.opacity(kind == .filled ? 0.3 : kind == .outline ? 0.02 : 0.12))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.white.opacity(kind == .outline ? 0.7 : 0.2), lineWidth: kind == .outline ? 1.2 : 1))
    }
}

// MARK: - детали

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).opacity(0.45)
    }
}

private struct Choice<Label: View>: View {
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(isOn ? 0.18 : hover ? 0.1 : 0.06)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(isOn ? 0.5 : 0.06), lineWidth: isOn ? 1.2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct Swatch<Content: View>: View {
    let isOn: Bool
    let help: String
    @ViewBuilder let content: Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
                .frame(width: 25, height: 25)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(isOn ? 0.95 : 0.15), lineWidth: isOn ? 2 : 1))
                .padding(2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct SmallButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hover ? 0.13 : 0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
