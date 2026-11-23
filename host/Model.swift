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
/// A view's own content hugging and compression resistance, before any
/// `width`, `height` or `squeeze` attribute changed them.
struct Natural {
    let hugWidth: NSLayoutConstraint.Priority
    let hugHeight: NSLayoutConstraint.Priority
    let resist: NSLayoutConstraint.Priority
}

final class Node {
    enum Kind { case element(String), text, comment }

    let kind: Kind
    var id: UInt32?
    var text = ""
    var attrs: [String: String] = [:]
    /// How its view hugged and resisted when it was made (Views.swift).
    var natural: Natural?
    /// The parent, held strongly (a weak reference costs every node a side
    /// table and slow reference counting, a third of a million-row mount);
    /// `Host.forget` and `detach` let go of it.
    var parent: Node?
    /// A list row not built yet: its template and hole values
    /// (`Host.materialize`).
    var lazy: LazyRow?
    /// Whether the node is in the host's `dirty` list.
    var marked = false
    /// The children, in order. Changes are merged in when the children are
    /// next read, so a batch that removes, inserts or moves many children of
    /// one parent (a list's rows: a filter narrowing or widening a million
    /// of them) costs one pass over the children, not one pass each. A
    /// detached child stays in `storage` until then; an inserted one waits
    /// in `pending` with the child it goes before.
    var children: [Node] {
        compact()
        return storage
    }
    private var storage: [Node] = []
    private var stale = 0
    private var pending: [(child: Node, before: Node?, tag: Int)] = []
    /// This node's place among its parent's children: `stored` in its
    /// `storage`, or waiting in its `pending` under `tag`.
    private var stored = false
    private var tag = 0
    private static var tags = 0

    private func compact() {
        guard stale > 0 || !pending.isEmpty else { return }
        // Each anchor's waiting children, in the order they were inserted;
        // they go just before it, where it stood when they were inserted.
        var before: [ObjectIdentifier: [Node]] = [:]
        var last: [Node] = []
        for entry in pending where entry.child.parent === self && entry.child.tag == entry.tag {
            if let anchor = entry.before {
                before[ObjectIdentifier(anchor), default: []].append(entry.child)
            } else {
                last.append(entry.child)
            }
        }
        var merged: [Node] = []
        merged.reserveCapacity(storage.count + pending.count)
        for child in storage {
            if !before.isEmpty, let waiting = before[ObjectIdentifier(child)] { merged.append(contentsOf: waiting) }
            if child.parent === self && child.stored { merged.append(child) }
        }
        merged.append(contentsOf: last)
        for child in merged { child.stored = true }
        storage = merged
        pending = []
        stale = 0
    }

    /// Drop every child (the caller forgets them).
    func removeAllChildren() {
        for child in storage where child.parent === self { child.parent = nil }
        for entry in pending where entry.child.parent === self { entry.child.parent = nil }
        storage = []
        pending = []
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

    /// Insert `child` before `before`, or last (merged in when the
    /// children are next read). An anchor that is itself waiting is merged
    /// in first, so every waiting child's anchor has its place.
    func insert(_ child: Node, before: Node?) {
        if let before, before.parent === self, !before.stored { compact() }
        if child.parent === self { stale += 1 }
        child.parent = self
        child.stored = false
        Node.tags += 1
        child.tag = Node.tags
        pending.append((child, before.flatMap { $0.parent === self ? $0 : nil }, child.tag))
    }

    func detach() {
        parent?.stale += 1
        parent = nil
        stored = false
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
    /// Whether a list row of it can wait to be built: its holes are only
    /// text, attributes and listeners, none an engine id or a ref, which
    /// commands could name before the row is shown.
    var deferrable: Bool { holes.allSatisfy { $0.kind != 4 && $0.kind != 5 } }
}

/// A list row's template and the values of its holes, kept up to date by
/// `TEXT`, `HATTR` and `HPROP` until the row is built.
final class LazyRow {
    let template: Template
    var values: [String?]
    init(template: Template, values: [String?]) {
        self.template = template
        self.values = values
    }
}
