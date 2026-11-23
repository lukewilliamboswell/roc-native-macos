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
final class ListBox: Box, NSTableViewDataSource, NSTableViewDelegate {
    static let bulkLimit = 64

    let table = NSTableView()
    unowned let host: Host
    private(set) var rows: [Node] = []
    private var cells: [ObjectIdentifier: (row: Node, cell: NSTableCellView)] = [:]
    private var updating = false
    private var bulk = false
    private var changes = 0
    /// Set while the host changes rows, so selection changes it causes are
    /// not reported as the user's.
    private var quiet = false

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

    // MARK: Row changes from the command stream

    /// Count one row change; false once the batch has become a reload.
    private func begin() -> Bool {
        changes += 1
        if changes > ListBox.bulkLimit { bulk = true }
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
        if bulk {
            quiet = true
            rows = owner.children.filter { $0.name != nil }
            // Only the rows that were shown have cells: keep those still here.
            cells = cells.filter { $0.value.row.parent === owner }
            table.reloadData()
        }
        bulk = false
        changes = 0
        quiet = false
    }

    // MARK: Data source and delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let n = rows[row]
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
        cells[ObjectIdentifier(n)] = (n, cell)
        return cell
    }

    func tableViewSelectionDidChange(_ note: Notification) {
        guard !quiet, !host.applying else { return }
        let at = table.selectedRow
        if at >= 0, at < rows.count { host.dispatch("select", at: rows[at]) }
    }

    /// Scroll so that row `k` is at the top of the visible rows.
    func scroll(toRow k: Int) {
        let y = table.rect(ofRow: k).origin.y
        contentView.scroll(to: NSPoint(x: 0, y: y))
        reflectScrolledClipView(contentView)
    }

    /// Select the row `n` as the user would.
    func select(_ n: Node) {
        guard let at = rows.firstIndex(where: { $0 === n }) else { return }
        table.scrollRowToVisible(at)
        table.selectRowIndexes(IndexSet(integer: at), byExtendingSelection: false)
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
