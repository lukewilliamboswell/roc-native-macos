// Scripted steps for the playback session (`audio:…`), so a recorded case
// drives and measures it without speakers (docs/apps.adoc, "Steps").

import AppKit

extension Host {
    /// `audio:manual`, `audio:render:MS`, `audio:status`, `audio:tone:HZ`,
    /// `audio:snapshot`, `audio:history`, `audio:eq`, `audio:sources`,
    /// `audio:stall:on|off`.
    func audioStep(_ arg: String) {
        let parts = arg.split(separator: ":", maxSplits: 1).map(String.init)
        let verb = parts.first ?? "", value = parts.count > 1 ? parts[1] : ""
        switch verb {
        case "manual":
            // The manual clock: render offline at 48 kHz, only when a
            // step says so. Before the first audio command.
            audio.manual = true
        case "render":
            guard let ms = Int(value), ms > 0 else { fatal("script: audio:render needs milliseconds, not \(value)") }
            audio.render(ms: ms)
        case "status":
            say("audio: \(audio.state.rawValue) at \(audio.ms(audio.frame())) ms of \(audio.ms(audio.durationFrames)) ms (track \(audio.track), \(audio.endings) ended, analysis \(audio.analysis.isRunning ? "on" : "off"))\(audio.manual ? "" : "; output latency \(Int((audio.outputLatency * 1000).rounded())) ms")")
        case "tone":
            guard let hz = Double(value), hz > 0 else { fatal("script: audio:tone needs a frequency in Hz, not \(value)") }
            let samples = audio.rendered.suffix(4096)
            guard samples.count == 4096 else { fatal("script: audio:tone needs at least 86 ms rendered by the last audio:render") }
            let db = Host.toneLevel(Array(samples), hz: hz, rate: AudioService.manualRate)
            say("audio: output at \(Int(hz)) Hz \(db.isFinite ? "\(Int(db.rounded())) dBFS" : "silent")")
        case "snapshot":
            guard let s = audio.analysis.latest() else { say("audio: no snapshot"); return }
            let finite = ([s.rmsDb, s.peakDb] + s.bandsDb + s.envelopeMin + s.envelopeMax).allSatisfy { $0.isFinite }
            let loud = s.bandsDb.enumerated().filter { $0.element > -60 }.sorted { $0.element > $1.element }.prefix(2).map { $0.offset }.sorted()
            let bands = loud.isEmpty ? "no band above -60 dB" : "loudest " + loud.map { b in
                "band \(b) (\(Int(AudioAnalysis.bandEdges[b]))–\(Int(AudioAnalysis.bandEdges[b + 1])) Hz) \(Int(s.bandsDb[b].rounded())) dB"
            }.joined(separator: ", ")
            say("audio: snapshot at \(Host.tenths(s.atMs)) ms of \(Int(s.sampleRate)) Hz: rms \(Int(s.rmsDb.rounded())) dB, peak \(Int(s.peakDb.rounded())) dB, \(finite ? "all finite" : "NOT FINITE"); \(bands)")
        case "history":
            let h = audio.analysis.snapshots()
            let c = audio.analysis.counters()
            let current = h.allSatisfy { $0.generation == audio.generation }
            let span = h.isEmpty ? "empty" : "\(Host.tenths(h.first!.atMs))–\(Host.tenths(h.last!.atMs)) ms"
            let ordered = zip(h, h.dropFirst()).allSatisfy { $0.centreFrame < $1.centreFrame }
            say("audio: history \(h.count) of \(AudioAnalysis.historyBound) (\(span)), \(current ? "current generation only" : "MIXED GENERATIONS"), \(ordered ? "in order" : "OUT OF ORDER"); ring \(c.waiting) of \(AudioAnalysis.slotCount) chunks waiting, \(c.skipped > 0 ? "older chunks skipped" : "none skipped")\(audio.manual ? "" : "; \(Int(c.tapped)) taps of \(c.chunkFrames) frames, newest \(h.last.map { Host.tenths($0.atMs) } ?? "-") ms with the playhead at \(audio.ms(audio.frame())) ms")")
        case "eq":
            let gains = audio.gains.map { g in Int(g.rounded()) == 0 ? "0" : "\(Int(g.rounded()))" }.joined(separator: " ")
            say("audio: eq \(audio.bypass ? "bypassed" : "on"), preamp \(Int(audio.preamp.rounded())) dB, bands \(gains) dB, volume \(Int((audio.volume * 100).rounded()))%")
        case "sources":
            // What a drawing surface would read now from each audio source.
            let parts = AudioSurfaceSources.names.map { name -> String in
                switch SurfaceSources.shared.source(name)?.latest(at: Bench.now()) {
                case .series(let v)?: return "\(name) \(v.count) values in \(Host.hundredths(v.min() ?? 0))…\(Host.hundredths(v.max() ?? 0))"
                case .scalar(let v)?: return "\(name) \(Host.hundredths(v))"
                case nil: return "\(name) none"
                }
            }
            say("audio: sources " + parts.joined(separator: ", "))
        case "stall":
            guard value == "on" || value == "off" else { fatal("script: audio:stall needs on or off, not \(value)") }
            audio.analysis.setStalled(value == "on")
        default:
            fatal("script: unknown audio step \(arg)")
        }
    }

    /// The level of the `hz` component of `x`, in dBFS (a full-scale sine
    /// reads 0): a Hann-windowed Goertzel filter.
    static func toneLevel(_ x: [Float], hz: Double, rate: Double) -> Double {
        let n = x.count
        let w = 2 * Double.pi * hz / rate, c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for i in 0..<n {
            let win = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n - 1))
            let s = Double(x[i]) * win + c * s1 - s2
            s2 = s1
            s1 = s
        }
        let p = s1 * s1 + s2 * s2 - c * s1 * s2
        let amplitude = p.squareRoot() * 2 / (Double(n) * 0.5)
        return amplitude > 1e-7 ? 20 * log10(amplitude) : -.infinity
    }

    static func hundredths(_ v: Float) -> String {
        let t = Int((Double(v) * 100).rounded())
        let r = abs(t % 100)
        return "\(t < 0 ? "-" : "")\(abs(t / 100)).\(r < 10 ? "0" : "")\(r)"
    }

    static func tenths(_ v: Double) -> String {
        let t = Int((v * 10).rounded())
        return "\(t / 10).\(abs(t % 10))"
    }
}
