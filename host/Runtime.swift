// Runtime symbols compiled Roc calls, defined by the host.
//
// Two kinds of Roc instance call them: the page's, on the main thread, and
// a worker instance, on its own worker thread (Workers.swift). Each symbol
// asks which one is running on the calling thread (`WorkerContext.current`,
// a thread-specific pointer that only a worker thread sets) and acts for
// that instance alone: a worker instance allocates from its own heap and
// releases handles in its own table, and a crash in it unwinds only its
// call. The page's instance keeps the plain allocator, and a crash in it
// stops the app.

import AppKit

// MARK: - Runtime symbols Roc calls

@_cdecl("roc_alloc")
public func rocAlloc(_ size: Int, _ alignment: Int) -> UnsafeMutableRawPointer {
    if let context = WorkerContext.current { return context.allocate(size, alignment) }
    var out: UnsafeMutableRawPointer? = nil
    let align = max(alignment, 16)
    if posix_memalign(&out, align, max(size, 1)) != 0 || out == nil {
        fatal("out of memory allocating \(size) bytes")
    }
    if poisonAllocations { memset(out!, 0x5A, max(size, 1)) }
    if countAllocations {
        pageHeap.allocations += 1
        pageHeap.bytes += size
    }
    return out!
}

/// The page instance's heap traffic, counted only while a spec runs
/// (`ROC_SPEC`), for its allocation metrics: every `roc_alloc`,
/// `roc_realloc` and `roc_dealloc` of the page's instance, and the bytes
/// `roc_alloc` and `roc_realloc` were asked for. Main thread only, like
/// the page's instance; a worker instance's heap (`WorkerContext`) is not
/// counted. A file handle's release is not a heap release, so it is not
/// counted either.
struct HeapCounts {
    var allocations = 0
    var reallocations = 0
    var deallocations = 0
    var bytes = 0
}

var pageHeap = HeapCounts()

/// Whether to count: only in a spec run, so a normal run pays one test of
/// a constant per call.
let countAllocations = getenv("ROC_SPEC") != nil

/// `ROC_POISON=1` fills every new allocation with 'Z', to expose reads of
/// uninitialized memory.
let poisonAllocations = getenv("ROC_POISON") != nil

@_cdecl("roc_dealloc")
public func rocDealloc(_ ptr: UnsafeMutableRawPointer?, _ alignment: Int) {
    guard let ptr else { return }
    if let context = WorkerContext.current { return context.deallocate(ptr) }
    // A file handle's box lives in the handle table, not the heap: releasing
    // it retires its slot (Files.swift).
    if fileHandles.contains(ptr) {
        if pthread_main_np() == 0 { fatal("a page file handle was released off the main thread") }
        if fileHandles.route(ptr) { return }
    }
    if countAllocations { pageHeap.deallocations += 1 }
    free(ptr)
}

@_cdecl("roc_realloc")
public func rocRealloc(_ ptr: UnsafeMutableRawPointer?, _ size: Int, _ alignment: Int) -> UnsafeMutableRawPointer {
    if let context = WorkerContext.current { return context.reallocate(ptr, size, alignment) }
    // Every allocation is 16-byte aligned by posix_memalign, and realloc
    // keeps malloc's 16-byte alignment, which covers every Roc layout here.
    guard let next = realloc(ptr, max(size, 1)) else { fatal("out of memory reallocating \(size) bytes") }
    if countAllocations {
        pageHeap.reallocations += 1
        pageHeap.bytes += size
    }
    return next
}

@_cdecl("roc_dbg")
public func rocDbg(_ bytes: UnsafePointer<UInt8>?, _ len: Int) {
    if let context = WorkerContext.current { context.checkStop() }
    fputs("[dbg] \(text(bytes, len))\n", __stderrp)
}

@_cdecl("roc_expect_failed")
public func rocExpectFailed(_ bytes: UnsafePointer<UInt8>?, _ len: Int) {
    // A failed `expect` in a job poisons its worker instance, as in
    // roc-signals (class expect_failed); on the page it is reported.
    if let context = WorkerContext.current, context.pointee.inCall { context.fault(.expectFailed, bytes, len) }
    fputs("[expect failed] \(text(bytes, len))\n", __stderrp)
}

@_cdecl("roc_crashed")
public func rocCrashed(_ bytes: UnsafePointer<UInt8>?, _ len: Int) {
    // A crash in a job unwinds that job's call and discards its instance;
    // the page and every other worker are untouched (Workers.swift).
    if let context = WorkerContext.current, context.pointee.inCall { context.fault(nil, bytes, len) }
    fatal("Roc crashed: \(text(bytes, len))")
}

private func text(_ bytes: UnsafePointer<UInt8>?, _ len: Int) -> String {
    guard let bytes else { return "" }
    return String(decoding: UnsafeBufferPointer(start: bytes, count: len), as: UTF8.self)
}

/// Set once the app is stopping on an error: no further turn runs, so the
/// alert's modal loop cannot re-enter Roc from a timer or queued event.
var halted = false

/// Stop on an error: print it, show it in an alert (not in a scripted run,
/// which must never block), then exit non-zero. A Roc crash arrives here
/// from inside a Roc call, so nothing after it calls Roc again.
func fatal(_ message: String) -> Never {
    fputs("roc-native-macos: \(message)\n", __stderrp)
    if !halted, !driven, Thread.isMainThread {
        halted = true
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "\(ProcessInfo.processInfo.processName) stopped"
        alert.informativeText = message
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    halted = true
    exit(1)
}
