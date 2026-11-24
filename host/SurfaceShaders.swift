// A drawing surface's own shaders (`Ui.surface`'s `shader`), in two stages
// shaped like a feedback visualizer's: a warp, which makes each frame from
// the previous one, and a composite, which maps the result to the screen.
//
// An app writes each stage as one Metal Shading Language function with a
// fixed signature, `float4 warp(Frame f, Params p)` or
// `float4 composite(Frame f, Params p)`, plus any helpers it likes above it.
// The host compiles it at run time with `makeLibrary(source:options:)`,
// between its own header (`ShaderSource.header`: the `Frame` and `Params`
// structs and the helpers) and its own fragment entry point, so the host
// build has no Metal step and stays reproducible. A `#line` directive before
// the app's text makes the compiler count the app's lines from 1, so an
// error names the line the app wrote.
//
// Compiling runs off the main thread (Metal's own completion queue) and its
// result comes back to the main thread; until then the surface keeps
// drawing with its last good stage, or none. A spec waits for it, so a spec
// draws the same frames everywhere. Programs are cached by their whole
// source (header, params and the app's text) while the renderer lives.
// Nothing here calls the engine: a surface reports its status through its
// `shader` event, which the host delivers after the frame, on the main run
// loop (docs/architecture.adoc, "Surface shaders").

import AppKit
import Metal

/// The two stages.
enum ShaderStage {
    case warp
    case composite

    /// The stage's function name, and its word in the `shader` event.
    var name: String {
        switch self {
        case .warp: return "warp"
        case .composite: return "composite"
        }
    }

    /// Whether this is the warp stage. A `switch`, not `stage == .warp`:
    /// Swift 6.3 calls `==` on a plain enum through the standard library's
    /// `Equatable` dispatch thunk, a symbol the catalog does not own.
    var isWarp: Bool {
        switch self {
        case .warp: return true
        case .composite: return false
        }
    }
}

/// One compile error, at the app's line and column (0 when it is in the
/// host's part, such as a missing function).
struct ShaderError {
    let stage: ShaderStage
    let line: Int
    let column: Int
    let message: String

    /// The error as a line of the `shader` event's payload.
    var word: String { "\(stage.name) \(line) \(column) \(message)" }
}

/// Each stage's errors.
struct StageErrors {
    var warp: [ShaderError] = []
    var composite: [ShaderError] = []

    subscript(stage: ShaderStage) -> [ShaderError]? {
        get { stage.isWarp ? warp : composite }
        set {
            if stage.isWarp { warp = newValue ?? [] } else { composite = newValue ?? [] }
        }
    }
}

/// A compiled stage: its pipeline and the params, in the order its `Params`
/// struct lays them out.
final class ShaderProgram {
    let pipeline: MTLRenderPipelineState
    let params: [String]

    init(pipeline: MTLRenderPipelineState, params: [String]) {
        self.pipeline = pipeline
        self.params = params
    }
}

/// What a stage's source compiled to, or is compiling to.
enum ShaderOutcome {
    case ready(ShaderProgram)
    case failed([ShaderError])
    case pending(ShaderCompile)
}

/// One compile. A person's runs on Metal's own queue, and its outcome
/// arrives on the main thread; a spec's compiles at once, on the main
/// thread, so a spec draws the same frames everywhere.
final class ShaderCompile {
    /// The outcome, once there is one (main thread).
    private(set) var outcome: ShaderOutcome?
    /// Called on the main thread once it is done.
    var finished: [() -> Void] = []

    init(_ stage: ShaderStage, source: String, params: [String], renderer: MetalRenderer, now: Bool) {
        let program = ShaderSource.program(stage, source, params: params)
        let lines = ShaderSource.appLines(source)
        if now {
            do {
                outcome = ShaderCompile.link(try renderer.device.makeLibrary(source: program, options: nil), stage, params, renderer)
            } catch {
                outcome = .failed(ShaderSource.errors(stage, AudioService.describe(error), appLines: lines))
            }
            return
        }
        renderer.device.makeLibrary(source: program, options: nil) { library, error in
            // Metal's queue: make the pipeline here too, then hand it over.
            let made = library.map { ShaderCompile.link($0, stage, params, renderer) }
                ?? .failed(ShaderSource.errors(stage, error.map { AudioService.describe($0) } ?? "it did not compile", appLines: lines))
            DispatchQueue.main.async {
                self.outcome = made
                let calls = self.finished
                self.finished = []
                for call in calls { call() }
            }
        }
    }

    /// A compiled library's stage as a pipeline.
    private static func link(_ library: MTLLibrary, _ stage: ShaderStage, _ params: [String], _ renderer: MetalRenderer) -> ShaderOutcome {
        guard let fragment = library.makeFunction(name: "roc_stage") else {
            return .failed([ShaderError(stage: stage, line: 0, column: 0, message: "the \(stage.name) shader has no entry point")])
        }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = renderer.fullVertex
        d.fragmentFunction = fragment
        d.colorAttachments[0].pixelFormat = MetalRenderer.colorFormat
        if stage.isWarp {
            // Drawn first in the multisampled pass the scene draws in.
            d.rasterSampleCount = MetalRenderer.samples
            d.stencilAttachmentPixelFormat = .stencil8
        }
        guard let pipeline = try? renderer.device.makeRenderPipelineState(descriptor: d) else {
            return .failed([ShaderError(stage: stage, line: 0, column: 0, message: "the GPU could not make a pipeline of the \(stage.name) shader")])
        }
        return .ready(ShaderProgram(pipeline: pipeline, params: params))
    }
}

/// The source a stage compiles from, and how its errors read.
enum ShaderSource {
    /// The most bytes of one stage's source.
    static let maxBytes = 65_536
    /// The most params a surface may name.
    static let maxParams = 16
    /// The audio block's layout, in floats: three 256-value waveforms (mono,
    /// left, right), then the 24 bands, padded to 800.
    static let wavePoints = 256
    static let bandCount = 24
    static let audioFloats = 800

    /// A param's name is a C identifier of lowercase letters, digits and
    /// `_`, not starting with a digit, at most 32 bytes.
    static func validName(_ name: String) -> Bool {
        guard let first = name.utf8.first, name.utf8.count <= 32, !(first >= 0x30 && first <= 0x39) else { return false }
        return name.utf8.allSatisfy { c in (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c == 0x5f }
    }

    /// The number of lines of the app's text.
    static func appLines(_ source: String) -> Int { source.split(separator: "\n", omittingEmptySubsequences: false).count }

    /// A stage's whole program: the header, the params struct, the app's
    /// text counted from its own line 1, and the entry point.
    static func program(_ stage: ShaderStage, _ source: String, params: [String]) -> String {
        let fields = params.isEmpty ? "    float unused_;\n" : params.map { "    float \($0);\n" }.joined()
        return header + "struct Params {\n" + fields + "};\n#line 1 \"" + stage.name + "\"\n" + source + "\n#line 1 \"roc-entry\"\n" + entry(stage)
    }

    /// The fragment function the host draws with, calling the app's.
    static func entry(_ stage: ShaderStage) -> String {
        """
        fragment float4 roc_stage(RocTextured in [[stage_in]], constant RocUniforms &u [[buffer(0)]], constant Params &p [[buffer(1)]],
                                  constant float *audio [[buffer(2)]], texture2d<float> image [[texture(0)]]) {
            Frame f;
            f.uv = in.uv;
            f.pixel = in.position.xy;
            f.size = u.size;
            f.texel = u.texel;
            f.aspect = u.aspect;
            f.time = u.time;
            f.dt = u.dt;
            f.frame = u.frame;
            f.bass = u.bass;
            f.mids = u.mids;
            f.treble = u.treble;
            f.level = u.level;
            f.image = image;
            f.audio = audio;
            float4 c = \(stage.name)(f, p);
            // Never a NaN, and premultiplied: no channel above the opacity.
            c = select(c, float4(0.0), isnan(c));
            c = saturate(c);
            return float4(min(c.rgb, c.a), c.a);
        }
        """
    }

    /// The compiler's messages as errors: each `FILE:LINE:COL: error: …`
    /// line, at the app's line when FILE is the stage's own text and at
    /// line 0 otherwise; the first eight.
    static func errors(_ stage: ShaderStage, _ log: String, appLines: Int) -> [ShaderError] {
        var found: [ShaderError] = []
        for raw in log.split(separator: "\n") {
            let line = String(raw)
            let parts = line.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5, let row = Int(parts[1]), let col = Int(parts[2]), parts[3].hasSuffix("error") else { continue }
            let message = String(parts[4].drop { $0 == " " })
            let own = parts[0].hasSuffix(stage.name) && row >= 1 && row <= appLines
            found.append(ShaderError(stage: stage, line: own ? row : 0, column: own ? col : 0,
                                     message: own ? message : "\(message) (in the host's part: does the source define float4 \(stage.name)(Frame f, Params p)?)"))
            if found.count == 8 { break }
        }
        if found.isEmpty {
            let first = log.split(separator: "\n").first.map(String.init) ?? "it did not compile"
            found.append(ShaderError(stage: stage, line: 0, column: 0, message: first))
        }
        return found
    }

    /// The header every stage compiles under (docs/ui.adoc, "Shaders").
    static let header = """
    #include <metal_stdlib>
    using namespace metal;

    // ---- What a stage is given (docs/ui.adoc, "Shaders") ----

    constant float PI = 3.14159265358979;
    constant float TAU = 6.28318530717959;

    struct RocUniforms {
        float2 size;
        float2 texel;
        float aspect;
        float time;
        float dt;
        uint frame;
        float bass;
        float mids;
        float treble;
        float level;
    };

    struct RocTextured {
        float4 position [[position]];
        float2 uv;
    };

    /// This pixel and the frame it is part of.
    struct Frame {
        float2 uv;       // the pixel's centre: 0 to 1 across and down from the top-left corner
        float2 pixel;    // the same in pixels
        float2 size;     // the surface in pixels
        float2 texel;    // one pixel in uv units, 1 / size
        float aspect;    // width / height
        float time;      // seconds since these shaders started
        float dt;        // seconds since the previous frame
        uint frame;      // frames since these shaders started, from 0
        float bass;      // audio.bass, audio.mids, audio.treble and audio.level, 0 to 1
        float mids;
        float treble;
        float level;
        texture2d<float> image;   // the previous frame (warp) or this frame (composite)
        constant float *audio;    // the waveforms and bands: use wave, left, right and band
    };

    // ---- Reading the image ----

    constexpr sampler roc_edge(filter::linear, address::clamp_to_edge);
    constexpr sampler roc_wrap(filter::linear, address::repeat);
    constexpr sampler roc_mirror(filter::linear, address::mirrored_repeat);

    /// The image at `uv`; outside 0 to 1 it repeats its nearest edge.
    float4 sample(Frame f, float2 uv) { return f.image.sample(roc_edge, uv); }
    /// The image at `uv`, tiled.
    float4 sample_wrap(Frame f, float2 uv) { return f.image.sample(roc_wrap, uv); }
    /// The image at `uv`, tiled with every other tile mirrored.
    float4 sample_mirror(Frame f, float2 uv) { return f.image.sample(roc_mirror, uv); }

    /// The image's pixel `p` (whole pixels from the top-left corner, held to
    /// the image), exactly as it was written: for state a warp keeps in its
    /// history, such as a value in row 0.
    float4 fetch(Frame f, int2 p) { return f.image.read(uint2(clamp(p, int2(0), int2(f.size) - 1))); }
    /// A number from 0 to 1 as two channels, and back: the history keeps 8
    /// bits a channel, so a value kept across frames in one channel has only
    /// 256 steps, and in two, 65,536.
    float2 pack(float v) {
        float x = round(saturate(v) * 65535.0);
        float hi = floor(x / 256.0);
        return float2(hi, x - hi * 256.0) / 255.0;
    }
    float unpack(float2 c) {
        float2 b = round(saturate(c) * 255.0);
        return (b.x * 256.0 + b.y) / 65535.0;
    }

    /// The image around `uv` blurred over about `radius` pixels (nine taps).
    float4 blur(Frame f, float2 uv, float radius) {
        float2 d = f.texel * radius;
        float4 c = sample(f, uv) * 0.25;
        c += (sample(f, uv + float2(d.x, 0)) + sample(f, uv - float2(d.x, 0)) + sample(f, uv + float2(0, d.y)) + sample(f, uv - float2(0, d.y))) * 0.125;
        c += (sample(f, uv + d) + sample(f, uv - d) + sample(f, uv + float2(d.x, -d.y)) + sample(f, uv + float2(-d.x, d.y))) * 0.0625;
        return c;
    }

    // ---- The sound ----

    float roc_series(constant float *a, int offset, int count, float x) {
        float t = clamp(x, 0.0, 1.0) * float(count - 1);
        int i = int(floor(t));
        int j = min(i + 1, count - 1);
        return mix(a[offset + i], a[offset + j], t - float(i));
    }

    /// The waveform (audio.waveform, the channels mixed) at `x`, 0 the oldest
    /// sample and 1 the newest, from -1 to 1; 256 points, interpolated.
    float wave(Frame f, float x) { return roc_series(f.audio, 0, 256, x); }
    /// The left channel's waveform (audio.left), as `wave`.
    float left(Frame f, float x) { return roc_series(f.audio, 256, 256, x); }
    /// The right channel's waveform (audio.right), as `wave`.
    float right(Frame f, float x) { return roc_series(f.audio, 512, 256, x); }
    /// The spectrum (audio.bands) at `x`, 0 the lowest band (40 Hz) and 1 the
    /// highest (16 kHz), from 0 to 1; 24 bands, interpolated.
    float band(Frame f, float x) { return roc_series(f.audio, 768, 24, x); }
    /// One band, 0 to 23.
    float band_at(Frame f, int i) { return f.audio[768 + clamp(i, 0, 23)]; }

    // ---- Coordinates ----

    /// The pixel's place from the centre: y from -1 at the top to 1 at the
    /// bottom, x the same scale (so -aspect to aspect).
    float2 centered(Frame f) { return (f.uv - 0.5) * float2(f.aspect, 1.0) * 2.0; }
    /// The uv of a `centered` place.
    float2 uv_of(Frame f, float2 p) { return p / (float2(f.aspect, 1.0) * 2.0) + 0.5; }
    /// A place as (distance from the origin, angle in radians, clockwise from
    /// the right, -PI to PI).
    float2 polar(float2 p) { return float2(length(p), atan2(p.y, p.x)); }
    /// The place at (distance, angle).
    float2 cartesian(float2 ra) { return ra.x * float2(cos(ra.y), sin(ra.y)); }
    /// `p` turned by `angle` radians, clockwise, about the origin.
    float2 rotate(float2 p, float angle) {
        float c = cos(angle), s = sin(angle);
        return float2(c * p.x - s * p.y, s * p.x + c * p.y);
    }

    // ---- Colour ----

    /// Hue (0 to 1 around the wheel), saturation and value to RGB.
    float3 hsv2rgb(float3 c) {
        float3 k = clamp(abs(fract(c.x + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        return c.z * mix(float3(1.0), k, c.y);
    }
    /// RGB to hue, saturation and value.
    float3 rgb2hsv(float3 c) {
        float4 k = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        float4 p = mix(float4(c.bg, k.wz), float4(c.gb, k.xy), step(c.b, c.g));
        float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
    }
    /// A cosine palette: a + b cos(TAU (c t + d)), each channel.
    float3 palette(float t, float3 a, float3 b, float3 c, float3 d) { return a + b * cos(TAU * (c * t + d)); }
    /// An opaque colour, each channel kept to 0 to 1.
    float4 opaque(float3 c) { return float4(saturate(c), 1.0); }

    // ---- Noise ----

    /// A repeatable pseudo-random number from 0 to 1 for each `p`.
    float hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }
    /// Smooth value noise from 0 to 1, one cell a unit.
    float noise(float2 p) {
        float2 i = floor(p), u = fract(p);
        u = u * u * (3.0 - 2.0 * u);
        return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
    }
    /// Four octaves of `noise`, from 0 to about 1.
    float fbm(float2 p) {
        float sum = 0.0, amp = 0.5;
        for (int i = 0; i < 4; i++) { sum += amp * noise(p); p = p * 2.03 + 17.0; amp *= 0.5; }
        return sum;
    }

    // ---- The app's params ----

    """

    /// The full-screen quad every stage draws: four vertices of a strip,
    /// uv 0 at the top-left corner.
    static let vertexSource = """
    vertex RocTextured roc_full_vertex(uint id [[vertex_id]]) {
        float2 uv = float2(float(id & 1), float(id >> 1));
        RocTextured out;
        out.position = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
        out.uv = uv;
        return out;
    }
    """
}

// MARK: - A surface's shaders

/// What a surface's `shader-*` attributes ask for.
struct ShaderRequest {
    var warp = ""
    var composite = ""
    /// Each param's name and its number, in order.
    var params: [(String, SceneNumber)] = []
    var paramsWord = ""

    var wanted: Bool { !warp.isEmpty || !composite.isEmpty }
    var names: [String] { params.map { $0.0 } }


    /// `shader-params`: one `NAME NUMBER` a line, NUMBER as a scene number.
    static func parseParams(_ text: String) -> [(String, SceneNumber)] {
        var out: [(String, SceneNumber)] = []
        for (i, line) in text.split(separator: "\n").enumerated() {
            var w = Scene.Words(line: String(line), number: i + 1)
            let name = w.word("a param name")
            let number = w.sceneNumber()
            w.end()
            out.append((name, number))
        }
        return out
    }

    /// Why the params cannot compile, if they cannot.
    var paramProblem: String? {
        if params.count > ShaderSource.maxParams { return "a surface's shaders take at most \(ShaderSource.maxParams) params, not \(params.count)" }
        var seen: [String] = []
        for name in names {
            if !ShaderSource.validName(name) { return "param \(name) is not a name of lowercase letters, digits and _ (at most 32), not starting with a digit" }
            if seen.contains(name) { return "param \(name) is named twice" }
            seen.append(name)
        }
        return nil
    }
}

extension MetalRenderer {
    /// A stage's program for `source` and `params`: ready, failed, or
    /// compiling (call again when it finishes).
    func program(_ stage: ShaderStage, _ source: String, params: [String]) -> ShaderOutcome {
        if source.utf8.count > ShaderSource.maxBytes {
            return .failed([ShaderError(stage: stage, line: 0, column: 0, message: "the \(stage.name) shader is \(source.utf8.count) bytes, more than \(ShaderSource.maxBytes)")])
        }
        let key = stage.name + "\u{1}" + params.joined(separator: ",") + "\u{1}" + source
        if let known = programs[key] {
            if case let .pending(compile) = known, let done = compile.outcome {
                programs[key] = done
                return done
            }
            return known
        }
        let compile = ShaderCompile(stage, source: source, params: params, renderer: self, now: Host.scripted)
        if let done = compile.outcome {
            programs[key] = done
            return done
        }
        programs[key] = .pending(compile)
        return .pending(compile)
    }
}

/// One frame's inputs to a surface's stages.
struct ShaderFrame {
    var warp: ShaderProgram?
    var composite: ShaderProgram?
    /// `RocUniforms`, as 12 floats (the frame count's bits in the eighth).
    var uniforms: [Float]
    /// The values of `params`, by each program's own order.
    var warpParams: [Float]
    var compositeParams: [Float]
    /// The audio block (`ShaderSource.audioFloats`).
    var audio: [Float]
}

extension DrawingSurface {
    /// The audio block at `time`: the three waveforms at 256 points each
    /// (means of each run of the source's values), then the bands.
    static func audioBlock(at time: Double) -> [Float] {
        var block = [Float](repeating: 0, count: ShaderSource.audioFloats)
        func series(_ name: String) -> [Float] {
            guard case let .series(values)? = SurfaceSources.shared.source(name)?.latest(at: time) else { return [] }
            return values
        }
        func put(_ values: [Float], at offset: Int, points: Int) {
            let n = values.count
            guard n > 0 else { return }
            for p in 0..<points {
                let lo = p * n / points, hi = max(lo + 1, (p + 1) * n / points)
                var sum: Float = 0
                for i in lo..<min(hi, n) { sum += values[i] }
                block[offset + p] = sum / Float(min(hi, n) - lo)
            }
        }
        let mono = series("audio.waveform")
        put(mono, at: 0, points: ShaderSource.wavePoints)
        let l = series("audio.left"), r = series("audio.right")
        put(l.isEmpty ? mono : l, at: 256, points: ShaderSource.wavePoints)
        put(r.isEmpty ? mono : r, at: 512, points: ShaderSource.wavePoints)
        let bands = series("audio.bands")
        for i in 0..<min(bands.count, ShaderSource.bandCount) { block[768 + i] = bands[i] }
        return block
    }

    /// A scalar source at `time`, or 0.
    static func scalar(_ name: String, at time: Double) -> Float {
        guard case let .scalar(v)? = SurfaceSources.shared.source(name)?.latest(at: time) else { return 0 }
        return v
    }
}

// MARK: - Development aids: frame timing and snapshots

/// `ROC_SURFACE_TIMING=1` prints each Metal surface's GPU time a frame
/// every two seconds; `ROC_SURFACE_SHOTS=DIR` writes a PNG of each Metal
/// surface's frame every two seconds of frame time, as
/// `DIR/LABEL-N.png` (docs/apps.adoc, "The environment").
enum SurfaceDiagnostics {
    static let timing = ProcessInfo.processInfo.environment["ROC_SURFACE_TIMING"] == "1"
    static let shots = ProcessInfo.processInfo.environment["ROC_SURFACE_SHOTS"]
    static let every = 2.0

    /// A file name's safe form of a label.
    static func fileName(_ label: String) -> String {
        var kept = ""
        for c in label.utf8 {
            let lower = c >= 0x41 && c <= 0x5a ? c + 0x20 : c
            let ok = (lower >= 0x61 && lower <= 0x7a) || (lower >= 0x30 && lower <= 0x39)
            kept += ok ? String(UnicodeScalar(lower)) : "-"
        }
        return kept.isEmpty ? "surface" : kept
    }
}

extension MetalTarget {
    /// Write the shown frame to `path` as a PNG (an sRGB, opaque image).
    func writePNG(_ path: String) {
        let rowBytes = width * 4
        guard let buffer = renderer.device.makeBuffer(length: rowBytes * height, options: .storageModeShared),
              let commands = renderer.queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder()
        else { return }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        // BGRA in memory, premultiplied: little-endian, alpha first.
        guard let c = CGContext(data: buffer.contents(), width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: DrawingSurface.sRGB,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let image = c.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        guard let file = fopen(path, "wb") else { return }
        png.withUnsafeBytes { _ = fwrite($0.baseAddress, 1, $0.count, file) }
        fclose(file)
    }
}
