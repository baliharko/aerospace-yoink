import AppKit

class YoinkPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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

        let textBlock = Layout.Text.appLabelHeight + Layout.Text.labelGap + Layout.Text.titleLabelHeight
        let base = (h - textBlock) / 2
        titleLabel.frame = NSRect(
            x: Layout.Text.leadingX, y: base,
            width: bounds.width - Layout.Text.trailingMargin,
            height: Layout.Text.titleLabelHeight
        )
        appLabel.frame = NSRect(
            x: Layout.Text.leadingX,
            y: base + Layout.Text.titleLabelHeight + Layout.Text.labelGap,
            width: bounds.width - Layout.Text.trailingMargin,
            height: Layout.Text.appLabelHeight
        )
        badgeLabel.frame = NSRect(
            x: bounds.width - Layout.Badge.trailingOffset,
            y: (h - Layout.Badge.height) / 2,
            width: Layout.Badge.width,
            height: Layout.Badge.height
        )
    }

    func configure(_ w: AeroWindow) {
        iconView.image = w.icon
        badgeLabel.stringValue = w.workspace
        appLabel.stringValue = w.appName
        titleLabel.stringValue = w.title
    }
}

class WindowRowView: NSTableRowView {
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
