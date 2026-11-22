// Scripted driving (`ROC_SCRIPT`), for checking an example without a person.

import AppKit

// MARK: - Scripted driving, for checking an example without a person

/// `ROC_SCRIPT="click:+;type:milk;enter;toggle:milk;wait:500;dump;quit"`
/// drives the real controls (the same action methods AppKit calls), one step
/// every 100 ms. `dump` prints the node tree as the views show it.
/// `files:/a.txt,/b.png` delivers files as if picked on the first file
/// button or drop zone (`drop:` as if dropped on the first drop zone),
/// without opening a panel.
extension Host {
    func run(script: String) {
        var steps = script.split(separator: ";").map(String.init)
        func next() {
            guard !steps.isEmpty else { return }
            let step = steps.removeFirst()
            let (verb, arg) = step.firstIndex(of: ":").map { (String(step[..<$0]), String(step[step.index(after: $0)...])) } ?? (step, "")
            var delay = 0.1
            switch verb {
            case "click":
                if let n = find({ $0.name == "ui-button" && $0.textContent == arg }), let b = n.view as? NSButton { pressed(b) }
                else { fatal("script: no button \(arg)") }
            case "type":
                if let n = find({ $0.name == "ui-text-field" }), let f = n.view as? NSTextField {
                    f.stringValue = arg
                    dispatch("input", at: n, text: arg)
                }
            case "write":
                // The first text area; `\n` in the argument is a line break.
                if let n = find({ $0.name == "ui-text-area" }), let text = (n.view as? NSScrollView)?.documentView as? NSTextView {
                    let value = arg.replacingOccurrences(of: "\\n", with: "\n")
                    text.string = value
                    dispatch("input", at: n, text: value)
                } else { fatal("script: no text area") }
            case "enter":
                if let n = find({ $0.name == "ui-text-field" }) { submit(from: n) }
            case "toggle":
                if let n = find({ $0.name == "ui-checkbox" && $0.attrs["title"] == arg }), let b = n.view as? NSButton {
                    b.state = b.state == .on ? .off : .on
                    toggled(b)
                } else { fatal("script: no checkbox \(arg)") }
            case "files", "drop":
                // Files as if picked on the first file control (`files`) or
                // dropped on the first drop zone (`drop`), without a panel.
                let paths = arg.split(separator: ",").map(String.init)
                let zone = verb == "drop"
                guard let n = find({ $0.name == "ui-drop-zone" || (!zone && $0.name == "ui-file-button") }) else { fatal("script: no file control") }
                deliverFiles(paths, type: n.name == "ui-drop-zone" ? "drop" : "change", at: n)
            case "choose":
                // A dropdown item or segment titled `arg`.
                guard let n = find({ ($0.name == "ui-dropdown" || $0.name == "ui-segmented") && Host.choices($0.attrs["choices"]).contains(arg) })
                else { fatal("script: no dropdown or segment \(arg)") }
                if let popup = n.view as? NSPopUpButton {
                    popup.selectItem(withTitle: arg)
                    chose(popup)
                } else if let control = n.view as? NSSegmentedControl {
                    control.selectedSegment = Host.choices(n.attrs["choices"]).firstIndex(of: arg) ?? -1
                    segmentChanged(control)
                }
            case "select":
                // The list row holding a text exactly `arg`.
                guard let row = find({ n in n.parent?.view is ListBox && n.name != nil && n.contains { $0.textContent == arg && $0.name != nil } }),
                      let box = row.parent?.view as? ListBox
                else { fatal("script: no list row \(arg)") }
                box.select(row)
            case "key":
                // `key:cmd+shift+n`: modifiers cmd, ctrl, alt (opt), shift, then the key.
                var parts = arg.split(separator: "+").map(String.init)
                let name = parts.popLast() ?? ""
                var flags: UInt8 = 0
                for p in parts {
                    switch p {
                    case "ctrl": flags |= 1
                    case "alt", "opt": flags |= 2
                    case "shift": flags |= 4
                    case "cmd": flags |= 8
                    default: fatal("script: unknown modifier \(p)")
                    }
                }
                let code = Keymap.asciiLetter(name).map { "Key" + String(UnicodeScalar($0 - 0x20)) } ?? Keymap.asciiDigit(name).map { "Digit" + String(UnicodeScalar($0)) } ?? name
                let prevented = deliverKey(down: true, key: name, code: code, flags: flags, target: nil, inText: false)
                _ = deliverKey(down: false, key: name, code: code, flags: flags, target: nil, inText: false)
                say("key \(arg)\(prevented ? " (heard)" : "")")
            case "window":
                // The window number, for `screencapture -l<number>`.
                say("window \(window.windowNumber)")
            case "wait":
                delay = (Double(arg) ?? 0) / 1000
            case "dump":
                let size = window.contentView?.frame.size ?? .zero
                say("--- \(Int(size.width))x\(Int(size.height))"); dump(root, 0)
            case "quit":
                NSApp.terminate(nil)  // through teardown (effects, then the engine), as a person quitting would
            default:
                fatal("script: unknown step \(step)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: next)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: next)
    }

    func say(_ line: String) { fputs(line + "\n", __stderrp) }

    func find(_ test: (Node) -> Bool) -> Node? {
        var found: Node?
        root.walk { if found == nil, test($0) { found = $0 } }
        return found
    }

    func dump(_ n: Node, _ depth: Int) {
        let pad = String(repeating: "  ", count: depth)
        let name = n.name ?? "text"
        switch n.view {
        case let s as NSStackView where n.name != nil:
            say("\(pad)\(name) [\(s.arrangedSubviews.count) views]")
            for c in n.children where c.name != nil || !c.text.isEmpty { dump(c, depth + 1) }
        case let box as ScrollBox:
            say("\(pad)\(name) [\(box.stack.arrangedSubviews.count) views, \(Int(box.frame.height))pt high]")
            for c in n.children where c.name != nil || !c.text.isEmpty { dump(c, depth + 1) }
        case let box as ListBox:
            let selected = box.table.selectedRow
            let shown = box.table.rows(in: box.table.visibleRect)
            let realized = box.rows.filter { $0.view != nil }.count
            say("\(pad)\(name) [\(box.table.numberOfRows) rows, \(realized) with views\(selected >= 0 ? ", row \(selected) selected" : ""), \(Int(box.frame.height))pt high]")
            if shown.length > 0 { say("\(pad)  rows \(shown.location)–\(shown.location + shown.length - 1) visible") }
            for c in box.rows.dropFirst(max(shown.location, 0)).prefix(3) { dump(c, depth + 1) }
            if box.rows.count > 3 { say("\(pad)  …") }
        case let popup as NSPopUpButton:
            say("\(pad)\(name) \"\(popup.titleOfSelectedItem ?? "")\" of \(popup.itemTitles)")
        case let control as NSSegmentedControl:
            let titles = (0..<control.segmentCount).map { i in control.selectedSegment == i ? "[\(control.label(forSegment: i) ?? "")]" : control.label(forSegment: i) ?? "" }
            say("\(pad)\(name) \(titles.joined(separator: " "))")
        case let b as NSButton:
            let extra = n.name == "ui-checkbox" ? " \(b.state == .on ? "[x]" : "[ ]")" : (b.isEnabled ? "" : " (disabled)")
            say("\(pad)\(name) \"\(b.title)\"\(extra)")
        case let f as NSTextField where n.name == "ui-text":
            let usual = ["text-style": "body", "font-size": "standard", "weight": "standard", "design": "proportional", "color": "label"]
            say("\(pad)\(name) \"\(f.stringValue)\"\(look(n, usual))")
        case let f as NSTextField:
            say("\(pad)\(name) \"\(f.stringValue)\"")
        case let s as NSSlider:
            say("\(pad)\(name) \(s.doubleValue)")
        case let s as NSScrollView where n.name == "ui-text-area":
            let text = (s.documentView as? NSTextView)?.string ?? ""
            say("\(pad)\(name) \"\(text.replacingOccurrences(of: "\n", with: "\\n"))\"")
        case let image as NSImageView:
            say("\(pad)\(name) \(n.attrs["symbol"] ?? "")\(image.image == nil ? " (missing)" : "")")
        case let picture as Picture:
            let (wide, high) = picture.pixels
            say("\(pad)\(name) \(picture.name) [\(wide)x\(high), \(Int(picture.frame.width))pt wide, \(Int(picture.frame.height))pt high]\(look(n, ["scaling": "fit", "label": ""]))")
        case let bar as NSProgressIndicator:
            say("\(pad)\(name) " + (bar.isIndeterminate ? (n.attrs["value"] == "1" ? "busy" : "idle") : "\(Int(bar.doubleValue))/\(Int(bar.maxValue))"))
        case is Surface:
            say("\(pad)\(name)\(look(n, ["fill": "control-background", "border": "none"]))")
            for c in n.children where c.name != nil { dump(c, depth + 1) }
        default:
            if n.name != nil { say("\(pad)\(name)") }
        }
    }

    /// The look attributes among `usual`'s keys whose value is not the usual
    /// one, as ` {name=value …}`, so a dump shows what the app styled.
    func look(_ n: Node, _ usual: [String: String]) -> String {
        let changed = usual.keys.sorted().compactMap { key in
            n.attrs[key].flatMap { $0 == usual[key] ? nil : "\(key)=\($0)" }
        }
        return changed.isEmpty ? "" : " {\(changed.joined(separator: " "))}"
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
