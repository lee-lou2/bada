import Foundation

/// Loudness handed from the audio thread to the screen.
final class LevelMeter {
    /// About -45 dBFS: quiet speech clears it, room tone and keyboard clicks do not.
    static let speakingRMS: Float = 0.0056

    /// Sample rate of the frames passed to `feed`, for turning frames into seconds.
    var sampleRate: Double = 48_000

    private let lock = UnfairLock()
    private var loudestSinceRead: Float = 0
    private var voicedFrames = 0

    func reset() {
        lock.lock()
        loudestSinceRead = 0
        voicedFrames = 0
        lock.unlock()
    }

    /// Called on the audio thread for every slice.
    func feed(rms: Float, frames: Int) {
        lock.lock()
        loudestSinceRead = max(loudestSinceRead, rms)
        if rms > LevelMeter.speakingRMS { voicedFrames += frames }
        lock.unlock()
    }

    /// Loudest level since the previous call, 0...1 on the waveform's scale.
    func read() -> Float {
        lock.lock()
        let rms = loudestSinceRead
        loudestSinceRead = 0
        lock.unlock()
        return LevelMeter.level(rms)
    }

    /// Time spent above speaking level in the current take.
    var voicedSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(voicedFrames) / sampleRate
    }

    /// dBFS mapped onto the bars: room noise sits at 0, normal speech fills most of the range.
    static func level(_ rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-7))
        let position = (db + 54) / 36
        return pow(min(max(position, 0), 1), 1.2)
    }
}
