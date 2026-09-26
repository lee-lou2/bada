import AVFoundation
import CoreAudio

/// Records the microphone as 16 kHz mono for the speech engine.
///
/// Audio arrives in ~10 ms slices on the real-time thread, goes through a lock-light ring buffer,
/// and is resampled on a private queue. Takes longer than ~24 s are cut at a pause and handed off
/// as they happen, so transcription finishes soon after the user stops, however long they spoke.
final class Recorder {
    struct Take {
        /// Audio after the last handed-off segment.
        var tail: [Float]
        var seconds: Double
        /// Time spent above speaking level. Near zero for silence, hum and clicks.
        var voicedSeconds: Double
    }

    enum Failure: LocalizedError {
        case noInput
        case deviceUnavailable

        var errorDescription: String? {
            switch self {
            case .noInput: return "입력 장치가 없어요"
            case .deviceUnavailable: return "고른 마이크를 열 수 없어요"
            }
        }
    }

    static let sampleRate: Double = 16_000

    /// A finished segment of a long take. Called on the main queue.
    var onSegment: (([Float]) -> Void)?
    /// The input device went away and could not be reopened. Called on the main queue.
    var onDeviceLost: (() -> Void)?

    let meter = LevelMeter()

    private static let longestSegment = Int(24 * sampleRate)
    private static let shortestSegment = Int(15 * sampleRate)
    private static let maxRestarts = 3

    private let queue = DispatchQueue(label: "app.bada.recorder", qos: .userInitiated)
    private let ring = SampleRing(capacity: 1 << 20)
    private let scratchCapacity = 16_384
    private let scratch: UnsafeMutablePointer<Float>
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Recorder.sampleRate, channels: 1, interleaved: false)!

    // Owned by `queue`.
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var pending: [Float] = []
    private var producedFrames = 0
    private var drainTimer: DispatchSourceTimer?
    private var configurationObserver: NSObjectProtocol?
    private var deviceUID: String?
    private var restarts = 0

    init() {
        scratch = .allocate(capacity: scratchCapacity)
        scratch.initialize(repeating: 0, count: scratchCapacity)
    }

    deinit { scratch.deallocate() }

    /// Opens the microphone (`nil` = system default). Completion runs on the main queue.
    func start(deviceUID: String?, completion: @escaping (Error?) -> Void) {
        queue.async {
            self.deviceUID = deviceUID
            self.restarts = 0
            do {
                try self.open(continuing: false)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                self.close()
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    /// Stops and returns what has not been handed off yet. Completion runs on the main queue.
    func stop(completion: @escaping (Take) -> Void) {
        queue.async {
            self.stopTimer()
            self.engine?.stop()
            self.drain(final: true)
            let take = Take(
                tail: self.pending,
                seconds: Double(self.producedFrames) / Recorder.sampleRate,
                voicedSeconds: self.meter.voicedSeconds
            )
            self.close()
            DispatchQueue.main.async { completion(take) }
        }
    }

    func cancel() {
        queue.async {
            self.stopTimer()
            self.engine?.stop()
            self.close()
        }
    }

    // MARK: Capture

    /// `continuing` keeps the audio gathered so far, for reopening after a device change.
    private func open(continuing: Bool) throws {
        close()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID {
            guard var device = AudioDevices.deviceID(forUID: deviceUID), let unit = input.audioUnit else {
                throw Failure.deviceUnavailable
            }
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &device, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else { throw Failure.deviceUnavailable }
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.noInput }
        try prepareConversion(from: format.sampleRate, continuing: continuing)

        let sink = AVAudioSinkNode(receiverBlock: makeReceiver())
        engine.attach(sink)
        engine.connect(input, to: sink, format: format)
        engine.prepare()
        let opening = Date()
        try engine.start()
        self.engine = engine

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.reopenAfterDeviceChange() }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.drain(final: false) }
        timer.resume()
        drainTimer = timer
        Log.info(String(format: "mic %d Hz × %d, opened in %.2fs", Int(format.sampleRate), format.channelCount, Date().timeIntervalSince(opening)))
    }

    /// Real-time callback: downmix to mono, measure loudness, copy into the ring. No allocation.
    private func makeReceiver() -> AVAudioSinkNodeReceiverBlock {
        let ring = self.ring
        let meter = self.meter
        let scratch = self.scratch
        let capacity = scratchCapacity
        return { _, frameCount, list -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            guard let first = buffers.first?.mData else { return noErr }
            let interleaved = buffers.count == 1 && buffers[0].mNumberChannels > 1
            let stride = interleaved ? Int(buffers[0].mNumberChannels) : 1
            let left = first.assumingMemoryBound(to: Float.self)
            let right = (!interleaved && buffers.count > 1 ? buffers[1].mData : nil)?.assumingMemoryBound(to: Float.self)
            var offset = 0
            while offset < Int(frameCount) {
                let count = min(Int(frameCount) - offset, capacity)
                var energy: Float = 0
                for i in 0..<count {
                    let frame = offset + i
                    let sample: Float
                    if interleaved {
                        sample = (left[frame * stride] + left[frame * stride + 1]) * 0.5
                    } else if let right {
                        sample = (left[frame] + right[frame]) * 0.5
                    } else {
                        sample = left[frame]
                    }
                    scratch[i] = sample
                    energy += sample * sample
                }
                meter.feed(rms: (energy / Float(count)).squareRoot(), frames: count)
                ring.write(scratch, count: count)
                offset += count
            }
            return noErr
        }
    }

    private func prepareConversion(from sampleRate: Double, continuing: Bool) throws {
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: mono, to: outputFormat) else { throw Failure.noInput }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        ring.reset()
        if !continuing {
            meter.reset()
            pending = []
            pending.reserveCapacity(Int(Recorder.sampleRate) * 30)
            producedFrames = 0
        }
        meter.sampleRate = sampleRate
        self.converter = converter
        inputFormat = mono
    }

    /// The hardware changed under us (device switch, AirPods changing mode). Keep the take going.
    private func reopenAfterDeviceChange() {
        guard engine != nil else { return }
        stopTimer()
        engine?.stop()
        drain(final: true)
        restarts += 1
        Log.info("input changed, reopening (\(restarts))")
        do {
            guard restarts <= Recorder.maxRestarts else { throw Failure.noInput }
            try open(continuing: true)
        } catch {
            close()
            DispatchQueue.main.async { [weak self] in self?.onDeviceLost?() }
        }
    }

    private func stopTimer() {
        drainTimer?.cancel()
        drainTimer = nil
    }

    private func close() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine = nil
        converter = nil
        inputFormat = nil
    }

    // MARK: Resampling

    /// Moves captured audio through the resampler, then hands off a segment if the take is long.
    private func drain(final: Bool) {
        guard let converter, let inputFormat else { return }
        let chunk = ring.read()
        if chunk.isEmpty && !final { return }

        var input: AVAudioPCMBuffer?
        if !chunk.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(chunk.count)) {
            buffer.frameLength = AVAudioFrameCount(chunk.count)
            chunk.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: chunk.count) }
            input = buffer
        }
        let capacity = AVAudioFrameCount(Double(chunk.count) * outputFormat.sampleRate / inputFormat.sampleRate) + 2048
        var supplied = false
        while let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if !supplied, let input {
                    supplied = true
                    state.pointee = .haveData
                    return input
                }
                state.pointee = final ? .endOfStream : .noDataNow
                return nil
            }
            if output.frameLength > 0, let samples = output.floatChannelData?[0] {
                pending.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
                producedFrames += Int(output.frameLength)
            }
            if status != .haveData { break }
        }

        if pending.count >= Recorder.longestSegment {
            let cut = Recorder.quietestPoint(in: pending, from: Recorder.shortestSegment, to: Recorder.longestSegment)
            let segment = Array(pending[..<cut])
            pending.removeFirst(cut)
            DispatchQueue.main.async { [weak self] in self?.onSegment?(segment) }
        }
    }

    // MARK: Helpers

    /// Drops silence before the first and after the last spoken moment, keeping a little air.
    /// Long silent stretches are where recognizers invent words.
    static func trimmingSilence(_ samples: [Float], leading: Bool, trailing: Bool) -> [Float] {
        let window = Int(0.02 * sampleRate)
        guard samples.count > window * 4 else { return samples }
        let threshold = LevelMeter.speakingRMS * LevelMeter.speakingRMS * Float(window)
        var first: Int?
        var last: Int?
        var position = 0
        while position + window <= samples.count {
            var energy: Float = 0
            for i in position..<(position + window) { energy += samples[i] * samples[i] }
            if energy > threshold {
                if first == nil { first = position }
                last = position + window
            }
            position += window
        }
        guard let first, let last else { return samples }
        let start = leading ? max(0, first - Int(0.3 * sampleRate)) : 0
        let end = trailing ? min(samples.count, last + Int(0.45 * sampleRate)) : samples.count
        return start < end ? Array(samples[start..<end]) : samples
    }

    /// Center of the quietest 0.3 s window between `lower` and `upper`, so a cut lands between words.
    static func quietestPoint(in samples: [Float], from lower: Int, to upper: Int) -> Int {
        let window = Int(0.3 * sampleRate)
        let step = Int(0.05 * sampleRate)
        var best = upper
        var lowest = Float.greatestFiniteMagnitude
        var position = lower
        while position + window <= min(upper, samples.count) {
            var energy: Float = 0
            for i in position..<(position + window) { energy += samples[i] * samples[i] }
            if energy < lowest {
                lowest = energy
                best = position + window / 2
            }
            position += step
        }
        return max(1, min(best, samples.count))
    }
}
