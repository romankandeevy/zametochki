import AppKit
import AVFoundation
import Observation

/// Голосовой ввод через движок FlowLocal: его Python, модели GigaAM и backend/server.py
/// берём из установленного FlowLocal только на чтение. Пока человек говорит, server.py присылает
/// живой текст (partial); после «стоп» - окончательный, с запятыми и заглавными.
@Observable
final class Dictation {
    enum State: Equatable {
        case idle
        case listening       // микрофон пишет, слова идут в текст
        case finishing       // ждём окончательный текст
        case failed(String)
    }

    static let shared = Dictation()

    private(set) var state: State = .idle
    /// Модель ещё грузится: первая запись после запуска ждёт её, звук при этом не теряется.
    private(set) var warming = false

    /// Куда идут слова - редактор заметки.
    @ObservationIgnored var onLive: ((String) -> Void)?
    @ObservationIgnored var onFinal: ((String) -> Void)?
    @ObservationIgnored var onCancel: (() -> Void)?

    @ObservationIgnored private let backend = FlowBackend()
    @ObservationIgnored private let mic = MicRecorder()
    @ObservationIgnored private var sessionID = 0
    @ObservationIgnored private var begun = false
    @ObservationIgnored private var preroll: [Float] = []
    @ObservationIgnored private var finishRequested = false
    @ObservationIgnored private var escMonitor: Any?
    @ObservationIgnored private var idleStop: DispatchWorkItem?

    private init() {
        backend.onEvent = { [weak self] event in self?.handle(event) }
        mic.onSamples = { [weak self] samples in self?.feed(samples) }
    }

    var isActive: Bool { state == .listening || state == .finishing }

    func toggle() {
        switch state {
        case .listening: finish()
        case .finishing: break
        default: start()
        }
    }

    // MARK: запись

    private func start() {
        if let problem = FlowBackend.missing() {
            fail(problem)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { ok ? self.start() : self.fail("Нет доступа к микрофону") }
            }
            return
        default:
            fail("Нет доступа к микрофону: Системные настройки → Конфиденциальность → Микрофон")
            return
        }

        idleStop?.cancel()
        if !backend.isRunning {
            warming = true
            backend.start()
        }
        sessionID += 1
        begun = false
        finishRequested = false
        preroll.removeAll()
        do {
            try mic.start()
        } catch {
            fail("Микрофон не запустился: \(error.localizedDescription)")
            return
        }
        state = .listening
        if backend.isReady { beginSession() }
        watchEscape()
    }

    private func beginSession() {
        guard !begun, isActive else { return }
        begun = true
        backend.begin(sessionID)
        if !preroll.isEmpty {
            backend.audio(sessionID, preroll)
            preroll.removeAll()
        }
        if finishRequested { sendFinish() }
    }

    private func feed(_ samples: [Float]) {
        guard isActive else { return }
        if begun {
            backend.audio(sessionID, samples)
        } else {
            preroll += samples
        }
    }

    func finish() {
        guard state == .listening else { return }
        mic.stop() // остаток звука уходит в feed синхронно
        state = .finishing
        // Порции, которые микрофон уже поставил в очередь главного потока, должны уйти раньше «finish».
        DispatchQueue.main.async {
            self.finishRequested = true
            if self.begun { self.sendFinish() }
        }
    }

    private func sendFinish() {
        let id = sessionID
        backend.finish(id, timeout: 60) { [weak self] result in
            guard let self, id == self.sessionID, self.state == .finishing else { return }
            self.stopWatchingEscape()
            switch result {
            case .success(let text):
                self.state = .idle
                self.onFinal?(text)
            case .failure(let error):
                self.onCancel?()
                self.fail(error.localizedDescription)
            }
            self.scheduleIdleStop()
        }
    }

    func cancel() {
        guard isActive else { return }
        mic.stop()
        if begun { backend.cancel(sessionID) }
        sessionID += 1
        state = .idle
        stopWatchingEscape()
        onCancel?()
        scheduleIdleStop()
    }

    private func fail(_ message: String) {
        state = .failed(message)
        warming = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if case .failed = self?.state { self?.state = .idle }
        }
    }

    /// Модели держат пару сотен МБ памяти - без диктовки 10 минут отпускаем процесс.
    private func scheduleIdleStop() {
        idleStop?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isActive else { return }
            self.backend.stop()
        }
        idleStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: work)
    }

    func shutdown() { backend.stop() }

    private func watchEscape() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.isActive else { return event }
            self.cancel()
            return nil
        }
    }

    private func stopWatchingEscape() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }

    // MARK: ответы движка

    private func handle(_ event: FlowBackend.Event) {
        switch event {
        case .ready:
            warming = false
            if state == .listening || state == .finishing { beginSession() }
        case .partial(let id, let text, let interim):
            guard id == sessionID, isActive else { return }
            onLive?([text, interim].filter { !$0.isEmpty }.joined(separator: " "))
        case .failed(let message):
            if isActive {
                mic.stop()
                stopWatchingEscape()
                onCancel?()
            }
            fail(message)
        case .exited:
            warming = false
            if isActive {
                mic.stop()
                stopWatchingEscape()
                onCancel?()
                fail("Распознавание остановилось")
            }
        }
    }
}

// MARK: - процесс server.py

/// Мост к backend/server.py из FlowLocal. Протокол - строки JSON, звук - сырые float32 16 кГц после заголовка.
final class FlowBackend {
    enum Event {
        case ready
        case failed(String)
        case exited
        case partial(id: Int, text: String, interim: String)
    }

    var onEvent: ((Event) -> Void)?
    private(set) var isReady = false

    private let queue = DispatchQueue(label: "zametki.dictation")
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var pending: [Int: (Result<String, Error>) -> Void] = [:]

    var isRunning: Bool { process?.isRunning == true }

    private static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FlowLocal", isDirectory: true)
    private static var python: URL { support.appendingPathComponent("Python/bin/python3") }
    private static var models: URL { support.appendingPathComponent("Models") }
    /// server.py лежит внутри установленного FlowLocal.app - ищем приложение по его bundle id.
    private static var server: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.flowlocal.mac")?
            .appendingPathComponent("Contents/Resources/backend/server.py")
    }

    /// Чего не хватает для диктовки, или nil, если всё на месте.
    static func missing() -> String? {
        guard let server, FileManager.default.fileExists(atPath: server.path) else {
            return "Для голосового ввода нужен FlowLocal"
        }
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            return "Сначала запустите FlowLocal - он поставит распознавание"
        }
        guard FileManager.default.fileExists(atPath: models.appendingPathComponent("gigaam-v3-e2e-rnnt-int8").path) else {
            return "Сначала запустите FlowLocal - он скачает модели"
        }
        return nil
    }

    func start() {
        guard process == nil, let server = Self.server else { return }
        let p = Process()
        p.executableURL = Self.python
        p.arguments = [server.path]
        p.currentDirectoryURL = server.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        env["FLOWLOCAL_MODELS"] = Self.models.path
        // server.py лежит в чужом подписанном .app: __pycache__ рядом с ним сломал бы его подпись.
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            self?.queue.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] proc in
            self?.queue.asyncAfter(deadline: .now() + 0.2) { self?.reap(proc) }
        }
        do {
            try p.run()
        } catch {
            emit(.failed("Не запустилось распознавание: \(error.localizedDescription)"))
            return
        }
        process = p
        input = inPipe.fileHandleForWriting
    }

    func stop() {
        queue.async { try? self.input?.write(contentsOf: Data("{\"cmd\":\"quit\"}\n".utf8)) }
        process?.terminate()
    }

    func begin(_ id: Int) { send(header(["cmd": "begin", "id": id, "lang": "auto"])) }

    func audio(_ id: Int, _ samples: [Float]) {
        guard !samples.isEmpty else { return }
        var data = header(["cmd": "audio", "id": id, "samples": samples.count])
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        send(data)
    }

    func cancel(_ id: Int) {
        queue.async { self.pending[id] = nil }
        send(header(["cmd": "cancel", "id": id]))
    }

    func finish(_ id: Int, timeout: Double, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            self.pending[id] = completion
            self.write(self.header(["cmd": "finish", "id": id]))
            self.queue.asyncAfter(deadline: .now() + timeout) { self.fail(id, "Распознавание не ответило") }
        }
    }

    private func header(_ obj: [String: Any]) -> Data {
        var d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        d.append(0x0A)
        return d
    }

    private func send(_ data: Data) { queue.async { self.write(data) } }

    private func write(_ data: Data) {
        guard let input, process?.isRunning == true else { return }
        try? input.write(contentsOf: data)
    }

    private func fail(_ id: Int, _ message: String) {
        guard let cb = pending.removeValue(forKey: id) else { return }
        let error = NSError(domain: "Zametki", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        DispatchQueue.main.async { cb(.failure(error)) }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let event = obj["event"] as? String {
                switch event {
                case "ready":
                    // Первым грузится русская модель - с ней уже можно работать.
                    DispatchQueue.main.async { self.isReady = true }
                    emit(.ready)
                case "error": emit(.failed(obj["message"] as? String ?? "Ошибка распознавания"))
                case "partial":
                    emit(.partial(id: obj["id"] as? Int ?? -1, text: obj["text"] as? String ?? "",
                                  interim: obj["interim"] as? String ?? ""))
                default: break
                }
                continue
            }
            guard let id = obj["id"] as? Int, let cb = pending.removeValue(forKey: id) else { continue }
            let result: Result<String, Error>
            if let error = obj["error"] as? String {
                result = .failure(NSError(domain: "Zametki", code: 2, userInfo: [NSLocalizedDescriptionKey: error]))
            } else {
                result = .success(obj["text"] as? String ?? "")
            }
            DispatchQueue.main.async { cb(result) }
        }
    }

    private func reap(_ proc: Process) {
        guard proc === process else { return }
        process = nil
        input = nil
        buffer.removeAll()
        let waiting = pending
        pending.removeAll()
        let error = NSError(domain: "Zametki", code: 3, userInfo: [NSLocalizedDescriptionKey: "Распознавание остановилось"])
        for cb in waiting.values { DispatchQueue.main.async { cb(.failure(error)) } }
        DispatchQueue.main.async { self.isReady = false }
        emit(.exited)
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { self.onEvent?(event) }
    }
}

// MARK: - микрофон

/// Микрофон → 16 кГц моно float32 порциями по ~0,25 с - так их ждёт server.py.
final class MicRecorder {
    var onSamples: (([Float]) -> Void)?

    private var engine: AVAudioEngine?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var pending: [Float] = []
    private let lock = NSLock()

    func start() throws {
        // Свой движок на каждую запись: сменили микрофон между записями - подхватится новый.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: target) else {
            throw NSError(domain: "Zametki", code: 4, userInfo: [NSLocalizedDescriptionKey: "нет входа звука"])
        }
        pending.removeAll()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.convert(buffer, with: converter)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        lock.lock()
        let rest = pending
        pending.removeAll()
        lock.unlock()
        if !rest.isEmpty { onSamples?(rest) }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        lock.lock()
        pending += samples
        let ready = pending.count >= 4000
        let chunk = ready ? pending : []
        if ready { pending.removeAll(keepingCapacity: true) }
        lock.unlock()
        if ready {
            DispatchQueue.main.async { self.onSamples?(chunk) }
        }
    }
}
