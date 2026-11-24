// A spec's steps for the playback session, so a spec drives and measures it
// without speakers (cli/Spec.roc, docs/apps.adoc, "Steps").

import AppKit

extension Host {
    /// The audio steps and expectations; nil for a verb that is not one.
    /// Each expectation prints its report as `name value` lines.
    func audioStep(_ line: SpecSteps.Line) -> Performed? {
        let f = line.fields
        func report(_ pairs: [(String, String)]) {
            emit("@\(line.k) obs")
            for (name, value) in pairs { emit("|\(name) \(SpecSteps.escape(value))") }
        }
        switch line.verb {
        case "render":
            guard audio.manual else { return .failed("render needs (audio-clock manual) in the spec's setup", nil) }
            guard let ms = Int(f.first ?? ""), ms > 0 else { return .failed("render needs milliseconds", nil) }
            audio.render(ms: ms)
        case "slide":
            // The slider moved to a value, as a drag ending there would leave it.
            let (parts, rest) = Host.locator(f)
            let found = locate(parts)
            guard found.nodes.count == 1, let s = found.nodes[0].view as? NSSlider else {
                return .failed("found \(found.nodes.isEmpty ? "no" : "\(found.nodes.count) of") \(Host.describe(parts)), looking for a slider; a step acts on exactly one", found)
            }
            guard let value = Double(rest.first ?? "") else { return .failed("slide needs a value", nil) }
            s.doubleValue = value
            slid(s)
        case "stall-analysis":
            audio.analysis.setStalled(f.first == "true")
        case "audio-status":
            report([("state", audio.state.rawValue), ("position", "\(audio.ms(audio.frame()))"), ("duration", "\(audio.ms(audio.durationFrames))"), ("track", "\(audio.track)"), ("ended", "\(audio.endings)"), ("analysis", "\(audio.analysis.isRunning)")])
        case "tone":
            guard let hz = Double(f.first ?? ""), hz > 0 else { return .failed("tone needs a frequency in Hz", nil) }
            let samples = audio.rendered.suffix(4096)
            guard samples.count == 4096 else { return .failed("tone needs at least 86 ms rendered by the last (render MS)", nil) }
            let db = Host.toneLevel(Array(samples), hz: hz, rate: AudioService.manualRate)
            report([("level", db.isFinite ? "\(Int(db.rounded()))" : "silent")])
        case "snapshot":
            guard let s = audio.analysis.latest() else { report([("present", "false")]); return .next }
            let finite = ([s.rmsDb, s.peakDb] + s.bandsDb + s.envelopeMin + s.envelopeMax).allSatisfy { $0.isFinite }
            let loud = s.bandsDb.enumerated().filter { $0.element > -60 }.sorted { $0.element > $1.element }.prefix(2).map { $0.offset }.sorted()
            let loudest = loud.isEmpty ? "none" : loud.map { "\($0) \(Int(s.bandsDb[$0].rounded()))" }.joined(separator: ", ")
            report([("present", "true"), ("at", Host.tenths(s.atMs)), ("rate", "\(Int(s.sampleRate))"), ("rms", "\(Int(s.rmsDb.rounded()))"), ("peak", "\(Int(s.peakDb.rounded()))"), ("finite", "\(finite)"), ("loudest", loudest)])
        case "history":
            let h = audio.analysis.snapshots()
            let c = audio.analysis.counters()
            let current = h.allSatisfy { $0.generation == audio.generation }
            let ordered = zip(h, h.dropFirst()).allSatisfy { $0.centreFrame < $1.centreFrame }
            report([("count", "\(h.count)"), ("bound", "\(AudioAnalysis.historyBound)"), ("first", h.first.map { Host.tenths($0.atMs) } ?? "-"), ("last", h.last.map { Host.tenths($0.atMs) } ?? "-"), ("current", "\(current)"), ("ordered", "\(ordered)"), ("waiting", "\(c.waiting)"), ("slots", "\(AudioAnalysis.slotCount)"), ("skipped", "\(c.skipped > 0)")])
        case "eq":
            let gains = audio.gains.map { g in Int(g.rounded()) == 0 ? "0" : "\(Int(g.rounded()))" }.joined(separator: " ")
            report([("bypass", "\(audio.bypass)"), ("preamp", "\(Int(audio.preamp.rounded()))"), ("bands", gains), ("volume", "\(Int((audio.volume * 100).rounded()))")])
        case "sources":
            // What a drawing surface would read now from each audio source.
            report(AudioSurfaceSources.names.map { name -> (String, String) in
                let field = name.hasPrefix("audio.") ? String(name.dropFirst(6)) : name
                switch SurfaceSources.shared.source(name)?.latest(at: Bench.now()) {
                case .series(let v)?: return (field, "\(v.count) \(Host.hundredths(v.min() ?? 0)) \(Host.hundredths(v.max() ?? 0))")
                case .scalar(let v)?: return (field, Host.hundredths(v))
                case nil: return (field, "none")
                }
            })
        default:
            return nil
        }
        return .next
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
