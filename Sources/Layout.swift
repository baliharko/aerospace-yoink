import CoreGraphics

enum Layout {
    enum Panel {
        static let maxWidth: CGFloat = 760
        static let screenWidthRatio: CGFloat = 0.45
        static let screenHeightRatio: CGFloat = 0.45
        static let maxTableHeight: CGFloat = 500
        static let verticalOffsetRatio: CGFloat = 0.08
        static let cornerRadius: CGFloat = 44
        static let cornerRadiusClip: CGFloat = cornerRadius + 2
    }

    enum Row {
        static let height: CGFloat = 68
        static let selectionInsetY: CGFloat = 1
        static let selectionCornerRadius: CGFloat = 28
        static let selectionAlpha: CGFloat = 0.1
    }

    enum Icon {
        static let size: CGFloat = 48
        static let leadingPad: CGFloat = 10
    }

    enum Text {
        static let leadingX: CGFloat = 72
        static let trailingMargin: CGFloat = 128
        static let appLabelHeight: CGFloat = 20
        static let titleLabelHeight: CGFloat = 17
        static let labelGap: CGFloat = 2
    }

    enum Badge {
        static let trailingOffset: CGFloat = 48
        static let width: CGFloat = 32
        static let height: CGFloat = 20
    }

    enum Search {
        static let fontSize: CGFloat = 24
        static let height: CGFloat = 48
        static let topPad: CGFloat = 24
        static let leadingPad: CGFloat = 32
        static let trailingPad: CGFloat = 20
        static let gapToList: CGFloat = 12
    }

    enum Scroll {
        static let topPad: CGFloat = 20
        static let sidePad: CGFloat = 16
        static let bottomPad: CGFloat = 20
    }

    enum Font {
        static let badge: CGFloat = 12
        static let appName: CGFloat = 14
        static let title: CGFloat = 12
    }

    enum Animation {
        static let fadeIn: CGFloat = 0.1
        static let fadeOut: CGFloat = 0.08
    }
}

enum KeyCode {
    static let escape = 53
    static let returnKey = 36
    static let enter = 76
    static let downArrow = 125
    static let upArrow = 126
}
