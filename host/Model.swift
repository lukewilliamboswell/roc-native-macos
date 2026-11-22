// The command stream reader, and the node tree mirroring what the engine built.

import AppKit

// MARK: - Reading the command stream

struct Reader {
    let bytes: [UInt8]
    var at = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var done: Bool { at >= bytes.count }

    mutating func u8() -> UInt8 {
        guard at < bytes.count else { fatal("command stream truncated") }
        defer { at += 1 }
        return bytes[at]
    }
    mutating func u16() -> UInt16 { UInt16(u8()) | UInt16(u8()) << 8 }
    mutating func u32() -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(u8()) << (8 * UInt32(i)) }
        return v
    }
    mutating func u64() -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(u8()) << (8 * UInt64(i)) }
        return v
    }
    mutating func raw(_ n: Int) -> [UInt8] {
        guard at + n <= bytes.count else { fatal("command stream truncated") }
        defer { at += n }
        return Array(bytes[at..<at + n])
    }
    mutating func str() -> String { String(decoding: raw(Int(u32())), as: UTF8.self) }

    /// `namespace:u8 [uri:str] prefix:str local:str`; the host uses the local name.
    mutating func expandedName() -> String {
        if u8() == 4 { _ = str() }
        _ = str()
        return str()
    }

    /// `presence:u8 [value:str]`: nil when absent.
    mutating func presence() -> String? { u8() == 1 ? str() : nil }
}

// MARK: - The node tree

/// One node the engine created (or one cloned from a row template, which
/// has no engine id of its own).
final class Node {
    enum Kind { case element(String), text, comment }

    let kind: Kind
    var id: UInt32?
    var text = ""
    var attrs: [String: String] = [:]
    weak var parent: Node?
    /// The children, in order. A detached child stays in `storage` until
    /// the children are next read, so removing many children of one parent
    /// in a batch (a list's rows) costs one pass, not one pass each.
    var children: [Node] {
        compact()
        return storage
    }
    private var storage: [Node] = []
    private var stale = 0

    private func compact() {
        if stale > 0 {
            storage.removeAll { $0.parent !== self }
            stale = 0
        }
    }

    /// Drop every child (the caller forgets them).
    func removeAllChildren() {
        for child in storage where child.parent === self { child.parent = nil }
        storage = []
        stale = 0
    }

    /// Event type → (handler number, payload kind).
    var listeners: [String: (handler: UInt32, kind: UInt8, policies: UInt32)] = [:]
    /// A row root's hole targets, by the template's hole index.
    var holes: [(node: Node, attr: String?)] = []
    var view: NSView?

    init(_ kind: Kind) { self.kind = kind }

    var name: String? { if case .element(let n) = kind { return n } else { return nil } }

    var textContent: String {
        switch kind {
        case .text: return text
        case .comment: return ""
        case .element: return children.map(\.textContent).joined()
        }
    }

    func clone() -> Node {
        let copy = Node(kind)
        copy.text = text
        copy.attrs = attrs
        copy.listeners = listeners
        for child in children { copy.append(child.clone()) }
        return copy
    }

    func append(_ child: Node) { insert(child, before: nil) }

    /// Insert `child` before `before` (searched from the end, where a
    /// growing list's anchor is), or last.
    func insert(_ child: Node, before: Node?) {
        compact()
        child.parent = self
        if let before, let i = storage.lastIndex(where: { $0 === before }) {
            storage.insert(child, at: i)
        } else {
            storage.append(child)
        }
    }

    func detach() {
        parent?.stale += 1
        parent = nil
    }

    func walk(_ visit: (Node) -> Void) {
        visit(self)
        for child in children { child.walk(visit) }
    }
}

/// A row template: its node tree and its hole table.
struct Template {
    struct Hole {
        let kind: UInt8
        let path: [Int]
        let attr: String?
    }
    let root: Node
    let holes: [Hole]
}
