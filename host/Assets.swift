// Assets: the files an app ships in its `assets/` directory, found by name.

import AppKit

// MARK: - Finding an asset

/// An app's assets are the files of the `assets/` directory beside its
/// `main.roc`. `macos.roc build` copies them into
/// `<name>.app/Contents/Resources/assets/`, and beside the bare program it
/// builds (`.macos/assets/`); `scripts/build.roc` leaves a repository
/// example's program beside its own. The host looks, in order, in
///
/// 1. `ROC_ASSETS`, when it is set: a program run away from its assets (the
///    release tests run bare programs from one directory);
/// 2. `Contents/Resources/assets` of the `.app` the program is in;
/// 3. `assets/` beside the program;
/// 4. for a bare program, `assets/` of the current directory: `roc main.roc`
///    builds its program in Roc's cache, away from `main.roc`, and runs it
///    in the directory it was started from.
///
/// An asset is read when a view first shows it, on the main thread, and an
/// image is kept by name for the life of the process. A missing asset, or a
/// file AppKit cannot read as an image, is a fatal error naming it.
enum Assets {
    /// The directories looked in, in order.
    static let searched: [String] = {
        if let dir = ProcessInfo.processInfo.environment["ROC_ASSETS"] { return [dir] }
        let program = Bundle.main.executablePath.flatMap(resolved) ?? "."
        let dir = String(program[..<(program.lastIndex(of: "/") ?? program.endIndex)])
        let inApp = dir.hasSuffix(".app/Contents/MacOS")
        return inApp ? ["\(dir.dropLast("MacOS".count))Resources/assets", "\(dir)/assets"] : ["\(dir)/assets", "assets"]
    }()

    /// The first of `searched` that is a directory, if any, resolved.
    static let directory: String? = searched.lazy.compactMap(resolved).first { kind($0) == 0o040000 }

    private static var images: [String: NSImage] = [:]

    /// The file an asset name stands for. A name is a path inside `assets/`
    /// (`logo.png`, `icons/star.pdf`), never outside it.
    static func path(_ name: String) -> String {
        switch lookup(name) {
        case .found(let path): return path
        case .missing(let why): fatal(why)
        }
    }

    /// Where an asset name leads: the file, or why there is none, for a
    /// caller that reports it rather than stopping (`Audio`'s `LoadAsset`).
    enum Lookup { case found(String), missing(String) }

    static func lookup(_ name: String) -> Lookup {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if name.isEmpty || parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            return .missing("asset \"\(name)\" is not a name inside the app's assets/ directory (such as logo.png or icons/star.pdf)")
        }
        guard let directory else {
            let looked = ProcessInfo.processInfo.environment["ROC_ASSETS"].map { ["ROC_ASSETS=\($0)"] } ?? searched
            return .missing("asset \"\(name)\": the app has no assets directory (looked in \(looked.joined(separator: ", "))). Run the program from the app's directory, which holds assets/ beside src/, or set ROC_ASSETS to the app's assets directory.")
        }
        let path = "\(directory)/\(name)"
        guard kind(path) == 0o100000 else {
            return .missing("asset \"\(name)\" is not in the app's assets (\(directory)). Put it in the app's assets/ directory, beside src/.")
        }
        return .found(path)
    }

    /// An image asset, read once.
    static func image(_ name: String) -> NSImage {
        if let image = images[name] { return image }
        let file = path(name)
        guard let image = NSImage(contentsOfFile: file), image.isValid, image.size.width > 0, image.size.height > 0 else {
            fatal("asset \"\(name)\" is not an image AppKit can read (\(file))")
        }
        images[name] = image
        return image
    }

    /// An absolute path with no symbolic links, `.` or `..`, or nil if
    /// nothing is there.
    private static func resolved(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }

    /// The `S_IFMT` bits of what is at `path` (POSIX <sys/stat.h>:
    /// `0o040000` a directory, `0o100000` a regular file), or 0 if nothing.
    private static func kind(_ path: String) -> UInt16 {
        var info = stat()
        return stat(path, &info) == 0 ? info.st_mode & 0o170000 : 0
    }
}

// MARK: - The view

/// `ui-asset-image`: an image from the app's assets, drawn in its frame.
/// Its natural size is the image's size in points. With only one side
/// bound it keeps the image's aspect ratio (a constraint at 760, above the
/// 750 the view hugs and resists with); `scaling` decides how it fits a
/// frame of another shape. `label` names it to VoiceOver; without one it is
/// decorative and VoiceOver skips it.
final class Picture: NSView {
    private(set) var name = ""
    private(set) var image: NSImage?
    private var aspect: NSLayoutConstraint?
    var scaling = "fit" { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        setContentHuggingPriority(.init(750), for: .horizontal)
        setContentHuggingPriority(.init(750), for: .vertical)
        setContentCompressionResistancePriority(.init(750), for: .horizontal)
        setContentCompressionResistancePriority(.init(750), for: .vertical)
        setAccessibilityElement(false)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatal("Picture is not archived") }

    /// Show the asset `name`.
    func show(_ name: String) {
        if name == self.name, image != nil { return }
        let image = Assets.image(name)
        self.name = name
        self.image = image
        aspect?.isActive = false
        let ratio = image.size.width / image.size.height
        aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: ratio)
        aspect?.priority = .init(760)
        aspect?.isActive = true
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// Name the image to VoiceOver, or (empty) leave it out as decorative.
    func label(_ text: String) {
        setAccessibilityLabel(text.isEmpty ? nil : text)
        setAccessibilityElement(!text.isEmpty)
    }

    override var intrinsicContentSize: NSSize {
        image?.size ?? NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let size = image.size
        let box = bounds
        var width = size.width
        var height = size.height
        switch scaling {
        case "stretch":
            width = box.width
            height = box.height
        case "fit", "fill":
            let across = box.width / size.width
            let down = box.height / size.height
            let factor = scaling == "fill" ? max(across, down) : min(across, down)
            width = size.width * factor
            height = size.height * factor
        default:  // original
            break
        }
        let rect = NSRect(x: box.origin.x + (box.width - width) / 2, y: box.origin.y + (box.height - height) / 2, width: width, height: height)
        NSBezierPath(rect: box).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// The image's size in pixels, from its first bitmap (a PDF has none,
    /// and answers its size in points).
    var pixels: (Int, Int) {
        guard let image else { return (0, 0) }
        if let rep = image.representations.first, rep.pixelsWide > 0 { return (rep.pixelsWide, rep.pixelsHigh) }
        return (Int(image.size.width), Int(image.size.height))
    }
}

extension Host {
    /// The words of an image's `scaling` attribute.
    static func imageScaling(_ word: String) -> String {
        switch word {
        case "fit", "fill", "stretch", "original": return word
        default: fatal("image scaling \(word) is not fit, fill, stretch or original")
        }
    }
}
