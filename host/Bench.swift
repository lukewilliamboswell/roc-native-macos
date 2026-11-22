// `ROC_BENCH=1`: how long each turn's phases take, for bench/ harnesses.
//
// Off by default: with the variable unset `Host.bench` is nil and nothing
// here runs. On, every operation (a mount, an event's turns, a pointer move's
// turns, a timer's turn) is one sample of four phases: the engine call(s),
// applying their commands to the views, laying the window out (`sync`), and
// a forced `displayIfNeeded`, so drawing is counted where it happens rather
// than on the next runloop pass. The scripted `stats` step prints them to
// stdout with the view count and peak RSS.

import AppKit

final class Bench: NSObject {
    static let on = getenv("ROC_BENCH") != nil
    static func now() -> Double { ProcessInfo.processInfo.systemUptime }
    /// When the process reached `main`, for the time to first display.
    static var launched = 0.0

    /// What started an operation.
    enum Kind {
        case mount, event, hover, timer
        static let all: [Kind] = [.mount, .event, .hover, .timer]
        var name: String {
            switch self {
            case .mount: return "mount"
            case .event: return "event"
            case .hover: return "hover"
            case .timer: return "timer"
            }
        }
    }

    /// One operation's phases, in seconds. (A class: a struct of Doubles in
    /// an array would make Swift reference Double's metadata, which the
    /// catalog does not own.)
    final class Sample: NSObject { var engine = 0.0, apply = 0.0, layout = 0.0, display = 0.0, turns = 0 }

    private var samples: [Kind: [Sample]] = [:]
    private var current = Sample()
    private var kind = Kind.event
    private var mark = 0.0
    /// The most timers alive at once.
    private(set) var peakTimers = 0
    private var firstShown: Double?
    private var firstDisplay = Sample()

    func begin(_ kind: Kind) {
        self.kind = kind
        current = Sample()
    }

    func engine(_ seconds: Double) {
        current.engine += seconds
        current.turns += 1
        mark = Bench.now()
    }

    func applied() {
        let t = Bench.now()
        current.apply += t - mark
        mark = t
    }

    /// The operation's last turn has been applied and laid out: draw now,
    /// and keep the sample.
    func end(_ host: Host) {
        var t = Bench.now()
        current.layout += t - mark
        if host.window.isVisible {
            host.window.displayIfNeeded()
            current.display = Bench.now() - t
        }
        t = Bench.now()
        samples[kind, default: []].append(current)
        peakTimers = max(peakTimers, host.timers.count)
        mark = t
    }

    func timerStarted(_ host: Host) { peakTimers = max(peakTimers, host.timers.count) }

    /// The window has just been ordered front: lay it out and draw it, and
    /// note how long after launch it was on screen.
    func shown(_ host: Host) {
        guard let content = host.window.contentView else { return }
        var t = Bench.now()
        content.layoutSubtreeIfNeeded()
        firstDisplay.layout = Bench.now() - t
        t = Bench.now()
        host.window.displayIfNeeded()
        firstDisplay.display = Bench.now() - t
        firstShown = Bench.now() - Bench.launched
    }

    // MARK: Report

    func report(_ host: Host) {
        var views = 0
        func count(_ v: NSView) { views += 1; for s in v.subviews { count(s) } }
        if let content = host.window.contentView { count(content) }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let rss = Double(usage.ru_maxrss) / 1_048_576  // bytes on macOS
        let size = host.window.contentView?.frame.size ?? .zero
        print("bench: views \(views) window \(Int(size.width))x\(Int(size.height)) rss-peak-mb \(f1(rss)) timers-peak \(peakTimers) timers-live \(host.timers.count)")
        if let shown = firstShown {
            let m = samples[.mount]?.first ?? Sample()
            print("bench: first-display \(ms(shown)) ms after launch: mount engine \(ms(m.engine)) apply \(ms(m.apply)) layout \(ms(m.layout)) | shown layout \(ms(firstDisplay.layout)) display \(ms(firstDisplay.display))")
        }
        for kind in Kind.all {
            guard let list = samples[kind], !list.isEmpty else { continue }
            let turns = list.reduce(0) { $0 + $1.turns }
            print("bench: \(kind.name) n \(list.count) turns \(turns)"
                + " | engine \(spread(list.map { $0.engine }))"
                + " | apply \(spread(list.map { $0.apply }))"
                + " | layout \(spread(list.map { $0.layout }))"
                + " | display \(spread(list.map { $0.display }))"
                + " | total \(spread(list.map { $0.engine + $0.apply + $0.layout + $0.display }))")
        }
    }

    /// `p50/p95/max` in milliseconds. (Sorted as whole microseconds: sorting
    /// Doubles would reference Double's metadata, which the catalog does
    /// not own.)
    private func spread(_ seconds: [Double]) -> String {
        let s = seconds.map { Int(($0 * 1_000_000).rounded()) }.sorted()
        func at(_ q: Double) -> String { f1(Double(s[min(s.count - 1, Int(Double(s.count - 1) * q + 0.5))]) / 1000) }
        return "\(at(0.5))/\(at(0.95))/\(at(1))"
    }

    private func ms(_ seconds: Double) -> String { f1(seconds * 1000) }

    /// One decimal place, without Foundation's formatters.
    private func f1(_ x: Double) -> String {
        let tenths = Int((x * 10).rounded())
        return "\(tenths / 10).\(abs(tenths % 10))"
    }
}
