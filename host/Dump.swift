// The window as an S-expression (`expect-dump`, `expect-tree`).

import AppKit

/// One item of a dumped node: a node, or a fixed form such as `(more)`.
enum DumpItem {
    case node(Node)
    case form(String)
}

extension Host {
    /// The window and its view tree, one node a line, as the tool reads it
    /// (cli/Spec.roc): `(window :width 360 :height 237 (vstack :views 1 …))`.
    func dumpWindow() -> [String] {
        let size = window.contentView?.frame.size ?? .zero
        var out = ["(window :width \(Int(size.width)) :height \(Int(size.height))"]
        tree(root, 1, &out)
        out[out.count - 1] += ")"
        return out
    }

    /// One node as an S-expression, one node a line, indented two spaces a
    /// level; a node's closing parenthesis ends its last line.
    func tree(_ n: Node, _ depth: Int, _ out: inout [String]) {
        let pad = String(repeating: "  ", count: depth)
        let (head, items) = form(n)
        if items.isEmpty {
            out.append("\(pad)(\(head))")
            return
        }
        out.append("\(pad)(\(head)")
        for item in items {
            switch item {
            case .node(let child): tree(child, depth + 1, &out)
            case .form(let text): out.append("\(pad)  \(text)")
            }
        }
        out[out.count - 1] += ")"
    }

    /// A node's head (its kind, text and attributes) and what it holds.
    func form(_ n: Node) -> (String, [DumpItem]) {
        var name = n.name ?? "text"
        if name.hasPrefix("ui-") { name = String(name.dropFirst(3)) }
        let named = n.children.filter { $0.name != nil }.map { DumpItem.node($0) }
        if n.name == "ui-hover" {
            return (name + (hovered.contains { $0 === n } ? " :pointer-inside #t" : ""), named)
        }
        switch n.view {
        case let s as NSStackView where n.name != nil:
            return ("\(name) :views \((s as? Stack)?.shownCount ?? s.arrangedSubviews.count)", named)
        case let box as ScrollBox:
            return ("\(name) :views \(box.stack.arrangedSubviews.count) :height \(Int(box.frame.height))", named)
        case let box as ListBox:
            let selected = box.table.selectedRow
            let shown = box.table.rows(in: box.table.visibleRect)
            let realized = box.rows.filter { $0.view != nil }.count
            var head = "\(name) :rows \(box.table.numberOfRows) :with-views \(realized)"
            if selected >= 0 { head += " :selected \(selected)" }
            head += " :height \(Int(box.frame.height))"
            if shown.length > 0 { head += " :visible-from \(shown.location) :visible-to \(shown.location + shown.length - 1)" }
            var items: [DumpItem] = []
            for i in max(shown.location, 0)..<min(max(shown.location, 0) + 3, box.table.numberOfRows) {
                if let c = box.node(at: i) { items.append(.node(c)) } else { items.append(.form("(placeholder)")) }
            }
            if box.table.numberOfRows > 3 { items.append(.form("(more)")) }
            return (head, items)
        case let popup as NSPopUpButton:
            return ("\(name) \(Host.quote(popup.titleOfSelectedItem ?? "")) :items (\(popup.itemTitles.map(Host.quote).joined(separator: " ")))", [])
        case let control as NSSegmentedControl:
            let titles = (0..<control.segmentCount).map { Host.quote(control.label(forSegment: $0) ?? "") }
            let chosen = control.selectedSegment >= 0 ? " :selected \(Host.quote(control.label(forSegment: control.selectedSegment) ?? ""))" : ""
            return ("\(name) :items (\(titles.joined(separator: " ")))\(chosen)", [])
        case let b as NSButton:
            if n.name == "ui-checkbox" { return ("\(name) \(Host.quote(b.title)) :checked \(b.state == .on ? "#t" : "#f")", []) }
            return ("\(name) \(Host.quote(b.title))\(b.isEnabled ? "" : " :enabled #f")", [])
        case let f as NSTextField where n.name == "ui-text":
            let usual = ["text-style": "body", "font-size": "standard", "weight": "standard", "design": "proportional", "color": "label"]
            return ("\(name) \(Host.quote(f.stringValue))\(looks(n, usual))", [])
        case let f as NSTextField:
            return ("\(name) \(Host.quote(f.stringValue))", [])
        case let s as NSSlider:
            return ("\(name) :value \(s.doubleValue)", [])
        case let s as NSScrollView where n.name == "ui-text-area":
            return ("\(name) \(Host.quote((s.documentView as? NSTextView)?.string ?? ""))", [])
        case let image as NSImageView:
            return ("\(name) \(Host.atom(n.attrs["symbol"] ?? ""))\(image.image == nil ? " :missing #t" : "")", [])
        case let picture as Picture:
            let (wide, high) = picture.pixels
            return ("\(name) \(Host.atom(picture.name)) :pixels \(wide)x\(high) :width \(Int(picture.frame.width)) :height \(Int(picture.frame.height))\(looks(n, ["scaling": "fit", "label": ""]))", [])
        case let bar as NSProgressIndicator:
            if bar.isIndeterminate { return ("\(name) \(n.attrs["value"] == "1" ? "busy" : "idle")", []) }
            return ("\(name) :value \(Int(bar.doubleValue)) :max \(Int(bar.maxValue))", [])
        case let surface as DrawingSurface:
            // A drawing surface, and its last frame's scene (Drawing.swift).
            surface.produceIfDue()
            return ("\(name) \(surface.dumpHead)", surface.sceneForms().map { DumpItem.form($0) })
        case is Overlay:
            return ("\(name)\(looks(n, ["horizontal": "fill", "vertical": "bottom"]))", named)
        case is Surface:
            return ("\(name)\(looks(n, ["fill": "control-background", "border": "none"]))", named)
        default:
            return (name, [])
        }
    }

    /// The look attributes among `usual`'s keys whose value is not the
    /// usual one, as ` :name value …`, so a dump shows what the app styled.
    func looks(_ n: Node, _ usual: [String: String]) -> String {
        let changed = usual.keys.sorted().compactMap { key in
            n.attrs[key].flatMap { $0 == usual[key] ? nil : " :\(key) \(Host.atom($0))" }
        }
        return changed.joined()
    }

    /// A string, quoted with the escapes a spec reads.
    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }

    /// A value as a bare word when it is one (`secondary-label`,
    /// `line:1:separator`, `64`), and quoted otherwise.
    static func atom(_ s: String) -> String {
        let plain = !s.isEmpty && s.unicodeScalars.allSatisfy { c in
            (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "-" || c == ":" || c == "." || c == "_"
        }
        return plain ? s : quote(s)
    }
}
