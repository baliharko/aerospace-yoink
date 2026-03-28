import AppKit

@MainActor
public class YoinkController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let panel: YoinkPanel
    private let searchField: NSTextField
    private let tableView: NSTableView
    private var scrollTopHidden: NSLayoutConstraint!
    private var scrollTopVisible: NSLayoutConstraint!
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var maxTableHeight: CGFloat = 0

    private let searchChrome = Layout.Search.topPad + Layout.Search.height
        + Layout.Search.gapToList + Layout.Scroll.bottomPad
    private let searchOnlyChrome = Layout.Search.topPad + Layout.Search.height
        + Layout.Search.bottomPad
    private let listOnlyChrome = Layout.Scroll.topPad + Layout.Scroll.bottomPad

    private var workspace = ""
    private var allWindows: [AeroWindow] = []
    private var filtered: [AeroWindow] = []
    private var keyMonitor: Any?
    private var resignObserver: Any?

    private let config: Config
    private let stack: YoinkStack
    private let pid: pid_t
    private var pollTimer: DispatchSourceTimer?
    private var focusAfterYoink = false
    private var previouslyFocusedWindowId: Int?
    private var previousApp: NSRunningApplication?

    public init(config: Config, stack: YoinkStack, pid: pid_t) {
        self.config = config
        self.stack = stack
        self.pid = pid
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

        // Search field — hidden until user types
        searchField = CenteredTextField()
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
        let scroll = Self.makeScrollView()
        tableView = Self.makeTableView()
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

        startPollTimerIfNeeded()

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
    public func activate(focus: Bool = false) {
        if panel.isVisible {
            hide()
            return
        }
        focusAfterYoink = focus
        searchField.stringValue = ""
        searchField.isHidden = true
        scrollTopVisible.isActive = false
        scrollTopHidden.isActive = true

        Task.detached { [weak self] in
            let (ws, wins, focusedId) = Aerospace.fetchWindows()
            await MainActor.run { [weak self] in
                guard let self, !wins.isEmpty else { return }

                previouslyFocusedWindowId = focusedId
                workspace = ws
                allWindows = wins
                filtered = wins
                tableView.reloadData()
                if !filtered.isEmpty {
                    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }

                recalculateMaxTableHeight()
                resizePanelForRows()

                // Only save previousApp if there was a focused window — on an empty
                // workspace, frontmostApplication points to another workspace's app
                // and restoring it would yank focus away.
                previousApp = focusedId != nil ? NSWorkspace.shared.frontmostApplication : nil
                panel.alphaValue = 0
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = self.config.fadeIn
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.panel.animator().alphaValue = 1
                }
            }
        }
    }

    public func hide(restoreFocus: Bool = true, then completion: (@MainActor () -> Void)? = nil) {
        let appToRestore = restoreFocus ? previousApp : nil
        previousApp = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = config.fadeOut
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.orderOut(nil)
                appToRestore?.activate()
                completion?()
            }
        })
    }

    // MARK: - Layout

    private static func makeScrollView() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        scroll.verticalScrollElasticity = .none
        scroll.contentView.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = false
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = .clear
        scroll.contentView.wantsLayer = true
        scroll.contentView.layer?.backgroundColor = .clear
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.scrollerInsets = NSEdgeInsetsZero
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }

    private static func makeTableView() -> NSTableView {
        let tv = NSTableView()
        tv.backgroundColor = .clear
        tv.wantsLayer = true
        tv.layer?.backgroundColor = .clear
        tv.headerView = nil
        tv.rowHeight = Layout.Row.height
        tv.intercellSpacing = NSSize(width: 0, height: 0)
        tv.selectionHighlightStyle = .regular
        tv.gridStyleMask = []
        tv.style = .plain
        let col = NSTableColumn(identifier: .init("main"))
        col.resizingMask = .autoresizingMask
        tv.addTableColumn(col)
        tv.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tv.sizeLastColumnToFit()
        return tv
    }

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
        let emptySearch = filtered.isEmpty && !searchField.isHidden
        let chrome = searchField.isHidden ? listOnlyChrome
            : emptySearch ? searchOnlyChrome : searchChrome
        let rowCount = CGFloat(emptySearch ? 0 : max(filtered.count, 1))
        let neededTableHeight = min(rowCount * Layout.Row.height, maxTableHeight)
        scrollHeightConstraint.constant = neededTableHeight
        tableView.enclosingScrollView?.isHidden = neededTableHeight == 0

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w = YoinkController.panelWidth(for: screen)
        let h = neededTableHeight + chrome
        let maxH = maxTableHeight + searchChrome
        let topY = screen.frame.midY + maxH / 2 + screen.frame.height * Layout.Panel.verticalOffsetRatio
        let frame = NSRect(
            x: screen.frame.midX - w / 2,
            y: topY - h,
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
        let restoreId = previouslyFocusedWindowId
        let focus = focusAfterYoink
        let ws = workspace
        stack.push(windowId: win.id, originWorkspace: win.workspace, destinationWorkspace: ws)
        stack.save(pid: pid)
        startPollTimerIfNeeded()
        hide(restoreFocus: !focus) {
            // Run aerospace commands off the main thread (they shell out synchronously)
            DispatchQueue.global().async {
                Aerospace.yoink(win.id, to: ws, focus: focus)
                if !focus, let restoreId {
                    Aerospace.run(["focus", "--window-id", "\(restoreId)"])
                }
            }
        }
    }

    /// Pop the most recently yoinked window and send it back to its origin.
    public func yeet() {
        guard let entry = stack.pop() else { return }
        Aerospace.yoink(entry.windowId, to: entry.originWorkspace, focus: false)
        stack.save(pid: pid)
        stopPollTimerIfEmpty()
    }

    // MARK: - Stack Polling

    private func startPollTimerIfNeeded() {
        guard !stack.isEmpty, pollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            self?.pollWindowLocations()
        }
        pollTimer = timer
        timer.resume()
    }

    private func stopPollTimerIfEmpty() {
        guard stack.isEmpty, let timer = pollTimer else { return }
        timer.cancel()
        pollTimer = nil
    }

    private func pollWindowLocations() {
        Task.detached {
            let locations = Aerospace.listAllWindowLocations()
            let locationMap = Dictionary(locations.map { ($0.windowId, $0.workspace) },
                                         uniquingKeysWith: { first, _ in first })
            await MainActor.run { [weak self] in
                guard let self else { return }
                var changed = false
                for entry in self.stack.entries {
                    let actual = locationMap[entry.windowId]
                    // Remove if window no longer exists or moved away from destination
                    if actual == nil || actual != entry.destinationWorkspace {
                        self.stack.remove(windowId: entry.windowId)
                        changed = true
                    }
                }
                if changed {
                    self.stack.save(pid: self.pid)
                    self.stopPollTimerIfEmpty()
                }
            }
        }
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
               event.modifierFlags.isDisjoint(with: [.command, .control]) {
                showSearch()
                panel.makeFirstResponder(searchField)
            }
            return event
        }
    }

    // MARK: - NSTableViewDataSource

    public func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    // MARK: - NSTableViewDelegate

    public func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tv.makeView(withIdentifier: id, owner: nil) as? WindowCell ?? {
            let c = WindowCell(frame: .zero)
            c.identifier = id
            return c
        }()
        cell.configure(filtered[row])
        return cell
    }

    public func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WindowRowView()
    }

    // MARK: - NSTextFieldDelegate

    public func controlTextDidChange(_ obj: Notification) {
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
