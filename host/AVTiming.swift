// The audio/visual timing harness: how far each flash a drawing surface
// shows is from the click that caused it, and how evenly its frames come
// (docs/architecture.adoc, "Audio/visual timing"; docs/apps.adoc, "Measure
// audio/visual sync").
//
// Everything here runs on the main thread. The audio side records, under
// the analysis lock, each tapped buffer's render stamp (its first frame's
// node sample time and host time) and, when asked, each click's onset
// frame (AudioAnalysis.swift); the drawing side records each display-paced
// frame: its display-link tick, the time it was drawn for, the `audio.level`
// it read, and, from Metal, when it was presented and its GPU time.
//
//   audible(click) = host(stamp holding the click's node frame)
//                    + (click node frame - stamp's node frame) / node rate
//                    + outputNode.presentationLatency
//   visible(flash) = presentedTime of the first presented frame at or after
//                    the first frame whose level reaches 0.5
//                    (Core Graphics: that frame's display-link targetTimestamp)
//   offset         = visible - audible   (positive: the picture trails the sound)

import AppKit

final class AVTiming {
    static let shared = AVTiming()

    /// `ROC_AV_TIMING=1`: record from launch and print a summary every
    /// `every` seconds on standard error.
    static let reporting = ProcessInfo.processInfo.environment["ROC_AV_TIMING"] == "1"
    static let every = 5.0
    /// The level (0…1, as `audio.level` reads) a flash reaches.
    static let threshold: Float = 0.5
    /// How far from a click a flash is still its flash, in seconds.
    static let window = (before: 0.2, after: 0.3)
    /// Frames kept, about 34 s at 120 Hz.
    static let capacity = 4096

    struct Frame {
        var id = 0
        var label = ""
        /// The display link's `timestamp` (the refresh that fired) and
        /// `targetTimestamp` (the one this frame is for), and the time the
        /// frame was drawn for (whichever of them the surface uses).
        var tick = 0.0, target = 0.0, drawnFor = 0.0
        var level: Float = 0
        /// The window centre of the snapshot it drew, in source frames (-1: none).
        var centre: Int64 = -1
        var short = 0.0
        var metal = false
        /// When Metal presented it (0 while pending, -1 when it was not).
        var presented = 0.0
        var gpuMs = -1.0
    }

    private(set) var recording = AVTiming.reporting
    private var frames = [Frame](repeating: Frame(), count: AVTiming.capacity)
    private var nextId = 1
    /// Frames due that the GPU was too far behind to draw.
    private var skipped = 0
    private var reportedAt = 0.0
    weak var audio: AudioService?

    /// Start again from now (a spec's `(mark-av-timing)`).
    func mark() {
        recording = true
        frames = [Frame](repeating: Frame(), count: AVTiming.capacity)
        skipped = 0
        audio?.analysis.markOnsets()
    }

    /// A frame drawn for a display-link tick: its id, for `presented`.
    func frame(label: String, tick: Double, target: Double, drawnFor: Double, metal: Bool) -> Int {
        guard recording else { return 0 }
        let id = nextId
        nextId += 1
        let level = DrawingSurface.scalar("audio.level", at: drawnFor)
        frames[id % AVTiming.capacity] = Frame(id: id, label: label, tick: tick, target: target, drawnFor: drawnFor, level: level, centre: audio?.drawnCentre ?? -1, short: audio?.drawnShort ?? 0, metal: metal)
        if AVTiming.reporting, !Host.scripted {
            let now = Bench.now()
            if reportedAt == 0 { reportedAt = now }
            if now - reportedAt >= AVTiming.every {
                reportedAt = now
                for line in summary() { fputs("av-timing: \(line)\n", __stderrp) }
                mark()
            }
        }
        return id
    }

    func skippedFrame() { if recording { skipped += 1 } }

    func presented(_ id: Int, at time: Double) {
        guard id > 0, frames[id % AVTiming.capacity].id == id else { return }
        frames[id % AVTiming.capacity].presented = time > 0 ? time : -1
    }

    func gpu(_ id: Int, ms: Double) {
        guard id > 0, frames[id % AVTiming.capacity].id == id else { return }
        frames[id % AVTiming.capacity].gpuMs = ms
    }

    // MARK: The report

    struct Report {
        var label = ""
        var clicks = 0, matched = 0
        var offsets: [Double] = []
        /// Each shown frame's time less the time its window's centre was heard.
        var windowLag: [Double] = []
        /// How far before the window wanted each frame's was, in ms.
        var short: [Double] = []
        /// Each presented Metal frame's presented time less its target.
        var presentLag: [Double] = []
        var frames = 0, dropped = 0, skipped = 0, presented = 0
        var frameMs: [Double] = []
        var gpuMs: [Double] = []
        var refreshMs = 0.0
        var latencyMs = 0.0
        var flashes = 0
    }

    /// The report for the surface with the most frames recorded.
    func report() -> Report {
        var r = Report()
        var kept: [Frame] = []
        for f in frames where f.id > 0 { kept.append(f) }
        kept.sort { $0.id < $1.id }
        // The label with the most frames (the first in order on a tie).
        var labels: [String] = [], counts: [Int] = []
        for f in kept {
            if let i = labels.firstIndex(of: f.label) { counts[i] += 1 } else { labels.append(f.label); counts.append(1) }
        }
        var best = -1
        for i in 0..<labels.count where best < 0 || counts[i] > counts[best] { best = i }
        guard best >= 0 else { return r }
        r.label = labels[best]
        var mine: [Frame] = []
        for f in kept where f.label == r.label { mine.append(f) }
        r.frames = mine.count
        r.skipped = skipped
        // Pacing: refreshes between ticks past the first are dropped.
        var periods: [Double] = []
        for f in mine where f.target > f.tick { periods.append(f.target - f.tick) }
        let period = AVTiming.percentile(periods, 50) ?? (1.0 / 60)
        r.refreshMs = period * 1000
        var i = 1
        while i < mine.count {
            r.dropped += max(0, Int(((mine[i].tick - mine[i - 1].tick) / period).rounded()) - 1)
            i += 1
        }
        // When each frame appeared: Metal's presented time, Core
        // Graphics' target; nil for a Metal frame never presented.
        func seen(_ f: Frame) -> Double? { f.metal ? (f.presented > 0 ? f.presented : nil) : f.target }
        var last: Double?
        for f in mine {
            guard let t = seen(f) else { continue }
            r.presented += 1
            if let l = last { r.frameMs.append((t - l) * 1000) }
            last = t
            if f.gpuMs >= 0 { r.gpuMs.append(f.gpuMs) }
            if f.metal { r.presentLag.append((t - f.target) * 1000) }
            if f.centre >= 0 { r.short.append(f.short) }
        }
        // Flashes: the first frame at or over the threshold after one
        // under it, seen when the first frame from it on that was shown appears.
        var flashes: [Double] = []
        i = 1
        while i < mine.count {
            if mine[i].level >= AVTiming.threshold, mine[i - 1].level < AVTiming.threshold {
                var j = i
                while j < mine.count, seen(mine[j]) == nil { j += 1 }
                if j < mine.count, let t = seen(mine[j]) { flashes.append(t) }
            }
            i += 1
        }
        guard let audio else { return r }
        r.latencyMs = audio.outputLatency * 1000
        var shownFrames: [Frame] = []
        for f in mine where f.centre >= 0 && seen(f) != nil { shownFrames.append(f) }
        let heard = audio.audibleTimes(shownFrames.map { $0.centre })
        for k in 0..<shownFrames.count {
            if let h = heard[k], let t = seen(shownFrames[k]) { r.windowLag.append((t - h) * 1000) }
        }
        let audible = audio.audibleClicks()
        r.clicks = audible.count
        r.flashes = flashes.count
        for a in audible {
            var nearest: Double?
            for v in flashes where v >= a - AVTiming.window.before && v <= a + AVTiming.window.after {
                if nearest == nil || abs(v - a) < abs(nearest! - a) { nearest = v }
            }
            guard let v = nearest else { continue }
            r.offsets.append((v - a) * 1000)
            r.matched += 1
        }
        return r
    }

    /// The report as `name value` lines.
    func summary() -> [String] {
        let r = report()
        func ms(_ v: Double?) -> String { v.map { Host.decimal($0, 1) } ?? "-" }
        let mean = r.offsets.isEmpty ? nil : r.offsets.reduce(0, +) / Double(r.offsets.count)
        let abs95 = AVTiming.percentile(r.offsets.map { abs($0) }, 95)
        return [
            "surface \(r.label)",
            "clicks \(r.clicks)",
            "flashes \(r.flashes)",
            "matched \(r.matched)",
            "mean \(ms(mean))",
            "p95 \(ms(abs95))",
            "max \(ms(r.offsets.map { abs($0) }.max()))",
            "min \(ms(r.offsets.min()))",
            "most \(ms(r.offsets.max()))",
            "lead \(ms(r.offsets.isEmpty ? nil : max(0, -(r.offsets.min() ?? 0))))",
            "latency \(ms(r.latencyMs))",
            "output \(audio?.outputReport() ?? "none")",
            "window-mean \(ms(r.windowLag.isEmpty ? nil : r.windowLag.reduce(0, +) / Double(r.windowLag.count)))",
            "window-p5 \(ms(AVTiming.percentile(r.windowLag, 5)))",
            "window-p95 \(ms(AVTiming.percentile(r.windowLag, 95)))",
            "short-p50 \(ms(AVTiming.percentile(r.short, 50)))",
            "short-p95 \(ms(AVTiming.percentile(r.short, 95)))",
            "present-p5 \(ms(AVTiming.percentile(r.presentLag, 5)))",
            "present-p50 \(ms(AVTiming.percentile(r.presentLag, 50)))",
            "present-p95 \(ms(AVTiming.percentile(r.presentLag, 95)))",
            "frames \(r.frames)",
            "presented \(r.presented)",
            "dropped \(r.dropped)",
            "skipped \(r.skipped)",
            "refresh \(ms(r.refreshMs))",
            "frame-p50 \(ms(AVTiming.percentile(r.frameMs, 50)))",
            "frame-p99 \(ms(AVTiming.percentile(r.frameMs, 99)))",
            "gpu-p50 \(Host.decimal(AVTiming.percentile(r.gpuMs, 50) ?? 0, 2))",
            "gpu-p99 \(Host.decimal(AVTiming.percentile(r.gpuMs, 99) ?? 0, 2))",
            "offsets \(r.offsets.map { Host.decimal($0, 1) }.joined(separator: " "))",
        ]
    }

    /// The nearest-rank percentile `p` of `values`.
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        // A shell sort: the standard library's sort of Doubles would need
        // Double's runtime metadata, a symbol the catalog does not own.
        var sorted = values
        var gap = sorted.count / 2
        while gap > 0 {
            for i in gap..<sorted.count {
                let v = sorted[i]
                var j = i
                while j >= gap, sorted[j - gap] > v { sorted[j] = sorted[j - gap]; j -= gap }
                sorted[j] = v
            }
            gap /= 2
        }
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
