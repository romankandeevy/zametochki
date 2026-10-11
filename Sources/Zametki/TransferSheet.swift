import AppKit
import Observation
import SwiftUI

extension Notification.Name {
    static let openTransfer = Notification.Name("zametki.openTransfer")
}

/// Что делает окно переноса.
enum TransferMode: String, Identifiable {
    case send, receive
    var id: String { rawValue }
}

/// Один перенос: от ввода кода до «готово». Все шаги идут в фоне, цифры для сверки показываются в окне.
@Observable
@MainActor
final class TransferModel {
    enum Step: Equatable {
        case start
        case working(String)
        case compare(String)
        case done(String)
        case failed(String)
    }

    var step: Step = .start
    var code = ""
    var receiveCode = ""
    /// Отправлять все заметки, а не выбранную с её страницами.
    var everything = false
    private var task: Task<Void, Never>?
    private var answer: CheckedContinuation<Bool, Never>?

    /// Отправляемые заметки: выбранная вместе со страницами или вообще все.
    func outgoing(_ store: Store) -> [Note] {
        guard !everything, let id = store.selectedID else { return store.notes }
        func walk(_ id: String) -> [Note] { (store.note(id).map { [$0] } ?? []) + store.children(of: id).flatMap { walk($0.id) } }
        return walk(id)
    }

    func send(store: Store) {
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else { step = .failed("Нужен шестизначный код с iPhone"); return }
        let notes = outgoing(store)
        step = .working("Соединяюсь…")
        task = Task {
            do {
                let payload = try TransferLink.payload(for: notes)
                try await TransferLink.send(code: digits, payload: payload) { [weak self] sas in
                    await self?.ask(sas) ?? false
                }
                let n = notes.filter { $0.doc.locked != true }.count
                step = .done("Отправлено заметок: \(n). Они уже на iPhone.")
            } catch is CancellationError {
                step = .start
            } catch {
                step = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func receive(store: Store) {
        step = .working("Готовлю код…")
        task = Task {
            do {
                let data = try await TransferLink.receive(
                    onCode: { [weak self] code in self?.receiveCode = code; self?.step = .working("Введите код на iPhone") },
                    confirm: { [weak self] sas in await self?.ask(sas) ?? false })
                step = .working("Добавляю заметки…")
                let added = store.importReceived(try TransferLink.items(from: data))
                step = .done(added == 0 ? "Всё это у вас уже есть" : "Добавлено заметок: \(added)")
            } catch is CancellationError {
                step = .start
            } catch {
                step = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func ask(_ sas: String) async -> Bool {
        step = .compare(sas)
        return await withCheckedContinuation { answer = $0 }
    }

    func reply(_ ok: Bool) {
        guard let answer else { return }
        self.answer = nil
        step = .working(ok ? "Передаю…" : "Отменяю…")
        answer.resume(returning: ok)
    }

    func cancel() {
        answer?.resume(returning: false)
        answer = nil
        task?.cancel()
    }
}

struct TransferSheet: View {
    let store: Store
    let mode: TransferMode
    let close: () -> Void
    @State private var model = TransferModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .send ? "Отправить на iPhone" : "Принять с iPhone")
                .font(.system(size: 18, weight: .semibold))
            content
            Spacer(minLength: 0)
            HStack {
                Spacer()
                if case .done = model.step {
                    button("Готово", prominent: true) { close() }
                } else {
                    button("Отмена") { model.cancel(); close() }
                }
            }
        }
        .padding(22)
        .frame(width: 420, height: 330)
        .foregroundStyle(.white)
        .background(Color(nsColor: store.currentStyle.panelColor))
        .preferredColorScheme(.dark)
        .onAppear {
            if mode == .receive { model.receive(store: store) } else { focused = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .start:
            if mode == .send { sendStart }
        case .working(let text):
            if mode == .receive, !model.receiveCode.isEmpty {
                receiveCode
            } else {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text(text) }.opacity(0.8)
            }
        case .compare(let sas):
            VStack(alignment: .leading, spacing: 12) {
                Text("Эти цифры должны быть и на iPhone:").opacity(0.8)
                Text(sas).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit().tracking(6)
                HStack(spacing: 10) {
                    button("Совпадают", prominent: true) { model.reply(true) }
                    button("Нет") { model.reply(false) }
                }
            }
        case .done(let text):
            Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green.opacity(0.9))
        case .failed(let text):
            VStack(alignment: .leading, spacing: 10) {
                Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                button("Ещё раз") { model.step = .start; model.receiveCode = ""; if mode == .receive { model.receive(store: store) } }
            }
        }
    }

    private var sendStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("На iPhone откройте Заметочки → шестерёнка → «Принять с Mac» и введите показанный там код.").opacity(0.75)
                .fixedSize(horizontal: false, vertical: true)
            TextField("000000", text: $model.code)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                .focused($focused)
                .onSubmit { model.send(store: store) }
                .onChange(of: model.code) { _, new in model.code = String(new.filter(\.isNumber).prefix(6)) }
                .padding(.horizontal, 12).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
            Picker("", selection: $model.everything) {
                Text("Эта заметка и её страницы").tag(false)
                Text("Все заметки").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            button("Отправить", prominent: true) { model.send(store: store) }
                .disabled(model.code.count != 6)
            Text("Картинки и файлы пока остаются на устройстве, закрытые заметки не отправляются.")
                .font(.system(size: 11.5)).opacity(0.5)
        }
    }

    private var receiveCode: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("На iPhone откройте Заметочки → шестерёнка → «Отправить на Mac» и введите код:").opacity(0.75)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.receiveCode.prefix(3) + " " + model.receiveCode.suffix(3))
                .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit().tracking(4)
            Text("Код живёт пять минут.").font(.system(size: 11.5)).opacity(0.5)
        }
    }

    private func button(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
                .padding(.horizontal, 16).frame(height: 32)
                .background(Capsule().fill(.white.opacity(prominent ? 0.22 : 0.10)))
        }
        .buttonStyle(.plain)
    }
}
