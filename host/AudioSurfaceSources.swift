// The playback session's measurements as drawing-surface sources
// (SurfaceSource.swift): `audio.waveform`, `audio.left`, `audio.right`, `audio.bands`, `audio.level`,
// `audio.bass`, `audio.mids` and `audio.treble`. A surface samples them on
// the main thread each frame; the analysis worker publishes into the
// history under its own lock (AudioAnalysis.swift), so a sample only copies
// the snapshot nearest the audible playhead. Sampling keeps the analysis on
// (AudioService.sampledNatively), and a second without a sample releases it.

import AppKit

final class AudioSurfaceSource: SurfaceSource {
    enum Kind { case waveform, left, right, bands, level, bass, mids, treble }
    let name: String
    private let kind: Kind
    private weak var audio: AudioService?
    /// The display values, for the fast rise and slow fall.
    private var shown: [Float] = []
    private var shownAt: Double = 0
    private var generation: UInt64 = .max

    /// The display range: -60 dB maps to 0 and 0 dB to 1.
    static let floorDb: Float = -60
    /// How fast a display value falls, in display units per second (a full
    /// meter falls in about 0.7 s); it rises at once.
    static let fallPerSecond: Float = 1.5
    /// The analysis bands (AudioAnalysis.bandEdges) each summary sums:
    /// bass 40–229 Hz, mids 229–3577 Hz, treble 3577 Hz–16 kHz.
    static let bass = 0..<7, mids = 7..<18, treble = 18..<24

    init(_ kind: Kind, audio: AudioService) {
        self.kind = kind
        self.audio = audio
        switch kind {
        case .waveform: name = "audio.waveform"
        case .left: name = "audio.left"
        case .right: name = "audio.right"
        case .bands: name = "audio.bands"
        case .level: name = "audio.level"
        case .bass: name = "audio.bass"
        case .mids: name = "audio.mids"
        case .treble: name = "audio.treble"
        }
    }

    /// `audio.waveform`: the window's mono signal (channels averaged), 1024
    /// values in -1…1, oldest first; `audio.left` and `audio.right`: the first
    /// and second channels alone, the same way (a mono source's are both its
    /// one channel). `audio.bands`: the 24 band energies in
    /// 0…1. `audio.level`: the RMS level; `audio.bass`, `audio.mids` and
    /// `audio.treble`: the energy of their bands, each in 0…1. A value is
    /// -60…0 dB mapped to 0…1, rising at once and falling slowly. Each is the
    /// snapshot whose window ends at the sound heard at `frameTime`
    /// (`ProcessInfo.systemUptime` seconds: when the frame will be seen;
    /// `AudioService.audibleSnapshot`). Nil before the first
    /// measurement of the current generation (after a seek or a replacement).
    func latest(at frameTime: Double) -> SurfaceSample? {
        guard let audio else { return nil }
        audio.sampledNatively()
        // A spec's controlled frame clock is not the audio's: it reads now.
        guard let snap = audio.audibleSnapshot(at: FrameClock.shared.manual ? Bench.now() : frameTime) else {
            shown = []
            return nil
        }
        switch kind {
        case .waveform:
            return .series(snap.waveform)
        case .left:
            return .series(snap.left.isEmpty ? snap.waveform : snap.left)
        case .right:
            return .series(snap.right.isEmpty ? snap.waveform : snap.right)
        case .bands:
            return .series(smoothed(snap.bandsDb, snap.generation, frameTime))
        case .level:
            return smoothed([snap.rmsDb], snap.generation, frameTime).first.map { .scalar($0) }
        case .bass, .mids, .treble:
            let range = kind == .bass ? AudioSurfaceSource.bass : kind == .mids ? AudioSurfaceSource.mids : AudioSurfaceSource.treble
            let energy = Float(range.reduce(0.0) { sum, b in sum + exp2(Double(snap.bandsDb[b]) * 0.332_192_809_488_736_2) })  // 10^(dB/10)
            return smoothed([AudioAnalysis.db(energy, power: true)], snap.generation, frameTime).first.map { .scalar($0) }
        }
    }

    private func smoothed(_ db: [Float], _ gen: UInt64, _ at: Double) -> [Float] {
        let target = db.map { min(max(($0 - AudioSurfaceSource.floorDb) / -AudioSurfaceSource.floorDb, 0), 1) }
        if gen != generation || shown.count != target.count {
            generation = gen
            shown = target
        } else {
            let fall = Float(max(at - shownAt, 0)) * AudioSurfaceSource.fallPerSecond
            shown = zip(shown, target).map { old, new in max(new, old - fall) }
        }
        shownAt = at
        return shown
    }
}

enum AudioSurfaceSources {
    static let names = ["audio.waveform", "audio.left", "audio.right", "audio.bands", "audio.level", "audio.bass", "audio.mids", "audio.treble"]

    /// Register the sources for `audio` (when the host starts).
    static func register(_ audio: AudioService, in registry: SurfaceSources = .shared) {
        for kind in [AudioSurfaceSource.Kind.waveform, .left, .right, .bands, .level, .bass, .mids, .treble] {
            registry.register(AudioSurfaceSource(kind, audio: audio))
        }
    }

    /// Unregister them (at quit and reload).
    static func unregister(in registry: SurfaceSources = .shared) {
        for name in names { registry.unregister(name) }
    }

    /// The transport moved without new measurements (a pause, a seek, a
    /// replacement): on-demand surfaces that read the sources redraw.
    static func changed(in registry: SurfaceSources = .shared) {
        for name in names { registry.changed(name) }
    }
}
