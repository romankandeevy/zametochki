import AppKit
import SwiftUI

/// Правка таблицы: лист поверх окна с сеткой полей. Клик по таблице в тексте открывает его.
enum TableEditor {
    static func present(_ table: Table, over window: NSWindow?, done: @escaping (Table) -> Void) {
        guard let window else { return }
        let sheet = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        sheet.appearance = NSAppearance(named: .darkAqua)
        sheet.backgroundColor = PageStyle.current.panelColor
        let close: (Table?) -> Void = { result in
            window.endSheet(sheet)
            if let result { done(result) }
        }
        sheet.contentView = NSHostingView(rootView: TableEditorView(table: table, close: close))
        window.beginSheet(sheet)
    }
}

private struct TableEditorView: View {
    @State var table: Table
    let close: (Table?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Таблица")
                .font(.system(size: 15, weight: .semibold))
            ScrollView([.horizontal, .vertical]) {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(table.cells.indices, id: \.self) { r in
                        GridRow {
                            ForEach(0..<table.columns, id: \.self) { c in
                                TextField(r == 0 ? "Заголовок" : "", text: binding(r, c))
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, weight: r == 0 ? .semibold : .regular))
                                    .padding(.horizontal, 8)
                                    .frame(width: 130, height: 28)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(r == 0 ? 0.12 : 0.07)))
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 360)
            HStack(spacing: 8) {
                Button("+ строка") { table.cells.append(Array(repeating: "", count: table.columns)) }
                Button("+ столбец") { for i in table.cells.indices { table.cells[i].append("") } }
                Button("− строка") { if table.rows > 1 { table.cells.removeLast() } }
                Button("− столбец") {
                    if table.columns > 1 { for i in table.cells.indices where !table.cells[i].isEmpty { table.cells[i].removeLast() } }
                }
                Spacer()
                Button("Отмена") { close(nil) }.keyboardShortcut(.cancelAction)
                Button("Готово") { close(table) }.keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
        }
        .padding(20)
        .frame(minWidth: 460)
        .foregroundStyle(.white)
    }

    private func binding(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: { c < table.cells[r].count ? table.cells[r][c] : "" },
            set: { value in
                while table.cells[r].count <= c { table.cells[r].append("") }
                table.cells[r][c] = value
            }
        )
    }
}
