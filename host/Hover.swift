// Hover: `Ui.hover`'s enter and leave, from one window-level tracking area.
//
// No view gets a tracking area of its own. The window's content view owns
// one (`.mouseMoved`, `.activeAlways`, `.inVisibleRect`); each mouse move
// AppKit delivers is hit-tested once, from the deepest view under the pointer
// up to the nearest node, and up the node tree to collect the elements that
// listen for `hover`. Leave and enter go only to the elements that left or
// joined that chain, as a browser's `mouseleave`/`mouseenter` do, so a move
// costs the depth of the tree, not its size, and a move within one element
// costs no turn at all. The turns of one move share one layout pass.
//
// `ui-hover` has no view of its own: its one child's view stands in its
// place in the parent's layout (`shownView`), so wrapping an element adds a
// node to the tree but no view.

import AppKit

/// The window's content view: the one tracking area every hover comes from.
final class ContentView: NSView {
    weak var host: Host?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatal("ContentView is not archived") }

    // A scripted run is driven by its steps alone (`move`, `hover`, `leave`),
    // never by wherever the person's pointer happens to be.
    private var live: Bool { !Host.scripted }

    override func mouseMoved(with event: NSEvent) { if live { host?.pointer(at: event.locationInWindow, time: event.timestamp) } }
    override func mouseEntered(with event: NSEvent) { if live { host?.pointer(at: event.locationInWindow, time: event.timestamp) } }
    override func mouseExited(with event: NSEvent) { if live { host?.pointerLeft() } }
}

extension Host {
    static let scripted = ProcessInfo.processInfo.environment["ROC_SCRIPT"] != nil

    /// The pointer is at `point`, in window coordinates, moved by an event
    /// at `time` (`systemUptime`; a scripted move is now).
    func pointer(at point: NSPoint, time: Double = Bench.now()) {
        bench?.moved(time)
        guard let content = window.contentView, let frame = content.superview else { return }
        let hit = content.hitTest(frame.convert(point, from: nil))
        hover(chain(under: hit), time: time)
    }

    /// The pointer has left the window.
    func pointerLeft() { hover([], time: Bench.now()) }

    /// The elements listening for `hover` at or above the node whose view is
    /// at or above `view`, outermost first.
    func chain(under view: NSView?) -> [Node] {
        var cursor = view
        var node: Node?
        while let v = cursor, node == nil {
            node = byView[ObjectIdentifier(v)]
            cursor = v.superview
        }
        var chain: [Node] = []
        while let n = node {
            if n.listeners["hover"] != nil { chain.append(n) }
            node = n.parent
        }
        return chain.reversed()
    }

    /// Move the hover to `next`: leave what it no longer holds, innermost
    /// first, then enter what it newly holds, outermost first.
    func hover(_ next: [Node], time: Double) {
        var kept = 0
        while kept < hovered.count, kept < next.count, hovered[kept] === next[kept] { kept += 1 }
        if kept == hovered.count, kept == next.count { return }
        var events: [(UInt32, UInt32, [UInt8])] = []
        func event(_ n: Node, _ word: String) {
            guard let listener = n.listeners["hover"], let id = route(n) else { return }
            events.append((id, listener.handler, Array(word.utf8)))
        }
        var i = hovered.count
        while i > kept { i -= 1; event(hovered[i], "leave") }
        for j in kept..<next.count { event(next[j], "enter") }
        hovered = next
        if !events.isEmpty { bench?.eventTime = time }
        send(events, as: .hover)
    }

    /// The node whose view shows `n` in its parent: `n`, or for a viewless
    /// `ui-hover`, its element child's (`nil` without one).
    func shownNode(_ n: Node) -> Node? {
        guard n.name == "ui-hover" else { return n }
        return n.children.first { $0.name != nil }.flatMap(shownNode)
    }

    func shownView(_ n: Node) -> NSView? { shownNode(n)?.view }
}
