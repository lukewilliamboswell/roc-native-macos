// Keyboard input: AppKit key events to the engine's key handlers (payload
// kind 4), matched against the keymaps the engine renders (properties 4
// and 5), as roc-signals' design.md "Keyboard input" specifies.

import AppKit

/// A decoded keymap: `(p|k)(a|o)(C|-)(A|-)(S|-)(M|-)<len>:<key>` entries,
/// then an optional `a*` or `o*` (every).
struct Keymap {
    struct Entry {
        let prevent: Bool
        let outside: Bool
        let mods: UInt8  // Ctrl 1, Alt 2, Shift 4, Meta 8
        let key: String
    }

    var entries: [Entry] = []
    /// `every`, and whether it is restricted to outside text entry.
    var every: Bool?

    init(_ encoded: String) {
        let b = Array(encoded.utf8)
        var i = 0
        func bad() -> Never { fatal("malformed keymap \(encoded)") }
        while i < b.count {
            if b.count - i == 2, b[i + 1] == UInt8(ascii: "*") {
                switch b[i] {
                case UInt8(ascii: "a"): every = false
                case UInt8(ascii: "o"): every = true
                default: bad()
                }
                return
            }
            guard b.count - i >= 8 else { bad() }
            let prevent: Bool
            switch b[i] { case UInt8(ascii: "p"): prevent = true; case UInt8(ascii: "k"): prevent = false; default: bad() }
            let outside: Bool
            switch b[i + 1] { case UInt8(ascii: "a"): outside = false; case UInt8(ascii: "o"): outside = true; default: bad() }
            var mods: UInt8 = 0
            let letters: [(UInt8, UInt8)] = [(UInt8(ascii: "C"), 1), (UInt8(ascii: "A"), 2), (UInt8(ascii: "S"), 4), (UInt8(ascii: "M"), 8)]
            for (offset, (letter, bit)) in letters.enumerated() {
                let c = b[i + 2 + offset]
                if c == letter { mods |= bit } else if c != UInt8(ascii: "-") { bad() }
            }
            i += 6
            var length = 0
            let digitsStart = i
            while i < b.count, b[i] >= 48, b[i] <= 57 {
                length = length * 10 + Int(b[i] - 48)
                i += 1
            }
            guard i > digitsStart, i < b.count, b[i] == UInt8(ascii: ":"), !(b[digitsStart] == 48 && i - digitsStart > 1) else { bad() }
            i += 1
            guard i + length <= b.count else { bad() }
            entries.append(Entry(prevent: prevent, outside: outside, mods: mods, key: String(decoding: b[i..<i + length], as: UTF8.self)))
            i += length
        }
    }

    /// The chord this map hears for an event, and whether it prevents the
    /// event's default; nil when it hears nothing.
    func match(key: String, code: String, flags: UInt8, inText: Bool) -> (mods: UInt8, key: String, prevent: Bool)? {
        let composing = flags & 32 != 0
        if !composing {
            let candidates = entries.filter { !$0.outside || !inText }
            for e in candidates where Keymap.modsMatch(e, flags) && Keymap.keyMatches(e.key, key) {
                return (e.mods, e.key, e.prevent)
            }
            for e in candidates where Keymap.modsMatch(e, flags) && Keymap.physicalMatches(e.key, key, code) {
                return (e.mods, e.key, e.prevent)
            }
        }
        if let outside = every, !(outside && inText) { return (flags & 15, key, false) }
        return nil
    }

    /// Ctrl, Alt and Meta compare exactly; Shift too, except for a chord of
    /// one punctuation or symbol scalar.
    static func modsMatch(_ e: Entry, _ flags: UInt8) -> Bool {
        let ignoreShift = isPunctuationOrSymbol(e.key)
        let mask: UInt8 = ignoreShift ? 1 | 2 | 8 : 15
        return e.mods & mask == flags & mask
    }

    static func isPunctuationOrSymbol(_ key: String) -> Bool {
        let scalars = key.unicodeScalars
        guard scalars.count == 1, let s = scalars.first else { return false }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    static func asciiLetter(_ s: String) -> UInt8? {
        let b = Array(s.utf8)
        guard b.count == 1, (65...90).contains(b[0]) || (97...122).contains(b[0]) else { return nil }
        return b[0] | 0x20
    }

    static func asciiDigit(_ s: String) -> UInt8? {
        let b = Array(s.utf8)
        guard b.count == 1, (48...57).contains(b[0]) else { return nil }
        return b[0]
    }

    /// One ASCII letter compares without case; any other key exactly.
    static func keyMatches(_ chord: String, _ key: String) -> Bool {
        if chord.isEmpty { return false }
        if let c = asciiLetter(chord) { return asciiLetter(key) == c }
        return chord == key
    }

    /// A chord of one ASCII letter or digit also hears its physical key
    /// (`KeyK`, `Digit1`) when the event's key is not an ASCII letter or digit.
    static func physicalMatches(_ chord: String, _ key: String, _ code: String) -> Bool {
        if asciiLetter(key) != nil || asciiDigit(key) != nil { return false }
        if let c = asciiLetter(chord) { return code == "Key" + String(UnicodeScalar(c - 0x20)) }
        if let d = asciiDigit(chord) { return code == "Digit" + String(UnicodeScalar(d)) }
        return false
    }
}

extension Host {
    /// An AppKit key event in the window; true when a keymap that heard it
    /// prevents its default (AppKit then never sees it).
    func key(_ event: NSEvent) -> Bool {
        guard let name = Host.keyName(event) else { return false }
        var flags: UInt8 = 0
        let m = event.modifierFlags
        if m.contains(.control) { flags |= 1 }
        if m.contains(.option) { flags |= 2 }
        if m.contains(.shift) { flags |= 4 }
        if m.contains(.command) { flags |= 8 }
        if event.type == .keyDown, event.isARepeat { flags |= 16 }
        var inText = false
        var view = window.firstResponder as? NSView
        if let text = window.firstResponder as? NSTextView {
            inText = true
            if text.hasMarkedText() { flags |= 32 }
            // A text field's editor stands in for the field.
            if text.isFieldEditor, let field = text.delegate as? NSView { view = field }
        }
        while let v = view, byView[ObjectIdentifier(v)] == nil { view = v.superview }
        let target = view.flatMap { byView[ObjectIdentifier($0)] }
        return deliverKey(down: event.type == .keyDown, key: name, code: Host.keyCode(event.keyCode), flags: flags, target: target, inText: inText)
    }

    /// Dispatch a key: the nearest element at or above `target` whose key
    /// handler's keymap hears it, otherwise the most recently mounted
    /// document handler that hears it. Returns whether it is prevented.
    func deliverKey(down: Bool, key: String, code: String, flags: UInt8, target: Node?, inText: Bool) -> Bool {
        let type = down ? "keydown" : "keyup"
        let mapName = down ? "keymap-down" : "keymap-up"
        func hears(_ n: Node, document: Bool) -> Bool? {
            guard let l = n.listeners[type], l.kind == 4, (l.policies & 16 != 0) == document,
                  let map = n.attrs[mapName],
                  let heard = Keymap(map).match(key: key, code: code, flags: flags, inText: inText)
            else { return nil }
            var payload: [UInt8] = [flags]
            Host.appendStr(&payload, key)
            Host.appendStr(&payload, code)
            payload.append(heard.mods)
            Host.appendStr(&payload, heard.key)
            var route: Node? = n
            while let r = route, r.id == nil { route = r.parent }
            if let id = route?.id { send(id, l.handler, payload) }
            return heard.prevent
        }
        var cursor = target
        while let n = cursor {
            if let prevent = hears(n, document: false) { return prevent }
            cursor = n.parent
        }
        for n in documentKeys.reversed() {
            if let prevent = hears(n, document: true) { return prevent }
        }
        return false
    }

    static func appendStr(_ bytes: inout [UInt8], _ s: String) {
        let utf8 = Array(s.utf8)
        let n = UInt32(utf8.count)
        for i in 0..<4 { bytes.append(UInt8(truncatingIfNeeded: n >> (8 * UInt32(i)))) }
        bytes.append(contentsOf: utf8)
    }

    /// The DOM `key` of an AppKit event: a named key, or the characters the
    /// key types ignoring every modifier but Shift.
    static func keyName(_ event: NSEvent) -> String? {
        if let named = namedKeys[event.keyCode] { return named }
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
        return chars
    }

    static let namedKeys: [UInt16: String] = [
        36: "Enter", 76: "Enter", 48: "Tab", 51: "Backspace", 53: "Escape", 117: "Delete",
        123: "ArrowLeft", 124: "ArrowRight", 125: "ArrowDown", 126: "ArrowUp",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// The DOM `code` of an AppKit key code (ANSI layout positions).
    static func keyCode(_ code: UInt16) -> String {
        if let name = codes[code] { return name }
        return namedKeys[code] ?? ""
    }

    static let codes: [UInt16: String] = {
        var table: [UInt16: String] = [:]
        let letters: [(UInt16, String)] = [
            (0, "A"), (1, "S"), (2, "D"), (3, "F"), (4, "H"), (5, "G"), (6, "Z"), (7, "X"), (8, "C"), (9, "V"),
            (11, "B"), (12, "Q"), (13, "W"), (14, "E"), (15, "R"), (16, "Y"), (17, "T"), (31, "O"), (32, "U"),
            (34, "I"), (35, "P"), (37, "L"), (38, "J"), (40, "K"), (45, "N"), (46, "M"),
        ]
        for (code, letter) in letters { table[code] = "Key" + letter }
        let digits: [(UInt16, String)] = [(18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"), (28, "8"), (25, "9"), (29, "0")]
        for (code, digit) in digits { table[code] = "Digit" + digit }
        let others: [(UInt16, String)] = [
            (24, "Equal"), (27, "Minus"), (30, "BracketRight"), (33, "BracketLeft"), (39, "Quote"), (41, "Semicolon"),
            (42, "Backslash"), (43, "Comma"), (44, "Slash"), (47, "Period"), (50, "Backquote"), (49, "Space"),
        ]
        for (code, name) in others { table[code] = name }
        return table
    }()
}
