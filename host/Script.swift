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
            case "wait":
                delay = (Double(arg) ?? 0) / 1000
            case "dump":
                say("---"); dump(root, 0)
            case "quit":
                exit(0)
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
        switch n.view {
        case let s as NSStackView where n.name != nil:
            say("\(pad)\(n.name!) [\(s.arrangedSubviews.count) views]")
            for c in n.children where c.name != nil || !c.text.isEmpty { dump(c, depth + 1) }
        case let b as NSButton:
            let extra = n.name == "ui-checkbox" ? " \(b.state == .on ? "[x]" : "[ ]")" : (b.isEnabled ? "" : " (disabled)")
            say("\(pad)\(n.name!) \"\(b.title)\"\(extra)")
        case let f as NSTextField:
            say("\(pad)\(n.name ?? "text") \"\(f.stringValue)\"")
        case let s as NSSlider:
            say("\(pad)\(n.name!) \(s.doubleValue)")
        case let z as DropZoneView:
            say("\(pad)\(n.name!) \"\(z.label.stringValue)\"")
        default:
            if n.name != nil { say("\(pad)\(n.name!)") }
        }
    }
}
