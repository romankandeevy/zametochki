import AppKit
import SwiftUI

/// Панель как в Notion: всплывает над выделенным текстом и не прячется, пока выделение на месте, -
/// можно нажать несколько стилей подряд. Слева тип строки (меню «Превратить в»), дальше стили и цвет.
struct FormatBar: View {
    enum Mode { case main, blocks, colors, slash }

    struct State {
        var block: Block = .text
        var on: Set<Editor.Command> = []
        var color: TextColor = .white
        /// Цвет маркера у выделения; nil - маркера нет.
        var mark: MarkColor?
    }

    static let rowHeight: CGFloat = 38

    let state: State
    let mode: Mode
    var highlighted: Int? = nil
    /// Пункты меню «+» и «/» (меню «/» отфильтровано по тому, что напечатано после «/»).
    var menuItems: [Block] = Editor.Coordinator.menuBlocks
    let run: (Editor.Command) -> Void
    let setMode: (Mode) -> Void

    /// Цвет панели - в тон текущей страницы (считается заново при каждом показе).
    private static var fill: Color { Color(nsColor: PageStyle.current.panelColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mode != .slash { row }
            switch mode {
            case .main: EmptyView()
            case .slash: insertMenu
            case .blocks: blocksMenu.transition(.opacity.combined(with: .offset(y: -4)))
            case .colors: colorsMenu.transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(12) // место под тень
        .fixedSize()
        .foregroundStyle(.white)
    }

    // MARK: ряд кнопок

    private var row: some View {
        HStack(spacing: 1) {
            toggle(.bold, "bold", "Жирный  ⌘B")
            toggle(.italic, "italic", "Курсив  ⌘I")
            toggle(.underline, "underline", "Подчёркнутый  ⌘U")
            toggle(.strike, "strikethrough", "Зачёркнутый  ⇧⌘X")
            toggle(.highlight, "highlighter", "Маркер  ⇧⌘M")
            separator

            Button { setMode(mode == .colors ? .main : .colors) } label: {
                HStack(spacing: 4) {
                    Text("А")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(nsColor: state.color.color))
                        .padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: state.mark?.color ?? .clear)))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .opacity(0.6)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Pill(isOn: mode == .colors))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Цвет текста и маркера")
        }
        .padding(5)
        .frame(height: Self.rowHeight)
        .background(Card())
    }

    private var separator: some View {
        Rectangle().fill(.white.opacity(0.13)).frame(width: 1, height: 18).padding(.horizontal, 4)
    }

    private func toggle(_ command: Editor.Command, _ symbol: String, _ help: String) -> some View {
        BarButton(isOn: state.on.contains(command), action: { run(command) }) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
        }
        .help(help)
    }

    // MARK: меню

    private var blocksMenu: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(mode == .slash ? "Тип строки  ↑↓ ↵" : "Превратить в")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.45)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 3)
            ForEach(Array(Block.menu.enumerated()), id: \.element) { index, block in
                let current = mode == .slash ? index == highlighted : state.block == block || (block == .todo && state.block == .done)
                MenuRow(isOn: current, action: { run(.block(block)) }) {
                    Image(systemName: block.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22)
                        .opacity(0.8)
                    Text(block.name).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 16)
                    if current && mode != .slash { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                }
            }
        }
        .padding(5)
        .frame(width: 230)
        .background(Card())
    }

    /// Меню «+» и «/»: «Базовые» - типы строки, «Вставить» - предметы. Стрелки и Enter тоже работают.
    private var insertMenu: some View {
        let blocks = menuItems
        let firstObject = blocks.firstIndex { $0.isObject }
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(blocks.enumerated()), id: \.element) { index, block in
                        if (index == 0 && !block.isObject) || index == firstObject {
                            Text(block.isObject ? "ВСТАВИТЬ" : "БАЗОВЫЕ")
                                .font(.system(size: 10.5, weight: .semibold))
                                .opacity(0.45)
                                .padding(.horizontal, 9)
                                .padding(.top, index == 0 ? 4 : 10)
                                .padding(.bottom, 4)
                        }
                        MenuRow(isOn: index == highlighted, action: { run(.block(block)) }) {
                            BlockIcon(block: block)
                            Text(block.name).font(.system(size: 13))
                            Spacer(minLength: 16)
                            if let shortcut = block.shortcut {
                                Text(shortcut)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .opacity(0.4)
                            }
                        }
                        .id(index)
                    }
                }
                .padding(5)
            }
            .frame(width: 272, height: min(344, CGFloat(blocks.count) * 36 + (firstObject != nil && firstObject != 0 ? 56 : 30)))
            .background(Card())
            // Открывается с начала списка; прокручивается только когда ходишь стрелками.
            .onAppear { if let highlighted, highlighted > 0 { proxy.scrollTo(highlighted, anchor: .center) } }
            .onChange(of: highlighted) { _, value in
                if let value { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value, anchor: .center) } }
            }
        }
    }

    private var colorsMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Цвет текста")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.45)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 5), spacing: 6) {
                ForEach(TextColor.allCases, id: \.self) { color in
                    Button { run(.color(color)) } label: {
                        Text("А")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(nsColor: color.color))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(state.color == color ? 0.2 : 0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(state.color == color ? 0.7 : 0), lineWidth: 1.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                    .accessibilityLabel(color.name)
                }
            }
            Text("Маркер")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.45)
                .padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 5), spacing: 6) {
                // Первый - «без маркера».
                Button { run(.mark(nil)) } label: {
                    Image(systemName: "nosign")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.6)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(state.mark == nil ? 0.2 : 0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(state.mark == nil ? 0.7 : 0), lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Без маркера")
                .accessibilityLabel("Без маркера")
                ForEach(MarkColor.allCases, id: \.self) { mark in
                    Button { run(.mark(mark)) } label: {
                        Text("А")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(nsColor: state.color.color))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: mark.color)))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(state.mark == mark ? 0.8 : 0), lineWidth: 1.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Маркер: " + mark.name.lowercased())
                    .accessibilityLabel("Маркер: " + mark.name.lowercased())
                }
            }
        }
        .padding(10)
        .background(Card())
    }

    // MARK: детали

    private struct Card: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FormatBar.fill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
        }
    }

    private struct Pill: View {
        let isOn: Bool
        var hover = false
        var body: some View {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(isOn ? 0.18 : hover ? 0.09 : 0))
        }
    }

    private struct BarButton<Label: View>: View {
        let isOn: Bool
        let action: () -> Void
        @ViewBuilder let label: Label
        @SwiftUI.State private var hover = false

        var body: some View {
            Button(action: action) {
                label
                    .frame(width: 30, height: 28)
                    .background(Pill(isOn: isOn, hover: hover))
                    .opacity(isOn || hover ? 1 : 0.72)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }

    private struct MenuRow<Content: View>: View {
        let isOn: Bool
        let action: () -> Void
        @ViewBuilder let content: Content
        @SwiftUI.State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) { content }
                    .padding(.horizontal, 7)
                    .frame(minHeight: 30)
                    .padding(.vertical, 2)
                    .background(Pill(isOn: isOn, hover: hover))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }
}

/// Клик по панели срабатывает сразу, даже если окно было неактивным, и не уводит фокус из текста.
final class FormatBarHost: NSHostingView<FormatBar> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
}
