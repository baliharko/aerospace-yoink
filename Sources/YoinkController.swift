import AppKit

@MainActor
class YoinkController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let panel: YoinkPanel
    private let searchField: NSTextField
    private let tableView: NSTableView
    private var scrollTopHidden: NSLayoutConstraint!
    private var scrollTopVisible: NSLayoutConstraint!
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var maxTableHeight: CGFloat = 0

    private let searchChrome = Layout.Search.topPad + Layout.Search.height
        + Layout.Search.gapToList + Layout.Scroll.bottomPad
    private let listOnlyChrome = Layout.Scroll.topPad + Layout.Scroll.bottomPad

    private var workspace = ""
    private var allWindows: [AeroWindow] = []
    private var filtered: [AeroWindow] = []
    private var keyMonitor: Any?
    private var resignObserver: Any?

    override init() {
        panel = YoinkPanel(
            contentRect: .zero,
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

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true

        // Search field — hidden until user types
        searchField = NSTextField()
        searchField.font = .systemFont(ofSize: Layout.Search.fontSize)
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
                    .font: NSFont.systemFont(ofSize: Layout.Search.fontSize),
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
        tableView.rowHeight = Layout.Row.height
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
        scrollTopHidden = scroll.topAnchor.constraint(equalTo: content.topAnchor,
            constant: Layout.Scroll.topPad)
        scrollTopVisible = scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor,
            constant: Layout.Search.gapToList)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor,
                constant: Layout.Search.topPad),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                constant: Layout.Search.leadingPad),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                constant: -Layout.Search.trailingPad),
            searchField.heightAnchor.constraint(equalToConstant: Layout.Search.height),

            scrollTopHidden,
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                constant: Layout.Scroll.sidePad),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                constant: -Layout.Scroll.sidePad),
        ])
        scrollHeightConstraint = scroll.heightAnchor.constraint(equalToConstant: 0)
        scrollHeightConstraint.isActive = true

        // Liquid Glass
        let glass = NSGlassEffectView()
        glass.contentView = content
        glass.cornerRadius = Layout.Panel.cornerRadius

        panel.contentView = glass
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = Layout.Panel.cornerRadiusClip
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
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    // MARK: - Panel Lifecycle

    /// Toggle panel — show if hidden, hide if visible
    func activate() {
        if panel.isVisible {
            hide()
            return
        }
        searchField.stringValue = ""
        searchField.isHidden = true
        scrollTopVisible.isActive = false
        scrollTopHidden.isActive = true

        Task.detached { [weak self] in
            let (ws, wins) = Aerospace.fetchWindows()
            await MainActor.run { [weak self] in
                guard let self, !wins.isEmpty else { return }

                workspace = ws
                allWindows = wins
                filtered = wins
                tableView.reloadData()
                if !filtered.isEmpty {
                    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }

                recalculateMaxTableHeight()
                resizePanelForRows()

                panel.alphaValue = 0
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Layout.Animation.fadeIn
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.panel.animator().alphaValue = 1
                }
            }
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Layout.Animation.fadeOut
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.orderOut(nil) }
        })
    }

    // MARK: - Layout

    private static func panelWidth(for screen: NSScreen) -> CGFloat {
        min(Layout.Panel.maxWidth, screen.frame.width * Layout.Panel.screenWidthRatio)
    }

    private func recalculateMaxTableHeight() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let availableHeight = min(Layout.Panel.maxTableHeight,
            screen.frame.height * Layout.Panel.screenHeightRatio) - listOnlyChrome
        maxTableHeight = floor(availableHeight / Layout.Row.height) * Layout.Row.height
    }

    private func resizePanelForRows() {
        let chrome = searchField.isHidden ? listOnlyChrome : searchChrome
        let rowCount = CGFloat(max(filtered.count, 1))
        let neededTableHeight = min(rowCount * Layout.Row.height, maxTableHeight)
        scrollHeightConstraint.constant = neededTableHeight

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w = YoinkController.panelWidth(for: screen)
        let h = neededTableHeight + chrome
        let frame = NSRect(
            x: screen.frame.midX - w / 2,
            y: screen.frame.midY - h / 2 + screen.frame.height * Layout.Panel.verticalOffsetRatio,
            width: w,
            height: h
        )
        panel.setFrame(frame, display: true)
    }

    // MARK: - Actions

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
            let targetY = CGFloat(row) * Layout.Row.height
            clipView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
        } else if rowRect.origin.y + Layout.Row.height > currentY + visibleHeight {
            let targetY = CGFloat(row + 1) * Layout.Row.height - visibleHeight
            clipView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
        }
    }

    // MARK: - Search

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

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case KeyCode.escape:
            if !searchField.stringValue.isEmpty {
                hideSearch()
                return nil
            }
            hide(); return nil
        case KeyCode.returnKey, KeyCode.enter:
            yoinkSelected(); return nil
        case KeyCode.downArrow:
            let next = min(tableView.selectedRow + 1, filtered.count - 1)
            if next >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                scrollToRow(next)
            }
            return nil
        case KeyCode.upArrow:
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
