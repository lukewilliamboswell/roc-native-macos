// Driving the window without a person: the pointer, keys and lists, for a
// spec's steps (Spec.swift).

import AppKit

/// The pointer, keys and lists as a spec's steps drive them (Spec.swift).
extension Host {
    /// `moves` pointer moves along the line from (x0, y0) to (x1, y1), one
    /// every `ms` milliseconds, as a steady hand would make (`v` is x0, y0,
    /// x1, y1, moves, ms); `done` runs after the last.
    func sweep(_ v: [Double], then done: @escaping () -> Void) {
        let moves = Int(v[4]), interval = v[5] / 1000, began = Bench.now()
        func move(_ i: Int) {
            let t = moves == 1 ? 1 : Double(i) / Double(moves - 1)
            pointer(at: windowPoint(NSPoint(x: v[0] + (v[2] - v[0]) * t, y: v[1] + (v[3] - v[1]) * t)))
            if i + 1 < moves {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) { move(i + 1) }
            } else {
                say("sweep: \(moves) moves in \(Int((Bench.now() - began) * 1000)) ms (planned \(Int(Double(moves - 1) * interval * 1000)) ms)")
                done()
            }
        }
        move(0)
    }

    /// Press and release `chord` (`cmd+shift+n`: modifiers cmd, ctrl, alt
    /// (opt), shift, then the key), as typed in the window: whether the app
    /// heard it, or nil for an unknown modifier.
    func press(_ chord: String) -> Bool? {
        var parts = chord.split(separator: "+").map(String.init)
        let name = parts.popLast() ?? ""
        var flags: UInt8 = 0
        for p in parts {
            switch p {
            case "ctrl": flags |= 1
            case "alt", "opt": flags |= 2
            case "shift": flags |= 4
            case "cmd": flags |= 8
            default: return nil
            }
        }
        let code = Keymap.asciiLetter(name).map { "Key" + String(UnicodeScalar($0 - 0x20)) } ?? Keymap.asciiDigit(name).map { "Digit" + String(UnicodeScalar($0)) } ?? name
        let prevented = deliverKey(down: true, key: name, code: code, flags: flags, target: nil, inText: false)
        _ = deliverKey(down: false, key: name, code: code, flags: flags, target: nil, inText: false)
        return prevented
    }

    func say(_ line: String) { fputs(line + "\n", __stderrp) }

    /// `x,y` as a point.
    static func point(_ text: String) -> NSPoint? {
        let v = text.split(separator: ",").compactMap { Double(String($0)) }
        return v.count == 2 ? NSPoint(x: v[0], y: v[1]) : nil
    }

    /// A point of the content view, from its top-left corner, in window
    /// coordinates.
    func windowPoint(_ p: NSPoint) -> NSPoint {
        guard let content = window.contentView else { return p }
        return content.convert(NSPoint(x: p.x, y: content.isFlipped ? p.y : content.bounds.height - p.y), to: nil)
    }

    /// The first list's view, found without walking its rows.
    func firstList() -> ListBox? {
        func search(_ n: Node) -> ListBox? {
            if let box = n.view as? ListBox { return box }
            for child in n.children { if let found = search(child) { return found } }
            return nil
        }
        return search(root)
    }

    func find(_ test: (Node) -> Bool) -> Node? {
        var found: Node?
        root.walk { if found == nil, test($0) { found = $0 } }
        return found
    }

}

extension Node {
    /// Whether this node or a descendant passes `test`.
    func contains(_ test: (Node) -> Bool) -> Bool {
        var found = false
        walk { if !found, test($0) { found = true } }
        return found
    }
}
