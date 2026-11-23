// Spec mode (`ROC_SPEC`): the steps of a `.scm` spec, which the `macos.roc`
// tool parses and lowers (cli/Spec.roc), performed on the real controls.

import AppKit

/// Whether this run is driven by steps rather than a person: `ROC_SPEC`
/// or the legacy `ROC_SCRIPT`. A driven run never shows an alert, takes
/// focus or reads the person's saved storage.
let specText = ProcessInfo.processInfo.environment["ROC_SPEC"]
let driven = specText != nil || ProcessInfo.processInfo.environment["ROC_SCRIPT"] != nil

/// A spec's lowered steps and how far the run has got. The tool writes
/// them (`Spec.lower`): a `roc-spec 1` line, then `k<TAB>verb<TAB>field…`
/// per step, `k` from 1 (0 for setup), each field escaping `\`, tab and
/// line break. The host performs each step and, for an expectation,
/// prints its observation on standard output as `@k obs` and one `|line`
/// per fact; a step it cannot take prints `@k fail MESSAGE` and ends the
/// run. `@done` says every step ran. The tool compares; the host never
/// judges an expectation.
final class SpecSteps {
    struct Line { let k: Int; let verb: String; let fields: [String] }
    var lines: [Line] = []
    var next = 0

    init(_ text: String) {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard rows.first == "roc-spec 1" else { fatal("ROC_SPEC does not hold roc-spec 1 steps; the macos.roc tool writes them") }
        for row in rows.dropFirst() {
            let parts = row.split(separator: "\t", omittingEmptySubsequences: false).map { SpecSteps.unescape(String($0)) }
            guard parts.count >= 2, let k = Int(parts[0]) else { fatal("ROC_SPEC: malformed step line \(row)") }
            lines.append(Line(k: k, verb: parts[1], fields: Array(parts.dropFirst(2))))
        }
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var escaping = false
        for c in s {
            if escaping {
                out.append(c == "n" ? "\n" : c == "t" ? "\t" : c)
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\t", with: "\\t").replacingOccurrences(of: "\n", with: "\\n")
    }
}

/// One part of a locator: a kind (`button`, `list-row#`) and its text.
struct LocPart {
    let kind: String
    let text: String
}

/// What a locator found: the nodes, and when there is not exactly one, the
/// texts of the things of its kind, for the tool to name the nearest.
struct Located {
    var nodes: [Node]
    var candidates: [String]
    var want: String
}

extension Host {
    /// Print a line of spec output on standard output (flushed when the
    /// app exits, which every run does through `exit`).
    func emit(_ line: String) { print(line) }

    /// Setup lines (`k` 0), before mount's first step.
    func setUp(_ steps: SpecSteps) {
        for line in steps.lines where line.k == 0 {
            switch line.verb {
            case "pool":
                guard let n = Int(line.fields.first ?? ""), n >= 1 else { fatal("ROC_SPEC: pool needs a count") }
                work.limit = n
            default:
                fatal("ROC_SPEC: unknown setup \(line.verb)")
            }
        }
    }

    func run(spec steps: SpecSteps) {
        func next() {
            while steps.next < steps.lines.count, steps.lines[steps.next].k == 0 { steps.next += 1 }
            guard steps.next < steps.lines.count else {
                emit("@done")
                NSApp.terminate(nil)
                return
            }
            let line = steps.lines[steps.next]
            steps.next += 1
            var delay = 0.1
            switch perform(line) {
            case .next: break
            case .wait(let ms): delay = ms / 1000
            case .handedOver: return
            case .failed(let message, let located):
                emit("@\(line.k) fail \(message)")
                if let located {
                    emit("|want \(SpecSteps.escape(located.want))")
                    for c in located.candidates { emit("|candidate \(SpecSteps.escape(c))") }
                }
                NSApp.terminate(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: next)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: next)
    }

    enum Performed {
        case next
        case wait(Double)
        case handedOver
        case failed(String, Located?)
    }

    /// One step; its observation, if it makes one, is printed here.
    func perform(_ line: SpecSteps.Line) -> Performed {
        let f = line.fields
        func one(_ what: String) -> (Node?, Performed) {
            let (parts, _) = Host.locator(f)
            let found = locate(parts)
            if found.nodes.count == 1 { return (found.nodes[0], .next) }
            return (nil, .failed("found \(found.nodes.isEmpty ? "no" : "\(found.nodes.count) of") \(Host.describe(parts)), looking for a \(what); a step acts on exactly one", found))
        }
        switch line.verb {
        case "click":
            let (n, miss) = one("button")
            guard let n else { return miss }
            guard let b = n.view as? NSButton, n.name == "ui-button" || n.name == "ui-checkbox" else { return .failed("\(Host.describe(Host.locator(f).0)) is not a button", nil) }
            if !b.isEnabled { return .failed("\(Host.describe(Host.locator(f).0)) is disabled", nil) }
            if n.name == "ui-checkbox" { b.state = b.state == .on ? .off : .on; toggled(b) } else { pressed(b) }
        case "fill":
            let (n, miss) = one("text field or area")
            guard let n else { return miss }
            let (_, rest) = Host.locator(f)
            let value = rest.first ?? ""
            if let field = n.view as? NSTextField, n.name == "ui-text-field" {
                field.stringValue = value
                dispatch("input", at: n, text: value)
            } else if let text = (n.view as? NSScrollView)?.documentView as? NSTextView, n.name == "ui-text-area" {
                text.string = value
                dispatch("input", at: n, text: value)
            } else {
                return .failed("\(Host.describe(Host.locator(f).0)) is not a text field or text area", nil)
            }
        case "submit":
            let (n, miss) = one("text field")
            guard let n else { return miss }
            submit(from: n)
        case "toggle":
            let (n, miss) = one("checkbox")
            guard let n else { return miss }
            guard let b = n.view as? NSButton, n.name == "ui-checkbox" else { return .failed("\(Host.describe(Host.locator(f).0)) is not a checkbox", nil) }
            b.state = b.state == .on ? .off : .on
            toggled(b)
        case "select":
            let (parts, _) = Host.locator(f)
            if let last = parts.last, last.kind == "list-row#" {
                let scope = locate(Host.allButLast(parts))
                guard parts.count == 1 || scope.nodes.count == 1 else { return .failed("found \(scope.nodes.count) of \(Host.describe(Host.allButLast(parts))); a step acts on exactly one", scope) }
                let boxes = lists(in: parts.count == 1 ? root : scope.nodes[0])
                guard boxes.count == 1, let box = boxes.first else { return .failed("found \(boxes.count) lists; (list-row K) needs exactly one", nil) }
                guard let k = Int(last.text), k >= 1, k <= box.table.numberOfRows else { return .failed("the list has \(box.table.numberOfRows) rows, so no row \(last.text)", nil) }
                box.select(row: k - 1)
            } else {
                let (n, miss) = one("list row")
                guard let n else { return miss }
                guard let box = n.parent?.view as? ListBox else { return .failed("\(Host.describe(parts)) is not a list row", nil) }
                box.select(n)
            }
        case "hover":
            let (n, miss) = one("hover target")
            guard let n else { return miss }
            var cursor: Node? = n
            while let c = cursor, c.listeners["hover"] == nil { cursor = c.parent }
            guard let target = cursor, let view = shownView(target) else { return .failed("\(Host.describe(Host.locator(f).0)) is not inside anything that listens for hover", nil) }
            let b = view.bounds
            pointer(at: view.convert(NSPoint(x: b.origin.x + b.size.width / 2, y: b.origin.y + b.size.height / 2), to: nil))
        case "choose":
            let arg = f.first ?? ""
            var controls: [Node] = []
            var choices: [String] = []
            root.walk { n in
                guard n.name == "ui-dropdown" || n.name == "ui-segmented" else { return }
                let these = Host.choices(n.attrs["choices"])
                choices += these
                if these.contains(arg) { controls.append(n) }
            }
            guard controls.count == 1, let n = controls.first else {
                return .failed("found \(controls.isEmpty ? "no" : "\(controls.count)") dropdowns or segmented controls offering \(arg); a step acts on exactly one", Located(nodes: controls, candidates: choices, want: arg))
            }
            if let popup = n.view as? NSPopUpButton {
                popup.selectItem(withTitle: arg)
                chose(popup)
            } else if let control = n.view as? NSSegmentedControl {
                control.selectedSegment = Host.choices(n.attrs["choices"]).firstIndex(of: arg) ?? -1
                segmentChanged(control)
            }
        case "press":
            guard let heard = press(f.first ?? "") else { return .failed("\(f.first ?? "") has an unknown modifier; they are cmd, ctrl, alt (opt) and shift", nil) }
            if f.count > 1, f[1] == "observe" {
                emit("@\(line.k) obs")
                emit("|heard \(heard)")
            }
        case "files", "drop":
            // `files` picks on the one file button (or, with none, the one
            // drop zone); `drop` drops on the one drop zone.
            var buttons: [Node] = [], zones: [Node] = []
            root.walk { n in
                if n.name == "ui-file-button" { buttons.append(n) }
                if n.name == "ui-drop-zone" { zones.append(n) }
            }
            let controls = line.verb == "files" && !buttons.isEmpty ? buttons : zones
            guard controls.count == 1, let n = controls.first else { return .failed("found \(controls.count) \(line.verb == "files" && !buttons.isEmpty ? "file buttons" : "drop zones"); \(line.verb) needs exactly one", nil) }
            deliverFiles(f, type: n.name == "ui-drop-zone" ? "drop" : "change", at: n)
        case "move":
            guard f.count == 2, let x = Double(f[0]), let y = Double(f[1]) else { return .failed("move needs x and y", nil) }
            pointer(at: windowPoint(NSPoint(x: x, y: y)))
        case "leave":
            pointerLeft()
        case "sweep":
            let v = f.compactMap { Double($0) }
            guard v.count == 6, v[4] >= 1 else { return .failed("sweep needs x0 y0 x1 y1 moves ms", nil) }
            guard let steps = specSteps else { return .failed("sweep outside a spec", nil) }
            sweep(v) { self.run(spec: steps) }
            return .handedOver
        case "scroll":
            guard let box = firstList(), let k = Int(f.first ?? ""), k >= 0, k < max(box.table.numberOfRows, 1) else { return .failed("no list row \(f.first ?? "") to scroll to", nil) }
            bench?.begin(.scroll)
            bench?.engine(0)
            box.scroll(toRow: k)
            window.contentView?.layoutSubtreeIfNeeded()
            bench?.end(self)
        case "phase":
            guard let bench else { return .failed("phase needs ROC_BENCH=1", nil) }
            bench.phase = f.first ?? ""
        case "stats":
            guard let bench else { return .failed("stats needs ROC_BENCH=1", nil) }
            bench.report(self)
        case "window":
            say("window \(window.windowNumber)")
        case "wait":
            return .wait(Double(f.first ?? "") ?? 0)
        case "reload":
            guard let fresh = (NSApp.delegate as? AppDelegate)?.reload(), let steps = specSteps else { return .failed("reload found no engine to reload", nil) }
            fresh.specSteps = steps
            fresh.run(spec: steps)
            return .handedOver
        case "dump":
            let size = window.contentView?.frame.size ?? .zero
            emit("@\(line.k) obs")
            emit("|--- \(Int(size.width))x\(Int(size.height))")
            dump(root, 0) { print("|" + $0.replacingOccurrences(of: "\n", with: "\n|")) }
        case "find":
            let (parts, _) = Host.locator(f)
            let found = locate(parts)
            emit("@\(line.k) obs")
            emit("|count \(found.nodes.count)")
            if found.nodes.count == 1 {
                let n = found.nodes[0]
                emit("|text \(SpecSteps.escape(shown(n)))")
                if n.name == "ui-checkbox", let b = n.view as? NSButton { emit("|checked \(b.state == .on)") }
                if Host.controls.contains(n.name ?? ""), let c = n.view as? NSControl { emit("|disabled \(!c.isEnabled)") }
            } else {
                for c in found.candidates { emit("|candidate \(SpecSteps.escape(c))") }
            }
        case "workers":
            let running = work.slots.filter { $0.job != nil }.count
            emit("@\(line.k) obs")
            for (name, count) in [("limit", work.limit), ("live", work.slots.count), ("running", running), ("queued", work.queue.count), ("started", work.spawned), ("answered", work.answered), ("lost", work.lost), ("stopped", work.stopped), ("timed-out", work.timedOut), ("dropped", work.dropped)] {
                emit("|\(name) \(count)")
            }
        default:
            fatal("ROC_SPEC: unknown step \(line.verb); this host and the macos.roc tool are from different releases")
        }
        return .next
    }

    /// The elements that can be disabled.
    static let controls: [String] = ["ui-button", "ui-checkbox", "ui-text-field", "ui-dropdown", "ui-segmented", "ui-slider", "ui-file-button"]

    /// A locator's parts from a step's fields (`n kind text …`), and the
    /// fields after it.
    static func locator(_ f: [String]) -> ([LocPart], [String]) {
        guard let n = Int(f.first ?? ""), f.count >= 1 + 2 * n else { return ([], f) }
        var parts: [LocPart] = []
        for i in 0..<n { parts.append(LocPart(kind: f[1 + 2 * i], text: f[2 + 2 * i])) }
        var rest: [String] = []
        for i in (1 + 2 * n)..<f.count { rest.append(f[i]) }
        return (parts, rest)
    }

    static func allButLast(_ parts: [LocPart]) -> [LocPart] {
        var out: [LocPart] = []
        for i in 0..<max(parts.count - 1, 0) { out.append(parts[i]) }
        return out
    }

    /// A locator as a spec writes it, for a message.
    static func describe(_ parts: [LocPart]) -> String {
        let shown = parts.map { p in
            p.kind.hasSuffix("#") ? "(\(p.kind.dropLast()) \(p.text))" : p.text.isEmpty ? "(\(p.kind))" : "(\(p.kind) \"\(p.text)\")"
        }
        guard var inner = shown.last else { return "nothing" }
        var i = shown.count - 1
        while i > 0 { i -= 1; inner = "(within \(shown[i]) \(inner))" }
        return inner
    }

    /// Everything a locator matches, each part looked for inside the one
    /// thing the part before it found.
    func locate(_ parts: [LocPart]) -> Located {
        var scope = root
        var result = Located(nodes: [root], candidates: [], want: "")
        for (i, part) in parts.enumerated() {
            result = locate(part.kind, part.text, in: scope)
            if i < parts.count - 1 {
                guard result.nodes.count == 1 else { return result }
                scope = result.nodes[0]
            }
        }
        return result
    }

    func locate(_ kind: String, _ text: String, in scope: Node) -> Located {
        var nodes: [Node] = []
        var candidates: [String] = []
        func note(_ s: String) { if !s.isEmpty, candidates.count < 200, !candidates.contains(s) { candidates.append(s) } }
        switch kind {
        case "button", "checkbox":
            let name = "ui-\(kind)"
            scope.walk { n in
                guard n.name == name else { return }
                let title = kind == "button" ? n.textContent : n.attrs["title"] ?? ""
                if title == text { nodes.append(n) } else { note(title) }
            }
        case "text":
            scope.walk { n in
                guard n.name != nil, n.lazy == nil else { return }
                let t = n.name == "ui-text-field" ? (n.view as? NSTextField)?.stringValue ?? "" : n.textContent
                let leaf = !n.children.contains { $0.name != nil && $0.textContent == t }
                guard leaf else { return }
                if t == text { nodes.append(n) } else if !n.children.contains(where: { $0.name != nil }) { note(t) }
            }
        case "text-field", "text-area":
            let name = "ui-\(kind)"
            scope.walk { n in
                guard n.name == name else { return }
                let placeholder = n.attrs["placeholder"] ?? ""
                if text.isEmpty || placeholder == text { nodes.append(n) } else { note(placeholder) }
            }
        case "list-row":
            for box in lists(in: scope) { box.rows.forEach(materialize) }
            scope.walk { n in
                guard n.parent?.view is ListBox, n.name != nil else { return }
                if n.contains({ $0.name != nil && $0.textContent == text }) { nodes.append(n) } else { n.walk { if $0.name != nil, !$0.children.contains(where: { $0.name != nil }) { note($0.textContent) } } }
            }
        case "list-row#":
            let boxes = lists(in: scope)
            if boxes.count == 1, let k = Int(text), let row = boxes[0].node(at: k - 1) {
                materialize(row)
                nodes.append(row)
            }
        case "hover-target#":
            var targets: [Node] = []
            scope.walk { if $0.listeners["hover"] != nil { targets.append($0) } }
            if let k = Int(text), targets.indices.contains(k - 1) { nodes.append(targets[k - 1]) }
        default:
            fatal("ROC_SPEC: unknown locator \(kind)")
        }
        return Located(nodes: nodes, candidates: nodes.count == 1 ? [] : candidates, want: text)
    }

    /// The lists at or under `scope`.
    func lists(in scope: Node) -> [ListBox] {
        var found: [ListBox] = []
        func search(_ n: Node) {
            if let box = n.view as? ListBox { found.append(box); return }
            for child in n.children { search(child) }
        }
        search(scope)
        return found
    }

    /// The text a node shows: a control's title or value, a text's string.
    func shown(_ n: Node) -> String {
        switch n.view {
        case let popup as NSPopUpButton: return popup.titleOfSelectedItem ?? ""
        case let control as NSSegmentedControl: return control.selectedSegment >= 0 ? control.label(forSegment: control.selectedSegment) ?? "" : ""
        case let b as NSButton: return b.title
        case let f as NSTextField: return f.stringValue
        case let s as NSScrollView where n.name == "ui-text-area": return (s.documentView as? NSTextView)?.string ?? ""
        case let bar as NSProgressIndicator: return bar.isIndeterminate ? (n.attrs["value"] == "1" ? "busy" : "idle") : "\(Int(bar.doubleValue))/\(Int(bar.maxValue))"
        default: return n.textContent
        }
    }
}
