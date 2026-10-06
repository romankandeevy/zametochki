import AppKit
import SwiftUI

/// Связь между холстом (AppKit) и панелями (SwiftUI): инструмент, цвет, выделение, зум, отмена.
final class BoardController: ObservableObject {
    weak var canvas: BoardCanvas? {
        didSet { canvas?.tool = tool; canvas?.color = color; canvas?.strokeWidth = CGFloat(width) }
    }

    @Published var tool: BoardTool = .select { didSet { canvas?.endEditing(); canvas?.tool = tool } }
    @Published var color: String = UserDefaults.standard.string(forKey: "boardColor") ?? "white" {
        didSet { UserDefaults.standard.set(color, forKey: "boardColor"); canvas?.color = color }
    }
    @Published var width: Double = UserDefaults.standard.object(forKey: "boardWidth") as? Double ?? 4 {
        didSet { UserDefaults.standard.set(width, forKey: "boardWidth"); canvas?.strokeWidth = CGFloat(width) }
    }
    @Published var selected: [BoardItem] = []
    @Published var zoom: CGFloat = 1
    @Published var canUndo = false
    @Published var canRedo = false
    /// Замочек: инструмент не возвращается к выбору после того, как поставил фигуру.
    @Published var toolLocked: Bool = UserDefaults.standard.bool(forKey: "boardToolLocked") {
        didSet { UserDefaults.standard.set(toolLocked, forKey: "boardToolLocked") }
    }
    /// Панель свойств справа можно спрятать - выбор запоминается.
    @Published var showProperties: Bool = UserDefaults.standard.object(forKey: "boardProperties") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showProperties, forKey: "boardProperties") }
    }

    /// Каждое изменение сразу уходит в заметку.
    var save: (Whiteboard) -> Void = { _ in }

    func boardChanged(_ board: Whiteboard) {
        save(board)
        canUndo = canvas?.canUndo ?? false
        canRedo = canvas?.canRedo ?? false
    }

    func selectionChanged(_ items: [BoardItem]) {
        if items != selected { selected = items }
        canUndo = canvas?.canUndo ?? false
        canRedo = canvas?.canRedo ?? false
    }

    func update(_ body: (inout BoardItem) -> Void) { canvas?.updateSelection(body) }
}

/// Окно доски: отдельное, большое, можно на весь экран. Изменения сохраняются в заметку сразу.
enum BoardWindow {
    private static var open: [String: NSWindow] = [:]
    private static var delegates: [String: Closer] = [:]

    static func show(_ board: Whiteboard, save: @escaping (Whiteboard) -> Void) {
        if let window = open[board.id] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = BoardController()
        controller.save = save
        let canvas = BoardCanvas(frame: .zero)
        canvas.load(board)
        canvas.controller = controller
        controller.canvas = canvas

        let main = NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        let frame = main.map { $0.frame.insetBy(dx: -40, dy: -30) } ?? NSRect(x: 100, y: 100, width: 1280, height: 820)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Доска"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = PageStyle.current.baseColor
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 520)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setFrame(frame, display: false)
        let close: () -> Void = { [weak window] in window?.performClose(nil) }
        window.contentView = NSHostingView(rootView: BoardView(controller: controller, canvas: canvas, close: close))
        let closer = Closer(id: board.id, canvas: canvas, controller: controller)
        window.delegate = closer
        delegates[board.id] = closer
        open[board.id] = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    /// При закрытии - дописать текст и сохранить.
    final class Closer: NSObject, NSWindowDelegate {
        let id: String
        weak var canvas: BoardCanvas?
        let controller: BoardController

        init(id: String, canvas: BoardCanvas, controller: BoardController) {
            self.id = id
            self.canvas = canvas
            self.controller = controller
        }

        func windowWillClose(_ notification: Notification) {
            if let board = canvas?.finish() { controller.save(board) }
            BoardWindow.open[id] = nil
            DispatchQueue.main.async { BoardWindow.delegates[self.id] = nil }
        }
    }
}

private struct CanvasHost: NSViewRepresentable {
    let canvas: BoardCanvas
    func makeNSView(context: Context) -> BoardCanvas { canvas }
    func updateNSView(_ nsView: BoardCanvas, context: Context) {}
}

private struct BoardView: View {
    @ObservedObject var controller: BoardController
    let canvas: BoardCanvas
    let close: () -> Void

    static let colors: [TextColor] = [.white, .yellow, .pink, .green, .sky, .orange, .coral, .lavender]
    static let widths: [(String, Double)] = [("Тонко", 2), ("Средне", 4), ("Толсто", 8), ("Очень толсто", 14)]
    static let drawTools: [BoardTool] = [.select, .hand, .pen, .marker, .eraser]
    static let shapeTools: [BoardTool] = [.line, .arrow, .rect, .ellipse, .diamond, .sticky, .text, .image]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .topTrailing) {
                CanvasHost(canvas: canvas)
                if !controller.selected.isEmpty, controller.showProperties {
                    PropertiesPanel(controller: controller)
                        .padding(14)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.smooth(duration: 0.2), value: controller.selected.isEmpty)
            .animation(.smooth(duration: 0.2), value: controller.showProperties)
            .overlay(alignment: .bottomLeading) { hints.padding(14) }
        }
        .foregroundStyle(.white)
        .background(Color(nsColor: PageStyle.current.baseColor))
        .ignoresSafeArea()
    }

    // MARK: верхняя панель

    /// Панель подстраивается под ширину окна: сначала прячет толщины, потом цвета (они для новых предметов).
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow(colors: true, widths: true)
            toolbarRow(colors: true, widths: false)
            toolbarRow(colors: false, widths: false)
        }
    }

    private func toolbarRow(colors: Bool, widths: Bool) -> some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 64, height: 1) // место под светофор
            group {
                IconButton(symbol: controller.toolLocked ? "lock.fill" : "lock.open", isOn: controller.toolLocked,
                           help: controller.toolLocked ? "Инструмент закреплён - после фигуры не возвращается к выбору (Q)"
                                                       : "Закрепить инструмент - ставить много фигур подряд (Q)") {
                    controller.toolLocked.toggle()
                }
                ForEach(Self.drawTools, id: \.self) { toolButton($0) }
            }
            group { ForEach(Self.shapeTools, id: \.self) { toolButton($0) } }
            if colors { group {
                ForEach(Self.colors, id: \.self) { ink in
                    Button { controller.color = ink.rawValue } label: {
                        Circle()
                            .fill(Color(nsColor: ink.color))
                            .frame(width: 15, height: 15)
                            .overlay(Circle().strokeBorder(.white.opacity(controller.color == ink.rawValue ? 0.95 : 0), lineWidth: 2).padding(-4))
                            .frame(width: 24, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Цвет для новых: " + ink.name.lowercased())
                    .accessibilityLabel(ink.name)
                }
            } }
            if widths { group {
                ForEach(Self.widths, id: \.1) { name, value in
                    Button { controller.width = value } label: {
                        Capsule().fill(.white)
                            .frame(width: 15, height: max(1.5, value / 1.6))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(controller.width == value ? 0.18 : 0)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Толщина: " + name.lowercased())
                    .accessibilityLabel("Толщина: " + name.lowercased())
                }
            } }
            Spacer(minLength: 6)
            group {
                IconButton(symbol: "sidebar.right", isOn: controller.showProperties,
                           help: controller.showProperties ? "Спрятать панель свойств (⌥⌘I)" : "Показать панель свойств (⌥⌘I)") {
                    controller.showProperties.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
            group {
                IconButton(symbol: "arrow.uturn.backward", help: "Отменить (⌘Z)") { canvas.undo() }
                    .disabled(!controller.canUndo).opacity(controller.canUndo ? 1 : 0.35)
                IconButton(symbol: "arrow.uturn.forward", help: "Повторить (⇧⌘Z)") { canvas.redo() }
                    .disabled(!controller.canRedo).opacity(controller.canRedo ? 1 : 0.35)
            }
            group {
                IconButton(symbol: "minus", help: "Отдалить (⌘−)") { canvas.setZoom(canvas.zoom / 1.25) }
                Button { canvas.setZoom(1) } label: {
                    Text("\(Int((controller.zoom * 100).rounded()))%")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .frame(width: 46, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Масштаб 100% (⌘1)")
                IconButton(symbol: "plus", help: "Приблизить (⌘+)") { canvas.setZoom(canvas.zoom * 1.25) }
                IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Показать всё (⌘0)") { canvas.fitContent() }
            }
            Button("Готово", action: close)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help("Закрыть доску (⌘↩). Всё сохраняется само.")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func toolButton(_ tool: BoardTool) -> some View {
        IconButton(symbol: tool.symbol, isOn: controller.tool == tool, help: "\(tool.name) (\(tool.key))") { controller.tool = tool }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 1) { content() }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
    }

    private var hints: some View {
        Text("Двигать холст - два пальца или пробел + мышь · Масштаб - щипок или ⌘ + колёсико · Тяни от синих точек - стрелка-связь")
            .font(.system(size: 11))
            .opacity(0.4)
            .allowsHitTesting(false)
    }
}

/// Свойства выделенного: цвет, заливка, толщина, пунктир, наконечники, размер текста, порядок.
private struct PropertiesPanel: View {
    @ObservedObject var controller: BoardController

    private var items: [BoardItem] { controller.selected }
    private var first: BoardItem? { items.first }
    private var hasStroke: Bool { items.contains { $0.hasStroke } }
    private var hasFillable: Bool { items.contains { $0.isShape || $0.kind == .sticky } }
    private var onlyStickies: Bool { items.allSatisfy { $0.kind == .sticky } }
    private var hasText: Bool { items.contains { $0.holdsText } }
    private var hasConnectors: Bool { items.contains { $0.isConnector } }
    private var hasLines: Bool { items.contains { $0.isConnector || $0.isShape || $0.kind == .pen } }

    private var title: String {
        if items.count > 1 { return "Выбрано: \(items.count)" }
        switch first?.kind {
        case .pen: return "Рисунок"
        case .marker: return "Маркер"
        case .line: return "Линия"
        case .arrow: return "Стрелка"
        case .rect: return "Прямоугольник"
        case .ellipse: return "Овал"
        case .diamond: return "Ромб"
        case .sticky: return "Стикер"
        case .text: return "Надпись"
        case .image: return "Картинка"
        case nil: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { controller.showProperties = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Спрятать панель (⌥⌘I). Вернуть - кнопкой справа вверху")
                .accessibilityLabel("Спрятать панель свойств")
            }
            if !onlyStickies, items.contains(where: { $0.kind != .image && $0.kind != .sticky }) {
                section(hasText && !hasStroke ? "Цвет текста" : "Цвет") {
                    swatches(selected: first?.color) { id in controller.update { $0.color = id ?? "white" } }
                }
            }
            if hasFillable {
                section(onlyStickies ? "Цвет стикера" : "Заливка") {
                    swatches(selected: first?.fill, allowNone: !onlyStickies) { id in
                        controller.update { item in
                            if item.isShape || item.kind == .sticky { item.fill = id ?? (item.kind == .sticky ? "yellow" : nil) }
                        }
                    }
                }
            }
            if hasStroke {
                section("Толщина") {
                    HStack(spacing: 8) {
                        Slider(value: Binding(get: { Double(first?.width ?? 4) },
                                              set: { value in controller.update { $0.width = CGFloat(value) } }), in: 1...24)
                            .controlSize(.small)
                        Text("\(Int(first?.width ?? 4))").font(.system(size: 11).monospacedDigit()).frame(width: 20).opacity(0.6)
                    }
                }
            }
            if hasLines {
                section("Линия") {
                    segmented(BoardItem.Dash.allCases, selected: first?.dash, label: { dash in
                        switch dash {
                        case .solid: AnyView(Rectangle().frame(width: 22, height: 2))
                        case .dashed: AnyView(HStack(spacing: 3) { ForEach(0..<3) { _ in Rectangle().frame(width: 5, height: 2) } })
                        case .dotted: AnyView(HStack(spacing: 3) { ForEach(0..<4) { _ in Circle().frame(width: 2.5, height: 2.5) } })
                        }
                    }) { dash in controller.update { $0.dash = dash } }
                }
            }
            if hasConnectors {
                section("Форма") {
                    segmented(BoardItem.Route.allCases, selected: first?.effectiveRoute, label: { route in
                        AnyView(RouteIcon(route: route).stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 22, height: 14))
                    }) { route in
                        controller.update { item in
                            guard item.isConnector else { return }
                            item.route = route
                            item.curve = nil
                            item.bend = nil
                            if route == .curved, (item.waypoints ?? []).isEmpty {
                                // Сразу заметный изгиб - дальше тянут за точку или добавляют новые.
                                item.waypoints = [CGPoint(x: 0.5, y: 0.22)]
                            }
                        }
                    }
                }
                Text("Тяни полупрозрачные точки на стрелке - появятся новые точки изгиба. Двойной клик по точке - убрать.")
                    .font(.system(size: 10.5))
                    .opacity(0.45)
                    .fixedSize(horizontal: false, vertical: true)
                section("Наконечники") {
                    segmented(BoardItem.Heads.allCases, selected: first?.effectiveHeads, label: { heads in
                        AnyView(Image(systemName: heads == .none ? "line.diagonal" : heads == .end ? "arrow.up.right" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold)))
                    }) { heads in controller.update { if $0.isConnector { $0.heads = heads } } }
                }
            }
            if hasText {
                section("Размер текста") {
                    let sizes: [(String, CGFloat)] = [("S", 16), ("M", 22), ("L", 32), ("XL", 48)]
                    HStack(spacing: 4) {
                        ForEach(sizes, id: \.1) { name, size in
                            let on = abs((first?.effectiveFontSize ?? 0) - size) < 0.5
                            Button { controller.update { if $0.holdsText { $0.fontSize = size } } } label: {
                                Text(name).font(.system(size: 11.5, weight: .semibold))
                                    .frame(maxWidth: .infinity).frame(height: 26)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(on ? 0.2 : 0.07)))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Divider().opacity(0.4)
            HStack(spacing: 4) {
                IconButton(symbol: "square.3.layers.3d.top.filled", help: "На передний план (⌘])") { controller.canvas?.bringToFront() }
                IconButton(symbol: "square.3.layers.3d.bottom.filled", help: "На задний план (⌘[)") { controller.canvas?.sendToBack() }
                IconButton(symbol: "plus.square.on.square", help: "Дублировать (⌘D)") { controller.canvas?.duplicate() }
                Spacer()
                IconButton(symbol: "trash", help: "Удалить (⌫)") { controller.canvas?.deleteSelection() }
            }
        }
        .padding(14)
        .frame(width: 236)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: PageStyle.current.panelColor))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1)))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).opacity(0.45)
            content()
        }
    }

    private func swatches(selected: String?, allowNone: Bool = false, pick: @escaping (String?) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 7), alignment: .leading, spacing: 6) {
            if allowNone {
                Button { pick(nil) } label: {
                    Image(systemName: "nosign").font(.system(size: 12)).opacity(0.6)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white.opacity(selected == nil ? 0.9 : 0.15), lineWidth: selected == nil ? 2 : 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Без заливки")
            }
            ForEach(BoardView.colors, id: \.self) { ink in
                Button { pick(ink.rawValue) } label: {
                    Circle().fill(Color(nsColor: ink.color))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(selected == ink.rawValue ? 0.95 : 0), lineWidth: 2).padding(-3))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(ink.name)
                .accessibilityLabel(ink.name)
            }
        }
    }

    private func segmented<T: Hashable>(_ values: [T], selected: T?, label: @escaping (T) -> AnyView, pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button { pick(value) } label: {
                    label(value)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(selected == value ? 0.2 : 0.07)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct IconButton: View {
    let symbol: String
    var isOn = false
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(isOn ? 0.2 : hover ? 0.09 : 0)))
                .opacity(isOn || hover ? 1 : 0.78)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}


/// Значок формы стрелки в панели свойств.
private struct RouteIcon: Shape {
    let route: BoardItem.Route

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let a = CGPoint(x: rect.minX + 1, y: rect.maxY - 1), b = CGPoint(x: rect.maxX - 1, y: rect.minY + 1)
        path.move(to: a)
        switch route {
        case .straight: path.addLine(to: b)
        case .curved: path.addQuadCurve(to: b, control: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY - rect.height * 0.3))
        case .elbow:
            path.addLine(to: CGPoint(x: b.x, y: a.y))
            path.addLine(to: b)
        }
        return path
    }
}
