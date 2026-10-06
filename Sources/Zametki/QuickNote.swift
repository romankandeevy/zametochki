import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Быстрая заметка из любой программы: ⌃⌥N открывает маленькое окошко поверх всего,
/// Enter - мысль улетает в конец заметки «Входящие», окошко закрывается. Заметочки при этом не выходят вперёд.
final class QuickNote {
    static let shared = QuickNote()
    static let settingKey = "quickNoteHotkey"
    static let shortcut = "⌃⌥N"

    private var panel: QuickNotePanel?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Растёт при каждом показе: запоздалое «спрятать» от прошлого закрытия не трогает новое окошко.
    private var generation = 0

    static var enabled: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    /// Включить или выключить глобальное сочетание - по настройке.
    func updateHotKey() {
        if Self.enabled { register() } else { unregister() }
    }

    private func register() {
        guard hotKey == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { QuickNote.shared.toggle() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5A4D_544B), id: 1) // «ZMTK»
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        let panel = self.panel ?? QuickNotePanel()
        self.panel = panel
        generation += 1
        let style = PageStyle.saved
        panel.backgroundColor = style.baseColor
        panel.contentView = NSHostingView(rootView: QuickNoteView(style: style, save: { [weak self] text in
            self?.save(text)
        }, cancel: { [weak self] in
            self?.close()
        }))
        // Верхняя треть экрана, где сейчас мышь, - как Spotlight.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = NSSize(width: 520, height: 150)
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.maxY - visible.height / 3 - size.height / 2,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        let shown = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard self?.generation == shown else { return }
            panel.orderOut(nil)
            panel.contentView = nil
        })
    }

    private func save(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let store = AppDelegate.store {
            store.appendToInbox(trimmed)
            if UserDefaults.standard.object(forKey: "typingSound") as? Bool ?? true { TypingSound.shared.play(.enter) }
        }
        close()
    }
}

/// Окошко быстрой заметки: без заголовка, поверх всех окон и на всех рабочих столах, становится ключевым,
/// не выводя вперёд само приложение.
final class QuickNotePanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: true)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override var canBecomeKey: Bool { true }

    /// Ушёл в другое окно - окошко закрывается само, как Spotlight.
    override func resignKey() {
        super.resignKey()
        QuickNote.shared.close()
    }
}

private struct QuickNoteView: View {
    let style: PageStyle
    let save: (String) -> Void
    let cancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 11, weight: .semibold))
                Text("Во «Входящие»").font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text("↵ сохранить · ⌥↵ новая строка · Esc").font(.system(size: 10.5)).opacity(0.7)
            }
            .opacity(0.55)
            TextField("Мысль, задача, ссылка…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Font(style.font(style.font == .hand ? 26 : 17) as CTFont))
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit { save(text) }
            Text("Начни с [] - будет задача, с @завтра 10:00 - ещё и напоминание")
                .font(.system(size: 10.5))
                .opacity(0.4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color(nsColor: style.text.color))
        .background(Color(nsColor: style.baseColor))
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onExitCommand(perform: cancel)
    }
}
