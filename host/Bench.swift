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
    final class Sample: NSObject { var engine = 0.0, apply = 0.0, layout = 0.0, display = 0.0, turns = 0, at = 0.0 }

    /// What the HUD summarises over its last second: when each sample
    /// ended, each event's latency to its paint, each pointer move and
    /// whether it lagged, and each operation that drew.
    private var recent: [Sample] = []
    private var latencies: [(at: Double, seconds: Double)] = []
    private var moves: [(at: Double, late: Bool)] = []
    private var draws: [Double] = []
    /// The timestamp of the input event the operation in progress answers.
    var eventTime: Double?
    private var hud: NSTextField?
    private var structureChanged = true
    private var views = 0, targets = 0

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
        if current.layout > 0.0005 { structureChanged = true }
        if host.window.isVisible {
            let drawing = host.window.viewsNeedDisplay
            host.window.displayIfNeeded()
            current.display = Bench.now() - t
            if drawing { draws.append(Bench.now()) }
        }
        t = Bench.now()
        current.at = t
        samples[kind, default: []].append(current)
        recent.append(current)
        if let event = eventTime { latencies.append((t, t - event)) }
        eventTime = nil
        peakTimers = max(peakTimers, host.timers.count)
        mark = t
    }

    /// A pointer move arrived (`time`: its event's timestamp). It lagged if
    /// it waited more than a 60 Hz frame for the main thread.
    func moved(_ time: Double) {
        let now = Bench.now()
        moves.append((now, now - time > 1.0 / 60))
    }

    // MARK: Live HUD

    /// A small panel over the window's top-right corner, refreshed twice a
    /// second from a host timer: the engine is never asked, so the HUD does
    /// not perturb what it shows. It lives in the window's frame view, out
    /// of the content's layout, so measuring the content never sees it.
    func startHUD(_ host: Host) {
        guard let frame = host.window.contentView?.superview else { return }
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .white
        label.drawsBackground = true
        label.backgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.72)
        label.maximumNumberOfLines = 0
        label.autoresizingMask = [.minXMargin, .minYMargin]
        frame.addSubview(label)
        hud = label
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self, weak host] _ in
            guard let self, let host else { return }
            self.refreshHUD(host)
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshHUD(host)
    }

    private func refreshHUD(_ host: Host) {
        guard let label = hud, let frame = label.superview else { return }
        let since = Bench.now() - 1
        recent.removeAll { $0.at < since }
        latencies.removeAll { $0.at < since }
        moves.removeAll { $0.at < since }
        draws.removeAll { $0 < since }
        if structureChanged {
            // Recounted only after a batch that laid the window out.
            structureChanged = false
            views = 0
            func count(_ v: NSView) { views += 1; for s in v.subviews { count(s) } }
            if let content = host.window.contentView { count(content) }
            targets = 0
            host.root.walk { if $0.listeners["hover"] != nil { self.targets += 1 } }
        }
        var side = 0
        while (side + 1) * (side + 1) <= targets { side += 1 }
        let grid = side * side == targets && side > 0 ? " (\(side)×\(side))" : ""
        var lines = ["\(targets) hover targets\(grid) · \(views) views · first display \(firstShown.map { ms($0) } ?? "–") ms"]
        if recent.isEmpty {
            lines.append("idle: nothing changed, nothing drawn")
        } else {
            let paint = latencies.map { $0.seconds }
            lines.append("event→paint ms  p50 \(paint.isEmpty ? "–" : pick(paint, 0.5))  p95 \(paint.isEmpty ? "–" : pick(paint, 0.95))")
            let ops = recent.filter { $0.turns > 0 }
            lines.append("draws/s \(draws.count) · moves/s \(moves.count) (lagging \(moves.filter { $0.late }.count)) · turns/s \(ops.reduce(0) { $0 + $1.turns })")
            lines.append("p95 ms  engine \(pick(ops.map { $0.engine }, 0.95))  apply \(pick(ops.map { $0.apply }, 0.95))  layout \(pick(ops.map { $0.layout }, 0.95))  display \(pick(ops.map { $0.display }, 0.95))")
        }
        lines.append("timers \(host.timers.count) · RSS \(f1(Bench.residentMB())) MB")
        label.stringValue = lines.joined(separator: "\n")
        label.sizeToFit()
        let size = label.frame.size
        // The content area's top-right corner, below the title bar.
        let content = host.window.contentLayoutRect
        let top = content.origin.y + content.size.height
        label.setFrameOrigin(NSPoint(x: frame.bounds.width - size.width - 8, y: top - size.height - 8))
    }

    /// One quantile of `seconds`, in milliseconds.
    private func pick(_ seconds: [Double], _ q: Double) -> String {
        guard !seconds.isEmpty else { return "–" }
        let s = seconds.map { Int(($0 * 1_000_000).rounded()) }.sorted()
        return f1(Double(s[min(s.count - 1, Int(Double(s.count - 1) * q + 0.5))]) / 1000)
    }

    /// The resident set size now, in MiB (`task_info`).
    static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(12)  // MACH_TASK_BASIC_INFO_COUNT: 48 bytes of natural_t
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 12) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
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
        startHUD(host)
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
