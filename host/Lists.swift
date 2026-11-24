// `ui-list`: a view-based NSTableView whose rows are the element's element
// children, as the engine inserts, removes and moves them.

import AppKit

/// The table keeps its own row model (`rows`) in step with the node tree:
/// each child insert, remove or move the engine commands is one
/// `insertRows`, `removeRows` or `moveRow` inside one `beginUpdates` per
/// batch. A batch that changes more than `bulkLimit` rows (a mount, a new
/// query, a `CLEAR`) instead reloads the table once from the node tree.
/// A row's own view is its cell view; the table creates nothing. A row
/// from a row template (`INST`) has no views until the table first asks
/// for it (`Host.realize`), so a list of thousands of rows creates views
/// only for the rows scrolled into sight.
///
/// A windowed list (`Ui.table_list`, which sets `window-start`) holds only
/// the rows of the engine's window: the engine draws `window` rows of its
/// view from `window-start` on and tells the list how many rows the view
/// keeps (`view-rows`). The table has that many rows; table row `i` is the
/// window's row `i - start`, and a row outside the window is a placeholder
/// until the window reaches it. As the visible rows near the window's edge
/// the list asks the engine for a new window (a `window` event, `start
/// count`), a screenful beyond the visible rows on each side, at most once
/// per pass of the run loop.
final class ListBox: Box, NSTableViewDataSource, NSTableViewDelegate {
    static let bulkLimit = 64
    /// The fewest rows a windowed list draws beyond the visible ones, on
    /// each side; a screenful when that is more.
    static let overscan = 20

    let table = NSTableView()
    unowned let host: Host
    /// The rows the list holds: every row, or a windowed list's window.
    private(set) var rows: [Node] = []
    private var cells: [ObjectIdentifier: (row: Node, cell: NSTableCellView)] = [:]

    /// Keep only the cells of rows `owner` still holds. A loop, not
    /// `cells.filter`: Swift 6.3 specializes Dictionary's rethrowing
    /// `filter` with typed-throws runtime calls.
    private func keepCells(of owner: Node) {
        var gone: [ObjectIdentifier] = []
        for (key, entry) in cells where entry.row.parent !== owner { gone.append(key) }
        for key in gone { cells.removeValue(forKey: key) }
    }
    private var updating = false
    private var bulk = false
    private var changes = 0
    /// Set while the host changes rows, so selection changes it causes are
    /// not reported as the user's.
    private var quiet = false

    // A windowed list (`window-start` set).
    private(set) var windowed = false
    /// The table row of the window's first row, and how many rows the
    /// view keeps (the table's row count).
    private(set) var start = 0
    private(set) var total = 0
    /// The row count the table was last told.
    private var shownTotal = 0
    /// The list element, which hears the `window` event.
    private weak var owner: Node?
    /// The window last asked for, so an answer that draws less than it
    /// (at the end of the view) is not asked again.
    private var asked: (start: Int, count: Int)?
    private var reportQueued = false
    /// A row the user selected outside the window: selected for the
    /// engine once the window holds it.
    private var pendingSelection: Int?
    /// A placeholder row's height: the first drawn row's.
    private var estimate = 0.0

    init(host: Host) {
        self.host = host
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.usesAutomaticRowHeights = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        documentView = table
        hasVerticalScroller = true
        autohidesScrollers = true
        borderType = .bezelBorder
    }

    required init?(coder: NSCoder) { fatal("ListBox is not archived") }

    // MARK: The window

    /// `window-start` on the list element: the list is windowed, and the
    /// engine's window starts at table row `at`.
    func windowStart(_ at: Int, owner n: Node) {
        windowed = true
        owner = n
        start = at
    }

    /// `view-rows`: how many rows the engine's view keeps.
    func viewRows(_ count: Int) { total = count }

    /// The node table row `i` shows, or nil for a placeholder.
    func node(at i: Int) -> Node? {
        let at = windowed ? i - start : i
        return at >= 0 && at < rows.count ? rows[at] : nil
    }

    /// The table row of the held row `n`.
    func index(of n: Node) -> Int? {
        rows.firstIndex(where: { $0 === n }).map { windowed ? $0 + start : $0 }
    }

    /// Ask, once this pass of the run loop is over, whether the window
    /// still covers the visible rows.
    func queueReport() {
        guard windowed, !reportQueued else { return }
        reportQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reportQueued = false
            self.report()
        }
    }

    /// Ask the engine for a window around the visible rows when they come
    /// within half the overscan of the window's edge (where the view goes
    /// on past it).
    private func report() {
        guard windowed, let owner, total > 0, !halted else { return }
        let visible = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { return }
        let first = visible.location, shown = visible.length
        let over = max(shown, ListBox.overscan)
        let end = start + rows.count
        let nearTop = start > 0 && first < start + over / 2
        let nearEnd = end < total && first + shown > end - over / 2
        guard nearTop || nearEnd else { return }
        let want = (start: max(first - over, 0), count: shown + 2 * over)
        if let asked, asked == want { return }
        asked = want
        host.dispatch("window", at: owner, text: "\(want.start) \(want.count)")
    }

    override func reflectScrolledClipView(_ clip: NSClipView) {
        super.reflectScrolledClipView(clip)
        queueReport()
    }

    // MARK: Row changes from the command stream

    /// Count one row change; false once the batch has become a reload.
    private func begin() -> Bool {
        changes += 1
        if changes > ListBox.bulkLimit || windowed { bulk = true }
        if bulk { return false }
        if !updating {
            quiet = true
            table.beginUpdates()
            updating = true
        }
        return true
    }

    /// The row index of element child `n` of `parent`.
    private func index(of n: Node, in parent: Node) -> Int {
        var i = 0
        for child in parent.children {
            if child === n { return i }
            if child.name != nil { i += 1 }
        }
        return i
    }

    func inserted(_ n: Node, in parent: Node) {
        guard n.name != nil, begin() else { return }
        let at = index(of: n, in: parent)
        rows.insert(n, at: at)
        table.insertRows(at: IndexSet(integer: at), withAnimation: [])
    }

    func removed(_ n: Node) {
        guard n.name != nil, begin(), let at = rows.firstIndex(where: { $0 === n }) else { return }
        rows.remove(at: at)
        cells.removeValue(forKey: ObjectIdentifier(n))
        table.removeRows(at: IndexSet(integer: at), withAnimation: [])
    }

    func moved(_ n: Node, in parent: Node) {
        guard n.name != nil, begin(), let from = rows.firstIndex(where: { $0 === n }) else { return }
        rows.remove(at: from)
        let to = index(of: n, in: parent)
        rows.insert(n, at: to)
        table.moveRow(at: from, to: to)
    }

    func cleared() { bulk = true }

    /// End the batch: close the updates, or reload from the node tree.
    func finish(_ owner: Node) {
        if updating {
            table.endUpdates()
            updating = false
        }
        if windowed {
            quiet = true
            rows = owner.children.filter { $0.name != nil }
            keepCells(of: owner)
            if shownTotal != total {
                // The view kept more or fewer rows: the table's rows are new.
                shownTotal = total
                table.reloadData()
            } else {
                // The window moved or its rows changed: redraw the rows the
                // table holds views for (those in sight and the few it
                // prepared around them) whose row is not the one shown.
                let visible = table.rows(in: table.visibleRect)
                let from = max(visible.location - visible.length - 4, 0)
                let to = min(visible.location + 2 * visible.length + 4, shownTotal)
                for i in from..<max(to, from) {
                    guard let shown = table.view(atColumn: 0, row: i, makeIfNecessary: false) else { continue }
                    let stale: Bool
                    if let n = node(at: i) { stale = shown !== cells[ObjectIdentifier(n)]?.cell } else { stale = shown.identifier != ListBox.placeholderID }
                    if stale {
                        table.reloadData(forRowIndexes: IndexSet(integer: i), columnIndexes: IndexSet(integer: 0))
                    }
                }
            }
            quiet = false
            bulk = false
            changes = 0
            if let p = pendingSelection, let n = node(at: p) {
                pendingSelection = nil
                if table.selectedRow == p { DispatchQueue.main.async { [weak self] in self?.host.dispatch("select", at: n) } }
            }
            queueReport()
            return
        }
        if bulk {
            quiet = true
            rows = owner.children.filter { $0.name != nil }
            // Only the rows that were shown have cells: keep those still here.
            keepCells(of: owner)
            table.reloadData()
        }
        bulk = false
        changes = 0
        quiet = false
    }

    // MARK: Data source and delegate

    func numberOfRows(in tableView: NSTableView) -> Int { windowed ? shownTotal : rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let n = node(at: row) else { return placeholder() }
        if let held = cells[ObjectIdentifier(n)] { return held.cell }
        if n.view == nil { host.realize(n) }
        let cell = NSTableCellView()
        if let view = n.view {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                view.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
                view.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                view.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            ])
        }
        if windowed, estimate == 0 {
            // Placeholders and rows not yet measured take the first drawn
            // row's height, so the scroller is sized for rows like it.
            let fitting = Double(cell.fittingSize.height)
            estimate = fitting > 16 ? fitting : 16
            table.rowHeight = CGFloat(estimate)
        }
        cells[ObjectIdentifier(n)] = (n, cell)
        return cell
    }

    func tableViewSelectionDidChange(_ note: Notification) {
        guard !quiet, !host.applying else { return }
        let at = table.selectedRow
        guard at >= 0 else { return }
        if let n = node(at: at) {
            pendingSelection = nil
            host.dispatch("select", at: n)
        } else if windowed {
            pendingSelection = at
            queueReport()
        }
    }

    static let placeholderID = NSUserInterfaceItemIdentifier("placeholder")

    /// A row outside the window, until the window reaches it: an empty
    /// cell as high as the rows drawn.
    private func placeholder() -> NSView {
        let cell = NSTableCellView()
        cell.identifier = ListBox.placeholderID
        cell.heightAnchor.constraint(equalToConstant: CGFloat(estimate > 0 ? estimate : 24)).isActive = true
        return cell
    }

    /// Scroll so that row `k` is at the top of the visible rows.
    func scroll(toRow k: Int) {
        let y = table.rect(ofRow: k).origin.y
        contentView.scroll(to: NSPoint(x: 0, y: y))
        reflectScrolledClipView(contentView)
    }

    /// Select table row `at` as the user would.
    func select(row at: Int) {
        table.scrollRowToVisible(at)
        table.selectRowIndexes(IndexSet(integer: at), byExtendingSelection: false)
    }

    /// Select the row `n` as the user would.
    func select(_ n: Node) {
        guard let at = index(of: n) else { return }
        select(row: at)
    }
}

extension Host {
    /// Give a list row that has none its views, with every attribute and
    /// text the engine has set on it so far.
    func realize(_ row: Node) {
        materialize(row)
        row.walk { n in
            makeView(n)
            n.attrs.forEach { applyAttr(n, $0.key, $0.value) }
        }
        row.walk { n in if n.view != nil, n.name != nil { refresh(n) } }
    }
}
