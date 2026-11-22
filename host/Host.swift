// The native macOS host of the platform.
//
// The reactive engine is pure Roc (copied verbatim from roc-signals). Its
// only output is the roc-signals command stream (design.md, Appendix B of
// roc-signals): this host decodes the subset the `Ui` vocabulary produces,
// keeps a small node tree mirroring what the engine built, and gives each
// `ui-*` element a live AppKit view. AppKit events go back into the engine
// as turns (`roc_engine_event`), and timers requested with `FX` come back as
// effect results.
//
// The host owns three things between calls, exactly as the roc-signals Wasm
// host does: the opaque engine state box, the last command list and the
// work record list. It never interprets the state.
//
// The ABI comes from glue/SwiftGlue.roc: `roc_swift_abi.h` declares the
// symbols and record layouts and is this file's bridging header for every file here, and
// `RocGlue.swift` builds and reads Roc lists and wraps each provided procedure.

import AppKit
// MARK: - Applying commands to AppKit

final class Host: NSObject, NSTextFieldDelegate {
    let engine = EngineInstance()
    let window: NSWindow
    let root = Node(.element("ui-vstack"))
    var nodes: [UInt32: Node] = [:]
    var refs: [UInt32: Node] = [:]
    var templates: [UInt32: Template] = [:]
    var timers: [UInt32: Timer] = [:]
    /// HTTP requests in flight, main-thread state (host/Http.swift).
    var flights: [UInt32: HttpFlight] = [:]
    lazy var http: HttpTransport = makeHttpTransport()
    /// File reads, digests and saves in flight (Files.swift).
    let files = Files()
    var byView: [ObjectIdentifier: Node] = [:]
    /// Nodes whose view needs its children or text refreshed after a batch.
    var dirty: [Node] = []
    var applying = false
    var queued: [(UInt32, UInt32, [UInt8])] = []
    /// Live document key declarations, in the order they were mounted.
    var documentKeys: [Node] = []
    /// Layout constraints the host made for a view, by view and purpose.
    var constraints: [ObjectIdentifier: [String: NSLayoutConstraint]] = [:]
    /// Whether the last sync found a scroll area or list (the window then
    /// stops growing to fit its content).
    var flexible = false
    var keyMonitor: Any?

    init(window: NSWindow) {
        self.window = window
        super.init()
        root.id = 0
        nodes[0] = root
        let stack = NSStackView()
        stack.orientation = .vertical
        root.view = stack
        // The app's root element fills the window.
        for (name, value) in [("spacing", "12"), ("padding", "20 20 20 20"), ("align", "fill")] { setAttr(root, name, value) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
        window.contentView = content
    }

    func start() {
        let v = engine.version
        if v != 23 { fatal("engine speaks protocol \(v), this host speaks 23") }
        timed { engine.mount() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.key(event) ? nil : event
        }
    }

    // MARK: Turns

    func send(_ node: UInt32, _ handler: UInt32, _ payload: [UInt8]) {
        if halted || engine.dropped { return }
        if applying { queued.append((node, handler, payload)); return }
        timed { engine.event(node: node, handler: handler, payload: payload) }
        while !queued.isEmpty {
            let (n, h, p) = queued.removeFirst()
            timed { engine.event(node: n, handler: h, payload: p) }
        }
    }

    /// Dispatch an AppKit event of `type` at `target`: the nearest element at
    /// or above it that listens for `type` handles it, routed through the
    /// nearest node at or above that element with an engine id.
    func dispatch(_ type: String, at target: Node, text: String = "", flag: Bool = false) {
        var cursor: Node? = target
        while let node = cursor {
            if let listener = node.listeners[type] {
                var route: Node? = node
                while let r = route, r.id == nil { route = r.parent }
                guard let id = route?.id else { return }
                let payload: [UInt8]
                switch listener.kind {
                case 10: payload = [0, 0]  // Click: no modifiers, not a link
                case 5: payload = [flag ? 1 : 0]  // OpenState
                default: payload = Array(text.utf8)  // Text
                }
                send(id, listener.handler, payload)
                return
            }
            cursor = node.parent
        }
    }

    /// Run one engine call and apply its batch; `ROC_TRACE=1` reports how
    /// long each half took.
    func timed(_ call: () -> [UInt8]) {
        let start = Date()
        let batch = call()
        let engineDone = Date()
        apply(batch)
        trace("turn: engine \(Int(engineDone.timeIntervalSince(start) * 1000)) ms, host \(Int(Date().timeIntervalSince(engineDone) * 1000)) ms, \(batch.count) bytes")
    }

    // MARK: The batch

    func apply(_ batch: [UInt8]) {
        // File handles Roc released during the call are dropped once the
        // batch, whose commands may still name them, has been applied.
        defer { releaseFiles() }
        guard !batch.isEmpty else { return }
        applying = true
        var r = Reader(batch)
        let flags = r.u8()
        if flags > 1 { fatal("unknown batch flags \(flags)") }
        var acknowledge = false
        var opportunities: [UInt64] = []
        while !r.done {
            let op = r.u8()
            switch op {
            case 1: // INST node parent before tpl holes...
                let id = r.u32(), parent = r.u32(), before = r.u32(), tpl = r.u32()
                guard let template = templates[tpl] else { fatal("INST of unknown template \(tpl)") }
                let row = template.root.clone()
                row.id = id
                nodes[id] = row
                for hole in template.holes {
                    var target = row
                    for index in hole.path { target = target.children[index] }
                    row.holes.append((target, hole.attr))
                    switch hole.kind {
                    case 1: target.text = r.str()
                    case 2: setAttr(target, hole.attr!, r.presence())
                    case 3: break
                    case 4: let pid = r.u32(); target.id = pid; nodes[pid] = target
                    case 5: refs[r.u32()] = target
                    case 6: setAttr(target, hole.attr!, r.str())
                    default: fatal("unknown hole kind \(hole.kind)")
                    }
                }
                // A list's row gets its views when the table first shows it.
                let into = before == 0 ? node(parent) : (node(before).parent ?? node(parent))
                if !(into.view is ListBox) {
                    row.walk { n in
                        self.makeView(n)
                        n.attrs.forEach { self.applyAttr(n, $0.key, $0.value) }
                        self.dirty.append(n)
                    }
                }
                insert(row, parent: parent, before: before)
            case 2: // TEXT node hole str
                let row = node(r.u32()), hole = Int(r.u8())
                let target = row.holes[hole].node
                target.text = r.str()
                markText(target)
            case 3: // HATTR node hole presence [value]
                let row = node(r.u32()), hole = row.holes[Int(r.u8())]
                setAttr(hole.node, hole.attr!, r.presence())
            case 4: // MOVE node before
                let n = node(r.u32()), before = r.u32()
                guard let parent = n.parent else { break }
                n.detach()
                parent.insert(n, before: before == 0 ? nil : node(before))
                (parent.view as? ListBox)?.moved(n, in: parent)
                markChildren(parent)
            case 5: // REMOVE node
                remove(node(r.u32()))
            case 6: // CLEAR parent site
                let parent = node(r.u32()); _ = r.u32()
                for child in parent.children { forget(child) }
                parent.removeAllChildren()
                (parent.view as? ListBox)?.cleared()
                markChildren(parent)
            case 7: // TEMPLATE tpl len bytes
                let tpl = r.u32()
                templates[tpl] = decodeTemplate(r.raw(Int(r.u32())))
            case 8: // ELEM node parent before name container
                let id = r.u32(), parent = r.u32(), before = r.u32(), name = r.expandedName()
                _ = r.u8()
                let n = Node(.element(name))
                n.id = id
                nodes[id] = n
                makeView(n)
                insert(n, parent: parent, before: before)
            case 9: // ATTR node name presence [value]
                let n = node(r.u32()), name = r.expandedName()
                setAttr(n, name, r.presence())
            case 10: // TEXTNODE node parent before text
                let id = r.u32(), parent = r.u32(), before = r.u32()
                let n = Node(.text)
                n.id = id
                n.text = r.str()
                nodes[id] = n
                insert(n, parent: parent, before: before)
            case 11: // LISTEN node handler type kind policies
                let n = node(r.u32()), handler = r.u32(), type = r.str(), kind = r.u8()
                let policies = r.u32()
                if kind == 4, policies & 16 != 0, !documentKeys.contains(where: { $0 === n }) { documentKeys.append(n) }
                n.listeners[type] = (handler, kind, policies)
            case 12: // SETTEXT node text
                let n = node(r.u32()), t = r.str()
                if case .element = n.kind {
                    for child in n.children { forget(child) }
                    n.removeAllChildren()
                    let t2 = Node(.text); t2.text = t; n.append(t2)
                } else {
                    n.text = t
                }
                markText(n)
            case 13: // FX id kind ...
                let id = r.u32(), kind = r.u8()
                trace("FX id \(id) kind \(kind)")
                effect(id: id, kind: kind, &r)
            case 14: // CANCEL id
                let id = r.u32()
                trace("CANCEL id \(id)")
                cancelEffect(id: id)
            case 15: // NAV mode url
                _ = r.u8(); _ = r.str()
            case 16: // STORAGE op key [value]
                let op = r.u8(), key = r.str()
                storage(op, key, &r)
            case 17: // TITLE text
                window.title = r.str()
            case 18: // REF op node ...
                let op = r.u8(), target = refs[r.u32()]
                switch op {
                case 6: _ = r.raw(3)
                case 7: for _ in 0..<2 { if r.u8() == 3 { _ = r.u32() } }; _ = r.u8()
                default: break
                }
                if [1, 3, 5].contains(op), let view = target?.view { window.makeFirstResponder(view) }
            case 20: // SAVE token start len name
                let token = r.u64(), start = r.u64(), len = r.u64(), name = r.str()
                save(token: token, start: start, len: len, name: name)
            case 21: // PROP node prop value
                let n = node(r.u32()), prop = r.u8(), value = r.str()
                setAttr(n, Host.propertyName(prop), value)
            case 22: // HPROP node hole value
                let row = node(r.u32()), hole = row.holes[Int(r.u8())]
                setAttr(hole.node, hole.attr ?? "value", r.str())
            case 23: // RELEASE node
                _ = r.u32()
            case 24: // TRANSITION n types
                for _ in 0..<r.u32() { _ = r.str() }
            case 25: // GUARD on
                _ = r.u8()
            case 26: // COMMENT node parent before data
                let id = r.u32(), parent = r.u32(), before = r.u32()
                _ = r.str()
                let n = Node(.comment)
                n.id = id
                nodes[id] = n
                insert(n, parent: parent, before: before)
            case 28: // STARTUP mode entry
                _ = r.u8(); _ = r.u32()
            case 29: // STARTUP_ACK
                acknowledge = true
            case 30: // STARTUP_COMPLETE
                break
            case 31: // OPPORTUNITY action generation
                let action = r.u8(), generation = r.u64()
                if action == 1 { opportunities.append(generation) }
            default:
                fatal("command \(op) is not supported by this host")
            }
        }
        applying = false
        sync()
        if acknowledge { queued.insert((EngineInstance.effectNode, 0, [254]), at: 0) }
        for generation in opportunities {
            DispatchQueue.main.async {
                var payload: [UInt8] = [255]
                for i in 0..<8 { payload.append(UInt8(truncatingIfNeeded: generation >> (8 * UInt64(i)))) }
                self.send(EngineInstance.effectNode, 0, payload)
            }
        }
    }

    /// `ROC_TRACE=1` reports effect requests and cancellations on stderr.
    func trace(_ line: @autoclosure () -> String) {
        if ProcessInfo.processInfo.environment["ROC_TRACE"] != nil { fputs(line() + "\n", __stderrp) }
    }

    /// The attribute an element property row (`PROP`, `HPROP`) stands for.
    static func propertyName(_ prop: UInt8) -> String {
        switch prop {
        case 2: return "checked"
        case 4: return "keymap-down"
        case 5: return "keymap-up"
        default: return "value"
        }
    }

    func node(_ id: UInt32) -> Node {
        guard let n = nodes[id] else { fatal("command names unknown node \(id)") }
        return n
    }

    func insert(_ n: Node, parent: UInt32, before: UInt32) {
        let p: Node
        let b: Node? = before == 0 ? nil : node(before)
        if let b, let bp = b.parent { p = bp } else { p = node(parent) }
        p.insert(n, before: b)
        (p.view as? ListBox)?.inserted(n, in: p)
        markChildren(p)
    }

    func remove(_ n: Node) {
        let parent = n.parent
        (parent?.view as? ListBox)?.removed(n)
        n.detach()
        forget(n)
        if let parent { markChildren(parent) }
    }

    /// Drop a removed subtree's ids and views from the host's indexes.
    func forget(_ n: Node) {
        n.walk { d in
            if let id = d.id, nodes[id] === d { nodes.removeValue(forKey: id) }
            if let v = d.view {
                byView.removeValue(forKey: ObjectIdentifier(v))
                if let inner = (v as? NSScrollView)?.documentView { byView.removeValue(forKey: ObjectIdentifier(inner)) }
                constraints.removeValue(forKey: ObjectIdentifier(v))
                v.removeFromSuperview()
            }
            if !documentKeys.isEmpty { documentKeys.removeAll { $0 === d } }
        }
        refs = refs.filter { entry in
            var inside = false
            n.walk { if $0 === entry.value { inside = true } }
            return !inside
        }
    }
}
