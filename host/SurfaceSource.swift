// Native sources a drawing surface's scene binds by name (`Ui.surface`).
//
// A scene names a source by a stable string, such as `audio.waveform`: a
// `Wave`, `Ring` or `Bars` draws its latest series, and a `Source` number its
// latest scalar. A native producer (an audio analyser, a sensor, the
// synthetic sources below) implements `SurfaceSource` and registers itself
// in `SurfaceSources.shared`; each frame of a surface asks it for its latest
// value, so a display-paced surface follows it without a turn of the engine.
//
// This file stands alone: it needs only Foundation and the host's `fatal`,
// so a native service can depend on it without the rest of the host (docs/architecture.adoc,
// "Surface sources").

import Foundation

/// One reading of a source: a bounded series, or one number.
enum SurfaceSample {
    /// At most `SurfaceSample.maxSeries` values, oldest first; a longer
    /// series is a fatal error naming its source.
    case series([Float])
    case scalar(Float)

    /// The most values one series may hold.
    static let maxSeries = 4096
}

/// A native producer of the values a surface's scene binds by `name`.
///
/// `latest(at:)` is called on the main thread only, once for each mark that
/// names the source in each frame a surface draws, so it must return
/// promptly without blocking (a producer on another thread publishes into
/// storage `latest` reads under its own short lock). `frameTime` is the
/// frame's time in seconds on a monotonic clock: `ProcessInfo.systemUptime`
/// (`mach_absolute_time`, which does not advance while the Mac sleeps), or
/// under a spec's controlled clock, the seconds its `frame` steps
/// have advanced. Return nil when there is nothing to show yet; the mark then
/// draws nothing, and a number reads as 0.
protocol SurfaceSource: AnyObject {
    /// The stable name a scene refers to, such as `audio.waveform`: letters,
    /// digits, `.`, `-` and `_`.
    var name: String { get }
    func latest(at frameTime: Double) -> SurfaceSample?
}

/// The registered sources, by name. Main thread only.
final class SurfaceSources {
    static let shared = SurfaceSources()

    private var byName: [String: SurfaceSource] = [:]

    /// Called with a source's name when it is registered, unregistered or
    /// `changed`; the host redraws the on-demand surfaces that name it.
    var onChange: ((String) -> Void)?

    /// Register `source` under its name, replacing any other of that name.
    func register(_ source: SurfaceSource) {
        guard SurfaceSources.valid(source.name) else {
            fatal("surface source name \"\(source.name)\" is not letters, digits, '.', '-' and '_'")
        }
        byName[source.name] = source
        onChange?(source.name)
    }

    /// Stop answering for `name`; marks that name it draw nothing.
    func unregister(_ name: String) {
        if byName.removeValue(forKey: name) != nil { onChange?(name) }
    }

    /// The source registered as `name`, if any.
    func source(_ name: String) -> SurfaceSource? { byName[name] }

    /// A source's value changed while no display-paced surface is reading
    /// it: on-demand surfaces that name it draw a new frame.
    func changed(_ name: String) { onChange?(name) }

    /// The registered names, sorted.
    var names: [String] { byName.keys.sorted() }

    static func valid(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.allSatisfy { c in
            (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == 0x2e || c == 0x2d || c == 0x5f
        }
    }
}

/// The platform's test signals, registered in every app: `synthetic.wave`,
/// nine values of one sine cycle, and `synthetic.level`, a scalar from 0 up
/// to just under 1. Each moves on by one step (an eighth of a cycle) for a
/// spec's `(step-source NAME)`; with the display clock it also moves with time, two
/// steps a second.
final class SyntheticSource: SurfaceSource {
    let name: String
    private let series: Bool
    /// Steps taken by `step`.
    private(set) var steps = 0
    /// Whether the value also moves with the frame time.
    static var followsTime = false

    init(name: String, series: Bool) {
        self.name = name
        self.series = series
    }

    func step(_ count: Int = 1) { steps += count }

    func latest(at frameTime: Double) -> SurfaceSample? {
        let phase = Double(steps) + (SyntheticSource.followsTime ? frameTime * 2 : 0)
        if series {
            return .series((0..<9).map { i in Float(sin(2 * Double.pi * (Double(i) + phase) / 8)) })
        }
        let turns = phase / 8
        return .scalar(Float(turns - turns.rounded(.down)))
    }

    /// The synthetic sources, by name.
    static var named: [String: SyntheticSource] = [:]

    static func registerAll() {
        for (name, series) in [("synthetic.wave", true), ("synthetic.level", false)] where named[name] == nil {
            let source = SyntheticSource(name: name, series: series)
            named[name] = source
            SurfaceSources.shared.register(source)
        }
    }
}
