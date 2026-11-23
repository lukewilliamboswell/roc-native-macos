// Stacks of fixed-size children, placed by frame instead of by Auto Layout.
//
// An NSStackView arranges its children with constraints: each child's width
// and height, and the stack's alignment and spacing between neighbours, all
// solved by the window's one Auto Layout engine. That is what made a grid of
// 10,000 fixed-size boxes take seconds and gigabytes to open
// (bench/grid/README.adoc). When every child of a stack has a size known
// without solving anything, the stack places them itself: the children keep
// their frames (`translatesAutoresizingMaskIntoConstraints`), carry no
// constraints of the host's, and the stack reports the total as its
// intrinsic content size, so its own place in the layout is solved as before.
//
// The stack is "framed" (`Host.framePlan`) when:
//
// * its `distribution` is `gravity`, its `align` is not `fill` (nor
//   `first-baseline` across a horizontal stack), its own `width` and
//   `height` are `auto`, and the window lays out left to right;
// * it has at least one child, and every child is an element (no bare text)
//   whose shown view is visible, is not a scroll area, list or spacer, and
//   either has a `fixed` width and a `fixed` height or is itself a framed
//   stack (so a grid of rows of fixed cells is framed throughout, and only
//   the outermost stack takes part in Auto Layout).
//
// Anything else is arranged by NSStackView as before. A framed stack
// reproduces what NSStackView does with the same children (measured, and
// checked by the recorded cases): children from the leading or top edge,
// `spacing` apart, inside the `padding` along the stack; across it, a
// leading (vertical) or top (horizontal) alignment keeps that edge's
// padding and the others keep none; slack along the stack is left after
// the last child, as a `gravity` stack's leading gravity area does; its
// hugging is NSStackView's own (just under 250) and it cannot be squeezed
// below its children.

import AppKit

/// `ui-hstack`, `ui-vstack`, `ui-form`, `ui-row`: an NSStackView, or, while
/// framed, a container that places its fixed-size children itself.
final class Stack: NSStackView {
    /// The children placed by frame, in order, and their sizes; nil while
    /// NSStackView arranges the children.
    private(set) var placed: [NSView]?
    private var widths: [Double] = []
    private var heights: [Double] = []
    /// Where each placed child starts along the stack, from its top or
    /// leading edge, for hit testing by search.
    private var starts: [Double] = []
    /// The framed stack's size: its children, spacing and padding.
    private(set) var framedWidth = 0.0
    private(set) var framedHeight = 0.0
    /// The content priorities the stack had before it was framed.
    /// (Raw values: a stored priority would make Swift bridge and hash
    /// Floats, symbols the catalog does not own.)
    private var savedHugWidth: Float = 250, savedHugHeight: Float = 250
    private var savedResistWidth: Float = 750, savedResistHeight: Float = 750

    var framed: Bool { placed != nil }

    /// How many children the stack shows (`dump`).
    var shownCount: Int { placed?.count ?? arrangedSubviews.count }

    /// Place `views`, of the given sizes, by frame. Returns whether the
    /// stack's own size changed (or it was not framed before).
    func frame(_ views: [NSView], widths: [Double], heights: [Double]) -> Bool {
        let wasFramed = framed
        if !wasFramed {
            // NSStackView's own hugging and clipping resistance (it has no
            // content size of its own, and so ignores its content
            // priorities; a framed stack has one). Kept to restore.
            savedHugWidth = contentHuggingPriority(for: .horizontal).rawValue
            savedHugHeight = contentHuggingPriority(for: .vertical).rawValue
            savedResistWidth = contentCompressionResistancePriority(for: .horizontal).rawValue
            savedResistHeight = contentCompressionResistancePriority(for: .vertical).rawValue
            setContentHuggingPriority(huggingPriority(for: .horizontal), for: .horizontal)
            setContentHuggingPriority(huggingPriority(for: .vertical), for: .vertical)
            setContentCompressionResistancePriority(clippingResistancePriority(for: .horizontal), for: .horizontal)
            setContentCompressionResistancePriority(clippingResistancePriority(for: .vertical), for: .vertical)
        }
        let vertical = orientation == .vertical
        let insets = edgeInsets
        var along = Double(vertical ? insets.top : insets.left)
        var across = 0.0
        starts = []
        for i in views.indices {
            if i > 0 { along += Double(spacing) }
            starts.append(along)
            along += vertical ? heights[i] : widths[i]
            across = max(across, vertical ? widths[i] : heights[i])
        }
        along += Double(vertical ? insets.bottom : insets.right)
        if vertical, alignment == .leading { across += Double(insets.left) }
        if !vertical, alignment == .top { across += Double(insets.top) }
        let width = vertical ? across : along, height = vertical ? along : across
        placed = views
        self.widths = widths
        self.heights = heights
        let resized = !wasFramed || width != framedWidth || height != framedHeight
        framedWidth = width
        framedHeight = height
        if resized { invalidateIntrinsicContentSize() }
        needsLayout = true
        return resized
    }

    /// Hand the children back to NSStackView.
    func unframe() {
        guard framed else { return }
        setContentHuggingPriority(.init(savedHugWidth), for: .horizontal)
        setContentHuggingPriority(.init(savedHugHeight), for: .vertical)
        setContentCompressionResistancePriority(.init(savedResistWidth), for: .horizontal)
        setContentCompressionResistancePriority(.init(savedResistHeight), for: .vertical)
        placed = nil
        widths = []
        heights = []
        starts = []
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    /// Whether a framed parent places this stack. It then reports no
    /// content size, so it adds nothing to Auto Layout.
    var inFrame = false {
        didSet { if inFrame != oldValue { invalidateIntrinsicContentSize() } }
    }

    override var intrinsicContentSize: NSSize {
        guard framed, !inFrame else { return super.intrinsicContentSize }
        return NSSize(width: framedWidth, height: framedHeight)
    }

    override func layout() {
        super.layout()
        guard let placed else { return }
        let vertical = orientation == .vertical
        let insets = edgeInsets
        let width = Double(bounds.size.width), height = Double(bounds.size.height)
        for (i, view) in placed.enumerated() {
            let w = widths[i], h = heights[i]
            var x: Double, top: Double
            if vertical {
                top = starts[i]
                switch alignment {
                case .centerX: x = (width - w) / 2
                case .trailing: x = width - w
                default: x = Double(insets.left)
                }
            } else {
                x = starts[i]
                switch alignment {
                case .centerY: top = (height - h) / 2
                case .bottom: top = height - h
                default: top = Double(insets.top)
                }
            }
            let y = isFlipped ? top : height - top - h
            view.frame = NSRect(x: x, y: y, width: w, height: h)
        }
    }

    /// The child under `point` (in the superview's coordinates), found by a
    /// search along the stack rather than by trying every child.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let placed, subviews.count == placed.count, !isHidden else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let width = Double(bounds.size.width), height = Double(bounds.size.height)
        let px = Double(local.x - bounds.origin.x), py = Double(local.y - bounds.origin.y)
        guard px >= 0, py >= 0, px < width, py < height else { return nil }
        let vertical = orientation == .vertical
        let along = vertical ? (isFlipped ? Double(local.y) : height - Double(local.y)) : Double(local.x)
        // The last child starting at or before `along`.
        var low = 0, high = placed.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= along { low = mid + 1 } else { high = mid }
        }
        if low > 0, let hit = placed[low - 1].hitTest(local) { return hit }
        return self
    }
}

extension Host {
    /// The children `stack` would place by frame, with their sizes, or nil
    /// when it must be arranged by NSStackView (the rule at the top of this
    /// file).
    func framePlan(_ stack: Stack, _ owner: Node) -> (views: [NSView], widths: [Double], heights: [Double])? {
        if stack.userInterfaceLayoutDirection != .leftToRight { return nil }
        if (owner.attrs["distribution"] ?? "gravity") != "gravity" { return nil }
        switch owner.attrs["align"] ?? "" {
        case "fill", "first-baseline": return nil
        default: break
        }
        for (name, usual) in [("width", "auto"), ("height", "auto"), ("squeeze", "standard")] where (owner.attrs[name] ?? usual) != usual { return nil }
        var views: [NSView] = [], widths: [Double] = [], heights: [Double] = []
        for child in owner.children {
            switch child.kind {
            case .comment: continue
            case .text: if child.text.isEmpty { continue } else { return nil }
            case .element: break
            }
            guard let shown = shownNode(child), let view = shown.view, !view.isHidden, !(view is Box), shown.name != "ui-spacer" else { return nil }
            if let inner = view as? Stack, inner.framed {
                widths.append(inner.framedWidth)
                heights.append(inner.framedHeight)
            } else if let w = Host.fixed(shown.attrs["width"]), let h = Host.fixed(shown.attrs["height"]) {
                widths.append(w)
                heights.append(h)
            } else {
                return nil
            }
            views.append(view)
        }
        return views.isEmpty ? nil : (views, widths, heights)
    }

    /// The points of a `fixed:N` length, or nil for any other.
    static func fixed(_ word: String?) -> Double? {
        guard let word, word.hasPrefix("fixed:") else { return nil }
        return Double(Host.points(String(word.dropFirst("fixed:".count)), "length"))
    }

    /// Place `owner`'s children by frame (`plan`), taking them out of
    /// NSStackView's arrangement and out of Auto Layout.
    func placeByFrame(_ stack: Stack, _ owner: Node, _ plan: (views: [NSView], widths: [Double], heights: [Double])) {
        let keep = Set(plan.views.map(ObjectIdentifier.init))
        for old in stack.arrangedSubviews {
            stack.removeArrangedSubview(old)
            if !keep.contains(ObjectIdentifier(old)) { old.removeFromSuperview() }
        }
        for old in stack.placed ?? [] where !keep.contains(ObjectIdentifier(old)) {
            if old.superview === stack { old.removeFromSuperview() }
            release(old)
        }
        for view in plan.views {
            let id = ObjectIdentifier(view)
            if !framedViews.contains(id) {
                framedViews.insert(id)
                setFill(view, in: stack, false)
                for (_, c) in constraints[id] ?? [:] { c.isActive = false }
                view.autoresizingMask = []
            }
            // A view with nothing for Auto Layout to solve (an empty box, a
            // framed stack) leaves it entirely: AppKit gives every view that
            // translates its autoresizing mask four constraints of its own,
            // which at 10,000 cells is most of the layout's time and memory.
            // Any other (a box holding a child, a control with a content
            // size) keeps its frame through its autoresizing constraints.
            let free = (view as? Stack)?.framed == true || ((view as? Surface).map { $0.child == nil } ?? false)
            if view.translatesAutoresizingMaskIntoConstraints == free { view.translatesAutoresizingMaskIntoConstraints = !free }
            (view as? Stack)?.inFrame = true
            if view.superview !== stack { stack.addSubview(view) }
        }
        if stack.frame(plan.views, widths: plan.widths, heights: plan.heights), let parent = owner.parent {
            // The parent places this stack by its size: arrange it again.
            markChildren(parent)
        }
    }

    /// Give a framed stack's children back to NSStackView (`arrange` then
    /// inserts them as arranged views).
    func unframe(_ stack: Stack, _ owner: Node) {
        guard let placed = stack.placed else { return }
        for view in placed { release(view) }
        stack.unframe()
        if let parent = owner.parent { markChildren(parent) }
    }

    /// A view placed by frame goes back to Auto Layout, with the size
    /// constraints it had.
    func release(_ view: NSView) {
        let id = ObjectIdentifier(view)
        guard framedViews.remove(id) != nil else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        (view as? Stack)?.inFrame = false
        for (key, c) in constraints[id] ?? [:] where key != "fill" { c.isActive = true }
    }
}
