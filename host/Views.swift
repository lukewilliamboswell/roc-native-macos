// AppKit views for the `ui-*` elements, and AppKit events back into the engine.

import AppKit

/// A view whose origin is its top-left, so a scroll area's content starts at the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A scroll view that takes the window's slack: it opens at its
/// `opening-height` and, once the window has been sized for it (`settled`),
/// gives that up so the window can size it within its `height`.
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

/// `ui-text`: a label. A wrapping one (`overflow` `wrap`) has no width of
/// its own; it wraps to the width its frame is given (`width` `fill` or a
/// bound), and its height follows from that width.
final class Label: NSTextField {
    private var wraps: Bool { maximumNumberOfLines != 1 }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        if wraps { size.width = NSView.noIntrinsicMetric }
        return size
    }

    override func layout() {
        super.layout()
        if wraps, preferredMaxLayoutWidth != frame.width {
            preferredMaxLayoutWidth = frame.width
            invalidateIntrinsicContentSize()
        }
    }
}

/// A line drawn around a surface.
enum Stroke {
    case none
    case solid(NSColor, Double)
    case dashed(NSColor, Double)
}

/// `ui-box`: one child inside `insets`, over a rounded fill with a border.
/// It draws with `NSColor`s in `draw(_:)`, where AppKit has set the view's
/// appearance, so a semantic or adaptive colour follows light and dark mode.
class Surface: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var border: Stroke = .none {
        didSet {
            // Drawn from here on: the layer stops drawing its own fill.
            if case .dashed = border, let layer {
                layer.backgroundColor = nil
                layer.borderWidth = 0
                layer.cornerRadius = 0
            }
            needsDisplay = true
        }
    }
    var radius: Double = 8 { didSet { needsDisplay = true } }
    private(set) var child: NSView?
    private var pins: [NSLayoutConstraint] = []
    /// Top, leading, bottom, trailing (Doubles: a stored NSEdgeInsets would
    /// make Swift emit field metadata naming CGFloat, an overlay symbol).
    var insets: [Double] = [12, 12, 12, 12] {
        didSet { place() }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatal("Surface is not archived") }

    /// Hold `view` (or nothing) as the child.
    func hold(_ view: NSView?) {
        if child === view { return }
        child?.removeFromSuperview()
        child = view
        guard let view else { pins = []; return }
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        place()
    }

    private func place() {
        NSLayoutConstraint.deactivate(pins)
        guard let view = child else { pins = []; return }
        pins = [
            view.topAnchor.constraint(equalTo: topAnchor, constant: insets[0]),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets[1]),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: insets[3]),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: insets[2]),
        ]
        NSLayoutConstraint.activate(pins)
    }

    /// A fill and a solid border are the layer's own properties: no
    /// backing store to draw into, which at 100,000 boxes was 1.5 GB of
    /// Core Animation memory and most of the first frame's time. A dashed
    /// border is drawn (`draw(_:)`).
    override var wantsUpdateLayer: Bool {
        if case .dashed = border { return false }
        return true
    }

    override func updateLayer() {
        guard let layer else { return }
        var lineWidth: Double = 0
        var stroke = NSColor.clear
        if case let .solid(color, width) = border {
            lineWidth = width
            stroke = color
        }
        // As `draw(_:)` strokes a path inset by half the line: the outer
        // corner radius is the radius plus half the line.
        layer.cornerRadius = radius + lineWidth / 2
        layer.backgroundColor = fill.cgColor
        layer.borderWidth = lineWidth
        layer.borderColor = stroke.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        var lineWidth: Double = 0
        switch border {
        case .none: break
        case let .solid(_, width), let .dashed(_, width): lineWidth = width
        }
        let rect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        switch border {
        case .none:
            break
        case let .solid(color, width):
            path.lineWidth = width
            color.setStroke()
            path.stroke()
        case let .dashed(color, width):
            path.lineWidth = width
            path.setLineDash([6, 4], count: 2, phase: 0)
            color.setStroke()
            path.stroke()
        }
    }
}

extension Host {
    // MARK: Views

    /// Give an element its AppKit view, decided once by its name.
    func makeView(_ n: Node) {
        // `ui-hover` has no view: its child's stands in its place (Hover.swift).
        guard n.view == nil, let name = n.name, name != "ui-hover" else { return }
        let view: NSView
        switch name {
        case "ui-hstack", "ui-vstack", "ui-form", "ui-row":
            let stack = Stack()  // Frames.swift
            let horizontal = name == "ui-hstack" || name == "ui-row"
            stack.orientation = horizontal ? .horizontal : .vertical
            stack.alignment = horizontal ? .centerY : .leading
            stack.spacing = 8
            view = stack
        case "ui-box":
            view = Surface()
        case "ui-scroll":
            let box = ScrollBox()
            box.setContentHuggingPriority(.init(1), for: .vertical)
            view = box
        case "ui-list":
            let box = ListBox(host: self)
            box.setContentHuggingPriority(.init(1), for: .vertical)
            view = box
        case "ui-text":
            view = Label(labelWithString: "")
        case "ui-button":
            view = NSButton(title: "", target: self, action: #selector(pressed(_:)))
        case "ui-text-field":
            let field = NSTextField(string: "")
            field.delegate = self
            view = field
        case "ui-text-area":
            let scroll = NSTextView.scrollableTextView()
            scroll.borderType = .bezelBorder
            if let text = scroll.documentView as? NSTextView {
                text.isRichText = false
                text.allowsUndo = true
                text.font = .systemFont(ofSize: NSFont.systemFontSize)
                text.textContainerInset = NSSize(width: 4, height: 6)
                text.delegate = self
                byView[ObjectIdentifier(text)] = n
            }
            view = scroll
        case "ui-checkbox":
            view = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggled(_:)))
        case "ui-slider":
            let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: self, action: #selector(slid(_:)))
            slider.isContinuous = true
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
            image.symbolConfiguration = NSImage.SymbolConfiguration(textStyle: .body, scale: .medium)
            view = image
        case "ui-asset-image":
            view = Picture()  // Assets.swift
        case "ui-progress":
            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.isIndeterminate = false
            bar.minValue = 0
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
        case "ui-file-button", "ui-drop-zone":
            view = makeFileView(name)  // Files.swift
        default:
            fatal("<\(name)> is not a native element this host knows")
        }
        // What the view hugs and resists with before any `width`, `height`
        // or `squeeze` attribute, so `auto` and `standard` can return to it.
        n.natural = Natural(
            hugWidth: view.contentHuggingPriority(for: .horizontal),
            hugHeight: view.contentHuggingPriority(for: .vertical),
            resist: view.contentCompressionResistancePriority(for: .horizontal))
        n.view = view
        byView[ObjectIdentifier(view)] = n
    }

    func setAttr(_ n: Node, _ name: String, _ value: String?) {
        if let value { n.attrs[name] = value } else { n.attrs.removeValue(forKey: name) }
        if !Host.paintOnly(name) { relayout = true }
        applyAttr(n, name, value)
    }

    /// Attributes that change how a view draws but never its size or place:
    /// a batch that only sets these needs a display, not a layout pass.
    static func paintOnly(_ name: String) -> Bool {
        switch name {
        case "fill", "border", "radius", "color": return true
        default: return false
        }
    }

    /// Apply one attribute to the live control. A control's own state
    /// (`value`, `checked`) is only written when it differs, so an edit in
    /// progress is not disturbed by the engine echoing it back. Look
    /// attributes use the closed grammar in docs/architecture.adoc; a word
    /// outside it is a fatal error.
    func applyAttr(_ n: Node, _ name: String, _ value: String?) {
        switch (n.view, name) {
        // Frame: any element
        case (let view?, "width"):
            setLength(view, n, .horizontal, value)
        case (let view?, "height"):
            setLength(view, n, .vertical, value)
        case (let view?, "squeeze"):
            let natural = n.natural?.resist ?? .init(750)
            let priority: NSLayoutConstraint.Priority
            switch value ?? "standard" {
            case "standard": priority = natural
            case "yield": priority = .init(250)
            case "resist": priority = .init(999)
            case let other: fatal("squeeze \(other) is not standard, yield or resist")
            }
            view.setContentCompressionResistancePriority(priority, for: .horizontal)
            if view is Stack { markChildren(n) }
        // Layout
        case (let stack as NSStackView, "spacing"), (let stack as NSStackView, "padding"),
             (let stack as NSStackView, "align"), (let stack as NSStackView, "distribution"):
            configure(stack, n)
        case (let box as ScrollBox, "spacing"), (let box as ScrollBox, "padding"):
            configure(box.stack, n)
        case (let box as Box, "opening-height"):
            setSize(box, "opening", value.map { Host.points($0, name) }, priority: .init(box.settled ? 49 : 300))
        // Surfaces
        case (let surface as Surface, "fill"):
            surface.fill = Host.color(value ?? "clear")
        case (let surface as Surface, "border"):
            surface.border = Host.stroke(value ?? "none")
        case (let surface as Surface, "radius"):
            surface.radius = Host.points(value ?? "0", name)
        case (let surface as Surface, "padding"):
            let e = Host.insets(value ?? "0 0 0 0")
            surface.insets = [e.top, e.left, e.bottom, e.right]
        // Text
        case (let label as NSTextField, "text-style"), (let label as NSTextField, "font-size"),
             (let label as NSTextField, "weight"), (let label as NSTextField, "design"):
            label.font = Host.font(n.attrs)
        case (let label as NSTextField, "color"):
            label.textColor = Host.color(value ?? "label")
        case (let label as NSTextField, "overflow"):
            setOverflow(label, value ?? "truncate-tail")
        case (let label as NSTextField, "text-align"):
            label.alignment = Host.textAlignment(value ?? "natural")
        // Symbols
        case (let image as NSImageView, "color"):
            image.contentTintColor = Host.color(value ?? "label")
        case (let image as NSImageView, "symbol"):
            image.image = value.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: $0) }
        case (let image as NSImageView, "text-style"), (let image as NSImageView, "scale"):
            image.symbolConfiguration = NSImage.SymbolConfiguration(
                textStyle: Host.textStyle(n.attrs["text-style"] ?? "body"),
                scale: Host.symbolScale(n.attrs["scale"] ?? "medium"))
        // Asset images (Assets.swift)
        case (let picture as Picture, "asset"):
            picture.show(value ?? "")
        case (let picture as Picture, "scaling"):
            picture.scaling = Host.imageScaling(value ?? "fit")
        case (let picture as Picture, "label"):
            picture.label(value ?? "")
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
        case (let bar as NSProgressIndicator, "size"):
            bar.controlSize = Host.controlSize(value ?? "regular")
        // Text area
        case (let scroll as NSScrollView, "value") where n.name == "ui-text-area":
            if let text = scroll.documentView as? NSTextView, text.string != (value ?? "") { text.string = value ?? "" }
        case (let scroll as NSScrollView, "design") where n.name == "ui-text-area":
            let size = NSFont.systemFontSize
            (scroll.documentView as? NSTextView)?.font = (value ?? "proportional") == "proportional"
                ? .systemFont(ofSize: size) : .monospacedSystemFont(ofSize: size, weight: .regular)
        // Controls
        case (let field as NSTextField, "value"):
            if field.stringValue != (value ?? "") { field.stringValue = value ?? "" }
        case (let field as NSTextField, "placeholder"):
            field.placeholderString = value
        case (let field as NSTextField, "bezel"):
            field.isBezeled = true
            switch value ?? "square" {
            case "square": field.bezelStyle = .squareBezel
            case "rounded": field.bezelStyle = .roundedBezel
            case let other: fatal("text field bezel \(other) is not square or rounded")
            }
        case (let button as NSButton, "checked"):
            button.state = value == "true" ? .on : .off
        case (let button as NSButton, "title"):
            button.title = value ?? ""
        case (let button as NSButton, "bezel"):
            setBezel(button, value ?? "push")
        case (let button as NSButton, "role"):
            setRole(button, n, value ?? "normal")
        case (let button as NSButton, "submit"):
            setRole(button, n, n.attrs["role"] ?? "normal")
        case (let button as NSButton, "icon"):
            let icon = value ?? "none"
            if icon == "none" {
                button.image = nil
            } else if icon.hasPrefix("symbol:") {
                let symbol = String(icon.dropFirst("symbol:".count))
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
            } else {
                fatal("icon \(icon) is not none or symbol:NAME")
            }
            setTitleDisplay(button, n.attrs["title-display"] ?? "visible")
        case (let button as NSButton, "title-display"):
            setTitleDisplay(button, value ?? "visible")
        case (let control as NSControl, "size"):
            let size = Host.controlSize(value ?? "regular")
            control.controlSize = size
            if !(control is NSSlider) { control.font = .systemFont(ofSize: NSFont.systemFontSize(for: size)) }
        case (let control as NSControl, "enabled"):
            switch value ?? "true" {
            case "true": control.isEnabled = true
            case "false": control.isEnabled = false
            case let other: fatal("enabled \(other) is not true or false")
            }
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
        // Setting a button's title, bezel or size can move its image, and
        // the attributes arrive in any order: place the image last.
        if let button = n.view as? NSButton, ["title", "bezel", "size", "icon", "title-display"].contains(name) {
            setTitleDisplay(button, n.attrs["title-display"] ?? "visible")
        }
    }

    /// A stack's `spacing`, `padding`, `align` and `distribution` attributes.
    func configure(_ stack: NSStackView, _ n: Node) {
        stack.spacing = Host.points(n.attrs["spacing"] ?? "8", "spacing")
        stack.edgeInsets = Host.insets(n.attrs["padding"] ?? "0 0 0 0")
        let align = n.attrs["align"]
        if stack.orientation == .vertical {
            switch align ?? "leading" {
            case "leading", "fill": stack.alignment = .leading
            case "center": stack.alignment = .centerX
            case "trailing": stack.alignment = .trailing
            case let other: fatal("vertical stack align \(other) is not leading, center, trailing or fill")
            }
        } else {
            switch align ?? "center" {
            case "top", "fill": stack.alignment = .top
            case "center": stack.alignment = .centerY
            case "bottom": stack.alignment = .bottom
            case "first-baseline": stack.alignment = .firstBaseline
            case let other: fatal("horizontal stack align \(other) is not top, center, bottom, first-baseline or fill")
            }
        }
        // `gravity` may become `.fill` in `layoutPass` (a stack holding a scroll area).
        switch n.attrs["distribution"] ?? "gravity" {
        case "gravity": break
        case "fill": stack.distribution = .fill
        case "fill-equally": stack.distribution = .fillEqually
        case "fill-proportionally": stack.distribution = .fillProportionally
        case "equal-spacing": stack.distribution = .equalSpacing
        case "equal-centering": stack.distribution = .equalCentering
        case let other: fatal("distribution \(other) is not in the grammar")
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

    // MARK: Look grammar (docs/architecture.adoc)

    /// A whole number of points.
    static func points(_ text: String, _ what: String) -> CGFloat {
        guard let n = UInt32(text) else { fatal("\(what) \(text) is not a whole number of points") }
        return CGFloat(Double(n))
    }

    /// `TOP LEADING BOTTOM TRAILING`.
    static func insets(_ text: String) -> NSEdgeInsets {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count == 4 else { fatal("padding \(text) is not four numbers") }
        return NSEdgeInsets(
            top: points(parts[0], "padding"), left: points(parts[1], "padding"),
            bottom: points(parts[2], "padding"), right: points(parts[3], "padding"))
    }

    static func textStyle(_ word: String) -> NSFont.TextStyle {
        switch word {
        case "large-title": return .largeTitle
        case "title1": return .title1
        case "title2": return .title2
        case "title3": return .title3
        case "headline": return .headline
        case "subheadline": return .subheadline
        case "body": return .body
        case "callout": return .callout
        case "footnote": return .footnote
        case "caption1": return .caption1
        case "caption2": return .caption2
        default: fatal("text style \(word) is not one of AppKit's")
        }
    }

    /// The font a text's `text-style`, `font-size`, `weight` and `design`
    /// name. The style's own font when nothing overrides it; otherwise the
    /// system face at the style's (or the fixed) size, in the named weight
    /// (`standard` being the style's: bold for a headline, else regular).
    static func font(_ attrs: [String: String]) -> NSFont {
        let styleWord = attrs["text-style"] ?? "body"
        let base = NSFont.preferredFont(forTextStyle: textStyle(styleWord))
        let sizeWord = attrs["font-size"] ?? "standard"
        let size = sizeWord == "standard" ? base.pointSize : points(sizeWord, "font-size")
        let weightWord = attrs["weight"] ?? "standard"
        let design = attrs["design"] ?? "proportional"
        if weightWord == "standard" && design == "proportional" && sizeWord == "standard" { return base }
        let weight: NSFont.Weight
        switch weightWord {
        case "standard": weight = styleWord == "headline" ? .bold : .regular
        case "light": weight = .light
        case "regular": weight = .regular
        case "medium": weight = .medium
        case "semibold": weight = .semibold
        case "bold": weight = .bold
        case "heavy": weight = .heavy
        default: fatal("weight \(weightWord) is not in the grammar")
        }
        switch design {
        case "proportional": return .systemFont(ofSize: size, weight: weight)
        case "monospaced-digits": return .monospacedDigitSystemFont(ofSize: size, weight: weight)
        case "monospaced": return .monospacedSystemFont(ofSize: size, weight: weight)
        default: fatal("design \(design) is not proportional, monospaced-digits or monospaced")
        }
    }

    static func textAlignment(_ word: String) -> NSTextAlignment {
        switch word {
        case "natural": return .natural
        case "leading": return NSApp.userInterfaceLayoutDirection == .rightToLeft ? .right : .left
        case "center": return .center
        case "trailing": return NSApp.userInterfaceLayoutDirection == .rightToLeft ? .left : .right
        case "justified": return .justified
        default: fatal("text align \(word) is not in the grammar")
        }
    }

    func setOverflow(_ label: NSTextField, _ word: String) {
        var lines = 1
        switch word {
        case "clip": label.lineBreakMode = .byClipping
        case "truncate-head": label.lineBreakMode = .byTruncatingHead
        case "truncate-middle": label.lineBreakMode = .byTruncatingMiddle
        case "truncate-tail": label.lineBreakMode = .byTruncatingTail
        case "wrap": label.lineBreakMode = .byWordWrapping; lines = 0
        default:
            guard word.hasPrefix("wrap:"), let n = Int(word.dropFirst("wrap:".count)), n > 0 else { fatal("overflow \(word) is not in the grammar") }
            label.lineBreakMode = .byWordWrapping
            lines = n
        }
        label.maximumNumberOfLines = lines
        label.cell?.wraps = lines != 1
        label.cell?.isScrollable = false
        label.cell?.truncatesLastVisibleLine = true
    }

    static func symbolScale(_ word: String) -> NSImage.SymbolScale {
        switch word {
        case "small": return .small
        case "medium": return .medium
        case "large": return .large
        default: fatal("symbol scale \(word) is not small, medium or large")
        }
    }

    static func controlSize(_ word: String) -> NSControl.ControlSize {
        switch word {
        case "mini": return .mini
        case "small": return .small
        case "regular": return .regular
        case "large": return .large
        default: fatal("control size \(word) is not mini, small, regular or large")
        }
    }

    /// A semantic colour, `clear`, or `adaptive:RRGGBB:RRGGBB` (light, dark).
    static func color(_ word: String) -> NSColor {
        switch word {
        case "label": return .labelColor
        case "secondary-label": return .secondaryLabelColor
        case "tertiary-label": return .tertiaryLabelColor
        case "quaternary-label": return .quaternaryLabelColor
        case "accent": return .controlAccentColor
        case "link": return .linkColor
        case "placeholder-text": return .placeholderTextColor
        case "separator": return .separatorColor
        case "window-background": return .windowBackgroundColor
        case "control-background": return .controlBackgroundColor
        case "under-page-background": return .underPageBackgroundColor
        case "text-background": return .textBackgroundColor
        case "selected-content-background": return .selectedContentBackgroundColor
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "mint": return .systemMint
        case "teal": return .systemTeal
        case "cyan": return .systemCyan
        case "blue": return .systemBlue
        case "indigo": return .systemIndigo
        case "purple": return .systemPurple
        case "pink": return .systemPink
        case "brown": return .systemBrown
        case "gray": return .systemGray
        case "clear": return .clear
        default:
            let parts = word.split(separator: ":").map(String.init)
            guard parts.count == 3, parts[0] == "adaptive", let light = rgb(parts[1]), let dark = rgb(parts[2]) else {
                fatal("colour \(word) is not a semantic colour or adaptive:RRGGBB:RRGGBB")
            }
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            }
        }
    }

    /// Six hexadecimal digits as an sRGB colour.
    static func rgb(_ hex: String) -> NSColor? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xff) / 255, green = Double((value >> 8) & 0xff) / 255, blue = Double(value & 0xff) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// `none`, `line:WIDTH:COLOUR` or `dashed:WIDTH:COLOUR`.
    static func stroke(_ word: String) -> Stroke {
        if word == "none" { return .none }
        let parts = word.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { fatal("border \(word) is not none, line:W:COLOUR or dashed:W:COLOUR") }
        let width = points(parts[1], "border width")
        switch parts[0] {
        case "line": return .solid(color(parts[2]), width)
        case "dashed": return .dashed(color(parts[2]), width)
        default: fatal("border \(word) is not none, line:W:COLOUR or dashed:W:COLOUR")
        }
    }

    func setBezel(_ button: NSButton, _ word: String) {
        button.isBordered = word != "borderless"
        switch word {
        case "push", "borderless": button.bezelStyle = .push
        case "flexible-push": button.bezelStyle = .flexiblePush
        case "toolbar": button.bezelStyle = .toolbar
        case "accessory-bar": button.bezelStyle = .accessoryBarAction
        case "badge": button.bezelStyle = .badge
        case "circular": button.bezelStyle = .circular
        case "small-square": button.bezelStyle = .smallSquare
        default: fatal("bezel \(word) is not in the grammar")
        }
    }

    /// `default` answers Return (as a form's submit button does), `cancel`
    /// answers Escape, `destructive` is drawn as destructive.
    func setRole(_ button: NSButton, _ n: Node, _ word: String) {
        let submits = n.attrs["submit"] != nil
        switch word {
        case "normal": button.keyEquivalent = submits ? "\r" : ""
        case "default": button.keyEquivalent = "\r"
        case "cancel": button.keyEquivalent = "\u{1b}"
        case "destructive": button.keyEquivalent = submits ? "\r" : ""
        default: fatal("role \(word) is not normal, default, cancel or destructive")
        }
        button.hasDestructiveAction = word == "destructive"
    }

    /// A hidden title still names the control to VoiceOver; only its symbol
    /// (or a checkbox's box) is drawn.
    func setTitleDisplay(_ button: NSButton, _ word: String) {
        let checkbox = byView[ObjectIdentifier(button)]?.name == "ui-checkbox"
        switch word {
        case "visible": button.imagePosition = checkbox || button.image != nil ? .imageLeading : .noImage
        case "hidden": button.imagePosition = .imageOnly
        default: fatal("title display \(word) is not visible or hidden")
        }
    }

    // MARK: Constraints the host owns

    /// A side's `Length`: its size constraints, and how it hugs. `fill` hugs
    /// least, so the view takes its stack's spare room along the stack, and
    /// is stretched to the stack across it (`arrange`).
    func setLength(_ view: NSView, _ n: Node, _ axis: NSLayoutConstraint.Orientation, _ value: String?) {
        let word = value ?? "auto"
        let side = axis == .horizontal ? "width" : "height"
        var exact: CGFloat?
        var least: CGFloat?
        var most: CGFloat?
        var fills = false
        let parts = word.split(separator: ":").map(String.init)
        switch parts.first ?? "" {
        case "auto" where parts.count == 1: break
        case "fill" where parts.count == 1: fills = true
        case "fill-at-least" where parts.count == 2: fills = true; least = Host.points(parts[1], side)
        case "fixed" where parts.count == 2: exact = Host.points(parts[1], side)
        case "at-least" where parts.count == 2: least = Host.points(parts[1], side)
        case "at-most" where parts.count == 2: most = Host.points(parts[1], side)
        case "between" where parts.count == 3:
            least = Host.points(parts[1], side)
            most = Host.points(parts[2], side)
        default: fatal("\(side) \(word) is not in the grammar")
        }
        setSize(view, "\(side)-exact", exact)
        setSize(view, "\(side)-least", least)
        setSize(view, "\(side)-most", most)
        let natural = axis == .horizontal ? n.natural?.hugWidth : n.natural?.hugHeight
        view.setContentHuggingPriority(fills ? .init(1) : natural ?? .init(250), for: axis)
        if let parent = n.parent { markChildren(parent) }
        // Whether a stack is framed depends on its own lengths.
        if view is Stack { markChildren(n) }
    }

    /// Set (or, for nil, drop) one of a view's size constraints, by purpose:
    /// `KEY-exact`, `KEY-least` and `KEY-most` bound a side; `opening` is a
    /// scroll area's starting height, a preference.
    func setSize(_ view: NSView, _ key: String, _ value: CGFloat?, priority: NSLayoutConstraint.Priority = .required) {
        let id = ObjectIdentifier(view)
        constraints[id]?[key]?.isActive = false
        constraints[id]?[key] = nil
        guard let value else { return }
        let anchor = key.hasPrefix("width") ? view.widthAnchor : view.heightAnchor
        let c: NSLayoutConstraint
        if key.hasSuffix("-least") {
            c = anchor.constraint(greaterThanOrEqualToConstant: value)
        } else if key.hasSuffix("-most") {
            c = anchor.constraint(lessThanOrEqualToConstant: value)
        } else {
            c = anchor.constraint(equalToConstant: value)
        }
        c.priority = priority
        // A view its stack places by frame keeps the constraint for when
        // it is arranged again (Frames.swift).
        c.isActive = !framedViews.contains(id)
        constraints[id, default: [:]][key] = c
    }

    /// Stretch `view` across `stack` (its width in a vertical stack, its
    /// height in a horizontal one), inside the stack's padding, or stop.
    func setFill(_ view: NSView, in stack: NSStackView, _ on: Bool) {
        let id = ObjectIdentifier(view)
        if let c = constraints[id]?["fill"], !on || c.secondItem !== stack {
            c.isActive = false
            constraints[id]?["fill"] = nil
        }
        guard on else { return }
        let vertical = stack.orientation == .vertical
        let inset = vertical ? -(stack.edgeInsets.left + stack.edgeInsets.right) : -(stack.edgeInsets.top + stack.edgeInsets.bottom)
        if let c = constraints[id]?["fill"] {
            c.constant = inset
            c.isActive = true
        } else {
            let c = vertical
                ? view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: inset)
                : view.heightAnchor.constraint(equalTo: stack.heightAnchor, constant: inset)
            c.isActive = true
            constraints[id, default: [:]]["fill"] = c
        }
    }

    /// Note that `n`'s children or text changed, once per layout pass
    /// however many of them did (a list's million rows).
    func markChildren(_ n: Node) {
        if n.marked { return }
        n.marked = true
        dirty.append(n)
    }

    func markText(_ n: Node) { markChildren(n) }

    /// Bring every view touched by the batch up to date: a text-bearing
    /// control shows its subtree's text, a stack arranges its children's
    /// views, a list applies its row changes. Then size the window: to fit
    /// its content exactly, or, once it holds a scroll area or list, never
    /// smaller than its content needs (the scroll areas take the slack).
    /// A batch that changed no structure, text or layout attribute (a
    /// colour change, the common case of a hover or a timer) skips all of
    /// it: measuring the window rebuilds a constraint solver over every
    /// view, which at 10,000 views takes seconds.
    func sync() {
        guard relayout || !dirty.isEmpty else { return }
        relayout = false
        // Deepest first, so a stack is arranged after the stacks inside it
        // have decided whether they are framed and how big they are; one
        // that changes marks its parent, which a later round arranges.
        while !dirty.isEmpty {
            var seen = Set<ObjectIdentifier>()
            var owners: [(depth: Int, node: Node)] = []
            let pending = dirty
            dirty = []
            for start in pending { start.marked = false }
            for start in pending {
                // The nearest element with a view at or above the changed node.
                var cursor: Node? = start
                while let c = cursor, c.view == nil || c.name == nil { cursor = c.parent }
                guard let owner = cursor, seen.insert(ObjectIdentifier(owner)).inserted else { continue }
                var depth = 0
                var up = owner.parent
                while let u = up { depth += 1; up = u.parent }
                owners.append((depth, owner))
            }
            owners.sort { $0.depth > $1.depth }
            for (_, owner) in owners { refresh(owner) }
        }
        var unsettled: [Box] = []
        let flexibleNow = layoutPass(root, &unsettled)
        if let content = window.contentView {
            // Twice: the first pass gives wrapping labels their widths, and
            // with them their heights (`Label`).
            content.layoutSubtreeIfNeeded()
            content.layoutSubtreeIfNeeded()
            let fit = content.fittingSize
            let current = content.frame.size
            let height = flexibleNow && flexible ? max(fit.height, current.height) : fit.height
            let size = NSSize(width: max(fit.width, window.contentLayoutRect.width), height: height)
            if size != current { window.setContentSize(size) }
        }
        // The window now has room for each new scroll area's opening
        // height; from here on the window decides it.
        for box in unsettled {
            box.settled = true
            constraints[ObjectIdentifier(box)]?["opening"]?.priority = .init(49)
        }
        flexible = flexibleNow
    }

    /// Whether `n` holds a scroll area or list outside any other one. A
    /// vertical stack that does, and whose distribution is `gravity`, fills
    /// its height (`.fill`), so the scroll area, which hugs least, takes the
    /// slack; so does a stack with a child that fills along it. Any other
    /// keeps its children at their natural sizes (`.gravityAreas`).
    func layoutPass(_ n: Node, _ unsettled: inout [Box]) -> Bool {
        if let box = n.view as? Box {
            if !box.settled { unsettled.append(box) }
            return true
        }
        var any = false
        for child in n.children where child.name != nil {
            if layoutPass(child, &unsettled) { any = true }
        }
        if let stack = n.view as? NSStackView, (n.attrs["distribution"] ?? "gravity") == "gravity" {
            // A child that fills along the stack (a spacer, or a `fill`
            // width in a horizontal stack, height in a vertical one) takes
            // the stack's spare room: the stack fills (`.fill`) and the
            // child, which hugs least, grows.
            let along = stack.orientation == .vertical ? "height" : "width"
            let grows = n.children.compactMap(shownNode).contains { $0.name == "ui-spacer" || ($0.attrs[along] ?? "auto").hasPrefix("fill") }
            let distribution: NSStackView.Distribution = grows || (any && stack.orientation == .vertical) ? .fill : .gravityAreas
            if stack.distribution != distribution { stack.distribution = distribution }
        }
        return any
    }

    func refresh(_ owner: Node) {
        switch owner.view {
        case let stack as NSStackView:
            arrange(stack, owner)
        case let box as ScrollBox:
            arrange(box.stack, owner, fillAll: true)
        case let box as ListBox:
            box.finish(owner)
        case let surface as Surface:
            surface.hold(owner.children.first { $0.name != nil }.flatMap(shownView))
            // A framed box that gains or loses its child changes how its
            // stack places it (Frames.swift).
            if framedViews.contains(ObjectIdentifier(surface)), let parent = owner.parent { markChildren(parent) }
        case let button as NSButton where owner.name == "ui-button" || owner.name == "ui-file-button":
            button.title = owner.textContent
            setTitleDisplay(button, owner.attrs["title-display"] ?? "visible")
        case let label as NSTextField where !label.isEditable:
            label.stringValue = owner.textContent
        default:
            break
        }
    }

    /// Make `stack`'s arranged views exactly its node's children's views,
    /// and stretch across the stack each child that fills that way: every
    /// child when the stack's `align` is `fill`, else each whose `width` (in
    /// a vertical stack) or `height` (in a horizontal one) is a fill.
    func arrange(_ stack: NSStackView, _ owner: Node, fillAll: Bool = false) {
        // Fixed-size children are placed by frame (Frames.swift).
        if let stack = stack as? Stack {
            if let plan = framePlan(stack, owner) { placeByFrame(stack, owner, plan); return }
            unframe(stack, owner)
        }
        var fills: [ObjectIdentifier: Bool] = [:]
        let across = stack.orientation == .vertical ? "width" : "height"
        let all = fillAll || owner.attrs["align"] == "fill"
        let views: [NSView] = owner.children.compactMap { child in
            switch child.kind {
            case .element:
                guard let shown = shownNode(child), let v = shown.view else { return nil }
                fills[ObjectIdentifier(v)] = all || (shown.attrs[across] ?? "auto").hasPrefix("fill")
                return v
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
        for v in views { setFill(v, in: stack, fills[ObjectIdentifier(v)] ?? all) }
        // Spacers in one stack share its spare room equally, so two of them
        // centre what is between them.
        let spacers = owner.children.filter { $0.name == "ui-spacer" }.compactMap { $0.view }
        for (i, v) in spacers.enumerated() {
            let id = ObjectIdentifier(v)
            constraints[id]?["share"]?.isActive = false
            constraints[id]?["share"] = nil
            guard i > 0 else { continue }
            let c = stack.orientation == .horizontal
                ? v.widthAnchor.constraint(equalTo: spacers[0].widthAnchor)
                : v.heightAnchor.constraint(equalTo: spacers[0].heightAnchor)
            c.isActive = true
            constraints[id, default: [:]]["share"] = c
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
