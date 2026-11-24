// Drawing surfaces (`ui-surface`) and overlays (`ui-overlay`).
//
// A surface is one view that draws an ordered scene (`Ui.Mark`s, one per
// line of its `scene` attribute) with Core Graphics. A new scene redraws
// this view alone: no view per shape, and no layout pass (`scene` is a
// paint-only attribute). Each frame the surface draws is a logical frame:
// it resolves the scene, reading every native source it names
// (SurfaceSource.swift) at the frame's time, and keeps the result, so an
// ordinary AppKit repaint shows that same frame again.
//
// A new frame is drawn when the scene, the look or the size changes (at the
// next repaint), and, for a display-paced surface, at each refresh of its
// display (`FrameClock`), while it is in a window and not hidden. The display
// link calls on the main thread, between engine turns, and never calls the
// engine. A refresh the main thread was too busy for is skipped, not queued:
// the next frame covers the time since the last one.
//
// A display-paced surface on a Mac with a Metal device draws with Metal
// instead (SurfaceMetal.swift), in the same order. With Core Graphics, a
// surface with a trail keeps two bitmaps: each frame clears one to the
// background, draws the previous frame (the other) into it moved and faded
// by the time since that frame, then the scene over it, and shows it as the
// layer's contents. They are at most `historyPixels` pixels each, at the
// backing scale or below it for a large surface, and are let go when the
// surface leaves its window (docs/architecture.adoc, "Drawing surfaces").

import AppKit
import QuartzCore

// MARK: - The scene

/// A number of a scene: `offset`, plus `scale` times a source's scalar, or,
/// with an `index`, times that value of the source's series.
struct SceneNumber {
    let offset: Double
    let source: String?
    let scale: Double
    var index: Int? = nil
}

/// A step of a path, in scene units.
enum PathStep {
    case move(Double, Double)
    case line(Double, Double)
    case quad(Double, Double, Double, Double)
    case curve(Double, Double, Double, Double, Double, Double)
    case close
}

enum SceneShape {
    /// A fixed path.
    case path([PathStep])
    /// A source's series as a polyline across x y w h (`values`: x y w h low high).
    case wave(String, [Double])
    /// Around a centre (`values`: x y radius depth low high).
    case ring(String, [Double])
    /// One series against another, as a polyline in x y w h (`values`: x y w h low high).
    case lissajous(String, String, [Double])
    /// As bars (`values`: x y w h low high gap).
    case bars(String, [Double])
}

enum SceneMark {
    case fill(SceneShape, NSColor, String)
    case stroke(SceneShape, NSColor, String, SceneNumber)
    case save
    case restore
    case translate(SceneNumber, SceneNumber)
    case rotate(SceneNumber)
    case scale(SceneNumber, SceneNumber)
    case matrix(Double, Double, Double, Double, Double, Double)
    case opacity(SceneNumber)
}

/// The grammar of the `scene` attribute, and its bounds.
enum Scene {
    /// The most points a frame may draw, a source's series included.
    static let maxPoints = 65_536
    /// The largest coordinate, in scene units, either side of zero.
    static let maxCoordinate = 1_000_000.0

    static func parse(_ text: String) -> [SceneMark] {
        var marks: [SceneMark] = []
        var points = 0
        var depth = 0
        for (i, line) in text.split(separator: "\n").enumerated() {
            var w = Words(line: String(line), number: i + 1)
            let verb = w.word("a mark")
            switch verb {
            case "fill":
                let word = w.word("a colour")
                marks.append(.fill(w.shape(&points), Host.color(word), word))
            case "stroke":
                let word = w.word("a colour")
                // A constant width is not negative; a bound one below 0
                // draws as 0.
                let width = w.sceneNumber()
                if width.source == nil, width.offset < 0 { w.fail("a line width is not negative") }
                marks.append(.stroke(w.shape(&points), Host.color(word), word, width))
            case "save":
                depth += 1
                marks.append(.save)
            case "restore":
                if depth == 0 { w.fail("restore has no save before it") }
                depth -= 1
                marks.append(.restore)
            case "translate": marks.append(.translate(w.sceneNumber(), w.sceneNumber()))
            case "rotate": marks.append(.rotate(w.sceneNumber()))
            case "scale": marks.append(.scale(w.sceneNumber(), w.sceneNumber()))
            case "matrix":
                let v = (0..<6).map { _ in w.number("a matrix entry") }
                marks.append(.matrix(v[0], v[1], v[2], v[3], v[4], v[5]))
            case "opacity": marks.append(.opacity(w.sceneNumber()))
            default: w.fail("\(verb) is not a mark")
            }
            w.end()
            if points > maxPoints { w.fail("the scene has more than \(maxPoints) points") }
        }
        return marks
    }

    /// The words of one line of a scene.
    struct Words {
        let line: String
        let number: Int
        private let words: [String]
        private var at = 0

        init(line: String, number: Int) {
            self.line = line
            self.number = number
            words = line.split(separator: " ").map(String.init)
        }

        func fail(_ why: String) -> Never {
            fatal("surface scene line \(number) (\(words.first ?? "empty")): \(why) (docs/architecture.adoc, \"Drawing surfaces\")")
        }

        mutating func word(_ what: String) -> String {
            guard at < words.count else { fail("it ends where \(what) belongs") }
            defer { at += 1 }
            return words[at]
        }

        mutating func number(_ what: String) -> Double {
            let text = word(what)
            guard let v = Double(text), v.isFinite, abs(v) <= Scene.maxCoordinate else { fail("\(text) is not \(what), a finite number within ±\(Int(Scene.maxCoordinate))") }
            return v
        }

        mutating func count() -> Int {
            let text = word("a count")
            guard let n = Int(text), n >= 0, n <= Scene.maxPoints else { fail("\(text) is not a count up to \(Scene.maxPoints)") }
            return n
        }

        mutating func source() -> String {
            let name = word("a source name")
            if !SurfaceSources.valid(name) { fail("\(name) is not a source name") }
            return name
        }

        /// A constant, `@source:scale:offset`, or `@source[index]:scale:offset`.
        mutating func sceneNumber() -> SceneNumber {
            let text = word("a number")
            guard text.hasPrefix("@") else {
                at -= 1
                return SceneNumber(offset: number("a number"), source: nil, scale: 0)
            }
            let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let name = parts.first?.split(separator: "@").map(String.init) ?? []
            // `source[index]`: one value of a series.
            let element = name.first?.split(separator: "[", omittingEmptySubsequences: false).map(String.init) ?? []
            guard parts.count == 3, name.count == 1, element.count == 1 || element.count == 2, SurfaceSources.valid(element[0]),
                  let scale = Double(parts[1]), let offset = Double(parts[2]), scale.isFinite, offset.isFinite
            else { fail("\(text) is not @source:scale:offset or @source[index]:scale:offset") }
            guard element.count == 2 else { return SceneNumber(offset: offset, source: element[0], scale: scale) }
            let digits = element[1].split(separator: "]", omittingEmptySubsequences: false).map(String.init)
            guard digits.count == 2, digits[1].isEmpty, let index = Int(digits[0]), index >= 0, index < SurfaceSample.maxSeries
            else { fail("\(text) does not index its source from 0 below \(SurfaceSample.maxSeries)") }
            return SceneNumber(offset: offset, source: element[0], scale: scale, index: index)
        }

        mutating func shape(_ points: inout Int) -> SceneShape {
            let kind = word("a shape")
            switch kind {
            case "rect", "oval":
                let x = number("x"), y = number("y"), width = number("a width"), height = number("a height")
                if width < 0 || height < 0 { fail("a \(kind)'s size is not negative") }
                points += kind == "rect" ? 4 : 13
                if kind == "rect" { return .path([.move(x, y), .line(x + width, y), .line(x + width, y + height), .line(x, y + height), .close]) }
                return .path(Scene.oval(x, y, width, height))
            case "line", "polygon":
                let n = count()
                var steps: [PathStep] = []
                steps.reserveCapacity(n + 1)
                for i in 0..<n {
                    let x = number("x"), y = number("y")
                    steps.append(i == 0 ? .move(x, y) : .line(x, y))
                }
                if kind == "polygon", n > 0 { steps.append(.close) }
                points += n
                return .path(steps)
            case "path":
                let n = count()
                var steps: [PathStep] = []
                for _ in 0..<n {
                    let op = word("a path step")
                    switch op {
                    case "M": steps.append(.move(number("x"), number("y"))); points += 1
                    case "L": steps.append(.line(number("x"), number("y"))); points += 1
                    case "Q": steps.append(.quad(number("x"), number("y"), number("x"), number("y"))); points += 2
                    case "C": steps.append(.curve(number("x"), number("y"), number("x"), number("y"), number("x"), number("y"))); points += 3
                    case "Z": steps.append(.close)
                    default: fail("\(op) is not a path step (M, L, Q, C or Z)")
                    }
                }
                if case .move = steps.first {} else if !steps.isEmpty { fail("a path starts with M") }
                return .path(steps)
            case "lissajous":
                let across = source(), down = source()
                var v = (0..<4).map { _ in number("x, y, width or height") }
                v.append(number("low"))
                v.append(number("high"))
                if v[2] < 0 || v[3] < 0 { fail("a lissajous's size is not negative") }
                if v[4] == v[5] { fail("low and high are different numbers") }
                return .lissajous(across, down, v)
            case "wave", "bars":
                let name = source()
                var v = (0..<4).map { _ in number("x, y, width or height") }
                v.append(number("low"))
                v.append(number("high"))
                if kind == "bars" { v.append(number("a gap")) }
                if v[2] < 0 || v[3] < 0 { fail("a \(kind)'s size is not negative") }
                if v[4] == v[5] { fail("low and high are different numbers") }
                return kind == "wave" ? .wave(name, v) : .bars(name, v)
            case "ring":
                let name = source()
                let v = ["x", "y", "a radius", "a depth", "low", "high"].map { number($0) }
                if v[4] == v[5] { fail("low and high are different numbers") }
                return .ring(name, v)
            default:
                fail("\(kind) is not a shape")
            }
        }

        func end() {
            if at < words.count { fail("\(words[at]) is left over") }
        }
    }

    /// An ellipse in a rectangle as four cubic curves (the usual 0.5523
    /// control distance), from its top.
    static func oval(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [PathStep] {
        let k = 0.5522847498, rx = width / 2, ry = height / 2, cx = x + rx, cy = y + ry
        return [
            .move(cx, y),
            .curve(cx + k * rx, y, x + width, cy - k * ry, x + width, cy),
            .curve(x + width, cy + k * ry, cx + k * rx, y + height, cx, y + height),
            .curve(cx - k * rx, y + height, x, cy + k * ry, x, cy),
            .curve(x, cy - k * ry, cx - k * rx, y, cx, y),
            .close,
        ]
    }
}

// MARK: - A frame

/// One drawing step of a resolved frame: every number read, every source
/// sampled.
enum DrawStep {
    case figure(fill: Bool, color: NSColor, word: String, width: Double, path: [PathStep])
    case save
    case restore
    case transform(Double, Double, Double, Double, Double, Double)
    case opacity(Double)
}

/// A surface's scene units in view points: `x' = x * scale + dx`.
struct Mapping {
    let scale: Double
    let dx: Double
    let dy: Double
}

extension DrawingSurface {
    /// The scene at `time`: each source it names asked once per mark.
    static func resolve(_ marks: [SceneMark], at time: Double) -> [DrawStep] {
        var steps: [DrawStep] = []
        steps.reserveCapacity(marks.count)
        var points = 0
        func series(_ name: String) -> [Float] {
            guard let sample = SurfaceSources.shared.source(name)?.latest(at: time) else { return [] }
            guard case let .series(values) = sample else { fatal("surface source \(name) gave a number where the scene needs a series") }
            if values.count > SurfaceSample.maxSeries { fatal("surface source \(name) gave \(values.count) values, more than the \(SurfaceSample.maxSeries) a series may hold") }
            return values
        }
        func value(_ n: SceneNumber) -> Double {
            guard let name = n.source else { return n.offset }
            if let index = n.index {
                // One value of the series; past its end, it reads 0.
                let values = series(name)
                return index < values.count ? n.offset + n.scale * Double(values[index]) : n.offset
            }
            guard let sample = SurfaceSources.shared.source(name)?.latest(at: time) else { return n.offset }
            guard case let .scalar(v) = sample else { fatal("surface source \(name) gave a series where the scene needs a number") }
            return n.offset + n.scale * Double(v)
        }
        func path(_ shape: SceneShape) -> [PathStep] {
            switch shape {
            case let .path(fixed):
                return fixed
            case let .wave(name, v):
                let values = series(name)
                let n = values.count
                var out: [PathStep] = []
                out.reserveCapacity(n)
                for (i, value) in values.enumerated() {
                    let t = (Double(value) - v[4]) / (v[5] - v[4])
                    let x = v[0] + (n == 1 ? 0 : v[2] * Double(i) / Double(n - 1))
                    let y = v[1] + v[3] * (1 - t)
                    out.append(i == 0 ? .move(x, y) : .line(x, y))
                }
                if n == 1, case let .move(x, y) = out[0] { out.append(.line(x, y)) }
                return out
            case let .lissajous(across, down, v):
                let xs = series(across), ys = series(down)
                let n = min(xs.count, ys.count)
                var out: [PathStep] = []
                out.reserveCapacity(n)
                for i in 0..<n {
                    let tx = (Double(xs[i]) - v[4]) / (v[5] - v[4]), ty = (Double(ys[i]) - v[4]) / (v[5] - v[4])
                    let x = v[0] + v[2] * tx, y = v[1] + v[3] * (1 - ty)
                    out.append(i == 0 ? .move(x, y) : .line(x, y))
                }
                if n == 1, case let .move(x, y) = out[0] { out.append(.line(x, y)) }
                return out
            case let .ring(name, v):
                let values = series(name)
                let n = values.count
                var out: [PathStep] = []
                out.reserveCapacity(n + 1)
                for (i, value) in values.enumerated() {
                    let t = (Double(value) - v[4]) / (v[5] - v[4])
                    let r = v[2] + v[3] * t
                    let angle = 2 * Double.pi * Double(i) / Double(n)
                    let x = v[0] + r * sin(angle), y = v[1] - r * cos(angle)
                    out.append(i == 0 ? .move(x, y) : .line(x, y))
                }
                if n > 0 { out.append(.close) }
                return out
            case let .bars(name, v):
                let values = series(name)
                let n = values.count
                guard n > 0 else { return [] }
                let pitch = v[2] / Double(n), width = max(0, pitch - v[6]), bottom = v[1] + v[3]
                var out: [PathStep] = []
                out.reserveCapacity(n * 5)
                for (i, value) in values.enumerated() {
                    let t = min(1, max(0, (Double(value) - v[4]) / (v[5] - v[4])))
                    let x = v[0] + pitch * Double(i) + (pitch - width) / 2, top = bottom - v[3] * t
                    out += [.move(x, bottom), .line(x + width, bottom), .line(x + width, top), .line(x, top), .close]
                }
                return out
            }
        }
        for mark in marks {
            switch mark {
            case let .fill(shape, color, word):
                let p = path(shape)
                points += p.count
                if !p.isEmpty { steps.append(.figure(fill: true, color: color, word: word, width: 0, path: p)) }
            case let .stroke(shape, color, word, width):
                let p = path(shape)
                points += p.count
                if !p.isEmpty { steps.append(.figure(fill: false, color: color, word: word, width: max(0, value(width)), path: p)) }
            case .save: steps.append(.save)
            case .restore: steps.append(.restore)
            case let .translate(x, y): steps.append(.transform(1, 0, 0, 1, value(x), value(y)))
            case let .rotate(angle):
                let a = value(angle)
                steps.append(.transform(cos(a), sin(a), -sin(a), cos(a), 0, 0))
            case let .scale(x, y): steps.append(.transform(value(x), 0, 0, value(y), 0, 0))
            case let .matrix(a, b, c, d, tx, ty): steps.append(.transform(a, b, c, d, tx, ty))
            case let .opacity(amount): steps.append(.opacity(min(1, max(0, value(amount)))))
            }
        }
        if points > Scene.maxPoints { fatal("a surface frame draws \(points) points, more than \(Scene.maxPoints)") }
        return steps
    }

    /// Draw `steps` into `c`, the current graphics context's, whose
    /// transform is the scene's space. Colours resolve in the current
    /// drawing appearance.
    static func render(_ steps: [DrawStep], in c: CGContext) {
        var alpha = 1.0
        var saved: [Double] = []
        for step in steps {
            switch step {
            case let .figure(fill, color, _, width, path):
                let shape = NSBezierPath()
                for p in path {
                    switch p {
                    case let .move(x, y): shape.move(to: NSPoint(x: x, y: y))
                    case let .line(x, y): shape.line(to: NSPoint(x: x, y: y))
                    case let .quad(cx, cy, x, y): shape.curve(to: NSPoint(x: x, y: y), controlPoint: NSPoint(x: cx, y: cy))
                    case let .curve(ax, ay, bx, by, x, y): shape.curve(to: NSPoint(x: x, y: y), controlPoint1: NSPoint(x: ax, y: ay), controlPoint2: NSPoint(x: bx, y: by))
                    case .close: shape.close()
                    }
                }
                c.setAlpha(alpha)
                if fill {
                    color.setFill()
                    shape.fill()
                } else {
                    shape.lineWidth = width
                    shape.lineJoinStyle = .round
                    shape.lineCapStyle = .round
                    color.setStroke()
                    shape.stroke()
                }
            case .save:
                saved.append(alpha)
                c.saveGState()
            case .restore:
                alpha = saved.popLast() ?? 1
                c.restoreGState()
            case let .transform(a, b, cc, d, tx, ty):
                c.concatenate(CGAffineTransform(a: a, b: b, c: cc, d: d, tx: tx, ty: ty))
            case let .opacity(amount):
                alpha *= amount
            }
        }
        for _ in saved { c.restoreGState() }
    }

    /// Draw `image`, made from a bitmap of this surface's history, over
    /// `width` by `height` points from the top-left corner of the current
    /// graphics context (flipped), at `fraction` of its opacity.
    static func drawImage(_ image: CGImage, width: Double, height: Double, fraction: Double = 1) {
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSImage(cgImage: image, size: rect.size).draw(in: rect, from: NSRect(x: 0, y: 0, width: 0, height: 0), operation: .sourceOver, fraction: fraction, respectFlipped: true, hints: nil)
    }

    /// Run `draw` with `c` as the current graphics context (its transform
    /// y down), in this surface's appearance.
    func drawing(into c: CGContext, _ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
        effectiveAppearance.performAsCurrentDrawingAppearance(draw)
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - The surface

/// A trail: how the previous frame is drawn beneath each new one.
struct TrailSpec: Equatable {
    let halfLifeMs: Double
    let zoom: Double
    let turn: Double
    let shiftX: Double
    let shiftY: Double
}

/// `ui-surface`: a drawing surface (see the top of this file).
final class DrawingSurface: NSView {
    /// The most pixels one history bitmap holds; a larger surface keeps its
    /// history below its backing scale. Measured on Apple silicon (M-series,
    /// Core Graphics on the CPU), compositing the previous frame costs about
    /// 14 ms a megapixel, so this keeps a trail's frame near 7 ms.
    static let historyPixels = 500_000.0
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The pixels a point covers in what the surface draws: its window's
    /// backing scale, except in a spec, which draws at 2 on any display
    /// (as `probe` renders Core Graphics), so a probe reads the same pixels
    /// on a 1x screen as on a Retina one.
    private var drawingScale: Double { driven ? 2 : Double(window?.backingScaleFactor ?? 2) }

    private var marks: [SceneMark] = []
    /// Scene units in points: nil for `points`, else the fitted width and height.
    private var space: (width: Double, height: Double)?
    private var background: NSColor = .clear
    private(set) var displayPaced = false
    private var trail: TrailSpec?
    private var resetWord: String?
    private(set) var label = ""

    /// Logical frames drawn so far, and the last one's time and steps.
    private(set) var frames = 0
    private var lastTime: Double?
    private var last: [DrawStep] = []
    /// Whether the next repaint draws a new frame first.
    private var due = true

    /// The two history bitmaps, the one the next frame draws into, the
    /// latest frame's image (from the other) and the scale they are at.
    private var bitmaps: [CGContext] = []
    private var next = 0
    private var current: CGImage?
    private var historyScale = 1.0
    private var historySize = (width: 0, height: 0)
    /// While display-paced and drawing with Metal (SurfaceMetal.swift).
    private var metal: MetalSurface?

    /// The shaders the app asks for, the programs drawing now (the last
    /// good of each stage), each stage's errors, and the status last
    /// reported (SurfaceShaders.swift).
    private var shaders = ShaderRequest()
    private var warpProgram: ShaderProgram?
    private var compositeProgram: ShaderProgram?
    private var shaderErrors = StageErrors()
    /// The frame time these shaders started at, and the frames since.
    private var shaderEpoch: Double?
    private var shaderFrames: UInt32 = 0
    private var reported: String?
    private var shadersDirty = false
    /// Reports the shader status (`none`, `running`, `fallback`, or
    /// `failed` and an error a line) as the `shader` event's payload.
    var onShaderStatus: ((String) -> Void)?
    /// The next frame time a `ROC_SURFACE_SHOTS` snapshot is due, and how many.
    private var nextShot: Double?
    private var shots = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        // What a scene draws outside the surface is not shown.
        clipsToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        _ = FrameClock.shared
    }

    required init?(coder: NSCoder) { fatal("DrawingSurface is not archived") }

    override var isFlipped: Bool { true }

    /// The attributes a surface reads (all of them paint only).
    static let attributes = ["scene", "space", "background", "pacing", "trail", "reset", "label", "shader-warp", "shader-composite", "shader-params"]

    func apply(_ name: String, _ value: String?) {
        let word = value ?? ""
        switch name {
        case "scene":
            marks = Scene.parse(word)
        case "space":
            let parts = word.split(separator: " ").map(String.init)
            if word.isEmpty || word == "points" {
                space = nil
            } else if parts.count == 3, parts[0] == "fit", let w = Double(parts[1]), let h = Double(parts[2]), w > 0, h > 0, w.isFinite, h.isFinite {
                space = (w, h)
            } else {
                fatal("surface space \(word) is not points or fit WIDTH HEIGHT")
            }
        case "background":
            background = Host.color(value ?? "clear")
        case "pacing":
            switch value ?? "on-demand" {
            case "on-demand": displayPaced = false
            case "display": displayPaced = true
            default: fatal("surface pacing \(word) is not on-demand or display")
            }
            updateTicking()
        case "trail":
            let parts = word.split(separator: " ").map(String.init)
            let was = trail
            if word.isEmpty || word == "none" {
                trail = nil
            } else if parts.count == 6, parts[0] == "trail" {
                let v = parts.dropFirst().compactMap { Double($0) }.filter { $0.isFinite }
                guard v.count == 5, v[0] > 0, v[1] > 0 else { fatal("surface trail \(word) is not trail HALF-LIFE ZOOM TURN SHIFT-X SHIFT-Y, a positive half-life and zoom") }
                trail = TrailSpec(halfLifeMs: v[0], zoom: v[1], turn: v[2], shiftX: v[3], shiftY: v[4])
            } else {
                fatal("surface trail \(word) is not none or trail HALF-LIFE ZOOM TURN SHIFT-X SHIFT-Y")
            }
            if (was == nil) != (trail == nil) {
                // Starting or ending a trail starts from an empty history.
                releaseHistory()
                layer?.contents = nil
            }
        case "reset":
            // A new value (not the first) clears the trail.
            if resetWord != nil, resetWord != value { clearHistory() }
            resetWord = value
        case "label":
            label = word
            setAccessibilityLabel(word.isEmpty ? nil : word)
        case "shader-warp", "shader-composite", "shader-params":
            var next = shaders
            if name == "shader-warp" { next.warp = word }
            if name == "shader-composite" { next.composite = word }
            if name == "shader-params" {
                next.params = ShaderRequest.parseParams(word)
                next.paramsWord = word
            }
            let restart = next.warp != shaders.warp || next.composite != shaders.composite
            shaders = next
            if restart {
                // New sources start from an empty history and time 0.
                shaderEpoch = nil
                metal?.clear()
            }
            // Once for all three attributes of a turn: after it, or at the
            // next frame, whichever is first.
            if !shadersDirty {
                shadersDirty = true
                DispatchQueue.main.async { [weak self] in self?.settleShaders() }
            }
        default:
            break
        }
        wantFrame()
    }

    /// Draw a new frame at the next repaint.
    func wantFrame() {
        due = true
        needsDisplay = true
    }

    /// Forget the trail: the next frame draws over the background alone.
    func clearHistory() {
        current = nil
        metal?.clear()
        wantFrame()
    }

    private func releaseHistory() {
        bitmaps = []
        current = nil
        historySize = (0, 0)
    }

    // MARK: Frames

    /// A display refresh (or a spec's `frame`): one new frame now.
    func tick(at time: Double, link: (tick: Double, target: Double)? = nil) {
        tickedBy = link
        produce(at: time)
        tickedBy = nil
        needsDisplay = true
    }

    /// The new frame, if one is due. A surface on the frame clock draws
    /// its frames at its ticks alone, so a change waits for the next one.
    func produceIfDue() {
        if due, !ticking { produce(at: FrameClock.shared.now) }
    }

    /// How long after its display-link target a frame reaches the glass:
    /// Metal's measure of its last frames, 0 for Core Graphics.
    var presentLag: Double { metal?.presentLag ?? 0 }

    /// The display-link tick being drawn, for AVTiming.
    private var tickedBy: (tick: Double, target: Double)?

    /// Draw one logical frame at `time`.
    private func produce(at time: Double) {
        settleShaders()
        let steps = DrawingSurface.resolve(marks, at: time)
        if let metal {
            // A frame the GPU is too far behind for is skipped; the next
            // covers its time.
            guard render(steps, with: metal, at: time) else { return }
            snapshotIfDue(at: time)
        } else {
            if let link = tickedBy { _ = AVTiming.shared.frame(label: label, tick: link.tick, target: link.target, drawnFor: time, metal: false) }
            if let trail { composite(steps, trail, at: time) }
        }
        last = steps
        lastTime = time
        frames += 1
        due = false
    }

    /// Into the bitmap the previous frame is not in: the background, the
    /// previous frame moved and faded by the time since it, then the scene.
    private func composite(_ steps: [DrawStep], _ trail: TrailSpec, at time: Double) {
        let width = Double(bounds.width), height = Double(bounds.height)
        guard width >= 1, height >= 1 else { releaseHistory(); return }
        let scale = min(drawingScale, (DrawingSurface.historyPixels / (width * height)).squareRoot())
        let size = (width: Int((width * scale).rounded(.up)), height: Int((height * scale).rounded(.up)))
        if bitmaps.isEmpty || size != historySize || scale != historyScale {
            bitmaps = (0..<2).compactMap { _ in
                let c = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: size.width * 4,
                                  space: DrawingSurface.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                // Points, from the top-left corner, y down.
                c?.translateBy(x: 0, y: Double(size.height))
                c?.scaleBy(x: scale, y: -scale)
                return c
            }
            if bitmaps.count != 2 { fatal("could not make a \(size.width)x\(size.height) history bitmap for a drawing surface") }
            historySize = size
            historyScale = scale
            current = nil
            next = 0
        }
        let c = bitmaps[next]
        let imageWidth = Double(size.width) / scale, imageHeight = Double(size.height) / scale
        drawing(into: c) {
            c.saveGState()
            c.clear(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            c.setFillColor(background.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            if let previous = current, let lastTime {
                let dt = max(0, time - lastTime)
                c.saveGState()
                c.translateBy(x: trail.shiftX * dt, y: trail.shiftY * dt)
                c.translateBy(x: width / 2, y: height / 2)
                c.rotate(by: trail.turn * dt)
                let zoom = pow(trail.zoom, dt)
                c.scaleBy(x: zoom, y: zoom)
                c.translateBy(x: -width / 2, y: -height / 2)
                c.interpolationQuality = .low
                DrawingSurface.drawImage(previous, width: imageWidth, height: imageHeight, fraction: pow(0.5, dt * 1000 / trail.halfLifeMs))
                c.restoreGState()
            }
            c.saveGState()
            let m = mapping()
            c.translateBy(x: m.dx, y: m.dy)
            c.scaleBy(x: m.scale, y: m.scale)
            DrawingSurface.render(steps, in: c)
            c.restoreGState()
            c.restoreGState()
        }
        current = c.makeImage()
        next = 1 - next
    }

    /// A frame with Metal: the same order as `composite`, at the full
    /// backing resolution; a warp shader takes the trail's place, and a
    /// composite shader maps the result to the screen. False when the
    /// frame was skipped.
    private func render(_ steps: [DrawStep], with metal: MetalSurface, at time: Double) -> Bool {
        layoutMetal()
        var move: Affine?
        var fade = 1.0
        let stages = shaderFrame(at: time, metal: metal)
        if stages?.warp != nil {
            // The warp shader replaces the trail.
        } else if let trail, let lastTime {
            let dt = max(0, time - lastTime)
            let cx = Double(bounds.width) / 2, cy = Double(bounds.height) / 2
            let angle = trail.turn * dt, zoom = pow(trail.zoom, dt)
            // Shift, then about the centre: turn, then zoom.
            let turnAndZoom = Affine(a: cos(angle) * zoom, b: sin(angle) * zoom, c: -sin(angle) * zoom, d: cos(angle) * zoom, tx: 0, ty: 0)
            move = Affine(tx: trail.shiftX * dt + cx, ty: trail.shiftY * dt + cy).concat(turnAndZoom).concat(Affine(tx: -cx, ty: -cy))
            fade = pow(0.5, dt * 1000 / trail.halfLifeMs)
        } else if trail == nil {
            metal.clear()
        }
        let m = mapping()
        var scene = Tessellation([], base: Affine())
        var paint: [Float] = [0, 0, 0, 0]
        effectiveAppearance.performAsCurrentDrawingAppearance {
            scene = Tessellation(steps, base: Affine(a: m.scale, d: m.scale, tx: m.dx, ty: m.dy))
            if let c = background.usingColorSpace(.sRGB) {
                let a = Double(c.alphaComponent)
                paint = [Float(Double(c.redComponent) * a), Float(Double(c.greenComponent) * a), Float(Double(c.blueComponent) * a), Float(a)]
            }
        }
        let timing = tickedBy.map { AVTiming.shared.frame(label: label, tick: $0.tick, target: $0.target, drawnFor: time, metal: true) } ?? 0
        let drawn = metal.frame(scene, background: paint, trail: move, fade: fade, shaders: stages, label: label, timing: timing, aim: tickedBy?.target)
        if !drawn { AVTiming.shared.skippedFrame() }
        if drawn, stages != nil { shaderFrames &+= 1 }
        return drawn
    }

    // MARK: Shaders

    /// This frame's shader inputs, or nil when no stage is ready.
    private func shaderFrame(at time: Double, metal: MetalSurface) -> ShaderFrame? {
        guard let target = metal.target else { return nil }
        return shaderFrame(at: time, width: target.width, height: target.height)
    }

    private func shaderFrame(at time: Double, width: Int, height: Int, dt fixed: Double? = nil) -> ShaderFrame? {
        guard warpProgram != nil || compositeProgram != nil else { return nil }
        if shaderEpoch == nil {
            shaderEpoch = time
            shaderFrames = 0
        }
        let elapsed = Float(max(0, time - (shaderEpoch ?? time)))
        var dt: Float = 0
        if let lastTime { dt = Float(max(0, time - lastTime)) }
        if let fixed { dt = Float(fixed) }
        let w = Float(width), h = Float(height)
        let uniforms: [Float] = [
            w, h, 1 / w, 1 / h, w / h, elapsed, dt, Float(bitPattern: shaderFrames),
            DrawingSurface.scalar("audio.bass", at: time), DrawingSurface.scalar("audio.mids", at: time),
            DrawingSurface.scalar("audio.treble", at: time), DrawingSurface.scalar("audio.level", at: time),
        ]
        // Each param read once, by name, in each program's own order.
        var values: [String: Float] = [:]
        for (name, number) in shaders.params { values[name] = Float(paramValue(number, at: time)) }
        return ShaderFrame(
            warp: warpProgram, composite: compositeProgram, uniforms: uniforms,
            warpParams: (warpProgram?.params ?? []).map { values[$0] ?? 0 },
            compositeParams: (compositeProgram?.params ?? []).map { values[$0] ?? 0 },
            audio: DrawingSurface.audioBlock(at: time))
    }

    /// `bench-surfaces`: this surface's last scene and its shaders drawn
    /// `frames` times at 60 Hz into a target of `width` by `height` pixels
    /// (at 2 pixels a point, the scene fitted as the surface fits it), each
    /// waited for; the GPU's mean and most time a frame, in milliseconds,
    /// or nil without a shader running.
    func benchShaders(frames: Int, width: Int, height: Int) -> (Double, Double)? {
        guard let metal, warpProgram != nil || compositeProgram != nil else { return nil }
        let target = MetalTarget(renderer: metal.renderer, width: width, height: height, scale: 2)
        let w = Double(width) / 2, h = Double(height) / 2
        var m = Mapping(scale: 1, dx: 0, dy: 0)
        if let space {
            let s = min(w / space.width, h / space.height)
            m = Mapping(scale: s, dx: (w - space.width * s) / 2, dy: (h - space.height * s) / 2)
        }
        var sum = 0.0, most = 0.0
        let start = FrameClock.shared.now
        for i in 0..<frames {
            let time = start + Double(i) / 60
            var scene = Tessellation([], base: Affine())
            effectiveAppearance.performAsCurrentDrawingAppearance {
                scene = Tessellation(DrawingSurface.resolve(marks, at: time), base: Affine(a: m.scale, d: m.scale, tx: m.dx, ty: m.dy))
            }
            guard let stages = shaderFrame(at: time, width: width, height: height, dt: 1.0 / 60),
                  let commands = target.render(scene, background: [0, 0, 0, 1], trail: nil, fade: 1, shaders: stages)
            else { return nil }
            commands.commit()
            commands.waitUntilCompleted()
            let ms = (commands.gpuEndTime - commands.gpuStartTime) * 1000
            sum += ms
            most = max(most, ms)
            shaderFrames &+= 1
        }
        return (sum / Double(max(frames, 1)), most)
    }

    /// A param's number at `time`, as a scene's numbers read.
    private func paramValue(_ n: SceneNumber, at time: Double) -> Double {
        guard let name = n.source else { return n.offset }
        guard let sample = SurfaceSources.shared.source(name)?.latest(at: time) else { return n.offset }
        switch sample {
        case let .scalar(v): return n.index == nil ? n.offset + n.scale * Double(v) : n.offset
        case let .series(values):
            guard let i = n.index else { fatal("surface source \(name) gave a series where a shader param needs a number") }
            return i < values.count ? n.offset + n.scale * Double(values[i]) : n.offset
        }
    }

    /// The shader attributes changed since the programs were brought in line.
    private func settleShaders() {
        guard shadersDirty else { return }
        shadersDirty = false
        updateShaders()
    }

    /// Bring the programs in line with what the app asks for and the
    /// renderer in use, and report the status when it changes. A stage
    /// still compiling keeps its last good program (or none) and calls
    /// back here when done; a spec waits for it.
    func updateShaders() {
        guard shaders.wanted else {
            warpProgram = nil
            compositeProgram = nil
            shaderErrors = StageErrors()
            report("none")
            return
        }
        guard let metal else {
            // Core Graphics: the marks and the trail alone. A display-paced
            // surface that would draw with Metal but is off the clock
            // (hidden, or not yet in a window) says nothing new.
            if !displayPaced || ticking || !SurfaceRenderer.usesMetal { report("fallback") }
            return
        }
        var pending = false
        for stage in [ShaderStage.warp, .composite] {
            let source = stage == .warp ? shaders.warp : shaders.composite
            if source.isEmpty {
                set(stage, nil)
                shaderErrors[stage] = nil
                continue
            }
            if let problem = shaders.paramProblem {
                shaderErrors[stage] = [ShaderError(stage: stage, line: 0, column: 0, message: problem)]
                continue
            }
            switch metal.renderer.program(stage, source, params: shaders.names) {
            case let .ready(program):
                set(stage, program)
                shaderErrors[stage] = nil
            case let .failed(errors):
                // The last good program keeps drawing.
                shaderErrors[stage] = errors
            case let .pending(compile):
                // A spec's compiles are never pending.
                pending = true
                compile.finished.append { [weak self] in self?.updateShaders() }
            }
        }
        if pending { return }
        let errors = (shaderErrors[.warp] ?? []) + (shaderErrors[.composite] ?? [])
        report(errors.isEmpty ? "running" : (["failed"] + errors.map { $0.word }).joined(separator: "\n"))
    }

    private func set(_ stage: ShaderStage, _ program: ShaderProgram?) {
        let old = stage == .warp ? warpProgram : compositeProgram
        if old === program { return }
        if stage == .warp { warpProgram = program } else { compositeProgram = program }
        if stage == .warp, old == nil || program == nil { metal?.clear() }
        wantFrame()
    }

    /// The GPU failed a frame that ran a shader: drop both stages until
    /// the app sends new sources, and say why.
    private func shaderFault(_ why: String) {
        guard warpProgram != nil || compositeProgram != nil else { return }
        warpProgram = nil
        compositeProgram = nil
        for stage in [ShaderStage.warp, .composite] where !(stage == .warp ? shaders.warp : shaders.composite).isEmpty {
            shaderErrors[stage] = [ShaderError(stage: stage, line: 0, column: 0, message: "the GPU stopped the frame (\(why)); the surface draws without its shaders until they change")]
        }
        metal?.clear()
        let errors = (shaderErrors[.warp] ?? []) + (shaderErrors[.composite] ?? [])
        report((["failed"] + errors.map { $0.word }).joined(separator: "\n"))
    }

    private func report(_ status: String) {
        guard status != reported else { return }
        // The first `none` of a surface without shaders says nothing.
        if reported == nil, status == "none" { reported = status; return }
        reported = status
        onShaderStatus?(status)
    }

    /// The status word a dump shows: running, failed, fallback or pending.
    var shaderWord: String? {
        guard shaders.wanted else { return nil }
        guard let r = reported, r != "none" else { return "pending" }
        return r.split(separator: "\n").first.map(String.init)
    }

    /// `ROC_SURFACE_SHOTS`: this frame as a PNG, every two seconds of frame time.
    private func snapshotIfDue(at time: Double) {
        guard let dir = SurfaceDiagnostics.shots, let target = metal?.target else { return }
        guard let due = nextShot else { nextShot = time + SurfaceDiagnostics.every; return }
        guard time >= due else { return }
        nextShot = time + SurfaceDiagnostics.every
        shots += 1
        target.writePNG("\(dir)/\(SurfaceDiagnostics.fileName(label))-\(shots).png")
    }

    /// The Metal layer to the view's size and backing scale.
    private func layoutMetal() {
        metal?.layout(width: Double(bounds.width), height: Double(bounds.height), scale: drawingScale)
    }

    /// Draw with Metal while display-paced, on the frame clock and Metal is
    /// chosen and there; with Core Graphics otherwise.
    func updateRenderer() {
        let wants = ticking && SurfaceRenderer.usesMetal
        if wants, metal == nil {
            metal = MetalSurface.make(over: layer)
            metal?.onShaderFault = { [weak self] why in self?.shaderFault(why) }
            releaseHistory()
            layoutMetal()
            needsDisplay = true
        } else if !wants, let old = metal {
            old.remove()
            metal = nil
            wantFrame()
        }
        updateShaders()
    }

    /// Which renderer draws this surface.
    var rendererName: String { metal == nil ? "core graphics" : "metal (\(MetalRenderer.device?.name ?? ""))" }

    override func layout() {
        super.layout()
        layoutMetal()
    }

    /// The scene's units in this view's points.
    func mapping() -> Mapping {
        guard let space else { return Mapping(scale: 1, dx: 0, dy: 0) }
        let width = Double(bounds.width), height = Double(bounds.height)
        let s = min(width / space.width, height / space.height)
        return Mapping(scale: s, dx: (width - space.width * s) / 2, dy: (height - space.height * s) / 2)
    }

    // MARK: Showing it

    /// With a trail the layer shows the latest history bitmap; without one,
    /// `draw(_:)` draws the frame at the backing scale.
    override var wantsUpdateLayer: Bool { trail != nil || metal != nil }

    override func updateLayer() {
        if metal != nil {
            // The Metal layer above shows the frame.
            layer?.contents = nil
            return
        }
        produceIfDue()
        layer?.contents = current
    }

    override func draw(_ dirtyRect: NSRect) {
        produceIfDue()
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.setFillColor(background.cgColor)
        c.fill(bounds)
        let m = mapping()
        c.saveGState()
        c.translateBy(x: m.dx, y: m.dy)
        c.scaleBy(x: m.scale, y: m.scale)
        DrawingSurface.render(last, in: c)
        c.restoreGState()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            clearHistory()
            layoutMetal()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        clearHistory()
        layoutMetal()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        wantFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            // Removed: let go of the history and stop the frames.
            releaseHistory()
            layer?.contents = nil
            lastTime = nil
        }
        updateTicking()
        wantFrame()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateTicking()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateTicking()
    }

    /// Display-paced, in a window and not hidden: on the frame clock.
    private func updateTicking() {
        let wants = displayPaced && window != nil && !isHiddenOrHasHiddenAncestor
        if wants { FrameClock.shared.start(self) } else { FrameClock.shared.stop(self) }
        updateRenderer()
    }

    var ticking: Bool { FrameClock.shared.isTicking(self) }

    /// Whether a mark of the scene reads `source`.
    func reads(_ source: String) -> Bool {
        func shape(_ s: SceneShape) -> Bool {
            switch s {
            case .path: return false
            case let .wave(name, _), let .ring(name, _), let .bars(name, _): return name == source
            case let .lissajous(across, down, _): return across == source || down == source
            }
        }
        func number(_ n: SceneNumber) -> Bool { n.source == source }
        if shaders.params.contains(where: { number($0.1) }) { return true }
        return marks.contains { mark in
            switch mark {
            case let .fill(s, _, _): return shape(s)
            case let .stroke(s, _, _, width): return shape(s) || number(width)
            case let .translate(x, y), let .scale(x, y): return number(x) || number(y)
            case let .rotate(n), let .opacity(n): return number(n)
            case .save, .restore, .matrix: return false
            }
        }
    }

    // MARK: Probes (specs)

    /// What the surface shows, drawn at twice its size in points into an
    /// sRGB bitmap; the colour at the point (`x`, `y`) from its top-left, as
    /// percentages of red, green, blue (not premultiplied) and opacity.
    func probe(_ x: Double, _ y: Double) -> [Int] {
        produceIfDue()
        if let metal {
            // The read follows the frames on the same queue.
            guard let target = metal.target else { return [0, 0, 0, 0] }
            let p = target.pixel(Int(x * target.scale), Int(y * target.scale))
            return DrawingSurface.percentages(p[0], p[1], p[2], p[3])
        }
        let scale = 2.0
        let width = Double(bounds.width), height = Double(bounds.height)
        let px = max(1, Int((width * scale).rounded(.up))), py = max(1, Int((height * scale).rounded(.up)))
        guard let c = CGContext(data: nil, width: px, height: py, bitsPerComponent: 8, bytesPerRow: px * 4,
                                space: DrawingSurface.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { fatal("could not make a bitmap to probe a drawing surface") }
        c.translateBy(x: 0, y: Double(py))
        c.scaleBy(x: scale, y: -scale)
        drawing(into: c) {
            if trail != nil {
                if let current {
                    DrawingSurface.drawImage(current, width: Double(historySize.width) / historyScale, height: Double(historySize.height) / historyScale)
                }
            } else {
                c.setFillColor(background.cgColor)
                c.fill(CGRect(x: 0, y: 0, width: width, height: height))
                let m = mapping()
                c.translateBy(x: m.dx, y: m.dy)
                c.scaleBy(x: m.scale, y: m.scale)
                DrawingSurface.render(last, in: c)
            }
        }
        let col = Int(x * scale), row = Int(y * scale)
        guard col >= 0, row >= 0, col < px, row < py, let data = c.data else { return [0, 0, 0, 0] }
        let p = data.assumingMemoryBound(to: UInt8.self) + row * px * 4 + col * 4
        return DrawingSurface.percentages(Int(p[0]), Int(p[1]), Int(p[2]), Int(p[3]))
    }

    /// A premultiplied 8-bit pixel as percentages, not premultiplied.
    static func percentages(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> [Int] {
        func channel(_ v: Int) -> Int { a == 0 ? 0 : Int((Double(v) / Double(a) * 100).rounded()) }
        return [channel(r), channel(g), channel(b), Int((Double(a) / 255 * 100).rounded())]
    }

    /// The surface's head in a spec's dump: its label, size, pacing and
    /// trail (`:trail held` once its trail has a bitmap, `empty` before).
    var dumpHead: String {
        let pacing = displayPaced ? "display" : "on-demand"
        let held = metal.map { $0.target?.hasHistory ?? false } ?? (current != nil)
        let history = trail == nil ? "" : " :trail \(held ? "held" : "empty")"
        let shading = shaderWord.map { " :shader \($0)" } ?? ""
        return "\(Host.quote(label)) :width \(Int(bounds.width)) :height \(Int(bounds.height)) :pacing \(pacing)\(displayPaced ? " :ticking \(ticking ? "#t" : "#f")" : "")\(history)\(shading)"
    }

    /// The last frame's scene, one form a line, for a spec's dump: the
    /// space it maps from, then each step in the order it drew.
    func sceneForms() -> [String] {
        guard !last.isEmpty || space != nil else { return [] }
        var lines: [String] = []
        let m = mapping()
        if let space {
            lines.append("(space :fit \(Host.decimal(space.width)) \(Host.decimal(space.height)) :scale \(Host.decimal(m.scale, 3)) :offset \(Host.decimal(m.dx)) \(Host.decimal(m.dy)))")
        } else {
            lines.append("(space :points)")
        }
        for step in last {
            switch step {
            case let .figure(fill, _, word, width, path):
                var ends: [String] = []
                for p in path {
                    switch p {
                    case let .move(x, y), let .line(x, y), let .quad(_, _, x, y), let .curve(_, _, _, _, x, y):
                        ends.append("\(Host.decimal(x)),\(Host.decimal(y))")
                    case .close: ends.append("close")
                    }
                }
                let paint = fill ? "fill \(Host.atom(word))" : "stroke \(Host.atom(word)) \(Host.decimal(width))"
                lines.append("(\(paint) \(ends.joined(separator: " ")))")
            case .save: lines.append("(save)")
            case .restore: lines.append("(restore)")
            case let .transform(a, b, c, d, tx, ty):
                lines.append("(transform \([a, b, c, d, tx, ty].map { Host.decimal($0, 3) }.joined(separator: " ")))")
            case let .opacity(amount): lines.append("(opacity \(Host.decimal(amount, 3)))")
            }
        }
        return lines
    }
}

// MARK: - The frame clock

/// Each display-paced surface's frames: at its display's refresh
/// (`NSView.displayLink`, on the main run loop in its common modes), or,
/// under a spec, only when a `frame` step advances the controlled clock,
/// so a spec runs the same everywhere.
final class FrameClock {
    static let shared = FrameClock()

    /// Whether frames come from `frame` steps rather than the display.
    private(set) var manual = Host.scripted
    /// The controlled clock's time, in seconds.
    private(set) var manualTime = 0.0
    /// The surfaces on the clock, in the order they started.
    private var ticking: [DrawingSurface] = []
    private var links: [ObjectIdentifier: FrameLink] = [:]
    init() {
        SyntheticSource.followsTime = !manual
        SyntheticSource.registerAll()
    }

    /// The time a new frame is drawn at: monotonic seconds.
    var now: Double { manual ? manualTime : ProcessInfo.processInfo.systemUptime }

    func isTicking(_ s: DrawingSurface) -> Bool { ticking.contains { $0 === s } }

    var tickingCount: Int { ticking.count }

    func start(_ s: DrawingSurface) {
        guard !isTicking(s) else { return }
        ticking.append(s)
        if !manual { links[ObjectIdentifier(s)] = FrameLink(view: s) }
    }

    func stop(_ s: DrawingSurface) {
        ticking.removeAll { $0 === s }
        links.removeValue(forKey: ObjectIdentifier(s))?.stop()
    }

    /// The controlled clock on by `seconds`, and one frame for every
    /// surface on it.
    func advance(_ seconds: Double) {
        manualTime += seconds
        for s in ticking { s.tick(at: manualTime) }
    }

    /// Frames from the display from here on (`clock:display`), or from
    /// `frame` steps (`clock:manual`).
    func use(manual: Bool) {
        guard manual != self.manual else { return }
        let surfaces = ticking
        for s in surfaces { stop(s) }
        self.manual = manual
        if manual { manualTime = ProcessInfo.processInfo.systemUptime }
        SyntheticSource.followsTime = !manual
        for s in surfaces { start(s) }
    }
}

/// A surface's display link. AppKit's (macOS 14) follows the screen the view
/// is on, calls on the main thread, and skips refreshes the main thread was
/// too busy for.
final class FrameLink: NSObject {
    private var link: CADisplayLink?
    private weak var surface: DrawingSurface?

    init(view: DrawingSurface) {
        surface = view
        super.init()
        let link = view.displayLink(target: self, selector: #selector(fire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc func fire(_ link: CADisplayLink) {
        guard let surface else { stop(); return }
        // The frame is drawn for when it will be on the screen, not for
        // now: the refresh it targets, plus how far behind their targets
        // its last frames reached the glass (Metal's presented times). Its
        // sources read the sound heard then, and its shaders' time and dt
        // count in the same refreshes.
        surface.tick(at: link.targetTimestamp + surface.presentLag, link: (link.timestamp, link.targetTimestamp))
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}

// MARK: - Overlay

/// `ui-overlay`: a background filling the view and sizing it, and a
/// foreground over it, inside `padding`, placed by `horizontal` and
/// `vertical`. The foreground is drawn by its own views, above the
/// background's layer, so it never enters a surface's history.
final class Overlay: NSView {
    private(set) var back: NSView?
    private(set) var front: NSView?
    private var pins: [NSLayoutConstraint] = []
    private var horizontal = "fill"
    private var vertical = "bottom"
    private var insets: [Double] = [16, 16, 16, 16]

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatal("Overlay is not archived") }

    override var isFlipped: Bool { true }

    func configure(_ attrs: [String: String]) {
        horizontal = attrs["horizontal"] ?? "fill"
        vertical = attrs["vertical"] ?? "bottom"
        if !["leading", "center", "trailing", "fill"].contains(horizontal) { fatal("overlay horizontal \(horizontal) is not leading, center, trailing or fill") }
        if !["top", "center", "bottom", "fill"].contains(vertical) { fatal("overlay vertical \(vertical) is not top, center, bottom or fill") }
        let e = Host.insets(attrs["padding"] ?? "16 16 16 16")
        insets = [Double(e.top), Double(e.left), Double(e.bottom), Double(e.right)]
        place()
    }

    /// Hold `background` and `foreground` (either may be nil).
    func hold(_ background: NSView?, _ foreground: NSView?) {
        if back === background, front === foreground { return }
        for old in [back, front] where old !== background && old !== foreground { old?.removeFromSuperview() }
        back = background
        front = foreground
        for v in [background, foreground].compactMap({ $0 }) {
            v.translatesAutoresizingMaskIntoConstraints = false
            if v.superview !== self { addSubview(v) }
        }
        // The foreground above the background.
        if let background, let foreground { addSubview(foreground, positioned: .above, relativeTo: background) }
        place()
    }

    private func place() {
        NSLayoutConstraint.deactivate(pins)
        pins = []
        if let back {
            pins += [
                back.topAnchor.constraint(equalTo: topAnchor),
                back.leadingAnchor.constraint(equalTo: leadingAnchor),
                back.trailingAnchor.constraint(equalTo: trailingAnchor),
                back.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        }
        if let front {
            let top = front.topAnchor, bottom = bottomAnchor, lead = front.leadingAnchor, trail = trailingAnchor
            // Always inside the padding.
            pins += [
                top.constraint(greaterThanOrEqualTo: topAnchor, constant: insets[0]),
                lead.constraint(greaterThanOrEqualTo: leadingAnchor, constant: insets[1]),
                bottom.constraint(greaterThanOrEqualTo: front.bottomAnchor, constant: insets[2]),
                trail.constraint(greaterThanOrEqualTo: front.trailingAnchor, constant: insets[3]),
            ]
            switch horizontal {
            case "leading": pins.append(lead.constraint(equalTo: leadingAnchor, constant: insets[1]))
            case "trailing": pins.append(trail.constraint(equalTo: front.trailingAnchor, constant: insets[3]))
            case "center": pins.append(front.centerXAnchor.constraint(equalTo: centerXAnchor, constant: (insets[1] - insets[3]) / 2))
            default:
                pins.append(lead.constraint(equalTo: leadingAnchor, constant: insets[1]))
                pins.append(trail.constraint(equalTo: front.trailingAnchor, constant: insets[3]))
            }
            switch vertical {
            case "top": pins.append(top.constraint(equalTo: topAnchor, constant: insets[0]))
            case "bottom": pins.append(bottom.constraint(equalTo: front.bottomAnchor, constant: insets[2]))
            case "center": pins.append(front.centerYAnchor.constraint(equalTo: centerYAnchor, constant: (insets[0] - insets[2]) / 2))
            default:
                pins.append(top.constraint(equalTo: topAnchor, constant: insets[0]))
                pins.append(bottom.constraint(equalTo: front.bottomAnchor, constant: insets[2]))
            }
        }
        NSLayoutConstraint.activate(pins)
    }
}

// MARK: - Spec steps

extension Host {
    /// A spec's drawing steps and expectations (cli/Spec.roc, docs/apps.adoc);
    /// nil for a verb that is not one of them.
    func drawingStep(_ line: SpecSteps.Line) -> Performed? {
        let clock = FrameClock.shared
        let f = line.fields
        switch line.verb {
        case "frame":
            // `(frame MS)` (a 60 Hz refresh, 16.667, if none): the manual
            // clock on by MS, and one frame for each display-paced surface on it.
            guard clock.manual else { return .failed("frame needs the manual frame clock, not (frame-clock display)", nil) }
            let arg = f.first ?? ""
            let ms = arg.isEmpty ? 1000.0 / 60 : (Double(arg) ?? -1)
            guard ms >= 0, ms.isFinite else { return .failed("frame takes milliseconds, not \(arg)", nil) }
            clock.advance(ms / 1000)
        case "frame-clock":
            switch f.first ?? "" {
            case "display": clock.use(manual: false)
            case "manual": clock.use(manual: true)
            default: return .failed("frame-clock is manual or display, not \(f.first ?? "")", nil)
            }
        case "step-source":
            // `(step-source "NAME" N)`: a synthetic source on by N steps.
            guard let name = f.first, let source = SyntheticSource.named[name], let count = Int(f.count > 1 ? f[1] : "1"), count >= 1
            else { return .failed("step-source names no synthetic source; they are \(SurfaceSources.shared.names.joined(separator: ", "))", nil) }
            source.step(count)
            for s in allSurfaces() where !s.ticking && s.reads(name) { s.wantFrame() }
        case "repaint":
            // Redraw every surface now, as AppKit may at any time.
            for s in allSurfaces() { s.display() }
        case "window-size":
            guard f.count == 2, let w = Double(f[0]), let h = Double(f[1]), w > 0, h > 0 else { return .failed("window-size needs a width and a height", nil) }
            let room = windowRoom()
            window.setContentSize(NSSize(width: min(w, room.width), height: min(h, room.height)))
            window.contentView?.layoutSubtreeIfNeeded()
        case "screen-size":
            // The window from here on has room for this much content, as on
            // a screen this size, and the page scrolls what does not fit.
            guard f.count == 2, let w = Double(f[0]), let h = Double(f[1]), w > 0, h > 0 else { return .failed("screen-size needs a width and a height", nil) }
            SpecScreen.room = NSSize(width: w, height: h)
            refit()
            window.contentView?.layoutSubtreeIfNeeded()
        case "renderer":
            // Display-paced surfaces from here on draw with this renderer
            // (`metal` without a device is Core Graphics).
            guard let chosen = SurfaceRenderer.named(f.first ?? "") else { return .failed("renderer is metal, cg or auto, not \(f.first ?? "")", nil) }
            SurfaceRenderer.choice = chosen
            for s in allSurfaces() { s.updateRenderer() }
        case "require-metal":
            // The rest of the spec needs a GPU: without one (or with
            // `ROC_SURFACE_RENDERER=cg`, to check this) the run ends here,
            // and the tool judges nothing after it.
            let forced = ProcessInfo.processInfo.environment["ROC_SURFACE_RENDERER"] == "cg"
            guard MetalRenderer.device != nil, !forced else {
                emit("@\(line.k) skip \(forced ? "ROC_SURFACE_RENDERER=cg" : "no Metal device")")
                emit("@done")
                NSApp.terminate(nil)
                return .handedOver
            }
        case "bench-surfaces":
            // N frames of a trail at three sizes with each renderer,
            // reported on standard error and never judged.
            let n = Int(f.first ?? "") ?? 100
            benchSurfaces(frames: n)
            // And each surface running shaders, its own frame, GPU time alone.
            for s in allSurfaces() {
                for (w, h) in [(1600, 1000), (2560, 1664), (2880, 1800)] {
                    guard let (mean, most) = s.benchShaders(frames: n, width: w, height: h) else { continue }
                    say("bench shaders \"\(s.label)\" \(w)x\(h) px: gpu \(Host.decimal(mean, 2)) ms mean, \(Host.decimal(most, 2)) ms most a frame")
                }
            }
        case "probe":
            // The colour a surface shows at a point, from its top-left, in
            // percent of red, green, blue and opacity.
            let (parts, rest) = Host.locator(f)
            let found = locate(parts)
            guard found.nodes.count == 1, let s = found.nodes[0].view as? DrawingSurface else {
                return .failed("found \(found.nodes.isEmpty ? "no" : "\(found.nodes.count) of") \(Host.describe(parts)), looking for a drawing surface; a step acts on exactly one", found)
            }
            guard rest.count == 2, let x = Double(rest[0]), let y = Double(rest[1]) else { return .failed("probe needs x and y", nil) }
            let v = s.probe(x, y)
            emit("@\(line.k) obs")
            for (name, value) in zip(["r", "g", "b", "a"], v) { emit("|\(name) \(value)") }
        case "surfaces":
            emit("@\(line.k) obs")
            emit("|shown \(allSurfaces().count)")
            emit("|ticking \(clock.tickingCount)")
            emit("|time \(Host.decimal(clock.manualTime * 1000))")
        default:
            return nil
        }
        return .next
    }

    /// A surface's or an overlay's own attribute, applied; false for any
    /// other. Not inlined into `applyAttr`, whose size would leave the
    /// string helpers this uses out of line (symbols the catalog does not own).
    @inline(never)
    func applyDrawingAttr(_ n: Node, _ name: String, _ value: String?) -> Bool {
        if let surface = n.view as? DrawingSurface, DrawingSurface.attributes.contains(name) {
            surface.apply(name, value)
            return true
        }
        if let overlay = n.view as? Overlay, ["horizontal", "vertical", "padding"].contains(name) {
            overlay.configure(n.attrs)
            return true
        }
        return false
    }

    /// A source's change redraws the on-demand surfaces that read it.
    func watchSurfaceSources() {
        SurfaceSources.shared.onChange = { [weak self] name in
            for s in self?.allSurfaces() ?? [] where !s.ticking && s.reads(name) { s.wantFrame() }
        }
    }

    func allSurfaces() -> [DrawingSurface] {
        var found: [DrawingSurface] = []
        root.walk { if let s = $0.view as? DrawingSurface { found.append(s) } }
        return found
    }

    /// `value` to `places` decimal places, without a negative zero.
    static func decimal(_ value: Double, _ places: Int = 1) -> String {
        var factor = 1.0
        for _ in 0..<places { factor *= 10 }
        let n = Int((value * factor).rounded())
        let whole = abs(n) / Int(factor), part = abs(n) % Int(factor)
        let digits = String(part)
        return "\(n < 0 ? "-" : "")\(whole).\(String(repeating: "0", count: places - digits.count))\(digits)"
    }
}
