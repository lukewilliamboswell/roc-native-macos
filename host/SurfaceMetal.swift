// The Metal renderer of a display-paced drawing surface (Drawing.swift).
//
// A display-paced surface draws with Metal when the Mac has a Metal device
// (`MTLCreateSystemDefaultDevice`) and the renderer is not forced to Core
// Graphics (`SurfaceRenderer`); an on-demand surface, a Mac without a device
// and, by default, a spec draw with Core Graphics, the reference.
//
// Each frame renders into one of two textures at the full backing
// resolution, in the order the Core Graphics renderer draws: clear to the
// background, the previous frame (the other texture) as a quad through the
// trail's transform at `0.5^(dt / half-life)` of its opacity, then the
// scene. The texture is then copied into the `CAMetalLayer`'s drawable and
// presented; a repaint shows the presented drawable again, so it never fades
// the trail.
//
// The scene's figures are drawn on the GPU by stencil, then cover: a fill's
// path is flattened (curves to segments) and fanned into triangles that add
// their winding to the stencil, and a stroke is tessellated into a quad per
// segment and a disk per point (round joins and caps) that mark it; one quad
// over the figure's bounds then paints where the stencil is not zero (the
// nonzero rule, and a stroke's overlaps painted once) and zeroes it for the
// next figure. Rendering is 4x multisampled and resolved into the texture.
//
// The shaders are source in this file, compiled once with
// `makeLibrary(source:options:)` when the first surface needs them, so the
// host build has no Metal step. The pipelines are kept while a surface
// renders with Metal and released with the last one. Everything here runs
// on the main thread; a frame never calls the engine.

import AppKit
import Metal
import QuartzCore

/// Which renderer a display-paced surface uses.
enum SurfaceRenderer {
    /// Metal when there is a device, else Core Graphics.
    case auto
    case metal
    case cg

    /// `ROC_SURFACE_RENDERER` (`auto`, `metal` or `cg`), or a spec's
    /// `(renderer …)` step; a spec draws with Core Graphics unless told.
    static var choice: SurfaceRenderer = {
        if let word = ProcessInfo.processInfo.environment["ROC_SURFACE_RENDERER"] {
            guard let chosen = named(word) else { fatal("ROC_SURFACE_RENDERER=\(word) is not auto, metal or cg") }
            return chosen
        }
        return Host.scripted ? .cg : .auto
    }()

    static func named(_ word: String) -> SurfaceRenderer? {
        if word == "auto" { return .auto }
        if word == "metal" { return .metal }
        if word == "cg" { return .cg }
        return nil
    }

    /// Whether a display-paced surface draws with Metal now: chosen and a
    /// device exists. `metal` without a device falls back to Core Graphics.
    static var usesMetal: Bool { choice != .cg && MetalRenderer.device != nil }
}

// MARK: - The device and its pipelines

/// The device, its queue and the pipeline states, while any surface renders
/// with Metal.
final class MetalRenderer {
    /// The system's default device, looked up once (nil on a Mac or a
    /// virtual machine without one).
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// The pipelines, kept while a surface holds them.
    private static weak var live: MetalRenderer?

    static let samples = 4
    static let colorFormat = MTLPixelFormat.bgra8Unorm

    let device: MTLDevice
    let queue: MTLCommandQueue
    /// The previous frame as a textured quad.
    let image: MTLRenderPipelineState
    /// Triangles into the stencil alone.
    let mark: MTLRenderPipelineState
    /// A figure's bounds, painted where the stencil is set.
    let cover: MTLRenderPipelineState
    let always: MTLDepthStencilState
    let winding: MTLDepthStencilState
    let union: MTLDepthStencilState
    let paint: MTLDepthStencilState
    /// The full-surface quad a shader stage draws (SurfaceShaders.swift).
    let fullVertex: MTLFunction
    /// Each shader stage's program by its whole source, while the renderer
    /// lives (SurfaceShaders.swift).
    var programs: [String: ShaderOutcome] = [:]

    /// The renderer in use, or a new one.
    static func acquire() -> MetalRenderer? {
        if let live { return live }
        guard let device else { return nil }
        let made = MetalRenderer(device: device)
        live = made
        return made
    }

    private init(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { fatal("the Metal device made no command queue") }
        self.queue = queue
        guard let library = try? device.makeLibrary(source: MetalRenderer.shaders, options: nil) else {
            fatal("the drawing surface's Metal shaders did not compile")
        }
        func function(_ name: String) -> MTLFunction {
            guard let f = library.makeFunction(name: name) else { fatal("the Metal shaders have no \(name)") }
            return f
        }
        func pipeline(_ vertex: String, _ fragment: String, writes: Bool) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = function(vertex)
            d.fragmentFunction = function(fragment)
            d.rasterSampleCount = MetalRenderer.samples
            d.stencilAttachmentPixelFormat = .stencil8
            let c = d.colorAttachments[0]!
            c.pixelFormat = MetalRenderer.colorFormat
            if writes {
                // Premultiplied source over.
                c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            } else {
                c.writeMask = []
            }
            guard let made = try? device.makeRenderPipelineState(descriptor: d) else {
                fatal("a drawing surface's Metal pipeline (\(vertex), \(fragment)) failed")
            }
            return made
        }
        fullVertex = function("roc_full_vertex")
        image = pipeline("image_vertex", "image_fragment", writes: true)
        mark = pipeline("shape_vertex", "solid_fragment", writes: false)
        cover = pipeline("shape_vertex", "solid_fragment", writes: true)
        func state(_ compare: MTLCompareFunction, front: MTLStencilOperation, back: MTLStencilOperation) -> MTLDepthStencilState {
            let d = MTLDepthStencilDescriptor()
            let f = MTLStencilDescriptor()
            f.stencilCompareFunction = compare
            f.depthStencilPassOperation = front
            let b = MTLStencilDescriptor()
            b.stencilCompareFunction = compare
            b.depthStencilPassOperation = back
            d.frontFaceStencil = f
            d.backFaceStencil = b
            guard let s = device.makeDepthStencilState(descriptor: d) else { fatal("the Metal device made no stencil state") }
            return s
        }
        always = state(.always, front: .keep, back: .keep)
        winding = state(.always, front: .incrementWrap, back: .decrementWrap)
        union = state(.always, front: .replace, back: .replace)
        paint = state(.notEqual, front: .zero, back: .zero)
    }

    /// Points to clip space: `view` is (2 / width, -2 / height) in points.
    static let shaders = """
    #include <metal_stdlib>
    using namespace metal;

    vertex float4 shape_vertex(uint id [[vertex_id]], const device float2 *points [[buffer(0)]], constant float2 &view [[buffer(1)]]) {
        float2 p = points[id];
        return float4(p.x * view.x - 1.0, 1.0 + p.y * view.y, 0.0, 1.0);
    }

    fragment float4 solid_fragment(constant float4 &color [[buffer(0)]]) {
        return color;
    }

    struct Textured {
        float4 position [[position]];
        float2 uv;
    };

    vertex Textured image_vertex(uint id [[vertex_id]], constant float4 *quad [[buffer(0)]]) {
        Textured out;
        out.position = float4(quad[id].xy, 0.0, 1.0);
        out.uv = quad[id].zw;
        return out;
    }

    fragment float4 image_fragment(Textured in [[stage_in]], texture2d<float> image [[texture(0)]], constant float &alpha [[buffer(0)]]) {
        constexpr sampler linear(filter::linear, address::clamp_to_zero);
        return image.sample(linear, in.uv) * alpha;
    }

    struct RocTextured {
        float4 position [[position]];
        float2 uv;
    };

    """ + ShaderSource.vertexSource
}

// MARK: - Tessellation

/// A 2D affine transform: `x' = a x + c y + tx`, `y' = b x + d y + ty`.
struct Affine {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

    /// This transform after `m` (as a canvas's concatenation).
    func concat(_ m: Affine) -> Affine {
        Affine(a: a * m.a + c * m.b, b: b * m.a + d * m.b, c: a * m.c + c * m.d, d: b * m.c + d * m.d,
               tx: a * m.tx + c * m.ty + tx, ty: b * m.tx + d * m.ty + ty)
    }

    /// How much it scales lengths, on average.
    var scale: Double { abs(a * d - b * c).squareRoot() }
}

/// One figure of a frame: its triangles' place in the vertex list, the
/// quad over its bounds, its rule and its colour (premultiplied sRGB).
struct Figure {
    let fill: Bool
    let start: Int
    let count: Int
    let cover: Int
    let red: Float, green: Float, blue: Float, alpha: Float
}

/// A frame's steps as triangles in view points.
struct Tessellation {
    var vertices: [Float] = []
    var figures: [Figure] = []

    /// `steps` mapped by `base` (the scene's space in points). Colours
    /// resolve in the current drawing appearance.
    init(_ steps: [DrawStep], base: Affine) {
        var ctm = base
        var alpha = 1.0
        var saved: [Affine] = []
        var savedAlpha: [Double] = []
        for step in steps {
            switch step {
            case let .figure(fill, color, _, width, path):
                let start = vertices.count / 2
                var box = Bounds()
                let paths = Tessellation.flatten(path, tolerance: 0.25 / max(ctm.scale, 1e-6))
                if fill {
                    for p in paths where p.count >= 6 {
                        for i in stride(from: 2, to: p.count - 2, by: 2) {
                            add(ctm, p[0], p[1], &box)
                            add(ctm, p[i], p[i + 1], &box)
                            add(ctm, p[i + 2], p[i + 3], &box)
                        }
                    }
                } else if width > 0 {
                    stroke(paths, width / 2, ctm, &box)
                }
                let count = vertices.count / 2 - start
                guard count > 0, box.valid else { continue }
                let cover = vertices.count / 2
                for (x, y) in [(box.minX, box.minY), (box.maxX, box.minY), (box.minX, box.maxY), (box.maxX, box.minY), (box.maxX, box.maxY), (box.minX, box.maxY)] {
                    vertices.append(Float(x))
                    vertices.append(Float(y))
                }
                let rgb = color.usingColorSpace(.sRGB)
                let a = Double(rgb?.alphaComponent ?? 0) * alpha
                figures.append(Figure(
                    fill: fill, start: start, count: count, cover: cover,
                    red: Float(Double(rgb?.redComponent ?? 0) * a), green: Float(Double(rgb?.greenComponent ?? 0) * a),
                    blue: Float(Double(rgb?.blueComponent ?? 0) * a), alpha: Float(a)))
            case .save:
                saved.append(ctm)
                savedAlpha.append(alpha)
            case .restore:
                ctm = saved.popLast() ?? base
                alpha = savedAlpha.popLast() ?? 1
            case let .transform(a, b, c, d, tx, ty):
                ctm = ctm.concat(Affine(a: a, b: b, c: c, d: d, tx: tx, ty: ty))
            case let .opacity(amount):
                alpha *= amount
            }
        }
    }

    /// A figure's bounds in view points.
    struct Bounds {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        var valid: Bool { minX <= maxX && minY <= maxY }
    }

    private mutating func add(_ m: Affine, _ x: Double, _ y: Double, _ box: inout Bounds) {
        let px = m.a * x + m.c * y + m.tx, py = m.b * x + m.d * y + m.ty
        vertices.append(Float(px))
        vertices.append(Float(py))
        box.minX = min(box.minX, px)
        box.minY = min(box.minY, py)
        box.maxX = max(box.maxX, px)
        box.maxY = max(box.maxY, py)
    }

    /// A quad per segment and a disk per point, `half` either side, in the
    /// figure's own units (so its transform scales the width as a canvas does).
    private mutating func stroke(_ paths: [[Double]], _ half: Double, _ m: Affine, _ box: inout Bounds) {
        let sides = min(48, max(8, Int((half * m.scale * 2).rounded(.up))))
        for p in paths where p.count >= 2 {
            let n = p.count / 2
            for i in 0..<n {
                let x = p[2 * i], y = p[2 * i + 1]
                // A disk: round joins and caps.
                for k in 0..<sides {
                    let a0 = 2 * Double.pi * Double(k) / Double(sides), a1 = 2 * Double.pi * Double(k + 1) / Double(sides)
                    add(m, x, y, &box)
                    add(m, x + half * cos(a0), y + half * sin(a0), &box)
                    add(m, x + half * cos(a1), y + half * sin(a1), &box)
                }
                guard i + 1 < n else { continue }
                let qx = p[2 * i + 2], qy = p[2 * i + 3]
                let dx = qx - x, dy = qy - y, length = (dx * dx + dy * dy).squareRoot()
                guard length > 0 else { continue }
                let nx = -dy / length * half, ny = dx / length * half
                add(m, x + nx, y + ny, &box); add(m, qx + nx, qy + ny, &box); add(m, qx - nx, qy - ny, &box)
                add(m, x + nx, y + ny, &box); add(m, qx - nx, qy - ny, &box); add(m, x - nx, y - ny, &box)
            }
        }
    }

    /// A path's subpaths as points (x, y pairs), curves flattened to within
    /// `tolerance` units; a closed subpath ends where it began.
    static func flatten(_ path: [PathStep], tolerance: Double) -> [[Double]] {
        var paths: [[Double]] = []
        var current: [Double] = []
        var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0
        func pieces(_ length: Double) -> Int { min(128, max(2, Int((length / max(tolerance, 1e-6)).squareRoot().rounded(.up)))) }
        for step in path {
            switch step {
            case let .move(px, py):
                if current.count >= 2 { paths.append(current) }
                current = [px, py]
                x = px; y = py; startX = px; startY = py
            case let .line(px, py):
                if current.isEmpty { current = [x, y] }
                current += [px, py]
                x = px; y = py
            case let .quad(cx, cy, px, py):
                if current.isEmpty { current = [x, y] }
                let n = pieces(hypot2(cx - x, cy - y) + hypot2(px - cx, py - cy))
                for i in 1...n {
                    let t = Double(i) / Double(n), u = 1 - t
                    current += [u * u * x + 2 * u * t * cx + t * t * px, u * u * y + 2 * u * t * cy + t * t * py]
                }
                x = px; y = py
            case let .curve(ax, ay, bx, by, px, py):
                if current.isEmpty { current = [x, y] }
                let n = pieces(hypot2(ax - x, ay - y) + hypot2(bx - ax, by - ay) + hypot2(px - bx, py - by))
                for i in 1...n {
                    let t = Double(i) / Double(n), u = 1 - t
                    let c0 = u * u * u, c1 = 3 * u * u * t, c2 = 3 * u * t * t, c3 = t * t * t
                    current += [c0 * x + c1 * ax + c2 * bx + c3 * px, c0 * y + c1 * ay + c2 * by + c3 * py]
                }
                x = px; y = py
            case .close:
                if current.count >= 2 {
                    current += [startX, startY]
                    paths.append(current)
                }
                current = []
                x = startX; y = startY
            }
        }
        if current.count >= 2 { paths.append(current) }
        return paths
    }

    private static func hypot2(_ dx: Double, _ dy: Double) -> Double { (dx * dx + dy * dy).squareRoot() }
}

// MARK: - A surface's textures

/// The textures one surface renders into at one size: the two history
/// textures, and the multisampled colour and stencil they resolve from.
final class MetalTarget {
    let renderer: MetalRenderer
    let width: Int
    let height: Int
    /// Pixels per point.
    let scale: Double
    private let frames: [MTLTexture]
    private let multisample: MTLTexture
    private let stencil: MTLTexture
    /// The texture holding the latest frame, and whether it is history.
    private(set) var latest = 0
    var hasHistory = false

    init(renderer: MetalRenderer, width: Int, height: Int, scale: Double) {
        self.renderer = renderer
        self.width = width
        self.height = height
        self.scale = scale
        let device = renderer.device
        func texture(_ format: MTLPixelFormat, samples: Int, usage: MTLTextureUsage) -> MTLTexture {
            MetalTarget.texture(device, width, height, format, samples: samples, usage: usage)
        }
        frames = [texture(MetalRenderer.colorFormat, samples: 1, usage: [.renderTarget, .shaderRead]),
                  texture(MetalRenderer.colorFormat, samples: 1, usage: [.renderTarget, .shaderRead])]
        multisample = texture(MetalRenderer.colorFormat, samples: MetalRenderer.samples, usage: [.renderTarget])
        stencil = texture(.stencil8, samples: MetalRenderer.samples, usage: [.renderTarget])
    }

    /// A private texture of this size.
    static func texture(_ device: MTLDevice, _ width: Int, _ height: Int, _ format: MTLPixelFormat, samples: Int, usage: MTLTextureUsage) -> MTLTexture {
        let d = MTLTextureDescriptor()
        d.pixelFormat = format
        d.width = width
        d.height = height
        d.textureType = samples > 1 ? .type2DMultisample : .type2D
        d.sampleCount = samples
        d.usage = usage
        d.storageMode = .private
        guard let t = device.makeTexture(descriptor: d) else { fatal("could not make a \(width)x\(height) Metal texture for a drawing surface") }
        return t
    }

    /// The texture a composite shader draws the screen into (made when one
    /// first runs), and whether the latest frame is shown from it.
    private var screen: MTLTexture?
    private var showsScreen = false

    /// What the latest frame shows: the composite's output, or the frame.
    var texture: MTLTexture { showsScreen ? (screen ?? frames[latest]) : frames[latest] }

    /// Render one frame into the texture the latest is not in: the
    /// background, then either the latest through the warp shader (if
    /// `shaders` has one) or the latest moved by `trail` (if it is history)
    /// at `fade`, then `scene`; then, with a composite shader, that frame
    /// through it into the screen texture. Returns the command buffer,
    /// uncommitted.
    func render(_ scene: Tessellation, background: [Float], trail: Affine?, fade: Double, shaders: ShaderFrame? = nil) -> MTLCommandBuffer? {
        guard let commands = renderer.queue.makeCommandBuffer() else { return nil }
        let target = 1 - latest
        let clear = MTLClearColor(red: Double(background[0]), green: Double(background[1]), blue: Double(background[2]), alpha: Double(background[3]))
        if shaders?.warp != nil, !hasHistory {
            // The warp's first frame reads the background.
            let first = MTLRenderPassDescriptor()
            first.colorAttachments[0].texture = frames[latest]
            first.colorAttachments[0].loadAction = .clear
            first.colorAttachments[0].storeAction = .store
            first.colorAttachments[0].clearColor = clear
            commands.makeRenderCommandEncoder(descriptor: first)?.endEncoding()
        }
        let pass = MTLRenderPassDescriptor()
        let color = pass.colorAttachments[0]!
        color.texture = multisample
        color.resolveTexture = frames[target]
        color.loadAction = .clear
        color.storeAction = .multisampleResolve
        color.clearColor = clear
        let s = pass.stencilAttachment!
        s.texture = stencil
        s.loadAction = .clear
        s.storeAction = .dontCare
        s.clearStencil = 0
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let pointsWide = Double(width) / scale, pointsHigh = Double(height) / scale
        if let shaders, let warp = shaders.warp {
            encoder.setRenderPipelineState(warp.pipeline)
            encoder.setDepthStencilState(renderer.always)
            MetalTarget.bind(encoder, shaders, params: shaders.warpParams, image: frames[latest])
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        } else if let trail, hasHistory {
            // The previous frame's corners in clip space, with their texture coordinates.
            var quad: [Float] = []
            for (u, v) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
                let x = u * pointsWide, y = v * pointsHigh
                let px = trail.a * x + trail.c * y + trail.tx, py = trail.b * x + trail.d * y + trail.ty
                quad += [Float(px / pointsWide * 2 - 1), Float(1 - py / pointsHigh * 2), Float(u), Float(v)]
            }
            var alpha = Float(fade)
            encoder.setRenderPipelineState(renderer.image)
            encoder.setDepthStencilState(renderer.always)
            quad.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.setFragmentTexture(frames[latest], index: 0)
            encoder.setFragmentBytes(&alpha, length: 4, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        if !scene.figures.isEmpty {
            let bytes = scene.vertices.count * 4
            let buffer: MTLBuffer? = scene.vertices.withUnsafeBytes { renderer.device.makeBuffer(bytes: $0.baseAddress!, length: bytes, options: .storageModeShared) }
            guard let buffer else { fatal("could not make a Metal buffer of \(bytes) bytes for a drawing surface") }
            var view: [Float] = [Float(2 / pointsWide), Float(-2 / pointsHigh)]
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            view.withUnsafeMutableBytes { encoder.setVertexBytes($0.baseAddress!, length: 8, index: 1) }
            for f in scene.figures {
                encoder.setRenderPipelineState(renderer.mark)
                encoder.setDepthStencilState(f.fill ? renderer.winding : renderer.union)
                encoder.setStencilReferenceValue(1)
                encoder.drawPrimitives(type: .triangle, vertexStart: f.start, vertexCount: f.count)
                var rgba: [Float] = [f.red, f.green, f.blue, f.alpha]
                encoder.setRenderPipelineState(renderer.cover)
                encoder.setDepthStencilState(renderer.paint)
                encoder.setStencilReferenceValue(0)
                rgba.withUnsafeMutableBytes { encoder.setFragmentBytes($0.baseAddress!, length: 16, index: 0) }
                encoder.drawPrimitives(type: .triangle, vertexStart: f.cover, vertexCount: 6)
            }
        }
        encoder.endEncoding()
        showsScreen = false
        if let shaders, let composite = shaders.composite {
            // The frame through the composite, into the screen texture; it
            // never feeds back.
            if screen == nil { screen = MetalTarget.texture(renderer.device, width, height, MetalRenderer.colorFormat, samples: 1, usage: [.renderTarget, .shaderRead]) }
            let out = MTLRenderPassDescriptor()
            out.colorAttachments[0].texture = screen
            out.colorAttachments[0].loadAction = .dontCare
            out.colorAttachments[0].storeAction = .store
            if let e = commands.makeRenderCommandEncoder(descriptor: out) {
                e.setRenderPipelineState(composite.pipeline)
                MetalTarget.bind(e, shaders, params: shaders.compositeParams, image: frames[target])
                e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                e.endEncoding()
                showsScreen = true
            }
        }
        latest = target
        hasHistory = true
        return commands
    }

    /// A stage's uniforms, params, audio block and image.
    private static func bind(_ e: MTLRenderCommandEncoder, _ shaders: ShaderFrame, params: [Float], image: MTLTexture) {
        shaders.uniforms.withUnsafeBytes { e.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        let values = params.isEmpty ? [Float(0)] : params
        values.withUnsafeBytes { e.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        shaders.audio.withUnsafeBytes { e.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
        e.setFragmentTexture(image, index: 0)
    }

    /// Copy the latest frame into `drawable`'s texture (same size and format).
    func copy(into commands: MTLCommandBuffer, _ drawable: CAMetalDrawable) {
        guard drawable.texture.width == width, drawable.texture.height == height, let blit = commands.makeBlitCommandEncoder() else { return }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: drawable.texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }

    /// The latest frame's pixel at (`col`, `row`), read back from the GPU:
    /// red, green, blue and alpha, premultiplied, 0 to 255.
    func pixel(_ col: Int, _ row: Int) -> [Int] {
        guard col >= 0, row >= 0, col < width, row < height,
              let buffer = renderer.device.makeBuffer(length: 4, options: .storageModeShared),
              let commands = renderer.queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder()
        else { return [0, 0, 0, 0] }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: col, y: row, z: 0), sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: 4, destinationBytesPerImage: 4)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let p = buffer.contents().assumingMemoryBound(to: UInt8.self)
        // BGRA in memory.
        return [Int(p[2]), Int(p[1]), Int(p[0]), Int(p[3])]
    }
}

// MARK: - A surface's layer

/// A display-paced surface's Metal state: its layer over the view's own,
/// and its target at the current size.
final class MetalSurface {
    let renderer: MetalRenderer
    let layer = CAMetalLayer()
    private(set) var target: MetalTarget?

    /// A Metal layer over `host`, or nil without a device.
    static func make(over host: CALayer?) -> MetalSurface? {
        guard let renderer = MetalRenderer.acquire(), let host else { return nil }
        return MetalSurface(renderer, over: host)
    }

    private init(_ renderer: MetalRenderer, over host: CALayer) {
        self.renderer = renderer
        layer.device = renderer.device
        layer.pixelFormat = MetalRenderer.colorFormat
        layer.framebufferOnly = false
        layer.isOpaque = false
        layer.colorspace = DrawingSurface.sRGB
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.addSublayer(layer)
        CATransaction.commit()
    }

    private var laidOut = [0.0, 0.0, 0.0]

    /// Follow the view's size (in points) and backing scale.
    func layout(width: Double, height: Double, scale: Double) {
        if laidOut == [width, height, scale], target != nil || width < 1 || height < 1 { return }
        laidOut = [width, height, scale]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        layer.contentsScale = scale
        CATransaction.commit()
        let px = max(1, Int((width * scale).rounded())), py = max(1, Int((height * scale).rounded()))
        layer.drawableSize = CGSize(width: Double(px), height: Double(py))
        if target?.width != px || target?.height != py || target?.scale != scale {
            target = width >= 1 && height >= 1 ? MetalTarget(renderer: renderer, width: px, height: py, scale: scale) : nil
        }
    }

    /// Forget the trail.
    func clear() { target?.hasHistory = false }

    /// Frames committed and not yet finished on the GPU (main thread).
    private(set) var inFlight = 0
    /// The most frames in flight: a frame due while this many are still on
    /// the GPU is skipped, so a slow shader slows the picture, never the
    /// main thread.
    static let maxInFlight = 2
    /// Called on the main thread when the GPU fails a frame that ran a
    /// shader (the system's GPU watchdog stops one that runs too long).
    var onShaderFault: ((String) -> Void)?
    /// GPU time of the frames since the last report (`ROC_SURFACE_TIMING`).
    private var gpuTimes: [Double] = []
    private var reportedAt: Double?

    /// Render a frame and present it; false when it was skipped because
    /// the GPU is behind.
    @discardableResult
    func frame(_ scene: Tessellation, background: [Float], trail: Affine?, fade: Double, shaders: ShaderFrame? = nil, label: String = "") -> Bool {
        guard inFlight < MetalSurface.maxInFlight || Host.scripted else { return false }
        guard let target, let commands = target.render(scene, background: background, trail: trail, fade: fade, shaders: shaders) else { return false }
        if let drawable = layer.nextDrawable() {
            target.copy(into: commands, drawable)
            commands.present(drawable)
        }
        let shaded = shaders.map { $0.warp != nil || $0.composite != nil } ?? false
        let timing = SurfaceDiagnostics.timing
        inFlight += 1
        commands.addCompletedHandler { [weak self] done in
            let failed = done.status == .error ? (done.error.map { AudioService.describe($0) } ?? "the GPU failed the frame") : nil
            let gpu = (done.gpuEndTime - done.gpuStartTime) * 1000
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight -= 1
                if let failed, shaded { self.onShaderFault?(failed) }
                if timing { self.timed(gpu, label: label, size: (target.width, target.height)) }
            }
        }
        commands.commit()
        return true
    }

    /// Note one frame's GPU time, and print the mean and the most every
    /// two seconds.
    private func timed(_ ms: Double, label: String, size: (Int, Int)) {
        gpuTimes.append(ms)
        let now = Bench.now()
        guard let since = reportedAt else { reportedAt = now; return }
        guard now - since >= SurfaceDiagnostics.every, !gpuTimes.isEmpty else { return }
        var sum = 0.0, most = 0.0
        for t in gpuTimes {
            sum += t
            most = max(most, t)
        }
        fputs("surface \"\(label)\" \(size.0)x\(size.1) px: gpu \(Host.decimal(sum / Double(gpuTimes.count), 2)) ms mean, \(Host.decimal(most, 2)) ms most, \(gpuTimes.count) frames\n", __stderrp)
        gpuTimes = []
        reportedAt = now
    }

    /// Off the view: the layer, the textures and (with the last surface) the pipelines go.
    func remove() {
        target = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeFromSuperlayer()
        CATransaction.commit()
    }
}

// MARK: - Measuring (a spec's `bench-surfaces` step)

extension Host {
    /// One trail frame (the previous frame turned, zoomed and faded, a
    /// 512-point stroke and 24 bars) drawn `frames` times offscreen at three
    /// sizes, with Core Graphics (as `composite` draws, at full size) and,
    /// with a device, Metal; prints the time a frame of each, waiting for
    /// the GPU to finish.
    func benchSurfaces(frames: Int) {
        var wave: [PathStep] = []
        for i in 0..<512 {
            let x = Double(i) / 511 * 1000, y = 250 + sin(Double(i) * 0.05) * 120
            wave.append(i == 0 ? .move(x, y) : .line(x, y))
        }
        var bars: [PathStep] = []
        for b in 0..<24 {
            let x = Double(b) * 1000 / 24 + 2, w = 1000 / 24 - 4.0, h = 500 * (0.2 + 0.03 * Double(b))
            bars += [.move(x, 500), .line(x + w, 500), .line(x + w, 500 - h), .line(x, 500 - h), .close]
        }
        let steps: [DrawStep] = [
            .figure(fill: false, color: .systemGreen, word: "green", width: 4, path: wave),
            .figure(fill: true, color: NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.6), word: "orange", width: 0, path: bars),
        ]
        for size in [[800, 500], [1600, 1000], [2880, 1800]] {
            let px = size[0], py = size[1]
            let scale = 2.0, w = Double(px) / scale, h = Double(py) / scale
            let base = Affine(a: w / 1000, d: h / 500)
            let z = 1.01, turn = 0.005
            let move = Affine(tx: w / 2, ty: h / 2).concat(Affine(a: z * cos(turn), b: z * sin(turn), c: -z * sin(turn), d: z * cos(turn))).concat(Affine(tx: -w / 2, ty: -h / 2))
            let contexts = (0..<2).compactMap { _ in
                CGContext(data: nil, width: px, height: py, bitsPerComponent: 8, bytesPerRow: px * 4, space: DrawingSurface.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            for c in contexts {
                c.translateBy(x: 0, y: Double(py))
                c.scaleBy(x: scale, y: -scale)
            }
            var previous: CGImage?
            var began = Bench.now()
            for f in 0..<frames {
                let c = contexts[f % 2]
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
                c.saveGState()
                c.clear(CGRect(x: 0, y: 0, width: w, height: h))
                c.setFillColor(NSColor.black.cgColor)
                c.fill(CGRect(x: 0, y: 0, width: w, height: h))
                if let previous {
                    c.saveGState()
                    c.concatenate(CGAffineTransform(a: move.a, b: move.b, c: move.c, d: move.d, tx: move.tx, ty: move.ty))
                    c.interpolationQuality = .low
                    DrawingSurface.drawImage(previous, width: w, height: h, fraction: 0.95)
                    c.restoreGState()
                }
                c.concatenate(CGAffineTransform(a: base.a, b: 0, c: 0, d: base.d, tx: 0, ty: 0))
                DrawingSurface.render(steps, in: c)
                c.restoreGState()
                NSGraphicsContext.restoreGraphicsState()
                previous = c.makeImage()
            }
            let cg = (Bench.now() - began) * 1000 / Double(frames)
            var line = "bench \(px)x\(py) px: core graphics \(Host.decimal(cg, 2)) ms"
            if let renderer = MetalRenderer.acquire() {
                let target = MetalTarget(renderer: renderer, width: px, height: py, scale: scale)
                began = Bench.now()
                var last: MTLCommandBuffer?
                for _ in 0..<frames {
                    let scene = Tessellation(steps, base: base)
                    last = target.render(scene, background: [0, 0, 0, 1], trail: move, fade: 0.95)
                    last?.commit()
                }
                last?.waitUntilCompleted()
                let metal = (Bench.now() - began) * 1000 / Double(frames)
                line += ", metal \(Host.decimal(metal, 2)) ms (\(renderer.device.name))"
            }
            say("\(line) a frame")
        }
    }
}
