// AppKit views for the `ui-*` elements, and AppKit events back into the engine.

import AppKit

extension Host {
    // MARK: Views

    /// Give an element its AppKit view, decided once by its name.
    func makeView(_ n: Node) {
        guard n.view == nil, let name = n.name else { return }
        let view: NSView
        switch name {
        case "ui-hstack", "ui-vstack", "ui-form":
            let stack = NSStackView()
            stack.orientation = name == "ui-hstack" ? .horizontal : .vertical
            stack.alignment = name == "ui-hstack" ? .centerY : .leading
            stack.spacing = 8
            view = stack
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
        case "ui-checkbox":
            view = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggled(_:)))
        case "ui-slider":
            let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: self, action: #selector(slid(_:)))
            slider.isContinuous = true
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            view = slider
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
        switch (n.view, name) {
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

    func markChildren(_ n: Node) { dirty.append(n) }

    func markText(_ n: Node) { dirty.append(n) }

    /// Bring every view touched by the batch up to date: a text-bearing
    /// control shows its subtree's text, a stack arranges its children's views.
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
        if let content = window.contentView {
            content.layoutSubtreeIfNeeded()
            let fit = content.fittingSize
            window.setContentSize(NSSize(width: max(fit.width, window.contentLayoutRect.width), height: fit.height))
        }
    }

    func refresh(_ owner: Node) {
        switch owner.view {
        case let stack as NSStackView:
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
                for old in stack.arrangedSubviews where !views.contains(old) {
                    stack.removeArrangedSubview(old)
                    old.removeFromSuperview()
                }
                for (i, v) in views.enumerated() {
                    if stack.arrangedSubviews.count > i, stack.arrangedSubviews[i] === v { continue }
                    if v.superview === stack { stack.removeArrangedSubview(v) }
                    stack.insertArrangedSubview(v, at: i)
                }
            }
        case let button as NSButton where owner.name == "ui-button":
            button.title = owner.textContent
        case let label as NSTextField where !label.isEditable:
            label.stringValue = owner.textContent
        default:
            break
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
