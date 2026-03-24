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

        badgeLabel.font = .systemFont(ofSize: 12, weight: .regular)
        badgeLabel.textColor = .tertiaryLabelColor
        badgeLabel.alignment = .right
        badgeLabel.isBordered = false
        badgeLabel.drawsBackground = false

        appLabel.font = .systemFont(ofSize: 14, weight: .medium)
        appLabel.textColor = .labelColor
        appLabel.lineBreakMode = .byTruncatingTail

        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        for v in [iconView, badgeLabel, appLabel, titleLabel] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        let iconSize: CGFloat = 48
        let iconPad: CGFloat = 10
        let textX: CGFloat = 72

        iconView.frame = NSRect(x: iconPad, y: (h - iconSize) / 2, width: iconSize, height: iconSize)

        let textBlock: CGFloat = 20 + 2 + 17
        let base = (h - textBlock) / 2
        titleLabel.frame = NSRect(x: textX, y: base, width: bounds.width - 128, height: 17)
        appLabel.frame = NSRect(x: textX, y: base + 17 + 2, width: bounds.width - 128, height: 20)
        badgeLabel.frame = NSRect(x: bounds.width - 48, y: (h - 20) / 2, width: 32, height: 20)
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
            let rect = bounds.insetBy(dx: 0, dy: 1)
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28).fill()
        }
    }
}
