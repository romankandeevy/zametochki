import AVFoundation

/// Мягкий щелчок при печати. Звук синтезируется в коде - никаких файлов и сети.
/// Движок запускается на первой клавише и гасится через пару секунд тишины, чтобы не есть батарею.
final class TypingSound {
    enum Key { case letter, space, enter, delete }

    static let shared = TypingSound()

    private let engine = AVAudioEngine()
    private let players = (0..<6).map { _ in AVAudioPlayerNode() }
    private var next = 0
    private var buffers: [Key: [AVAudioPCMBuffer]] = [:]
    private var idleStop: DispatchWorkItem?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {
        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = 0.55
        // У каждой клавиши несколько вариантов, чтобы серия нажатий не звучала как пулемёт.
        buffers[.letter] = (0..<5).map { make(thump: 210 + Double($0) * 14, click: 0.9, length: 0.045, seed: $0) }
        buffers[.space] = (0..<3).map { make(thump: 150 + Double($0) * 8, click: 0.7, length: 0.06, seed: 10 + $0) }
        buffers[.enter] = (0..<2).map { make(thump: 120 + Double($0) * 6, click: 0.8, length: 0.07, seed: 20 + $0) }
        buffers[.delete] = (0..<3).map { make(thump: 260 + Double($0) * 12, click: 0.55, length: 0.035, seed: 30 + $0) }
    }

    func play(_ key: Key) {
        guard let variants = buffers[key], let buffer = variants.randomElement() else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let player = players[next]
        next = (next + 1) % players.count
        player.stop()
        player.volume = Float.random(in: 0.75...1)
        player.scheduleBuffer(buffer)
        player.play()

        idleStop?.cancel()
        let stop = DispatchWorkItem { [weak self] in self?.engine.pause() }
        idleStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: stop)
    }

    /// Короткий приглушённый «тук»: низкий тон с быстрым затуханием плюс мягкий шумовой щелчок сверху.
    private func make(thump: Double, click: Double, length: Double, seed: Int) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        var rng = UInt64(seed &+ 1) &* 0x9E37_79B9_7F4A_7C15
        var lowpassed = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            let noise = Double(rng % 20_000) / 10_000 - 1
            // Однополюсный фильтр срезает верха: щелчок «войлочный», а не трескучий.
            lowpassed += (noise - lowpassed) * 0.22
            let attack = min(1, t / 0.0015)
            let body = sin(2 * .pi * thump * t) * exp(-t / 0.011) * 0.55
            let tick = lowpassed * exp(-t / 0.0035) * click
            out[i] = Float((body + tick) * attack * 0.5)
        }
        return buffer
    }
}
