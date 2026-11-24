// Typed ports (roc-signals' `Port`), served by native services in place of
// a page's JavaScript.

import AppKit

// MARK: - Declarations

/// A port the program declares (declaration section 5): its name, its shape
/// (1 command, 2 call, 3 subscription) and, for a subscription, how its
/// undelivered messages wait (delivery 1 `Every(bound)`, 2 `Latest`).
struct PortDeclaration: Equatable {
    let name: String
    let kind: UInt8
    let delivery: UInt8
    let bound: UInt32

    static func command(_ name: String) -> PortDeclaration { PortDeclaration(name: name, kind: 1, delivery: 0, bound: 0) }
    static func latest(_ name: String) -> PortDeclaration { PortDeclaration(name: name, kind: 3, delivery: 2, bound: 1) }
    static func every(_ name: String, _ n: UInt32) -> PortDeclaration { PortDeclaration(name: name, kind: 3, delivery: 1, bound: n) }

    var shape: String {
        switch kind {
        case 1: return "a command"
        case 2: return "a call"
        default: return delivery == 2 ? "a subscription delivering Latest" : "a subscription delivering Every(\(bound))"
        }
    }
}

/// A message as it crosses: the JSON text, its blobs and the files it names
/// (a token and the range of its file the value holds).
struct PortMessage {
    var json: String
    var blobs: [[UInt8]] = []
    var files: [(token: UInt64, start: UInt64, len: UInt64)] = []

    /// `json:str nblobs:u32 (len:u32 bytes)* nfiles:u32 (token:u64 start:u64 len:u64)*`.
    static func read(_ r: inout Reader) -> PortMessage {
        let json = r.str()
        let blobs = (0..<r.u32()).map { _ in r.raw(Int(r.u32())) }
        let files = (0..<r.u32()).map { _ in (token: r.u64(), start: r.u64(), len: r.u64()) }
        return PortMessage(json: json, blobs: blobs, files: files)
    }
}

/// A native service behind one or more ports. Every method runs on the main
/// thread, while a batch is applied: a service decides, and anything it
/// answers is delivered later through `PortHost.emit`, never re-entering
/// the engine.
protocol PortService: AnyObject {
    /// The ports it serves, as the program must declare them.
    var declarations: [PortDeclaration] { get }
    /// A command (`PORT`, opcode 19).
    func command(port: String, _ message: PortMessage)
    /// A new subscription (`FX` kind 10) with id `id`.
    func subscribe(id: UInt32, port: String, _ message: PortMessage)
    /// The engine ended the subscription (`CANCEL`, or its site was
    /// disposed): nothing more may be delivered to it.
    func unsubscribe(id: UInt32)
    /// Teardown: quit or reload.
    func teardown()
}

// MARK: - The port host

/// The ports the program declared and the subscriptions it holds open, with
/// the messages waiting for each. Main-thread state only.
final class PortHost {
    private(set) var declared: [String: PortDeclaration] = [:]
    private var services: [String: PortService] = [:]
    private var all: [PortService] = []
    private struct Open { let port: String; let service: PortService; let delivery: UInt8; let bound: UInt32; var waiting: [[UInt8]] = [] }
    private var open: [UInt32: Open] = [:]
    private var order: [UInt32] = []
    private var flushing = false
    /// Delivers one effect result (`Host.send`).
    var deliver: (UInt32, [UInt8]) -> Void = { _, _ in }

    /// Register a service for its ports.
    func serve(_ service: PortService) {
        all.append(service)
        for d in service.declarations { services[d.name] = service }
    }

    /// The program's section 5: every declared port must be one a service
    /// here serves, in the same shape, or mounting is a fatal error (the
    /// browser runtime refuses to mount a page whose handlers do not match).
    func declare(_ ports: [PortDeclaration]) {
        let served = Dictionary(all.flatMap { $0.declarations }.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for p in ports {
            guard let mine = served[p.name] else { fatal("the program declares port \"\(p.name)\", which this host does not serve") }
            if mine != p { fatal("the program declares port \"\(p.name)\" as \(p.shape); this host serves it as \(mine.shape)") }
            declared[p.name] = p
        }
    }

    private func service(_ port: String) -> PortService {
        guard declared[port] != nil, let s = services[port] else { fatal("a request names port \"\(port)\", which the program did not declare") }
        return s
    }

    /// `PORT port message`.
    func command(_ r: inout Reader) {
        let port = r.str(), message = PortMessage.read(&r)
        service(port).command(port: port, message)
    }

    /// `FX id 10 port message`.
    func subscribe(id: UInt32, _ r: inout Reader) {
        let port = r.str(), message = PortMessage.read(&r)
        let s = service(port), d = declared[port]!
        open[id] = Open(port: port, service: s, delivery: d.delivery, bound: d.bound)
        order.append(id)
        s.subscribe(id: id, port: port, message)
    }

    /// `FX id 9`: no service here is a call.
    func call(id: UInt32, _ r: inout Reader) {
        let port = r.str()
        fatal("port \"\(port)\" is called, but this host serves no call ports")
    }

    /// `CANCEL id`: whether `id` was a subscription.
    func cancel(_ id: UInt32) -> Bool {
        guard let o = open.removeValue(forKey: id) else { return false }
        order.removeAll { $0 == id }
        o.service.unsubscribe(id: id)
        return true
    }

    /// Queue a message for subscription `id` as JSON text: `Latest` keeps
    /// only the newest undelivered one, `Every(n)` up to `n`, refusing more
    /// (answers false), as the browser runtime's `emit` does. Delivery is one
    /// turn per message, from the main queue, never inside a batch.
    @discardableResult
    func emit(_ id: UInt32, json: String) -> Bool {
        guard var o = open[id] else { return false }
        var payload: [UInt8] = [14]
        putStr(&payload, json)
        put32(&payload, 0)  // no blobs
        put32(&payload, 0)  // no files
        if o.delivery == 2 {
            o.waiting = [payload]
        } else {
            if o.waiting.count >= Int(o.bound) { return false }
            o.waiting.append(payload)
        }
        open[id] = o
        schedule()
        return true
    }

    /// End subscription `id` from the host's side (`PortFailed(Closed)`).
    func close(_ id: UInt32) {
        guard let o = open.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        o.service.unsubscribe(id: id)
        DispatchQueue.main.async { self.deliver(id, [15, 3]) }
    }

    /// The ids of the open subscriptions to `port`.
    func subscriptions(_ port: String) -> [UInt32] { order.filter { open[$0]?.port == port } }

    private func schedule() {
        if flushing { return }
        flushing = true
        DispatchQueue.main.async { self.flush() }
    }

    /// Deliver what waits, oldest subscription first. A message whose
    /// subscription ended while it waited is dropped.
    private func flush() {
        flushing = false
        for id in order {
            while let o = open[id], !o.waiting.isEmpty {
                var next = o
                let payload = next.waiting.removeFirst()
                open[id] = next
                deliver(id, payload)
            }
        }
    }

    /// Quit or reload: every service lets go, and nothing more is delivered.
    func teardown() {
        open.removeAll()
        order.removeAll()
        for s in all { s.teardown() }
    }
}

// MARK: - JSON, as the port format writes and reads it

/// A JSON value: the port format's text (`PortJson`) as the host reads it.
indirect enum Json: Equatable {
    case null, bool(Bool), number(Double), string(String), array([Json]), object([String: Json])

    /// Parse a whole text; nil when it is not JSON.
    static func parse(_ text: String) -> Json? {
        var p = JsonParser(Array(text.utf8))
        guard let v = p.value() else { return nil }
        p.ws()
        return p.at == p.b.count ? v : nil
    }

    subscript(_ key: String) -> Json? { if case .object(let o) = self { return o[key] } else { return nil } }

    /// A number, or the strings the format writes for integers past 2^53
    /// and for NaN and the infinities.
    var double: Double? {
        switch self {
        case .number(let d): return d
        case .string(let s): return s == "NaN" ? .nan : s == "Infinity" ? .infinity : s == "-Infinity" ? -.infinity : Double(s)
        default: return nil
        }
    }

    var uint64: UInt64? {
        switch self {
        case .number(let d): return d >= 0 && d < 18446744073709551616.0 && d.rounded() == d ? UInt64(d) : nil
        case .string(let s): return UInt64(s)
        default: return nil
        }
    }

    /// A tag: its name and payload (`"Play"`, `{"Seek":5}`).
    var tag: (String, Json?)? {
        switch self {
        case .string(let s): return (s, nil)
        case .object(let o) where o.count == 1: return (o.first!.key, o.first!.value)
        default: return nil
        }
    }

    /// A file marker `{"$file":N}`: its index in the message's files.
    var fileIndex: Int? { self["$file"]?.uint64.map(Int.init) }
}

private struct JsonParser {
    let b: [UInt8]
    var at = 0
    init(_ b: [UInt8]) { self.b = b }

    mutating func ws() { while at < b.count, [0x20, 0x09, 0x0a, 0x0d].contains(b[at]) { at += 1 } }

    mutating func value() -> Json? {
        ws()
        guard at < b.count else { return nil }
        switch b[at] {
        case UInt8(ascii: "{"):
            at += 1
            var o: [String: Json] = [:]
            ws()
            if at < b.count, b[at] == UInt8(ascii: "}") { at += 1; return .object(o) }
            while true {
                ws()
                guard case .string(let k)? = string() else { return nil }
                ws()
                guard at < b.count, b[at] == UInt8(ascii: ":") else { return nil }
                at += 1
                guard let v = value() else { return nil }
                o[k] = v
                ws()
                guard at < b.count else { return nil }
                if b[at] == UInt8(ascii: ",") { at += 1; continue }
                if b[at] == UInt8(ascii: "}") { at += 1; return .object(o) }
                return nil
            }
        case UInt8(ascii: "["):
            at += 1
            var a: [Json] = []
            ws()
            if at < b.count, b[at] == UInt8(ascii: "]") { at += 1; return .array(a) }
            while true {
                guard let v = value() else { return nil }
                a.append(v)
                ws()
                guard at < b.count else { return nil }
                if b[at] == UInt8(ascii: ",") { at += 1; continue }
                if b[at] == UInt8(ascii: "]") { at += 1; return .array(a) }
                return nil
            }
        case UInt8(ascii: "\""): return string()
        case UInt8(ascii: "t"): return word("true", .bool(true))
        case UInt8(ascii: "f"): return word("false", .bool(false))
        case UInt8(ascii: "n"): return word("null", .null)
        default: return number()
        }
    }

    mutating func word(_ w: String, _ v: Json) -> Json? {
        let u = Array(w.utf8)
        guard at + u.count <= b.count, Array(b[at..<at + u.count]) == u else { return nil }
        at += u.count
        return v
    }

    mutating func number() -> Json? {
        let start = at
        while at < b.count, "+-0123456789.eE".utf8.contains(b[at]) { at += 1 }
        guard at > start, let d = Double(String(decoding: b[start..<at], as: UTF8.self)) else { return nil }
        return .number(d)
    }

    mutating func string() -> Json? {
        guard at < b.count, b[at] == UInt8(ascii: "\"") else { return nil }
        at += 1
        var out: [UInt8] = []
        while at < b.count {
            let c = b[at]
            at += 1
            if c == UInt8(ascii: "\"") { return .string(String(decoding: out, as: UTF8.self)) }
            if c != UInt8(ascii: "\\") { out.append(c); continue }
            guard at < b.count else { return nil }
            let e = b[at]
            at += 1
            switch e {
            case UInt8(ascii: "n"): out.append(0x0a)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "r"): out.append(0x0d)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0c)
            case UInt8(ascii: "u"):
                guard at + 4 <= b.count, let unit = UInt32(String(decoding: b[at..<at + 4], as: UTF8.self), radix: 16) else { return nil }
                at += 4
                // A lone surrogate becomes U+FFFD; the format writes none.
                out += Array(String(UnicodeScalar(unit).map(Character.init) ?? "\u{FFFD}").utf8)
            default: out.append(e)
            }
        }
        return nil
    }
}

/// Writing the port format's JSON: a record's keys in ascending byte order,
/// numbers in their shortest form.
enum JsonText {
    static func string(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    let digits = Array("0123456789abcdef")
                    out += "\\u00" + String(digits[Int(u.value >> 4)]) + String(digits[Int(u.value & 15)])
                } else {
                    out += String(u)
                }
            }
        }
        return out + "\""
    }

    static func number(_ f: Float) -> String {
        if f.isNaN { return "\"NaN\"" }
        if f.isInfinite { return f > 0 ? "\"Infinity\"" : "\"-Infinity\"" }
        // Written through Double, whose text reads back to the same Float.
        return "\(Double(f))"
    }

    static func number(_ d: Double) -> String {
        if d.isNaN { return "\"NaN\"" }
        if d.isInfinite { return d > 0 ? "\"Infinity\"" : "\"-Infinity\"" }
        return "\(d)"
    }

    /// An object, its keys sorted by their bytes.
    static func object(_ fields: [(String, String)]) -> String {
        "{" + fields.sorted { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }.map { "\(string($0.0)):\($0.1)" }.joined(separator: ",") + "}"
    }

    static func array(_ items: [String]) -> String { "[" + items.joined(separator: ",") + "]" }

    /// A tag with one payload (`{"Name":payload}`) or none (`"Name"`).
    static func tag(_ name: String, _ payload: String? = nil) -> String { payload.map { "{\(string(name)):\($0)}" } ?? string(name) }
}
