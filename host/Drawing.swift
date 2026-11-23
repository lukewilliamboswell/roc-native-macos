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
// A surface with a trail keeps two bitmaps: each frame clears one to the
// background, draws the previous frame (the other) into it moved and faded
// by the time since that frame, then the scene over it, and shows it as the
// layer's contents. They are at most `historyPixels` pixels each, at the
// backing scale or below it for a large surface, and are let go when the
// surface leaves its window (docs/architecture.adoc, "Drawing surfaces").

import AppKit
import QuartzCore

// MARK: - The scene

/// A number of a scene: `offset`, plus `scale` times a source's scalar.
struct SceneNumber {
    let offset: Double
    let source: String?
    let scale: Double
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
    /// As bars (`values`: x y w h low high gap).
    case bars(String, [Double])
}

enum SceneMark {
    case fill(SceneShape, NSColor, String)
    case stroke(SceneShape, NSColor, String, Double)
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
                let width = w.number("a line width")
                if width < 0 { w.fail("a line width is not negative") }
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

        /// A constant, or `@source:scale:offset`.
        mutating func sceneNumber() -> SceneNumber {
            let text = word("a number")
            guard text.hasPrefix("@") else {
                at -= 1
                return SceneNumber(offset: number("a number"), source: nil, scale: 0)
            }
            let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let name = parts.first?.split(separator: "@").map(String.init) ?? []
            guard parts.count == 3, name.count == 1, SurfaceSources.valid(name[0]), let scale = Double(parts[1]), let offset = Double(parts[2]), scale.isFinite, offset.isFinite
            else { fail("\(text) is not @source:scale:offset") }
            return SceneNumber(offset: offset, source: name[0], scale: scale)
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
        func value(_ n: SceneNumber) -> Double {
            guard let name = n.source else { return n.offset }
            guard let sample = SurfaceSources.shared.source(name)?.latest(at: time) else { return n.offset }
            guard case let .scalar(v) = sample else { fatal("surface source \(name) gave a series where the scene needs a number") }
            return n.offset + n.scale * Double(v)
        }
        func series(_ name: String) -> [Float] {
            guard let sample = SurfaceSources.shared.source(name)?.latest(at: time) else { return [] }
            guard case let .series(values) = sample else { fatal("surface source \(name) gave a number where the scene needs a series") }
            if values.count > SurfaceSample.maxSeries { fatal("surface source \(name) gave \(values.count) values, more than the \(SurfaceSample.maxSeries) a series may hold") }
            return values
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
                if !p.isEmpty { steps.append(.figure(fill: false, color: color, word: word, width: width, path: p)) }
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
    static let attributes = ["scene", "space", "background", "pacing", "trail", "reset", "label"]

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
        wantFrame()
    }

    private func releaseHistory() {
        bitmaps = []
        current = nil
        historySize = (0, 0)
    }

    // MARK: Frames

    /// A display refresh (or a scripted `frame`): one new frame now.
    func tick(at time: Double) {
        produce(at: time)
        needsDisplay = true
    }

    /// The new frame, if one is due. A surface on the frame clock draws
    /// its frames at its ticks alone, so a change waits for the next one.
    func produceIfDue() {
        if due, !ticking { produce(at: FrameClock.shared.now) }
    }

    /// Draw one logical frame at `time`.
    private func produce(at time: Double) {
        let steps = DrawingSurface.resolve(marks, at: time)
        if let trail { composite(steps, trail, at: time) }
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
        let backing = Double(window?.backingScaleFactor ?? 2)
        let scale = min(backing, (DrawingSurface.historyPixels / (width * height)).squareRoot())
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
    override var wantsUpdateLayer: Bool { trail != nil }

    override func updateLayer() {
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
        if changed { clearHistory() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        clearHistory()
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
    }

    var ticking: Bool { FrameClock.shared.isTicking(self) }

    /// Whether a mark of the scene reads `source`.
    func reads(_ source: String) -> Bool {
        func shape(_ s: SceneShape) -> Bool {
            switch s {
            case .path: return false
            case let .wave(name, _), let .ring(name, _), let .bars(name, _): return name == source
            }
        }
        func number(_ n: SceneNumber) -> Bool { n.source == source }
        return marks.contains { mark in
            switch mark {
            case let .fill(s, _, _), let .stroke(s, _, _, _): return shape(s)
            case let .translate(x, y), let .scale(x, y): return number(x) || number(y)
            case let .rotate(n), let .opacity(n): return number(n)
            case .save, .restore, .matrix: return false
            }
        }
    }

    // MARK: Probes (scripted runs)

    /// What the surface shows, drawn at twice its size in points into an
    /// sRGB bitmap; the colour at the point (`x`, `y`) from its top-left, as
    /// percentages of red, green, blue (not premultiplied) and opacity.
    func probe(_ x: Double, _ y: Double) -> [Int] {
        produceIfDue()
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
        let a = Double(p[3])
        func channel(_ v: UInt8) -> Int { a == 0 ? 0 : Int((Double(v) / a * 100).rounded()) }
        return [channel(p[0]), channel(p[1]), channel(p[2]), Int((a / 255 * 100).rounded())]
    }

    /// The dump's line: size, frames, pacing and trail.
    var summary: String {
        let pacing = displayPaced ? (ticking ? "display-paced, ticking" : "display-paced, suspended") : "on demand"
        let history = trail == nil ? "" : (current == nil ? ", trail empty" : ", trail of 2 bitmaps")
        return "\"\(label)\" [\(Int(bounds.width))pt wide, \(Int(bounds.height))pt high, \(pacing)\(history)]"
    }

    /// The last frame's steps, for the scripted `scene` step.
    func describe() -> [String] {
        var lines: [String] = []
        let m = mapping()
        if let space {
            lines.append("space fit \(Host.decimal(space.width))x\(Host.decimal(space.height)) in \(Int(bounds.width))pt wide, \(Int(bounds.height))pt high: scale \(Host.decimal(m.scale, 3)), offset \(Host.decimal(m.dx)),\(Host.decimal(m.dy))")
        } else {
            lines.append("space points in \(Int(bounds.width))pt wide, \(Int(bounds.height))pt high")
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
                let paint = fill ? "fill \(word)" : "stroke \(word) \(Host.decimal(width))"
                lines.append("\(paint): \(ends.joined(separator: " "))")
            case .save: lines.append("save")
            case .restore: lines.append("restore")
            case let .transform(a, b, c, d, tx, ty):
                lines.append("transform \([a, b, c, d, tx, ty].map { Host.decimal($0, 3) }.joined(separator: " "))")
            case let .opacity(amount): lines.append("opacity \(Host.decimal(amount, 3))")
            }
        }
        return lines
    }
}

// MARK: - The frame clock

/// Each display-paced surface's frames: at its display's refresh
/// (`NSView.displayLink`, on the main run loop in its common modes), or,
/// under a scripted run, only when a `frame` step advances the controlled
/// clock, so a recorded case runs the same everywhere.
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
        surface.tick(at: ProcessInfo.processInfo.systemUptime)
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

// MARK: - Scripted steps

extension Host {
    /// The drawing steps of a scripted run (docs/apps.adoc); false for a
    /// verb that is not one of them.
    func surfaceStep(_ verb: String, _ arg: String) -> Bool {
        let clock = FrameClock.shared
        switch verb {
        case "frame":
            // `frame:MS` (default 16.667): the controlled clock on by MS,
            // and one frame for each display-paced surface on it.
            guard clock.manual else { fatal("script: frame needs the controlled clock, not clock:display") }
            let ms = arg.isEmpty ? 1000.0 / 60 : (Double(arg) ?? -1)
            guard ms >= 0, ms.isFinite else { fatal("script: frame:\(arg) is not a number of milliseconds") }
            let count = clock.tickingCount
            clock.advance(ms / 1000)
            say("frame at \(Host.decimal(clock.manualTime * 1000)) ms: \(count == 1 ? "1 surface" : "\(count) surfaces")")
        case "clock":
            switch arg {
            case "display": clock.use(manual: false)
            case "manual": clock.use(manual: true)
            default: fatal("script: clock:\(arg) is not clock:display or clock:manual")
            }
        case "step":
            // `step:NAME` or `step:NAME,COUNT`: a synthetic source on.
            let parts = arg.split(separator: ",").map(String.init)
            guard let name = parts.first, let source = SyntheticSource.named[name],
                  parts.count <= 2, let count = parts.count == 2 ? Int(parts[1]) : 1
            else { fatal("script: step:\(arg) names no synthetic source (\(SurfaceSources.shared.names.joined(separator: ", ")))") }
            source.step(count)
            for s in allSurfaces() where !s.ticking && s.reads(name) { s.wantFrame() }
        case "probe":
            // `probe:x,y`: the first surface's colour at a point, from its top-left.
            guard let p = Host.point(arg) else { fatal("script: probe needs x,y, not \(arg)") }
            let v = firstSurface().probe(Double(p.x), Double(p.y))
            say("probe \(arg): r\(v[0]) g\(v[1]) b\(v[2]) a\(v[3])")
        case "scene":
            let s = firstSurface()
            s.produceIfDue()
            say("scene of \"\(s.label)\":")
            for line in s.describe() { say("  \(line)") }
        case "repaint":
            // Redraw every surface now, as AppKit may at any time.
            for s in allSurfaces() { s.display() }
            say("repaint")
        case "size":
            // `size:W,H`: the window's content size, in points.
            guard let p = Host.point(arg), p.x > 0, p.y > 0 else { fatal("script: size needs W,H, not \(arg)") }
            window.setContentSize(NSSize(width: p.x, height: p.y))
            window.contentView?.layoutSubtreeIfNeeded()
        case "surfaces":
            let all = allSurfaces()
            say("surfaces: \(all.count) shown, \(clock.tickingCount) on the frame clock")
        default:
            return false
        }
        return true
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

    func firstSurface() -> DrawingSurface {
        guard let s = allSurfaces().first else { fatal("script: no drawing surface") }
        return s
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
