import AppKit
import AVFoundation

/// Голосовые заметки: звук лежит в папке вложений (.m4a), в тексте - плашка с кнопкой, волной и длительностью.
/// Расшифровка встаёт строкой под плашкой.
enum VoiceRecording {
    /// Записать отсчёты 16 кГц моно в .m4a; вернёт имя файла во вложениях.
    static func save(_ samples: [Float], sampleRate: Double = 16_000) -> String? {
        guard !samples.isEmpty else { return nil }
        let name = UUID().uuidString.prefix(8) + "-Голосовая заметка.m4a"
        let url = Assets.url(String(name))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        do {
            // Файл дописывается и закрывается, когда file уходит из области видимости.
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return nil }
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress!, count: samples.count)
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            try file.write(from: buffer)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return String(name)
    }

    private static var cache: [String: (peaks: [Float], duration: Double)] = [:]

    /// Волна (громкость кусками, 0…1) и длительность записи в секундах.
    static func info(_ name: String) -> (peaks: [Float], duration: Double) {
        if let cached = cache[name] { return cached }
        let bars = 48
        guard let file = try? AVAudioFile(forReading: Assets.url(name)),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData?[0] else {
            return ([], 0)
        }
        let count = Int(buffer.frameLength)
        let duration = Double(count) / file.processingFormat.sampleRate
        var peaks: [Float] = []
        let step = max(count / bars, 1)
        var i = 0
        while i < count, peaks.count < bars {
            let end = min(i + step, count)
            var sum: Float = 0
            for j in i..<end { sum += channel[j] * channel[j] }
            peaks.append(sqrt(sum / Float(end - i)))
            i = end
        }
        let top = max(peaks.max() ?? 1, 0.0001)
        let result = (peaks.map { min($0 / top, 1) }, duration)
        cache[name] = result
        return result
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Проигрыватель голосовых заметок: одна играет за раз. Пока играет - редактор перерисовывает плашку.
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayer()

    private(set) var playing: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    /// Плашку нужно перерисовать: сменилась позиция или запись остановилась.
    var onChange: (() -> Void)?

    func isPlaying(_ name: String) -> Bool { playing == name && player?.isPlaying == true }

    /// Сколько уже прослушано, 0…1.
    func progress(_ name: String) -> Double {
        guard playing == name, let player, player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }

    func toggle(_ name: String) {
        if playing == name, let player {
            if player.isPlaying { player.pause(); stopTimer() } else { player.play(); startTimer() }
            onChange?()
            return
        }
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: Assets.url(name)) else { return }
        player.delegate = self
        player.play()
        self.player = player
        playing = name
        startTimer()
        onChange?()
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
        stopTimer()
        onChange?()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { stop() }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.onChange?() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

/// Плашка голосовой заметки в тексте: круглая кнопка, волна (прослушанное ярче) и время.
final class AudioCell: NSTextAttachmentCell {
    let name: String
    static let height: CGFloat = 60

    init(name: String) {
        self.name = name
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("не используется") }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: 0, y: -14, width: min(Objects.width(textContainer, lineFrag), 460), height: Self.height)
    }

    override func cellSize() -> NSSize { NSSize(width: 320, height: Self.height) }
    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let rect = frame.insetBy(dx: 0.5, dy: 4)
        let text = PageStyle.current.text.color
        let card = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.white.withAlphaComponent(0.08).setFill()
        card.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        card.lineWidth = 1
        card.stroke()

        let player = AudioPlayer.shared
        let playing = player.isPlaying(name)
        let info = VoiceRecording.info(name)

        // Кнопка: белый круг с треугольником или паузой цвета страницы.
        let d = rect.height - 14
        let button = NSRect(x: rect.minX + 7, y: rect.midY - d / 2, width: d, height: d)
        text.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: button).fill()
        PageStyle.current.baseColor.setFill()
        if playing {
            for dx in [-4.0, 2.0] {
                NSBezierPath(roundedRect: NSRect(x: button.midX + dx, y: button.midY - 6, width: 3, height: 12), xRadius: 1, yRadius: 1).fill()
            }
        } else {
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: button.midX - 3.5, y: button.midY - 7))
            tri.line(to: NSPoint(x: button.midX + 7, y: button.midY))
            tri.line(to: NSPoint(x: button.midX - 3.5, y: button.midY + 7))
            tri.close()
            tri.fill()
        }

        // Время справа: сколько осталось, пока играет, иначе вся длина.
        let progress = player.progress(name)
        let seconds = playing || progress > 0 ? info.duration * (1 - progress) : info.duration
        let label = NSAttributedString(string: info.duration > 0 ? VoiceRecording.time(seconds) : "Нет файла", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: text.withAlphaComponent(0.6),
        ])
        let labelSize = label.size()
        label.draw(at: NSPoint(x: rect.maxX - 18 - labelSize.width, y: rect.midY - labelSize.height / 2))

        // Волна между кнопкой и временем.
        let left = button.maxX + 14
        let right = rect.maxX - 30 - labelSize.width
        guard right > left, !info.peaks.isEmpty else { return }
        let count = info.peaks.count
        let step = (right - left) / CGFloat(count)
        let barWidth = max(step * 0.55, 1.5)
        for (i, peak) in info.peaks.enumerated() {
            let h = max(3, CGFloat(peak) * (rect.height - 26))
            let x = left + CGFloat(i) * step
            let played = Double(i) / Double(count) < progress
            text.withAlphaComponent(played ? 0.95 : 0.38).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: rect.midY - h / 2, width: barWidth, height: h),
                         xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}
