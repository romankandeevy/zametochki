import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Закрытые заметки: текст шифруется на диске (AES-256-GCM), ключ лежит в связке ключей этого Mac,
/// а открывается заметка по Touch ID или паролю. В сеть ничего не уходит.
/// В файле остаются только место в дереве и стиль - сам текст и оформление зашифрованы.
enum Vault {
    private static let service = "com.romankandeevy.zametki.lock"
    private static let account = "notes-key"

    /// Что прячем: текст и куски оформления.
    struct Content: Codable {
        var text: String
        var runs: [Formatting.Run]
    }

    // MARK: шифр

    static func seal(_ content: Content, key: SymmetricKey) -> String? {
        guard let data = try? JSONEncoder().encode(content),
              let box = try? AES.GCM.seal(data, using: key), let combined = box.combined else { return nil }
        return combined.base64EncodedString()
    }

    static func open(_ sealed: String, key: SymmetricKey) -> Content? {
        guard let combined = Data(base64Encoded: sealed), let box = try? AES.GCM.SealedBox(combined: combined),
              let data = try? AES.GCM.open(box, using: key) else { return nil }
        return try? JSONDecoder().decode(Content.self, from: data)
    }

    // MARK: ключ в связке ключей

    /// Ключ заметок. Нет - при create создаётся новый. Потерян ключ - закрытые заметки не открыть никак.
    static func key(create: Bool) -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var found: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data {
            return SymmetricKey(data: data)
        }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? key : nil
    }

    // MARK: Touch ID

    /// Просит Touch ID или пароль Mac. done вызывается на главном потоке.
    static func authenticate(reason: String, done: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            DispatchQueue.main.async { done(false) }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

import AppKit
import SwiftUI

/// Плашка поверх редактора закрытой заметки: пока не открыта, текста под ней нет вовсе.
struct LockCover: View {
    let store: Store
    @State private var failed = false

    var body: some View {
        ZStack {
            PageBackground(style: store.currentStyle)
            VStack(spacing: 14) {
                Image(systemName: "lock.fill").font(.system(size: 30, weight: .medium)).opacity(0.7)
                Text("Заметка закрыта").font(.system(size: 20, weight: .semibold))
                Button { open() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "touchid")
                        Text(failed ? "Попробовать ещё раз" : "Открыть")
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Capsule().fill(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .foregroundStyle(.white)
        }
        // Заметка сразу просит Touch ID, как только её выбрали.
        .task(id: store.selectedID) { open() }
    }

    private func open() {
        guard let id = store.selectedID else { return }
        store.unlock(id) { ok in failed = !ok }
    }
}

extension View {
    /// Поверх редактора, пока выбранная заметка закрыта.
    func lockCover(_ store: Store) -> some View {
        overlay {
            if store.isClosed(store.selectedID) { LockCover(store: store).transition(.opacity) }
        }
    }
}
