// Live measurements of a playback session's signal: a tap after the EQ and
// before the output volume, copied into preallocated storage, analysed with
// Accelerate on a native worker thread, published as a bounded history of
// timestamped snapshots (docs/architecture.adoc, "Audio analysis").

import AVFAudio
import Accelerate
import AppKit

/// One measurement of one analysis window. Plain Swift data, safe to hand
/// to any thread.
struct AudioSnapshot {
    /// The playback generation it belongs to (Audio.swift): a seek, a
    /// replacement or a stop starts a new one, and invalidates the old one's.
    let generation: UInt64
    /// Counts snapshots across generations, so a reader can tell new from seen.
    let seq: UInt64
    /// The source frame at the window's centre, and the source's rate.
    let centreFrame: Int64
    let sampleRate: Double
    /// Mean-square level over the window, averaged across channels, in dB
    /// relative to full scale (a full-scale square wave reads 0, a
    /// full-scale sine -3.01); the floor is -120.
    let rmsDb: Float
    /// The largest absolute sample over the window and channels, in dBFS.
    let peakDb: Float
    /// Energy per band (`AudioAnalysis.bandEdges`), in dB relative to a
    /// full-scale sine whose energy falls in one band; the floor is -120.
    let bandsDb: [Float]
    /// The window's mono signal (channels averaged) as `envelopePoints`
    /// min/max pairs, each over 64 samples, in sample units (-1...1).
    let envelopeMin: [Float]
    let envelopeMax: [Float]
    /// The window's mono signal at half its rate: `waveformPoints` values,
    /// each the mean of two samples, oldest first.
    let waveform: [Float]

    /// The window centre's place on the source timeline, in milliseconds.
    var atMs: Double { Double(centreFrame) * 1000 / sampleRate }
}

/// Where the tapped signal stands on the source timeline. The main thread
/// sets it at every change of generation and transport; the tap reads it.
struct AudioAnchor {
    var generation: UInt64 = 0
    /// Whether the player is playing from a known start: a tapped buffer
    /// otherwise is silence or of unknown place, which is left out.
    var playing = false
    /// The node time (in the tapped node's frames) the player started at,
    /// and the source frame it started from. A frame rendered before it
    /// belongs to an earlier generation or run.
    var startNode: Int64 = 0
    var startSource: Int64 = 0
    var sampleRate: Double = 44100
}

final class AudioAnalysis {
    static let window = 2048
    static let hop = 512
    static let log2n: vDSP_Length = 11
    static let bandCount = 24
    static let envelopePoints = 32
    static let waveformPoints = 1024
    /// Snapshots kept, about 350 ms at 48 kHz.
    static let historyBound = 32
    /// Tap chunks waiting for the worker, and the frames each holds.
    static let slotCount = 4
    static let slotFrames = 8192
    /// Channels measured: the first two (a mono source is one).
    static let maxChannels = 2
    /// How many times the tap tries the lock before it drops a buffer.
    static let lockAttempts = 4096
    /// Band edges in Hz: 24 bands, logarithmically spaced from 40 Hz to
    /// 16 kHz (each about a third of an octave wide, a ratio of 400^(1/24)).
    static let bandEdges: [Double] = (0...bandCount).map { 40 * pow(400, Double($0) / Double(bandCount)) }

    // MARK: Shared with the tap thread, under `lock` (the tap only tries it)

    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var anchor = AudioAnchor()
    private struct Slot { var generation: UInt64 = 0; var start: Int64 = 0; var frames = 0; var channels = 0; var rate: Double = 0 }
    private var slots = [Slot](repeating: Slot(), count: AudioAnalysis.slotCount)
    private let slotData: UnsafeMutablePointer<Float>
    private var head = 0, count = 0
    private var stalled = false
    /// Counters a spec's `expect-history` reports.
    private(set) var tapped: Int64 = 0, skipped: Int64 = 0, busy: Int64 = 0, consumed: Int64 = 0, chunkFrames = 0
    /// The newest render time a tap delivered, in the tapped node's frames.
    private var tappedTo: Int64 = .min

    // MARK: The history, under `historyLock` (the worker writes, readers copy)

    private let historyLock: UnsafeMutablePointer<os_unfair_lock>
    private var history: [AudioSnapshot] = []
    private var seq: UInt64 = 0

    // MARK: The worker's own

    private var worker: Thread?
    private var running = false
    /// Whether the worker thread has returned (under `lock`).
    private var exited = true
    private let fft: FFTSetup
    private let hann: UnsafeMutablePointer<Float>
    private let fifo: UnsafeMutablePointer<Float>
    private var fifoFrames = 0, fifoStart: Int64 = 0, fifoGeneration: UInt64 = .max, fifoChannels = 0, fifoRate: Double = 0
    private let scratch: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>, imag: UnsafeMutablePointer<Float>
    private let power: UnsafeMutablePointer<Float>
    private let fifoCapacity = AudioAnalysis.window + AudioAnalysis.slotFrames

    init() {
        func alloc(_ n: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        lock = .allocate(capacity: 1); lock.initialize(to: os_unfair_lock())
        historyLock = .allocate(capacity: 1); historyLock.initialize(to: os_unfair_lock())
        slotData = alloc(AudioAnalysis.slotCount * AudioAnalysis.slotFrames * AudioAnalysis.maxChannels)
        guard let setup = vDSP_create_fftsetup(AudioAnalysis.log2n, FFTRadix(kFFTRadix2)) else { fatal("audio analysis: cannot create the FFT setup") }
        fft = setup
        hann = alloc(AudioAnalysis.window)
        vDSP_hann_window(hann, vDSP_Length(AudioAnalysis.window), Int32(vDSP_HANN_DENORM))
        fifo = alloc((AudioAnalysis.window + AudioAnalysis.slotFrames) * AudioAnalysis.maxChannels)
        scratch = alloc(AudioAnalysis.window)
        real = alloc(AudioAnalysis.window / 2)
        imag = alloc(AudioAnalysis.window / 2)
        power = alloc(AudioAnalysis.window / 2)
    }

    deinit {
        stop()
        vDSP_destroy_fftsetup(fft)
    }

    // MARK: The main thread's side

    /// Start the worker (the first consumer arrived).
    func start() {
        if running { return }
        running = true
        exited = false
        // The thread holds the analysis until `stop` has seen it return.
        let thread = Thread { self.work() }
        thread.name = "roc-native-macos.audio-analysis"
        thread.qualityOfService = .userInitiated
        worker = thread
        thread.start()
    }

    /// Stop the worker (the last consumer left) and forget everything.
    func stop() {
        guard running else { return }
        os_unfair_lock_lock(lock)
        running = false
        head = 0; count = 0
        os_unfair_lock_unlock(lock)
        // The worker finishes at most the window it is measuring, and never
        // waits on this thread, so this wait is short and cannot deadlock.
        while true {
            os_unfair_lock_lock(lock)
            let done = exited
            os_unfair_lock_unlock(lock)
            if done { break }
            Thread.sleep(forTimeInterval: 0.001)
        }
        worker = nil
        fifoGeneration = .max
        clearHistory()
    }

    var isRunning: Bool { running }

    /// A new anchor: from now on, a tapped buffer is measured against it.
    /// A new generation clears the history, so no consumer sees the old
    /// stream's measurements after a seek or a replacement.
    func setAnchor(_ a: AudioAnchor) {
        os_unfair_lock_lock(lock)
        let fresh = a.generation != anchor.generation
        anchor = a
        if fresh { head = 0; count = 0 }
        os_unfair_lock_unlock(lock)
        if fresh { clearHistory() }
    }

    /// `audio:stall`: the worker takes nothing while stalled, as a worker
    /// that has fallen behind would, so the tap overwrites the oldest chunks.
    func setStalled(_ on: Bool) {
        os_unfair_lock_lock(lock)
        stalled = on
        os_unfair_lock_unlock(lock)
    }

    var isStalled: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return stalled
    }

    /// The history, oldest first, of the current generation only.
    func snapshots() -> [AudioSnapshot] {
        os_unfair_lock_lock(historyLock)
        defer { os_unfair_lock_unlock(historyLock) }
        return history
    }

    func latest() -> AudioSnapshot? {
        os_unfair_lock_lock(historyLock)
        defer { os_unfair_lock_unlock(historyLock) }
        return history.last
    }

    private func clearHistory() {
        os_unfair_lock_lock(historyLock)
        history.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(historyLock)
    }

    /// The counters and the ring's fill, for `audio:history`.
    func counters() -> (tapped: Int64, skipped: Int64, busy: Int64, consumed: Int64, waiting: Int, chunkFrames: Int, tappedTo: Int64) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return (tapped, skipped, busy, consumed, count, chunkFrames, tappedTo)
    }

    /// Whether the worker has measured everything tapped so far.
    var drained: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return count == 0 && !inFlight
    }
    private var inFlight = false

    // MARK: The tap's side: copy and return, never wait

    /// Called by AVAudioEngine's tap with each rendered buffer of the
    /// tapped node, `at` its render time in the node's frames. It calls
    /// nothing of AVFAudio's: the anchor alone places the buffer on the
    /// source timeline (asking the player from here would wait on the
    /// player's lock, which the main thread holds while it stops the player
    /// and waits for this tap).
    func tap(_ buffer: AVAudioPCMBuffer, at: Int64) {
        // The main thread and the worker hold the lock only to copy a few
        // values or one chunk. Try it a bounded number of times, never
        // blocking; if it is still held, drop the buffer rather than wait.
        var attempts = 0
        while !os_unfair_lock_trylock(lock) {
            attempts += 1
            if attempts == AudioAnalysis.lockAttempts {
                busy += 1  // a benign race: counted only for the report
                return
            }
        }
        defer { os_unfair_lock_unlock(lock) }
        let frames = Int(buffer.frameLength)
        chunkFrames = frames
        tappedTo = max(tappedTo, at + Int64(frames))
        tapped += 1
        guard running, anchor.playing, let data = buffer.floatChannelData else { return }
        // The source frame of the buffer's first sample: the player's
        // time there (negative before it started) after the segment's start.
        // The source frame of the buffer's first sample, and what of it was
        // rendered before the player started.
        let first = anchor.startSource + (at - anchor.startNode)
        let skip = Int(max(0, min(Int64(frames), anchor.startNode - at)))
        guard skip < frames else { return }
        let channels = min(Int(buffer.format.channelCount), AudioAnalysis.maxChannels)
        var offset = skip
        while offset < frames {
            let n = min(frames - offset, AudioAnalysis.slotFrames)
            let index: Int
            if count == AudioAnalysis.slotCount {
                // The worker is behind: the oldest chunk is overwritten.
                index = head
                head = (head + 1) % AudioAnalysis.slotCount
                skipped += 1
            } else {
                index = (head + count) % AudioAnalysis.slotCount
                count += 1
            }
            slots[index] = Slot(generation: anchor.generation, start: first + Int64(offset), frames: n, channels: channels, rate: buffer.format.sampleRate)
            for c in 0..<channels {
                (slotData + (index * AudioAnalysis.maxChannels + c) * AudioAnalysis.slotFrames).update(from: data[c] + offset, count: n)
            }
            offset += n
        }
    }

    // MARK: The worker

    private func work() {
        while true {
            os_unfair_lock_lock(lock)
            if !running { exited = true; os_unfair_lock_unlock(lock); return }
            var taken: Slot?
            let generation = anchor.generation
            if !stalled, count > 0 {
                let index = head
                taken = slots[index]
                let s = slots[index]
                for c in 0..<s.channels {
                    (fifoInput + c * AudioAnalysis.slotFrames).update(from: slotData + (index * AudioAnalysis.maxChannels + c) * AudioAnalysis.slotFrames, count: s.frames)
                }
                head = (head + 1) % AudioAnalysis.slotCount
                count -= 1
                consumed += 1
                inFlight = true
            }
            os_unfair_lock_unlock(lock)
            guard let slot = taken else {
                Thread.sleep(forTimeInterval: 0.004)
                continue
            }
            if slot.generation == generation { measure(slot) }
            os_unfair_lock_lock(lock)
            inFlight = false
            os_unfair_lock_unlock(lock)
        }
    }

    private lazy var fifoInput: UnsafeMutablePointer<Float> = {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: AudioAnalysis.slotFrames * AudioAnalysis.maxChannels)
        p.initialize(repeating: 0, count: AudioAnalysis.slotFrames * AudioAnalysis.maxChannels)
        return p
    }()

    /// Append a chunk to the rolling window and measure every full window,
    /// one hop apart. A chunk that does not continue the last one (a new
    /// generation, a resume after a pause, a dropped chunk) starts again.
    private func measure(_ s: Slot) {
        if s.generation != fifoGeneration || s.start != fifoStart + Int64(fifoFrames) || s.channels != fifoChannels || s.rate != fifoRate {
            fifoGeneration = s.generation
            fifoStart = s.start
            fifoFrames = 0
            fifoChannels = s.channels
            fifoRate = s.rate
        }
        for c in 0..<s.channels {
            (fifo + c * fifoCapacity + fifoFrames).update(from: fifoInput + c * AudioAnalysis.slotFrames, count: s.frames)
        }
        fifoFrames += s.frames
        var at = 0
        while fifoFrames - at >= AudioAnalysis.window {
            snapshot(offset: at)
            at += AudioAnalysis.hop
        }
        if at > 0 {
            for c in 0..<fifoChannels {
                let base = fifo + c * fifoCapacity
                base.update(from: base + at, count: fifoFrames - at)
            }
            fifoFrames -= at
            fifoStart += Int64(at)
        }
    }

    private func snapshot(offset: Int) {
        let n = AudioAnalysis.window, half = n / 2
        let channels = max(fifoChannels, 1)
        var meanSquare: Float = 0, peak: Float = 0
        var bins = [Float](repeating: 0, count: half)
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            let x = fifo + c * fifoCapacity + offset
            var ms: Float = 0, mx: Float = 0
            vDSP_measqv(x, 1, &ms, vDSP_Length(n))
            vDSP_maxmgv(x, 1, &mx, vDSP_Length(n))
            meanSquare += ms / Float(channels)
            peak = max(peak, mx)
            mono.withUnsafeMutableBufferPointer { m in vDSP_vadd(m.baseAddress!, 1, x, 1, m.baseAddress!, 1, vDSP_Length(n)) }
            // Hann window, then a real FFT of 2048 points.
            vDSP_vmul(x, 1, hann, 1, scratch, 1, vDSP_Length(n))
            var split = DSPSplitComplex(realp: real, imagp: imag)
            scratch.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half)) }
            vDSP_fft_zrip(fft, &split, 1, AudioAnalysis.log2n, FFTDirection(kFFTDirection_Forward))
            // Bin 0 packs DC (real) with Nyquist (imaginary): keep DC only.
            imag[0] = 0
            vDSP_zvmags(&split, 1, power, 1, vDSP_Length(half))
            // Channel powers are averaged, so opposite-phase stereo registers.
            for k in 0..<half { bins[k] += power[k] / Float(channels) }
        }
        // vDSP_fft_zrip's output is twice the DFT's, and a Hann-windowed sine
        // of amplitude A has a one-sided energy of 3 A² N² / 32 in the DFT:
        // a full-scale sine's energy reads 1 (0 dB).
        let norm = Float(3 * n * n) / 8
        let rate = fifoRate
        let width = rate / Double(n)
        var bands = [Float](repeating: 0, count: AudioAnalysis.bandCount)
        for b in 0..<AudioAnalysis.bandCount {
            let lo = AudioAnalysis.bandEdges[b], hi = min(AudioAnalysis.bandEdges[b + 1], rate / 2)
            var sum: Double = 0
            if hi > lo {
                // A bin spans ±half a bin around its frequency; a band takes
                // the share of each bin its range overlaps, so a band
                // narrower than a bin still reads the energy there.
                let first = max(1, Int((lo / width - 0.5).rounded(.down))), last = min(half - 1, Int((hi / width + 0.5).rounded(.up)))
                if first <= last {
                    for k in first...last {
                        let a = (Double(k) - 0.5) * width, z = (Double(k) + 0.5) * width
                        let overlap = max(0, min(z, hi) - max(a, lo)) / width
                        sum += Double(bins[k]) * overlap
                    }
                }
            }
            bands[b] = AudioAnalysis.db(Float(sum) / norm, power: true)
        }
        var lows = [Float](repeating: 0, count: AudioAnalysis.envelopePoints), highs = lows
        let per = n / AudioAnalysis.envelopePoints
        let scale = 1 / Float(channels)
        for p in 0..<AudioAnalysis.envelopePoints {
            var lo: Float = .greatestFiniteMagnitude, hi: Float = -.greatestFiniteMagnitude
            for i in (p * per)..<((p + 1) * per) { let v = mono[i] * scale; lo = min(lo, v); hi = max(hi, v) }
            lows[p] = lo; highs[p] = hi
        }
        let step = n / AudioAnalysis.waveformPoints
        var wave = [Float](repeating: 0, count: AudioAnalysis.waveformPoints)
        for p in 0..<AudioAnalysis.waveformPoints {
            var sum: Float = 0
            for i in (p * step)..<((p + 1) * step) { sum += mono[i] }
            wave[p] = sum * scale / Float(step)
        }
        let centre = fifoStart + Int64(offset + n / 2)
        os_unfair_lock_lock(historyLock)
        seq += 1
        let snap = AudioSnapshot(generation: fifoGeneration, seq: seq, centreFrame: centre, sampleRate: rate, rmsDb: AudioAnalysis.db(meanSquare, power: true), peakDb: AudioAnalysis.db(peak, power: false), bandsDb: bands, envelopeMin: lows, envelopeMax: highs, waveform: wave)
        if history.count >= AudioAnalysis.historyBound { history.removeFirst() }
        history.append(snap)
        os_unfair_lock_unlock(historyLock)
    }

    /// A power or an amplitude in dB, never below -120.
    static func db(_ v: Float, power: Bool) -> Float {
        guard v.isFinite, v > 0 else { return -120 }
        return max(-120, (power ? 10 : 20) * log10(v))
    }

    /// The band (0–23) holding `hz`, if any.
    static func band(of hz: Double) -> Int? { (0..<bandCount).first { bandEdges[$0] <= hz && hz < bandEdges[$0 + 1] } }
}
