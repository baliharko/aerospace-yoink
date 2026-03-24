import AppKit

class YoinkController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let panel: YoinkPanel
    private let searchField: NSTextField
    private let tableView: NSTableView
    private var scrollTopHidden: NSLayoutConstraint!
    private var scrollTopVisible: NSLayoutConstraint!
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var maxTableHeight: CGFloat = 0
    private let rowHeight: CGFloat = 68
    private let searchChrome: CGFloat = 24 + 48 + 12 + 20  // top pad + search + gap + bottom pad
    private let listOnlyChrome: CGFloat = 20 + 20  // top pad + bottom pad
    private let glassCornerRadius: CGFloat = 44
    private var workspace = ""
    private var allWindows: [AeroWindow] = []
    private var filtered: [AeroWindow] = []
    private var keyMonitor: Any?
    private var resignObserver: Any?

    override init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w = YoinkController.panelWidth(for: screen)

        let maxHeight = min(500, screen.frame.height * 0.45) - listOnlyChrome
        let visibleRows = floor(maxHeight / rowHeight)
        maxTableHeight = visibleRows * rowHeight
        let h = maxTableHeight + listOnlyChrome

        let origin = NSPoint(
            x: screen.frame.midX - w / 2,
            y: screen.frame.midY - h / 2 + screen.frame.height * 0.08
        )

        panel = YoinkPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: w, height: h)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true

        // Content wrapper with Auto Layout
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true

        // Search field — hidden until user types
        searchField = NSTextField()
        searchField.font = .systemFont(ofSize: 24)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.textColor = .labelColor
        searchField.focusRingType = .none
        searchField.isHidden = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        if let cell = searchField.cell as? NSTextFieldCell {
            cell.placeholderAttributedString = NSAttributedString(
                string: "Filter...",
                attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 24),
                ]
            )
        }
        content.addSubview(searchField)

        // Table
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        scroll.verticalScrollElasticity = .none
        scroll.contentView.postsBoundsChangedNotifications = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.scrollerInsets = NSEdgeInsetsZero
        scroll.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.gridStyleMask = []
        tableView.style = .plain
        let col = NSTableColumn(identifier: .init("main"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.sizeLastColumnToFit()
        scroll.documentView = tableView
        content.addSubview(scroll)

        // Toggleable constraints for search visible/hidden
        scrollTopHidden = scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 20)
        scrollTopVisible = scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            searchField.heightAnchor.constraint(equalToConstant: 48),

            scrollTopHidden,  // active by default — list starts at top
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
        ])
        scrollHeightConstraint = scroll.heightAnchor.constraint(equalToConstant: maxTableHeight)
        scrollHeightConstraint.isActive = true

        // Liquid Glass
        let glass = NSGlassEffectView()
        glass.contentView = content
        glass.cornerRadius = glassCornerRadius

        panel.contentView = glass
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = glassCornerRadius + 2
        panel.contentView?.layer?.masksToBounds = true

        super.init()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(doubleClicked)
        tableView.target = self
        searchField.delegate = self

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in
            self?.handleKey($0)
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
    }

    private static func panelWidth(for screen: NSScreen) -> CGFloat {
        min(760, screen.frame.width * 0.45)
    }

    /// Show panel immediately, fetch data in background
    func activate() {
        searchField.stringValue = ""
        searchField.isHidden = true
        scrollTopVisible.isActive = false
        scrollTopHidden.isActive = true

        // Recalculate dimensions for the current screen
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w = YoinkController.panelWidth(for: screen)
        let maxHeight = min(500, screen.frame.height * 0.45) - listOnlyChrome
        let visibleRows = floor(maxHeight / rowHeight)
        maxTableHeight = visibleRows * rowHeight
        scrollHeightConstraint.constant = maxTableHeight

        let h = maxTableHeight + listOnlyChrome
        let panelFrame = NSRect(
            x: screen.frame.midX - w / 2,
            y: screen.frame.midY - h / 2 + screen.frame.height * 0.08,
            width: w,
            height: h
        )
        panel.setFrame(panelFrame, display: false)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Fetch aerospace data in background
        DispatchQueue.global().async { [self] in
            let (ws, wins) = Aerospace.fetchWindows()
            DispatchQueue.main.async { [self] in
                if wins.isEmpty {
                    hide()
                    return
                }
                workspace = ws
                allWindows = wins
                filtered = wins
                tableView.reloadData()
                if !filtered.isEmpty {
                    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
                resizePanelForRows()
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    @objc private func doubleClicked() {
        yoinkSelected()
    }

    private func yoinkSelected() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < filtered.count else { return }
        let win = filtered[tableView.selectedRow]
        hide()
        Aerospace.yoink(win.id, to: workspace)
    }

    private func scrollToRow(_ row: Int) {
        guard let clipView = tableView.enclosingScrollView?.contentView else { return }
        let rowRect = tableView.rect(ofRow: row)
        let visibleHeight = clipView.bounds.height
        let currentY = clipView.bounds.origin.y

        if rowRect.origin.y < currentY {
            let targetY = CGFloat(row) * rowHeight
            clipView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
        } else if rowRect.origin.y + rowHeight > currentY + visibleHeight {
            let targetY = CGFloat(row + 1) * rowHeight - visibleHeight
            clipView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
        }
    }

    private func resizePanelForRows() {
        let chrome = searchField.isHidden ? listOnlyChrome : searchChrome
        let rowCount = CGFloat(max(filtered.count, 1))
        let neededTableHeight = min(rowCount * rowHeight, maxTableHeight)
        scrollHeightConstraint.constant = neededTableHeight

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let h = neededTableHeight + chrome
        let frame = NSRect(
            x: screen.frame.midX - panel.frame.width / 2,
            y: screen.frame.midY - h / 2 + screen.frame.height * 0.08,
            width: panel.frame.width,
            height: h
        )
        panel.setFrame(frame, display: true)
    }

    private func showSearch() {
        guard searchField.isHidden else { return }
        searchField.isHidden = false
        scrollTopHidden.isActive = false
        scrollTopVisible.isActive = true
        resizePanelForRows()
    }

    private func hideSearch() {
        guard !searchField.isHidden else { return }
        searchField.stringValue = ""
        searchField.isHidden = true
        scrollTopVisible.isActive = false
        scrollTopHidden.isActive = true

        filtered = allWindows
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            scrollToRow(0)
        }
        resizePanelForRows()
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case 53:  // Escape
            if !searchField.stringValue.isEmpty {
                hideSearch()
                return nil
            }
            hide(); return nil
        case 36, 76:  // Return / Enter
            yoinkSelected(); return nil
        case 125:  // Down arrow
            let next = min(tableView.selectedRow + 1, filtered.count - 1)
            if next >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                scrollToRow(next)
            }
            return nil
        case 126:  // Up arrow
            let prev = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
            scrollToRow(prev)
            return nil
        default:
            if searchField.isHidden,
               let chars = event.characters, !chars.isEmpty,
               event.modifierFlags.intersection([.command, .control]).isEmpty {
                showSearch()
                panel.makeFirstResponder(searchField)
            }
            return event
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tv.makeView(withIdentifier: id, owner: nil) as? WindowCell ?? {
            let c = WindowCell(frame: .zero)
            c.identifier = id
            return c
        }()
        cell.configure(filtered[row])
        return cell
    }

    func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WindowRowView()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        let q = searchField.stringValue
        if q.isEmpty {
            hideSearch()
            return
        }
        filtered = allWindows.filter { $0.matches(q) }
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            scrollToRow(0)
        }
        resizePanelForRows()
    }
}
