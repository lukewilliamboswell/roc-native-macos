// Files (roc-signals design.md, "Files"): handles, picking, reading,
// digests and saving, performed natively.
//
// A file the user gives the app (picked in an open panel or dropped on a
// drop zone) reaches Roc as a handle, never as bytes: the host keeps the
// file's URL, size, name and type under a token, mints a `Box(U64)` holding
// that token in its handle table, and the engine pairs each handle with the
// file record into a `File`. Roc's reference count decides when the app is
// done with a file: Roc frees the box through `roc_dealloc`, the table
// retires the slot, and once the batch has been applied (its commands may
// still name the token) the host drops the entry.
//
// Threading follows the rules of roc-signals' Workers: Roc runs only on the
// main thread and no Roc value or Roc-owned memory crosses threads. A read,
// digest or save resolves its token on the main thread into a `FileEntry`
// (plain Swift data: a URL and a range), runs on `Files.queue` over that,
// and returns plain bytes to the main thread, where they are encoded and
// enter the engine as one turn through `Host.send`. `CANCEL` drops a job:
// its worker stops at the next chunk and its completion, which is checked
// against the job table on the main thread, never enters Roc.

import AppKit
import CommonCrypto

// MARK: - The handle table

/// A file the host holds for a handle: plain Swift data, safe to hand to a
/// background job.
struct FileEntry {
    /// The file's absolute path. A non-sandboxed app needs no
    /// security-scoped bookmark to read it again later.
    let path: String
    let size: UInt64
    let name: String
    let mime: String
}

/// The host's `Box(U64)` file handles, after roc-signals'
/// `resources.Heap(.blob, 64, _)`. Each slot is one box laid out as the glue
/// reports `Box(U64)` (`RocBoxU64`): a refcount word, then the token. Roc
/// increments and decrements the refcount like any box and frees the slot's
/// address with `roc_dealloc`, which offers it here first (`route`): an
/// address in the table retires its slot instead of being freed. Retired
/// slots keep their entry until `drainReleased`, after the batch.
///
/// Only the main thread touches it: Roc runs only there, so `roc_dealloc`
/// reaches it only there, and `route` checks that.
final class FileHandles {
    /// The most file handles live at once, as in the browser host (design.md,
    /// "Boundedness"). Files an event carries beyond the free slots are
    /// refused (`Received.refused`).
    static let capacity = 64

    /// A token: generation, kind (1, a file) and slot index + 1, as
    /// resources.zig encodes them, so a stale or foreign token never resolves.
    private static let indexBits: UInt64 = 16
    private static let kindBits: UInt64 = 8
    private static let kind: UInt64 = 1

    private let table: UnsafeMutableRawPointer
    private var entries: [FileEntry?] = Array(repeating: nil, count: capacity)
    private var tokens: [UInt64] = Array(repeating: 0, count: capacity)
    private var generations: [UInt64] = Array(repeating: 0, count: capacity)
    private var retired: [Bool] = Array(repeating: false, count: capacity)
    private(set) var liveCount = 0

    init() {
        var raw: UnsafeMutableRawPointer? = nil
        let bytes = RocBoxU64.stride * FileHandles.capacity
        if posix_memalign(&raw, max(RocBoxU64.alignment, 16), bytes) != 0 || raw == nil { fatal("cannot allocate the file handle table") }
        memset(raw!, 0, bytes)
        table = raw!
    }

    var free: Int { FileHandles.capacity - liveCount }

    /// Mint a handle owning `entry`: a unique box Roc will own, or nil when
    /// every slot is taken.
    func mint(_ entry: FileEntry) -> UnsafeMutableRawPointer? {
        for index in 0..<FileHandles.capacity where entries[index] == nil {
            generations[index] += 1
            let token = generations[index] << (FileHandles.indexBits + FileHandles.kindBits)
                | FileHandles.kind << FileHandles.indexBits | UInt64(index + 1)
            entries[index] = entry
            tokens[index] = token
            liveCount += 1
            return RocBoxU64.initialize(at: table + index * RocBoxU64.stride, token)
        }
        return nil
    }

    /// Offer an address `roc_dealloc` is freeing: true when it is a handle's
    /// (now retired), false when it is not this table's. An address inside
    /// the table that is not a live handle's is a fatal corruption.
    func route(_ ptr: UnsafeMutableRawPointer) -> Bool {
        let offset = ptr - table
        guard offset >= 0, offset < RocBoxU64.stride * FileHandles.capacity else { return false }
        if pthread_main_np() == 0 { fatal("a file handle was released off the main thread") }
        let index = offset / RocBoxU64.stride
        guard offset % RocBoxU64.stride == 0, entries[index] != nil, !retired[index],
              RocBoxU64.value(of: ptr + RocBoxU64.headerBytes) == tokens[index]
        else { fatal("roc_dealloc of a file handle that is not live (offset \(offset))") }
        retired[index] = true
        return true
    }

    /// The file a live (or retired, not yet drained) handle's token names.
    func entry(_ token: UInt64) -> FileEntry? {
        let index = Int(token & ((1 << FileHandles.indexBits) - 1)) - 1
        guard index >= 0, index < FileHandles.capacity, tokens[index] == token else { return nil }
        return entries[index]
    }

    /// Free the slots Roc released since the last drain; returns their tokens.
    func drainReleased() -> [UInt64] {
        var released: [UInt64] = []
        for index in 0..<FileHandles.capacity where retired[index] {
            released.append(tokens[index])
            retired[index] = false
            entries[index] = nil
            tokens[index] = 0
            liveCount -= 1
        }
        return released
    }
}

/// The one handle table; `roc_dealloc` routes through it.
let fileHandles = FileHandles()

// MARK: - Jobs off the main thread

/// One read, digest or save in flight. The worker reads `isCancelled`
/// between chunks; the main thread decides whether its completion counts.
final class FileJob {
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var cancelled = false

    init() { lock.initialize(to: os_unfair_lock()) }
    deinit { lock.deallocate() }

    func cancel() { os_unfair_lock_lock(lock); cancelled = true; os_unfair_lock_unlock(lock) }

    var isCancelled: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return cancelled
    }
}

/// What a job hands back to the main thread: plain bytes, never Roc memory.
enum FileOutcome {
    case bytes([UInt8])
    case failed(UInt8)
}

/// The host's file service: the job table (main thread only) and the queue
/// jobs run on.
final class Files {
    /// The most bytes one read into the page or one digest covers, whatever
    /// the app asks: the browser's `maxFileBytes` default (256 MiB).
    /// `ROC_MAX_FILE_BYTES` lowers it, for checking `TooLarge`.
    static let maxFileBytes: UInt64 = ProcessInfo.processInfo.environment["ROC_MAX_FILE_BYTES"].flatMap { UInt64($0) } ?? 256 << 20

    /// How much a worker reads at once, and between cancellation checks.
    static let chunk = 1 << 20

    /// `FileFailed` reasons (design.md, Appendix B, result tag 13).
    static let unreadable: UInt8 = 1, tooLarge: UInt8 = 2, unavailable: UInt8 = 3

    /// Reads and digests run concurrently, bounded by the engine's in-flight
    /// limit; nothing on this queue touches Roc or the handle table.
    let queue = DispatchQueue(label: "roc-native-macos.files", qos: .userInitiated, attributes: .concurrent)

    /// Effect id → its job in flight. Main thread only.
    var jobs: [UInt32: FileJob] = [:]

    /// Saves wait here for the save panel, one at a time.
    var saves: [(entry: FileEntry, start: UInt64, len: UInt64, name: String)] = []
    var saving = false
}

// MARK: - Host: events, effects and saves

extension Host {
    // MARK: Files-kind events

    /// Deliver files the user picked or dropped as a files-kind `type` event
    /// (`change` or `drop`) at `target`: mint a handle for each file that
    /// fits, and send the file record and the handles as one turn.
    func deliverFiles(_ paths: [String], type: String, at target: Node) {
        if applying {
            DispatchQueue.main.async { self.deliverFiles(paths, type: type, at: target) }
            return
        }
        let entries = paths.compactMap(fileEntry)
        guard !entries.isEmpty else { return }  // no files: no dispatch
        var cursor: Node? = target
        while let node = cursor, node.listeners[type]?.kind != 2 { cursor = node.parent }
        guard let listener = cursor, let handler = listener.listeners[type]?.handler else { return }
        var route: Node? = listener
        while let r = route, r.id == nil { route = r.parent }
        guard let id = route?.id else { return }
        var boxes: [UnsafeMutableRawPointer] = []
        var record = Bytes()
        for entry in entries {
            guard let box = fileHandles.mint(entry) else { break }
            boxes.append(box)
            record.u64(entry.size); record.str(entry.name); record.str(entry.mime)
        }
        var head = Bytes()
        head.u32(UInt32(boxes.count)); head.u32(UInt32(entries.count - boxes.count))
        trace("files \(type): \(boxes.count) minted, \(entries.count - boxes.count) refused, \(fileHandles.liveCount) live")
        apply(engine.files(node: id, handler: handler, record: head.bytes + record.bytes, handles: boxes))
    }

    /// A regular file's entry, or nil (a folder, or a file that cannot be read).
    func fileEntry(_ given: String) -> FileEntry? {
        guard let resolved = realpath(given, nil) else { return nil }
        let path = String(cString: resolved)
        free(resolved)
        var info = stat()
        // S_IFMT and S_IFREG (POSIX <sys/stat.h>): a regular file, not a
        // folder or device.
        guard stat(path, &info) == 0, info.st_mode & 0o170000 == 0o100000 else { return nil }
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let ext = name.lastIndex(of: ".").map { String(name[name.index(after: $0)...]) } ?? ""
        return FileEntry(path: path, size: UInt64(info.st_size), name: name, mime: mimeType(ext))
    }

    /// Drop the entries of handles Roc released, once the batch that may
    /// name them has been applied and its effects resolved.
    func releaseFiles() {
        for token in fileHandles.drainReleased() { trace("file released \(token)") }
    }

    // MARK: Effects (FX 11, 13, 14)

    /// The file a request names: a token the host does not hold is the
    /// runtime's contract fault, as in the browser host.
    func resolve(_ token: UInt64) -> FileEntry {
        guard let entry = fileHandles.entry(token) else { fatal("a request names file token \(token), which the host does not hold") }
        return entry
    }

    func fileEffect(id: UInt32, kind: UInt8, _ r: inout Reader) {
        switch kind {
        case 11: // READ mode token start len max_bytes
            let mode = r.u8(), entry = resolve(r.u64()), start = r.u64(), len = r.u64(), maxBytes = r.u64()
            guard mode == 1 || mode == 2 else { fatal("read mode \(mode) is not 1 (bytes) or 2 (text)") }
            if len > maxBytes || len > Files.maxFileBytes { return answer(id, .failed(Files.tooLarge)) }
            run(id) { job in Files.read(entry, start, len, tag: mode == 1 ? 16 : 17, job) }
        case 13: // DIGEST algorithm token start len
            let algorithm = r.u8(), entry = resolve(r.u64()), start = r.u64(), len = r.u64()
            guard algorithm == 1 else { fatal("digest algorithm \(algorithm) is not 1 (SHA-256)") }
            if len > Files.maxFileBytes { return answer(id, .failed(Files.tooLarge)) }
            run(id) { job in Files.sha256(entry, start, len, job) }
        case 14: // URL token start len
            let entry = resolve(r.u64()), start = r.u64(), len = r.u64()
            // A file:// URL shows the whole file; a range of one has no URL
            // of its own natively.
            if start != 0 || len != entry.size { return answer(id, .failed(Files.unavailable)) }
            let url = NSURL(fileURLWithPath: entry.path).absoluteString ?? ""
            answer(id, .bytes([19] + Array(url.utf8)))
        default:
            fatal("effect kind \(kind) is not supported by this host")
        }
    }

    /// Run `work` on the file queue under effect `id`, and deliver its
    /// outcome on the main thread unless it was cancelled meanwhile.
    func run(_ id: UInt32, _ work: @escaping (FileJob) -> FileOutcome?) {
        let job = FileJob()
        files.jobs[id] = job
        files.queue.async {
            guard let outcome = work(job) else { return }  // stopped: cancelled
            DispatchQueue.main.async { self.complete(id, job, outcome) }
        }
    }

    /// Answer `id` one task later, through the same path as a job.
    func answer(_ id: UInt32, _ outcome: FileOutcome) {
        let job = FileJob()
        files.jobs[id] = job
        DispatchQueue.main.async { self.complete(id, job, outcome) }
    }

    /// On the main thread: deliver a job's outcome as one turn, if the job is
    /// still the one tracked under its id.
    func complete(_ id: UInt32, _ job: FileJob, _ outcome: FileOutcome) {
        guard files.jobs[id] === job, !job.isCancelled else {
            trace("file job \(id) finished after it was cancelled: dropped")
            return
        }
        files.jobs.removeValue(forKey: id)
        switch outcome {
        case .bytes(let payload): send(EngineInstance.effectNode, id, payload)
        case .failed(let reason): send(EngineInstance.effectNode, id, [13, reason])
        }
    }

    /// `CANCEL` of a file job: it stops at its next chunk, and its completion
    /// is dropped. Returns whether `id` was one.
    @discardableResult
    func cancelFileJob(_ id: UInt32) -> Bool {
        guard let job = files.jobs.removeValue(forKey: id) else { return false }
        job.cancel()
        return true
    }

    // MARK: SAVE

    /// `SAVE token start len name`: resolved while the batch is applied (the
    /// handle may be released in the same batch), then saved after it.
    func save(token: UInt64, start: UInt64, len: UInt64, name: String) {
        // A save streams the range a chunk at a time, so it is not bounded
        // by maxFileBytes.
        files.saves.append((resolve(token), start, len, name))
        DispatchQueue.main.async { self.nextSave() }
    }

    /// Show the save panel for the next waiting save. A scripted run never
    /// opens one: with `ROC_SAVE_DIR` it writes there, otherwise it skips.
    func nextSave() {
        guard !files.saving, !files.saves.isEmpty else { return }
        let next = files.saves.removeFirst()
        let env = ProcessInfo.processInfo.environment
        if let dir = env["ROC_SAVE_DIR"] {
            write(next.entry, next.start, next.len, to: dir + "/" + next.name)
            return nextSave()
        }
        if env["ROC_SCRIPT"] != nil {
            say("save \(next.name): skipped (scripted run without ROC_SAVE_DIR)")
            return nextSave()
        }
        files.saving = true
        let panel = NSSavePanel()
        panel.nameFieldStringValue = next.name
        panel.beginSheetModal(for: window) { response in
            self.files.saving = false
            if response == .OK, let path = (panel.url as NSURL?)?.path { self.write(next.entry, next.start, next.len, to: path) }
            self.nextSave()
        }
    }

    /// Copy a file's range to `destination` off the main thread. A save has
    /// no result in Roc; the outcome is reported on stderr.
    func write(_ entry: FileEntry, _ start: UInt64, _ len: UInt64, to destination: String) {
        files.queue.async {
            let ok = Files.copy(entry, start, len, to: destination)
            DispatchQueue.main.async {
                self.say(ok ? "saved \(destination) (\(len) bytes)" : "save to \(destination) failed")
            }
        }
    }
}

// MARK: - Views: picking and dropping

extension Host {
    /// `ui-file-button` (a push button that opens an open panel) or
    /// `ui-drop-zone` (a bordered area that takes dropped files).
    func makeFileView(_ name: String) -> NSView {
        if name == "ui-file-button" {
            return NSButton(title: "", target: self, action: #selector(pickFiles(_:)))
        }
        let zone = DropZoneView()
        zone.host = self
        return zone
    }

    /// Ask for files in an open panel, as a sheet on the window, and deliver
    /// the chosen ones as a `change` event.
    @objc func pickFiles(_ sender: NSButton) {
        guard let n = byView[ObjectIdentifier(sender)] else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            self.deliverFiles(panel.urls.compactMap { ($0 as NSURL).path }, type: "change", at: n)
        }
    }
}

/// A drop target for files around one child (`ui-drop-zone`): a dashed
/// outline, in the accent colour while files are dragged over it. Dropped
/// file URLs become a `drop` event.
final class DropZoneView: Surface {
    weak var host: Host?
    private var targeted = false {
        didSet {
            border = targeted ? .solid(.controlAccentColor, 2) : .dashed(.separatorColor, 1.5)
            fill = targeted ? NSColor.controlAccentColor.withAlphaComponent(0.08) : .clear
        }
    }

    override init() {
        super.init()
        registerForDraggedTypes([.fileURL])
        border = .dashed(.separatorColor, 1.5)
        fill = .clear
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The paths of the file URLs being dragged.
    private func filePaths(_ info: NSDraggingInfo) -> [String] {
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) ?? []
        return objects.compactMap { ($0 as? NSURL).flatMap { $0.isFileURL ? $0.path : nil } }
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        targeted = !filePaths(info).isEmpty
        return targeted ? .copy : []
    }

    override func draggingExited(_ info: NSDraggingInfo?) { targeted = false }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        targeted = false
        let paths = filePaths(info)
        guard let host, !paths.isEmpty, let n = host.byView[ObjectIdentifier(self)] else { return false }
        host.deliverFiles(paths, type: "drop", at: n)
        return true
    }
}

// MARK: - The work itself (any thread; plain Swift data only)

extension Files {
    enum Progress { case done, cancelled, unreadable }

    /// Visit `len` bytes of the file from `start`, a chunk at a time
    /// (stdio: `fopen`, `fseeko`, `fread`), stopping when `job` is
    /// cancelled. A file that cannot be opened, or that now holds fewer
    /// bytes than the range, is unreadable.
    static func chunks(_ entry: FileEntry, _ start: UInt64, _ len: UInt64, _ job: FileJob?, _ visit: (UnsafeRawBufferPointer) -> Void) -> Progress {
        guard let file = fopen(entry.path, "rb") else { return .unreadable }
        defer { fclose(file) }
        guard fseeko(file, off_t(start), SEEK_SET) == 0 else { return .unreadable }
        var buffer = [UInt8](repeating: 0, count: chunk)
        var left = len
        while left > 0 {
            if job?.isCancelled == true { return .cancelled }
            let want = Int(min(left, UInt64(chunk)))
            let got = buffer.withUnsafeMutableBytes { fread($0.baseAddress, 1, want, file) }
            if got == 0 { return .unreadable }
            buffer.withUnsafeBytes { visit(UnsafeRawBufferPointer(rebasing: $0[0..<got])) }
            left -= UInt64(got)
        }
        return .done
    }

    /// The range's bytes after the result tag (16 bytes, 17 text; the
    /// engine checks that text is UTF-8), or nil when cancelled.
    static func read(_ entry: FileEntry, _ start: UInt64, _ len: UInt64, tag: UInt8, _ job: FileJob) -> FileOutcome? {
        var payload: [UInt8] = [tag]
        payload.reserveCapacity(Int(len) + 1)
        switch chunks(entry, start, len, job, { payload.append(contentsOf: $0) }) {
        case .done: return .bytes(payload)
        case .cancelled: return nil
        case .unreadable: return .failed(unreadable)
        }
    }

    /// The range's SHA-256 digest (result tag 18), streamed through
    /// CommonCrypto a chunk at a time, or nil when cancelled.
    static func sha256(_ entry: FileEntry, _ start: UInt64, _ len: UInt64, _ job: FileJob) -> FileOutcome? {
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
        let progress = chunks(entry, start, len, job) { _ = CC_SHA256_Update(&context, $0.baseAddress, CC_LONG($0.count)) }
        switch progress {
        case .done:
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256_Final(&digest, &context)
            return .bytes([18] + digest)
        case .cancelled: return nil
        case .unreadable: return .failed(unreadable)
        }
    }

    /// Write the range to `destination`, replacing it.
    static func copy(_ entry: FileEntry, _ start: UInt64, _ len: UInt64, to destination: String) -> Bool {
        guard let out = fopen(destination, "wb") else { return false }
        var failed = false
        let progress = chunks(entry, start, len, nil) { bytes in
            if !failed, fwrite(bytes.baseAddress, 1, bytes.count, out) != bytes.count { failed = true }
        }
        if fclose(out) != 0 { failed = true }
        return progress == .done && !failed
    }
}

// MARK: - Encoding and media types

/// Little-endian encoding for event payloads and file records.
struct Bytes {
    var bytes: [UInt8] = []
    mutating func u32(_ v: UInt32) { for i in 0..<4 { bytes.append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) } }
    mutating func u64(_ v: UInt64) { for i in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: v >> (8 * UInt64(i)))) } }
    mutating func str(_ s: String) { let utf8 = Array(s.utf8); u32(UInt32(utf8.count)); bytes += utf8 }
}

/// A file's media type from its extension, `""` when unknown (as a browser
/// reports a type it does not know). A short table instead of
/// UniformTypeIdentifiers, which would be another framework to link.
func mimeType(_ ext: String) -> String {
    switch ext.lowercased() {
    case "txt", "text", "log": return "text/plain"
    case "md", "markdown": return "text/markdown"
    case "csv": return "text/csv"
    case "html", "htm": return "text/html"
    case "css": return "text/css"
    case "js", "mjs": return "text/javascript"
    case "json": return "application/json"
    case "xml": return "application/xml"
    case "pdf": return "application/pdf"
    case "zip": return "application/zip"
    case "gz": return "application/gzip"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "svg": return "image/svg+xml"
    case "heic": return "image/heic"
    case "mp3": return "audio/mpeg"
    case "wav": return "audio/wav"
    case "mp4": return "video/mp4"
    case "mov": return "video/quicktime"
    case "wasm": return "application/wasm"
    default: return ""
    }
}
