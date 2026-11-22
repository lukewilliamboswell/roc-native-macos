// Runtime symbols compiled Roc calls, defined by the host.

import AppKit

// MARK: - Runtime symbols Roc calls

@_cdecl("roc_alloc")
public func rocAlloc(_ size: Int, _ alignment: Int) -> UnsafeMutableRawPointer {
    var out: UnsafeMutableRawPointer? = nil
    let align = max(alignment, 16)
    if posix_memalign(&out, align, max(size, 1)) != 0 || out == nil {
        fatal("out of memory allocating \(size) bytes")
    }
    if poisonAllocations { memset(out!, 0x5A, max(size, 1)) }
    return out!
}

/// `ROC_POISON=1` fills every new allocation with 'Z', to expose reads of
/// uninitialized memory.
let poisonAllocations = getenv("ROC_POISON") != nil

@_cdecl("roc_dealloc")
public func rocDealloc(_ ptr: UnsafeMutableRawPointer?, _ alignment: Int) {
    guard let ptr else { return }
    // A file handle's box lives in the handle table, not the heap: releasing
    // it retires its slot (Files.swift).
    if fileHandles.route(ptr) { return }
    free(ptr)
}

@_cdecl("roc_realloc")
public func rocRealloc(_ ptr: UnsafeMutableRawPointer?, _ size: Int, _ alignment: Int) -> UnsafeMutableRawPointer {
    // Every allocation is 16-byte aligned by posix_memalign, and realloc
    // keeps malloc's 16-byte alignment, which covers every Roc layout here.
    guard let next = realloc(ptr, max(size, 1)) else { fatal("out of memory reallocating \(size) bytes") }
    return next
}

@_cdecl("roc_dbg")
public func rocDbg(_ bytes: UnsafePointer<UInt8>?, _ len: Int) {
    fputs("[dbg] \(text(bytes, len))\n", __stderrp)
}

@_cdecl("roc_expect_failed")
public func rocExpectFailed(_ bytes: UnsafePointer<UInt8>?, _ len: Int) {
    fputs("[expect failed] \(text(bytes, len))\n", __stderrp)
}

@_cdecl("roc_crashed")
public func rocCrashed(_ bytes: UnsafePointer<UInt8>?, _ len: Int) {
    fatal("Roc crashed: \(text(bytes, len))")
}

private func text(_ bytes: UnsafePointer<UInt8>?, _ len: Int) -> String {
    guard let bytes else { return "" }
    return String(decoding: UnsafeBufferPointer(start: bytes, count: len), as: UTF8.self)
}

func fatal(_ message: String) -> Never {
    fputs("roc-native-macos: \(message)\n", __stderrp)
    exit(1)
}
