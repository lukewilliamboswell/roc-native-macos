// AppKit views for the `ui-*` elements, and AppKit events back into the engine.

import AppKit

/// A view whose origin is its top-left, so a scroll area's content starts at the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A scroll view that takes the window's slack: it opens at its `height`
/// and, once the window has been sized for it (`settled`), gives that up so
/// the window can shrink it to its `min-height`.
class Box: NSScrollView {
    var settled = false
}

/// `ui-scroll`: a vertical stack in a vertically scrolling view.
final class ScrollBox: Box {
    let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        documentView = document
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.topAnchor.constraint(equalTo: contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatal("ScrollBox is not archived") }
}

extension Host {
    // MARK: Views

    /// Give an element its AppKit view, decided once by its name.
    func makeView(_ n: Node) {
        guard n.view == nil, let name = n.name else { return }
        let view: NSView
        switch name {
        case "ui-hstack", "ui-vstack", "ui-form", "ui-row":
            let stack = NSStackView()
            let horizontal = name == "ui-hstack" || name == "ui-row"
            stack.orientation = horizontal ? .horizontal : .vertical
            stack.alignment = horizontal ? .centerY : .leading
            stack.spacing = 8
            view = stack
        case "ui-scroll":
            let box = ScrollBox()
            box.setContentHuggingPriority(.init(1), for: .vertical)
            view = box
        case "ui-list":
            let box = ListBox(host: self)
            box.setContentHuggingPriority(.init(1), for: .vertical)
            box.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
            view = box
        case "ui-title":
            let label = NSTextField(labelWithString: "")
            label.font = .boldSystemFont(ofSize: 22)
            view = label
        case "ui-readout":
            let label = NSTextField(labelWithString: "")
            label.font = .monospacedDigitSystemFont(ofSize: 36, weight: .medium)
            view = label
        case "ui-label":
            view = NSTextField(labelWithString: "")
        case "ui-button":
            view = NSButton(title: "", target: self, action: #selector(pressed(_:)))
        case "ui-text-field":
            let field = NSTextField(string: "")
            field.delegate = self
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            view = field
        case "ui-text-area":
            let scroll = NSTextView.scrollableTextView()
            scroll.borderType = .bezelBorder
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            if let text = scroll.documentView as? NSTextView {
                text.isRichText = false
                text.allowsUndo = true
                text.font = .systemFont(ofSize: NSFont.systemFontSize)
                text.delegate = self
                byView[ObjectIdentifier(text)] = n
            }
            view = scroll
        case "ui-checkbox":
            view = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggled(_:)))
        case "ui-slider":
            let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: self, action: #selector(slid(_:)))
            slider.isContinuous = true
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            view = slider
        case "ui-dropdown":
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.target = self
            popup.action = #selector(chose(_:))
            view = popup
        case "ui-segmented":
            let control = NSSegmentedControl()
            control.trackingMode = .selectOne
            control.target = self
            control.action = #selector(segmentChanged(_:))
            view = control
        case "ui-image":
            let image = NSImageView()
            image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            view = image
        case "ui-progress":
            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.isIndeterminate = false
            bar.minValue = 0
            bar.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
            view = bar
        case "ui-shortcut":
            // Only its key handler matters; a hidden view takes no room in a stack.
            view = NSView()
            view.isHidden = true
        case "ui-divider":
            let box = NSBox()
            box.boxType = .separator
            view = box
        case "ui-spacer":
            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            spacer.setContentHuggingPriority(.init(1), for: .vertical)
            view = spacer
        default:
            fatal("<\(name)> is not a native element this host knows")
        }
        n.view = view
        byView[ObjectIdentifier(view)] = n
    }

    func setAttr(_ n: Node, _ name: String, _ value: String?) {
        if let value { n.attrs[name] = value } else { n.attrs.removeValue(forKey: name) }
        applyAttr(n, name, value)
    }

    /// Apply one attribute to the live control. A control's own state
    /// (`value`, `checked`) is only written when it differs, so an edit in
    /// progress is not disturbed by the engine echoing it back.
    func applyAttr(_ n: Node, _ name: String, _ value: String?) {
        let number = value.flatMap { Double($0) }.map { CGFloat($0) }
        switch (n.view, name) {
        // Layout
        case (let stack as NSStackView, "spacing"), (let stack as NSStackView, "padding"), (let stack as NSStackView, "align"):
            configure(stack, n)
        case (let box as ScrollBox, "spacing"), (let box as ScrollBox, "padding"):
            configure(box.stack, n)
        case (let view?, "min-width"):
            setSize(view, "min-width", number.flatMap { $0 > 0 ? $0 : nil })
        case (let box as Box, "height"):
            setSize(box, "height", number, priority: .init(box.settled ? 49 : 100))
        case (let box as Box, "min-height"):
            setSize(box, "min-height", number)
        // Text style
        case (let label as NSTextField, "font"):
            label.font = Host.font(value)
        case (let label as NSTextField, "color"):
            label.textColor = Host.color(value)
        case (let image as NSImageView, "color"):
            image.contentTintColor = Host.color(value)
        case (let image as NSImageView, "symbol"):
            image.image = value.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: $0) }
        // Choices
        case (let popup as NSPopUpButton, "choices"):
            popup.removeAllItems()
            popup.addItems(withTitles: Host.choices(value))
            popup.selectItem(withTitle: n.attrs["value"] ?? "")
        case (let popup as NSPopUpButton, "value"):
            if popup.titleOfSelectedItem != value { popup.selectItem(withTitle: value ?? "") }
        case (let control as NSSegmentedControl, "choices"):
            let titles = Host.choices(value)
            control.segmentCount = titles.count
            for (i, title) in titles.enumerated() { control.setLabel(title, forSegment: i) }
            selectSegment(control, n.attrs["value"])
        case (let control as NSSegmentedControl, "value"):
            selectSegment(control, value)
        // Progress
        case (let bar as NSProgressIndicator, "max"):
            bar.maxValue = Double(value ?? "") ?? 100
        case (let bar as NSProgressIndicator, "indeterminate"):
            bar.isIndeterminate = value != nil
        case (let bar as NSProgressIndicator, "value"):
            if bar.isIndeterminate {
                if value == "1" { bar.startAnimation(nil) } else { bar.stopAnimation(nil) }
            } else {
                bar.doubleValue = Double(value ?? "") ?? 0
            }
        // Text area
        case (let scroll as NSScrollView, "value") where n.name == "ui-text-area":
            if let text = scroll.documentView as? NSTextView, text.string != (value ?? "") { text.string = value ?? "" }
        case (let scroll as NSScrollView, "height") where n.name == "ui-text-area":
            setSize(scroll, "min-height", number)
        // Controls
        case (let field as NSTextField, "value"):
            if field.stringValue != (value ?? "") { field.stringValue = value ?? "" }
        case (let field as NSTextField, "placeholder"):
            field.placeholderString = value
        case (let button as NSButton, "checked"):
            button.state = value == "true" ? .on : .off
        case (let button as NSButton, "title"):
            button.title = value ?? ""
        case (let control as NSControl, "disabled"):
            control.isEnabled = value == nil
        case (let button as NSButton, "submit"):
            button.keyEquivalent = value == nil ? "" : "\r"
        case (let slider as NSSlider, "min"):
            slider.minValue = Double(value ?? "") ?? 0
        case (let slider as NSSlider, "max"):
            slider.maxValue = Double(value ?? "") ?? 100
        case (let slider as NSSlider, "value"):
            let v = Double(value ?? "") ?? 0
            if slider.doubleValue != v { slider.doubleValue = v }
        default:
            break
        }
    }

    /// A stack's `spacing`, `padding` and `align` attributes.
    func configure(_ stack: NSStackView, _ n: Node) {
        stack.spacing = n.attrs["spacing"].flatMap { Double($0) }.map { CGFloat($0) } ?? 8
        let pad = n.attrs["padding"].flatMap { Double($0) }.map { CGFloat($0) } ?? 0
        stack.edgeInsets = NSEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        if stack.orientation == .vertical {
            switch n.attrs["align"] {
            case "center": stack.alignment = .centerX
            case "trailing": stack.alignment = .trailing
            default: stack.alignment = .leading
            }
        } else {
            switch n.attrs["align"] {
            case "top": stack.alignment = .top
            case "bottom": stack.alignment = .bottom
            default: stack.alignment = .centerY
            }
        }
        markChildren(n)
    }

    static func choices(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    func selectSegment(_ control: NSSegmentedControl, _ value: String?) {
        for i in 0..<control.segmentCount where control.label(forSegment: i) == value {
            if control.selectedSegment != i { control.selectedSegment = i }
            return
        }
        control.selectedSegment = -1
    }

    static func font(_ name: String?) -> NSFont {
        let size = NSFont.systemFontSize
        switch name {
        case "title": return .boldSystemFont(ofSize: 22)
        case "headline": return .boldSystemFont(ofSize: size)
        case "caption": return .systemFont(ofSize: NSFont.smallSystemFontSize)
        case "mono": return .monospacedSystemFont(ofSize: size, weight: .regular)
        default: return .systemFont(ofSize: size)
        }
    }

    static func color(_ name: String?) -> NSColor {
        switch name {
        case "secondary": return .secondaryLabelColor
        case "tertiary": return .tertiaryLabelColor
        case "accent": return .controlAccentColor
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "green": return .systemGreen
        case "blue": return .systemBlue
        default: return .labelColor
        }
    }

    // MARK: Constraints the host owns

    /// Set (or, for nil, drop) one of a view's size constraints, by purpose:
    /// `min-width` and `min-height` are lower bounds, `height` a preference.
    func setSize(_ view: NSView, _ key: String, _ value: CGFloat?, priority: NSLayoutConstraint.Priority = .required) {
        let id = ObjectIdentifier(view)
        constraints[id]?[key]?.isActive = false
        constraints[id]?[key] = nil
        guard let value else { return }
        let c: NSLayoutConstraint
        switch key {
        case "min-width": c = view.widthAnchor.constraint(greaterThanOrEqualToConstant: value)
        case "min-height": c = view.heightAnchor.constraint(greaterThanOrEqualToConstant: value)
        default: c = view.heightAnchor.constraint(equalToConstant: value)
        }
        c.priority = priority
        c.isActive = true
        constraints[id, default: [:]][key] = c
    }

    /// Stretch `view` to the width of the vertical `stack` it is arranged
    /// in, inside its padding, or stop doing so.
    func setFill(_ view: NSView, in stack: NSStackView, _ on: Bool) {
        let id = ObjectIdentifier(view)
        if let c = constraints[id]?["fill"], !on || c.secondItem !== stack {
            c.isActive = false
            constraints[id]?["fill"] = nil
        }
        guard on else { return }
        let inset = -(stack.edgeInsets.left + stack.edgeInsets.right)
        if let c = constraints[id]?["fill"] {
            c.constant = inset
            c.isActive = true
        } else {
            let c = view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: inset)
            c.isActive = true
            constraints[id, default: [:]]["fill"] = c
        }
    }

    func markChildren(_ n: Node) { dirty.append(n) }

    func markText(_ n: Node) { dirty.append(n) }

    /// Bring every view touched by the batch up to date: a text-bearing
    /// control shows its subtree's text, a stack arranges its children's
    /// views, a list applies its row changes. Then size the window: to fit
    /// its content exactly, or, once it holds a scroll area or list, never
    /// smaller than its content needs (the scroll areas take the slack).
    func sync() {
        var seen = Set<ObjectIdentifier>()
        let pending = dirty
        dirty = []
        for start in pending {
            // The nearest element with a view at or above the changed node.
            var cursor: Node? = start
            while let c = cursor, c.view == nil || c.name == nil { cursor = c.parent }
            guard let owner = cursor, seen.insert(ObjectIdentifier(owner)).inserted else { continue }
            refresh(owner)
        }
        var unsettled: [Box] = []
        let flexibleNow = layoutPass(root, &unsettled)
        if let content = window.contentView {
            content.layoutSubtreeIfNeeded()
            let fit = content.fittingSize
            let current = content.frame.size
            let height = flexibleNow && flexible ? max(fit.height, current.height) : fit.height
            let size = NSSize(width: max(fit.width, window.contentLayoutRect.width), height: height)
            if size != current { window.setContentSize(size) }
        }
        // The window now has room for each new scroll area's starting
        // height; from here on the window decides it.
        for box in unsettled {
            box.settled = true
            constraints[ObjectIdentifier(box)]?["height"]?.priority = .init(49)
        }
        flexible = flexibleNow
    }

    /// Whether `n` holds a scroll area or list outside any other one. A
    /// vertical stack that does fills its height (`.fill`), so the scroll
    /// area, which hugs least, takes the slack; any other keeps its
    /// children at their natural heights.
    func layoutPass(_ n: Node, _ unsettled: inout [Box]) -> Bool {
        if let box = n.view as? Box {
            if !box.settled { unsettled.append(box) }
            return true
        }
        var any = false
        for child in n.children where child.name != nil {
            if layoutPass(child, &unsettled) { any = true }
        }
        if let stack = n.view as? NSStackView, stack.orientation == .vertical {
            let distribution: NSStackView.Distribution = any ? .fill : .gravityAreas
            if stack.distribution != distribution { stack.distribution = distribution }
        }
        return any
    }

    func refresh(_ owner: Node) {
        switch owner.view {
        case let stack as NSStackView:
            arrange(stack, owner, fill: owner.attrs["align"] == "fill")
        case let box as ScrollBox:
            arrange(box.stack, owner, fill: true)
        case let box as ListBox:
            box.finish(owner)
        case let button as NSButton where owner.name == "ui-button":
            button.title = owner.textContent
        case let label as NSTextField where !label.isEditable:
            label.stringValue = owner.textContent
        default:
            break
        }
    }

    /// Make `stack`'s arranged views exactly its node's children's views.
    /// In a vertical stack, scroll views (scroll areas, lists, text areas)
    /// always fill its width, and every child does when `fill` is set.
    func arrange(_ stack: NSStackView, _ owner: Node, fill: Bool) {
        let views: [NSView] = owner.children.compactMap { child in
            switch child.kind {
            case .element: return child.view
            case .comment: return nil
            case .text:
                if child.text.isEmpty { return nil }
                if child.view == nil { child.view = NSTextField(labelWithString: "") }
                (child.view as? NSTextField)?.stringValue = child.text
                return child.view
            }
        }
        if stack.arrangedSubviews != views {
            let keep = Set(views.map(ObjectIdentifier.init))
            for old in stack.arrangedSubviews where !keep.contains(ObjectIdentifier(old)) {
                stack.removeArrangedSubview(old)
                old.removeFromSuperview()
            }
            for (i, v) in views.enumerated() {
                if stack.arrangedSubviews.count > i, stack.arrangedSubviews[i] === v { continue }
                if v.superview === stack { stack.removeArrangedSubview(v) }
                stack.insertArrangedSubview(v, at: i)
            }
        }
        if stack.orientation == .vertical {
            for v in views { setFill(v, in: stack, fill || v is NSScrollView) }
        }
    }

    // MARK: AppKit events

    @objc func pressed(_ sender: NSButton) {
        guard let n = byView[ObjectIdentifier(sender)] else { return }
        if n.attrs["submit"] != nil {
            submit(from: n)
        } else {
            dispatch("click", at: n)
        }
    }

    @objc func toggled(_ sender: NSButton) {
        guard let n = byView[ObjectIdentifier(sender)] else { return }
        let on = sender.state == .on
        // Keep showing the engine's state until it answers.
        sender.state = n.attrs["checked"] == "true" ? .on : .off
        dispatch("change", at: n, flag: on)
    }

    @objc func slid(_ sender: NSSlider) {
        guard let n = byView[ObjectIdentifier(sender)] else { return }
        dispatch("input", at: n, text: String(Int(sender.doubleValue.rounded())))
    }

    @objc func chose(_ sender: NSPopUpButton) {
        guard let n = byView[ObjectIdentifier(sender)], let title = sender.titleOfSelectedItem else { return }
        // Keep showing the engine's choice until it answers.
        sender.selectItem(withTitle: n.attrs["value"] ?? "")
        dispatch("change", at: n, text: title)
    }

    @objc func segmentChanged(_ sender: NSSegmentedControl) {
        guard let n = byView[ObjectIdentifier(sender)], sender.selectedSegment >= 0 else { return }
        let title = sender.label(forSegment: sender.selectedSegment) ?? ""
        selectSegment(sender, n.attrs["value"])
        dispatch("change", at: n, text: title)
    }

    func controlTextDidChange(_ note: Notification) {
        guard let field = note.object as? NSTextField, let n = byView[ObjectIdentifier(field)] else { return }
        dispatch("input", at: n, text: field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)), let n = byView[ObjectIdentifier(control)] else { return false }
        submit(from: n)
        return true
    }

    func submit(from n: Node) {
        var cursor: Node? = n
        while let c = cursor, c.name != "ui-form" { cursor = c.parent }
        if let form = cursor { dispatch("submit", at: form) }
    }
}

extension Host: NSTextViewDelegate {
    /// A text area's edit: the engine gets the whole text. The text view is
    /// left alone when the engine echoes the same text back.
    func textDidChange(_ note: Notification) {
        guard let text = note.object as? NSTextView, let n = byView[ObjectIdentifier(text)] else { return }
        dispatch("input", at: n, text: text.string)
    }
}
