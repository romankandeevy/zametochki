import AppKit
import SwiftUI

/// Канбан-доска: колонки с карточками. В тексте - один символ-вложение, как таблица;
/// клик открывает доску на правку, карточки перетаскиваются между колонками.
struct Board: Codable, Equatable {
    struct Card: Codable, Equatable, Identifiable {
        var id = UUID().uuidString
        var text: String
    }

    struct Column: Codable, Equatable, Identifiable {
        var id = UUID().uuidString
        var title: String
        var cards: [Card] = []
    }

    var columns: [Column]

    static var empty: Board {
        Board(columns: [Column(title: "Надо сделать"), Column(title: "В работе"), Column(title: "Готово")])
    }

    var json: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "{\"columns\":[]}"
    }

    init(columns: [Column]) { self.columns = columns }

    init(json: String) {
        self = (try? JSONDecoder().decode(Board.self, from: Data(json.utf8))) ?? .empty
    }

    /// Карточка переезжает в колонку column перед карточкой before (nil - в конец).
    mutating func move(_ cardID: String, to column: String, before: String? = nil) {
        guard cardID != before,
              let from = columns.firstIndex(where: { $0.cards.contains { $0.id == cardID } }),
              let at = columns[from].cards.firstIndex(where: { $0.id == cardID }) else { return }
        let card = columns[from].cards.remove(at: at)
        guard let to = columns.firstIndex(where: { $0.id == column }) else {
            columns[from].cards.insert(card, at: at)
            return
        }
        let index = before.flatMap { id in columns[to].cards.firstIndex { $0.id == id } } ?? columns[to].cards.count
        columns[to].cards.insert(card, at: index)
    }
}

// MARK: - доска в тексте

final class BoardCell: NSTextAttachmentCell {
    let board: Board
    static let header: CGFloat = 34
    static let cardHeight: CGFloat = 34
    static let maxCards = 6

    init(json: String) {
        board = Board(json: json)
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("не используется") }

    /// Сколько строк карточек видно: по самой длинной колонке, но не больше maxCards (+ строка «ещё N»).
    private var visibleRows: Int {
        let longest = board.columns.map(\.cards.count).max() ?? 0
        return longest > Self.maxCards ? Self.maxCards + 1 : max(longest, 1)
    }

    private var height: CGFloat { Self.header + CGFloat(visibleRows) * (Self.cardHeight + 6) + 14 }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: 0, y: -10, width: Objects.width(textContainer, lineFrag), height: height)
    }

    override func cellSize() -> NSSize { NSSize(width: 300, height: height) }
    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let rect = frame.insetBy(dx: 0.5, dy: 4)
        let style = PageStyle.current
        let text = style.text.color
        let outline = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)
        NSColor.white.withAlphaComponent(0.04).setFill()
        outline.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let columns = max(board.columns.count, 1)
        let gap: CGFloat = 8
        let width = (rect.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleSize: CGFloat = style.font == .hand ? 19 : 13
        let cardSize: CGFloat = style.font == .hand ? 18 : 12.5

        for (c, column) in board.columns.enumerated() {
            let x = rect.minX + gap + CGFloat(c) * (width + gap)
            let lane = NSRect(x: x, y: rect.minY + 6, width: width, height: rect.height - 12)
            NSColor.black.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: lane, xRadius: 8, yRadius: 8).fill()

            let title = NSAttributedString(string: column.title.isEmpty ? "Колонка" : column.title, attributes: [
                .font: style.font(titleSize, weight: 700), .foregroundColor: text, .paragraphStyle: paragraph,
            ])
            let count = NSAttributedString(string: "\(column.cards.count)", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: text.withAlphaComponent(0.45),
            ])
            let countSize = count.size()
            let titleHeight = title.size().height
            title.draw(in: NSRect(x: lane.minX + 10, y: lane.minY + (Self.header - titleHeight) / 2,
                                  width: lane.width - 30 - countSize.width, height: titleHeight))
            count.draw(at: NSPoint(x: lane.maxX - 10 - countSize.width, y: lane.minY + (Self.header - countSize.height) / 2))

            let shown = column.cards.count > Self.maxCards ? Array(column.cards.prefix(Self.maxCards)) : column.cards
            for (i, card) in shown.enumerated() {
                let box = NSRect(x: lane.minX + 6, y: lane.minY + Self.header + CGFloat(i) * (Self.cardHeight + 6),
                                 width: lane.width - 12, height: Self.cardHeight)
                NSColor.white.withAlphaComponent(0.1).setFill()
                NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
                let label = NSAttributedString(string: card.text, attributes: [
                    .font: style.font(cardSize), .foregroundColor: text.withAlphaComponent(0.92), .paragraphStyle: paragraph,
                ])
                let h = label.size().height
                label.draw(in: NSRect(x: box.minX + 9, y: box.midY - h / 2, width: box.width - 18, height: h))
            }
            if column.cards.count > Self.maxCards {
                let more = NSAttributedString(string: "ещё \(column.cards.count - Self.maxCards)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11.5, weight: .medium), .foregroundColor: text.withAlphaComponent(0.5),
                ])
                more.draw(at: NSPoint(x: lane.minX + 12, y: lane.minY + Self.header + CGFloat(Self.maxCards) * (Self.cardHeight + 6) + 8))
            }
            if column.cards.isEmpty {
                let empty = NSAttributedString(string: "пусто", attributes: [
                    .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: text.withAlphaComponent(0.3),
                ])
                empty.draw(at: NSPoint(x: lane.minX + 12, y: lane.minY + Self.header + 9))
            }
        }
    }
}

// MARK: - правка доски

/// Доска на правку: лист поверх окна. Карточки тащатся мышью между колонками и внутри колонки.
enum BoardEditor {
    static func present(_ board: Board, over window: NSWindow?, done: @escaping (Board) -> Void) {
        guard let window else { return }
        let sheet = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .resizable], backing: .buffered, defer: true)
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        sheet.appearance = NSAppearance(named: .darkAqua)
        sheet.backgroundColor = PageStyle.current.panelColor
        let close: (Board?) -> Void = { result in
            window.endSheet(sheet)
            if let result { done(result) }
        }
        sheet.contentView = NSHostingView(rootView: BoardEditorView(board: board, close: close))
        window.beginSheet(sheet)
    }
}

private struct BoardEditorView: View {
    @State var board: Board
    let close: (Board?) -> Void
    @State private var target: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Доска").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Карточки перетаскиваются мышью").font(.system(size: 11.5)).opacity(0.45)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach($board.columns) { $column in
                        lane($column)
                    }
                    Button {
                        withAnimation(.smooth(duration: 0.2)) { board.columns.append(.init(title: "Новая колонка")) }
                    } label: {
                        Label("Колонка", systemImage: "plus")
                            .font(.system(size: 12.5, weight: .medium))
                            .frame(width: 120, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)
            }
            .frame(minHeight: 300, maxHeight: .infinity)
            HStack {
                Spacer()
                Button("Отмена") { close(nil) }.keyboardShortcut(.cancelAction)
                Button("Готово") { close(board) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 440)
        .foregroundStyle(.white)
    }

    private func lane(_ column: Binding<Board.Column>) -> some View {
        let id = column.wrappedValue.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                TextField("Колонка", text: column.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(column.wrappedValue.cards.count)").font(.system(size: 11, weight: .semibold)).opacity(0.45)
                Menu {
                    Button("Удалить колонку", role: .destructive) {
                        withAnimation(.smooth(duration: 0.2)) { board.columns.removeAll { $0.id == id } }
                    }
                    .disabled(board.columns.count <= 1)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 6)
            .frame(height: 28)

            ForEach(column.cards) { $card in
                CardRow(card: $card) {
                    withAnimation(.smooth(duration: 0.2)) { column.wrappedValue.cards.removeAll { $0.id == card.id } }
                }
                .draggable(card.id)
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first else { return false }
                    withAnimation(.smooth(duration: 0.2)) { board.move(dragged, to: id, before: card.id) }
                    return true
                }
            }
            Button {
                withAnimation(.smooth(duration: 0.2)) { column.wrappedValue.cards.append(.init(text: "")) }
            } label: {
                Label("Карточка", systemImage: "plus")
                    .font(.system(size: 12))
                    .opacity(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 200)
        .frame(minHeight: 260, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(target == id ? 0.28 : 0.18)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(target == id ? 0.4 : 0), lineWidth: 1.5))
        // Брошенная на пустое место колонки карточка встаёт в её конец.
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first else { return false }
            withAnimation(.smooth(duration: 0.2)) { board.move(dragged, to: id) }
            return true
        } isTargeted: { on in
            if on { target = id } else if target == id { target = nil }
        }
    }

    private struct CardRow: View {
        @Binding var card: Board.Card
        let delete: () -> Void
        @State private var hover = false

        var body: some View {
            HStack(spacing: 4) {
                TextField("Что сделать", text: $card.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(1...4)
                if hover {
                    Button(action: delete) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).opacity(0.6) }
                        .buttonStyle(.plain)
                        .help("Удалить карточку")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(hover ? 0.14 : 0.1)))
            .onHover { hover = $0 }
        }
    }
}
