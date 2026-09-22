import AppKit

class CenteredTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        titleRect.origin.y = rect.origin.y + (rect.height - textHeight) / 2
        titleRect.size.height = textHeight
        return titleRect
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }
}

class CenteredTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { CenteredTextFieldCell.self }
        set {}
    }
}

class YoinkPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension YoinkController {
    static func makeScrollView() -> NSScrollView {
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

    static func makeTableView() -> NSTableView {
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
}

extension YoinkController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

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
        let id = NSUserInterfaceItemIdentifier("row")
        if let reused = tv.makeView(withIdentifier: id, owner: nil) as? WindowRowView {
            return reused
        }
        let rowView = WindowRowView()
        rowView.identifier = id
        return rowView
    }
}

class WindowCell: NSTableCellView {
    private let iconView = NSImageView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)

        iconView.imageScaling = .scaleProportionallyUpOrDown

        badgeLabel.font = .systemFont(ofSize: Layout.Font.badge, weight: .regular)
        badgeLabel.textColor = .tertiaryLabelColor
        badgeLabel.alignment = .right
        badgeLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.isBordered = false
        badgeLabel.drawsBackground = false

        appLabel.font = .systemFont(ofSize: Layout.Font.appName, weight: .medium)
        appLabel.textColor = .labelColor
        appLabel.lineBreakMode = .byTruncatingTail

        titleLabel.font = .systemFont(ofSize: Layout.Font.title, weight: .regular)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        for v in [iconView, badgeLabel, appLabel, titleLabel] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height

        iconView.frame = NSRect(
            x: Layout.Icon.leadingPad,
            y: (h - Layout.Icon.size) / 2,
            width: Layout.Icon.size,
            height: Layout.Icon.size
        )

        // The badge hugs the trailing edge and widens for long workspace
        // names; the app and title labels get the space left of it. cellSize,
        // unlike intrinsicContentSize, includes the label's own padding.
        let fitted = ceil(badgeLabel.cell?.cellSize.width ?? 0)
        let badgeWidth = min(max(fitted, Layout.Badge.minWidth), Layout.Badge.maxWidth)
        badgeLabel.frame = NSRect(
            x: bounds.width - Layout.Badge.trailingPad - badgeWidth,
            y: (h - Layout.Badge.height) / 2,
            width: badgeWidth,
            height: Layout.Badge.height
        )
        let textWidth = badgeLabel.frame.minX - Layout.Badge.gap - Layout.Text.leadingX

        let textBlock = Layout.Text.appLabelHeight + Layout.Text.labelGap + Layout.Text.titleLabelHeight
        let base = (h - textBlock) / 2
        titleLabel.frame = NSRect(
            x: Layout.Text.leadingX, y: base,
            width: textWidth,
            height: Layout.Text.titleLabelHeight
        )
        appLabel.frame = NSRect(
            x: Layout.Text.leadingX,
            y: base + Layout.Text.titleLabelHeight + Layout.Text.labelGap,
            width: textWidth,
            height: Layout.Text.appLabelHeight
        )
    }

    func configure(_ w: AeroWindow) {
        iconView.image = w.icon
        badgeLabel.stringValue = w.workspace
        appLabel.stringValue = w.appName
        titleLabel.stringValue = w.title
        needsLayout = true // the badge width depends on the workspace name
    }
}

class WindowRowView: NSTableRowView {
    override var isOpaque: Bool { false }

    override func drawBackground(in dirtyRect: NSRect) {
        // Don't draw row background — let the glass show through.
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let rect = bounds.insetBy(dx: 0, dy: Layout.Row.selectionInsetY)
            NSColor.labelColor.withAlphaComponent(Layout.Row.selectionAlpha).setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: Layout.Row.selectionCornerRadius,
                yRadius: Layout.Row.selectionCornerRadius
            ).fill()
        }
    }
}
