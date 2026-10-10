import CryptoKit
import Foundation

/// Перенос заметок между Mac и iPhone по шестизначному коду.
/// Ключ получается на самих устройствах (ECDH P-256 → HKDF), посредник на Cloudflare видит только шифртекст.
/// Протокол и формат те же, что в docs/app/transfer.js.
enum TransferLink {
    /// Адрес посредника (transfer-worker/). Можно подменить: defaults write com.romankandeevy.zametki transferRelay <url>
    static let defaultRelay = "https://zametochki-transfer.romankandeevy.workers.dev"
    static var relay: String { UserDefaults.standard.string(forKey: "transferRelay") ?? defaultRelay }

    enum Failure: LocalizedError {
        case mismatch, cancelled, badCode, relay(Int), network(String), tooBig, unreadable

        var errorDescription: String? {
            switch self {
            case .mismatch: "Цифры не совпали - перенос отменён"
            case .cancelled: "Отменено"
            case .badCode: "Код не подошёл или устарел. Проверьте цифры на iPhone"
            case .relay(let code): "Сервер ответил ошибкой \(code)"
            case .network(let text): "Нет связи: \(text)"
            case .tooBig: "Слишком много данных для одного переноса (лимит около 20 МБ)"
            case .unreadable: "Не удалось прочитать полученное"
            }
        }
    }

    static let salt = Data("zametki-transfer-v1".utf8)
    static let chunkSize = 900_000
    static let maxChunks = 24

    // MARK: шифр (совпадает с transfer.js)

    /// Общий ключ AES-GCM и четыре цифры для сверки. Оба публичных ключа входят в вывод - подмена видна по цифрам.
    static func derive(_ priv: P256.KeyAgreement.PrivateKey, theirPub: Data,
                       receiverPub: Data, senderPub: Data) throws -> (key: SymmetricKey, sas: String) {
        let theirs = try P256.KeyAgreement.PublicKey(x963Representation: theirPub)
        let secret = try priv.sharedSecretFromKeyAgreement(with: theirs)
        let binding = receiverPub + senderPub
        func bits(_ label: String, _ count: Int) -> SymmetricKey {
            secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                           sharedInfo: Data(label.utf8) + binding, outputByteCount: count)
        }
        let sasBytes = bits("sas", 4).withUnsafeBytes { Array($0) }
        let number = (UInt32(sasBytes[0]) << 24 | UInt32(sasBytes[1]) << 16 | UInt32(sasBytes[2]) << 8 | UInt32(sasBytes[3])) % 10000
        return (bits("key", 32), String(format: "%04d", number))
    }

    static func encrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.seal(data, using: key).combined ?? Data()
    }

    static func decrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }

    // MARK: посредник

    private static func call(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: relay + path) else { throw Failure.network("адрес") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw Failure.network(error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw status == 404 || status == 409 ? Failure.badCode : Failure.relay(status) }
        return data
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// Получатель: создаёт комнату и показывает код (onCode), ждёт отправителя, просит сверить цифры и забирает данные.
    static func receive(onCode: @MainActor @Sendable (String) -> Void,
                        confirm: @MainActor @Sendable (String) async -> Bool) async throws -> Data {
        let mine = P256.KeyAgreement.PrivateKey()
        let myPub = mine.publicKey.x963Representation
        let created = try JSONSerialization.jsonObject(with: await call("/s/new", method: "POST",
                                                                         body: json(["pub": myPub.base64EncodedString()]))) as? [String: Any]
        guard let code = created?["code"] as? String else { throw Failure.unreadable }
        await onCode(code)
        defer { Task { _ = try? await call("/s/\(code)", method: "DELETE") } }

        var state: [String: Any] = [:]
        while true {
            try Task.checkCancellation()
            state = (try JSONSerialization.jsonObject(with: await call("/s/\(code)")) as? [String: Any]) ?? [:]
            if state["joined"] is String { break }
            try await Task.sleep(for: .milliseconds(1200))
        }
        guard let joined = (state["joined"] as? String).flatMap({ Data(base64Encoded: $0) }) else { throw Failure.unreadable }
        let (key, sas) = try derive(mine, theirPub: joined, receiverPub: myPub, senderPub: joined)
        guard await confirm(sas) else { throw Failure.mismatch }
        while true {
            try Task.checkCancellation()
            state = (try JSONSerialization.jsonObject(with: await call("/s/\(code)")) as? [String: Any]) ?? [:]
            if state["count"] is Int { break }
            try await Task.sleep(for: .milliseconds(1000))
        }
        var sealed = Data()
        for i in 0..<(state["count"] as? Int ?? 0) { sealed += try await call("/s/\(code)/chunk/\(i)") }
        do { return try decrypt(sealed, key: key) } catch { throw Failure.unreadable }
    }

    /// Отправитель: входит по коду, показывает цифры на сверку и отправляет данные.
    static func send(code: String, payload: Data,
                     confirm: @MainActor @Sendable (String) async -> Bool) async throws {
        let mine = P256.KeyAgreement.PrivateKey()
        let myPub = mine.publicKey.x963Representation
        let joined = try JSONSerialization.jsonObject(with: await call("/s/\(code)/join", method: "POST",
                                                                        body: json(["pub": myPub.base64EncodedString()]))) as? [String: Any]
        guard let receiverPub = (joined?["pub"] as? String).flatMap({ Data(base64Encoded: $0) }) else { throw Failure.unreadable }
        let (key, sas) = try derive(mine, theirPub: receiverPub, receiverPub: receiverPub, senderPub: myPub)
        guard await confirm(sas) else { throw Failure.mismatch }
        let sealed = try encrypt(payload, key: key)
        let count = (sealed.count + chunkSize - 1) / chunkSize
        guard count <= maxChunks else { throw Failure.tooBig }
        for i in 0..<count {
            try Task.checkCancellation()
            let part = sealed.subdata(in: (i * chunkSize)..<min((i + 1) * chunkSize, sealed.count))
            _ = try await call("/s/\(code)/chunk/\(i)", method: "PUT", body: part)
        }
        _ = try await call("/s/\(code)/done", method: "POST", body: json(["count": count]))
    }
}

// MARK: что переносим

extension TransferLink {
    /// Заметка в пути: «id + её настоящий документ» (Mac → iPhone) или «id + Markdown» (iPhone → Mac).
    struct Item: Codable {
        var id: String
        var parent: String?
        var order: Double?
        var doc: Formatting.Doc?
        var md: String?
    }

    struct Payload: Codable {
        var v = 1
        var from: String
        var notes: [Item]
    }

    static func payload(for notes: [Note]) throws -> Data {
        // Закрытые заметки наружу не уходят - они остаются зашифрованными на Mac.
        let items = notes.filter { $0.doc.locked != true }
            .map { Item(id: $0.id, parent: $0.parent, order: $0.doc.order, doc: $0.doc, md: nil) }
        return try JSONEncoder().encode(Payload(from: "mac", notes: items))
    }

    static func items(from data: Data) throws -> [Item] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.v == 1 else { throw Failure.unreadable }
        return payload.notes
    }
}
