// Boot facts: the program's declarations in, the boot sections out.

import AppKit

// MARK: - Declarations (roc_engine_keys)

/// What the program declared it reads at boot (design.md, Appendix B, Boot):
/// sections 2, 5, 6, 10, 11 and 14 as `tag:u8 len:u32 body`. Section 12
/// (protocol facts) is not appended by this platform's root.
struct Declarations {
    var localKeys: [String] = []
    var mediaQueries: [String] = []
    var zoneDays: UInt16 = 0
    var sessionKeys: [String] = []
    /// The whole section 14 body: profile 0 is `[0]`; profile 1 carries the
    /// declared mount root, which the boot's section 13 must then match.
    var startup: [UInt8] = [0]
    /// Section 5: the ports the program declares (Ports.swift).
    var ports: [PortDeclaration] = []

    init(_ bytes: [UInt8]) {
        var r = Reader(bytes)
        var seen: [UInt8] = []
        while !r.done {
            let tag = r.u8()
            var body = Reader(r.raw(Int(r.u32())))
            seen.append(tag)
            switch tag {
            case 2: localKeys = (0..<body.u32()).map { _ in body.str() }
            case 5: ports = (0..<body.u32()).map { _ in PortDeclaration(name: body.str(), kind: body.u8(), delivery: body.u8(), bound: body.u32()) }
            case 6: mediaQueries = (0..<body.u32()).map { _ in body.str() }
            case 10: zoneDays = body.u16()
            case 11: sessionKeys = (0..<body.u32()).map { _ in body.str() }
            case 14: startup = body.bytes; continue
            default: fatal("declaration section \(tag) is not supported by this host")
            }
            if !body.done { fatal("declaration section \(tag) has trailing bytes") }
        }
        if seen != [2, 5, 6, 10, 11, 14] { fatal("unexpected declaration sections \(seen)") }
    }
}

// MARK: - Local and session storage

/// Local storage persists in `UserDefaults`. A spec run (`ROC_SPEC`)
/// keeps it in memory instead, so a spec never sees what an
/// earlier run saved; `ROC_STORAGE_SUITE=<name>` gives a spec run a
/// named `UserDefaults` suite, to check persistence across runs.
enum LocalStorage {
    private static let environment = ProcessInfo.processInfo.environment
    private static let defaults: UserDefaults? =
        environment["ROC_STORAGE_SUITE"].flatMap { UserDefaults(suiteName: $0) }
        ?? (driven ? nil : UserDefaults.standard)
    private static var memory: [String: String] = [:]

    static func get(_ key: String) -> String? { defaults.map { $0.string(forKey: key) } ?? memory[key] }

    /// A spec's `(local-storage KEY VALUE)`, before mount.
    static func seed(_ key: String, _ value: String) {
        if let defaults { defaults.set(value, forKey: key) } else { memory[key] = value }
    }

    static func set(_ key: String, _ value: String) {
        if let defaults { defaults.set(value, forKey: key) } else { memory[key] = value }
    }

    static func remove(_ key: String) {
        if let defaults { defaults.removeObject(forKey: key) } else { memory.removeValue(forKey: key) }
    }
}

/// Session storage lasts for the process: STORAGE ops 3 and 4 write here,
/// FX 17 and boot section 11 read it back.
enum SessionStorage {
    static var values: [String: String] = [:]
}

extension Host {
    /// STORAGE `op key [value]`: 1/2 local set/remove (`LocalStorage`), 3/4
    /// session set/remove.
    func storage(_ op: UInt8, _ key: String, _ r: inout Reader) {
        switch op {
        case 1: LocalStorage.set(key, r.str())
        case 2: LocalStorage.remove(key)
        case 3: SessionStorage.values[key] = r.str()
        case 4: SessionStorage.values.removeValue(forKey: key)
        default: fatal("STORAGE op \(op) is not supported by this host")
        }
    }
}

// MARK: - Boot sections (roc_engine_init)

/// The boot bytes: sections 1–4, 6–11, 13 and 14 in ascending tag order.
func bootBytes(_ d: Declarations, now: Date = Date()) -> [UInt8] {
    var out: [UInt8] = []
    func section(_ tag: UInt8, _ body: [UInt8]) {
        out.append(tag)
        put32(&out, UInt32(body.count))
        out += body
    }
    func pairs(_ keys: [String], _ read: (String) -> String?) -> [UInt8] {
        // Only keys that exist; a key declared twice is read twice.
        let found = keys.compactMap { k in read(k).map { (k, $0) } }
        var b: [UInt8] = [1]
        put32(&b, UInt32(found.count))
        for (k, v) in found { putStr(&b, k); putStr(&b, v) }
        return b
    }
    let nowMs = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))

    var url: [UInt8] = []
    putStr(&url, "/")
    section(1, url)
    section(2, pairs(d.localKeys) { LocalStorage.get($0) })
    section(3, [1])  // online
    section(4, [1])  // visible
    section(6, d.mediaQueries.map { mediaMatches($0) ? 1 : 0 })
    var time: [UInt8] = []
    put64(&time, UInt64(bitPattern: nowMs))
    section(7, time)
    var seed = [UInt8](repeating: 0, count: 16)
    arc4random_buf(&seed, 16)
    section(8, seed)
    section(9, languages())
    section(10, zone(days: d.zoneDays, at: nowMs))
    section(11, pairs(d.sessionKeys) { SessionStorage.values[$0] })
    section(13, mountRoot(d.startup))
    // Profile 0 is the one byte; profile 1 mounts fresh, letting Roc pick
    // the entry from the pathname (or its fallback).
    section(14, d.startup.first == 1 ? [1, 0, 0xff, 0xff, 0xff, 0xff] : [0])
    return out
}

/// Section 13: an HTML `div` (namespace 0, no prefix), unless a profile-1
/// declaration names its own root, which the actual root must match.
private func mountRoot(_ startup: [UInt8]) -> [UInt8] {
    if startup.first == 1 {
        var r = Reader(startup)
        r.at = 1
        let start = r.at
        if r.u8() == 4 { _ = r.str() }
        _ = r.str(); _ = r.str()
        return Array(startup[start..<r.at])
    }
    var b: [UInt8] = [0]
    putStr(&b, "")
    putStr(&b, "div")
    return b
}

/// The few media queries the system answers directly; any other is false.
private func mediaMatches(_ query: String) -> Bool {
    let q = query.lowercased().filter { $0 != " " }
    // The system-wide setting (what a browser reports), not this window's.
    let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    switch q {
    case "(prefers-color-scheme:dark)": return dark
    case "(prefers-color-scheme:light)": return !dark
    default: return false
    }
}

/// Section 9: 1–16 BCP 47 tags of at most 64 bytes; `en-US` when none.
private func languages() -> [UInt8] {
    var tags = Locale.preferredLanguages.filter { !$0.isEmpty && $0.utf8.count <= 64 }
    tags = Array(tags.prefix(16))
    if tags.isEmpty { tags = ["en-US"] }
    var b: [UInt8] = []
    put32(&b, UInt32(tags.count))
    for t in tags { putStr(&b, t) }
    return b
}

/// Section 10: the zone over `days` on each side of mount. The first offset
/// starts exactly at `from_ms`; later ones are the transitions inside the
/// span, strictly ascending, at most 128 in all (the span is cut short
/// before the 128th transition if it has more).
private func zone(days: UInt16, at nowMs: Int64) -> [UInt8] {
    let tz = TimeZone.current
    let reach = Int64(days) * 86_400_000
    let fromMs = nowMs - reach
    var untilMs = nowMs + reach
    func minutes(_ ms: Int64) -> Int32 {
        Int32(tz.secondsFromGMT(for: Date(timeIntervalSince1970: Double(ms) / 1000)) / 60)
    }
    var offsets: [(Int64, Int32)] = [(fromMs, minutes(fromMs))]
    var cursor = Date(timeIntervalSince1970: Double(fromMs) / 1000)
    while let next = tz.nextDaylightSavingTimeTransition(after: cursor) {
        let ms = Int64((next.timeIntervalSince1970 * 1000).rounded(.down))
        if ms > untilMs { break }
        cursor = next
        if ms <= offsets.last!.0 { continue }
        let m = minutes(ms)
        if m == offsets.last!.1 { continue }
        if offsets.count == 128 { untilMs = ms - 1; break }
        offsets.append((ms, m))
    }
    var name = tz.identifier
    if name.utf8.count > 64 { name = "" }
    var b: [UInt8] = []
    putStr(&b, name)
    put64(&b, UInt64(bitPattern: fromMs))
    put64(&b, UInt64(bitPattern: untilMs))
    put32(&b, UInt32(offsets.count))
    for (ms, m) in offsets {
        put64(&b, UInt64(bitPattern: ms))
        put32(&b, UInt32(bitPattern: m))
    }
    return b
}

func put32(_ b: inout [UInt8], _ v: UInt32) {
    for i in 0..<4 { b.append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) }
}

func put64(_ b: inout [UInt8], _ v: UInt64) {
    for i in 0..<8 { b.append(UInt8(truncatingIfNeeded: v >> (8 * UInt64(i)))) }
}

func putStr(_ b: inout [UInt8], _ s: String) {
    put32(&b, UInt32(s.utf8.count))
    b += Array(s.utf8)
}
