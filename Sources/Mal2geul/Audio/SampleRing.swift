import os

/// Fixed-size sample buffer between one writer (the audio thread) and one reader.
/// Writes never allocate; if the reader falls a full buffer behind, the oldest samples are dropped.
final class SampleRing {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let lock = UnfairLock()
    private var written = 0
    private var consumed = 0

    init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit { storage.deallocate() }

    func reset() {
        lock.lock()
        written = 0
        consumed = 0
        lock.unlock()
    }

    func write(_ samples: UnsafePointer<Float>, count: Int) {
        lock.lock()
        let start = written
        lock.unlock()
        walk(count, from: start) { offset, index, length in
            (storage + index).update(from: samples + offset, count: length)
        }
        lock.lock()
        written = start + count
        lock.unlock()
    }

    /// Everything written since the last read.
    func read() -> [Float] {
        lock.lock()
        let end = written
        let begin = max(consumed, end - capacity)
        lock.unlock()
        let count = end - begin
        guard count > 0 else { return [] }
        var output = [Float](repeating: 0, count: count)
        output.withUnsafeMutableBufferPointer { buffer in
            let destination = buffer.baseAddress!
            walk(count, from: begin) { offset, index, length in
                (destination + offset).update(from: storage + index, count: length)
            }
        }
        lock.lock()
        consumed = end
        lock.unlock()
        return output
    }

    /// Visits `count` samples from absolute position `start` in contiguous runs, splitting where the buffer wraps.
    private func walk(_ count: Int, from start: Int, _ body: (_ offset: Int, _ index: Int, _ length: Int) -> Void) {
        var offset = 0
        var index = start % capacity
        while offset < count {
            let length = min(count - offset, capacity - index)
            body(offset, index, length)
            offset += length
            index = 0
        }
    }
}

/// `os_unfair_lock` at a stable address, safe to take on the audio thread.
final class UnfairLock {
    private let pointer: os_unfair_lock_t

    init() {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    @inline(__always) func lock() { os_unfair_lock_lock(pointer) }
    @inline(__always) func unlock() { os_unfair_lock_unlock(pointer) }
}
