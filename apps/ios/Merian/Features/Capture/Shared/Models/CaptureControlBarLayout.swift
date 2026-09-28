import CoreGraphics

enum CaptureControlBarLayout {
    static let primaryControlSize: CGFloat = 80
    static let bottomInset: CGFloat = 124
    static let reservedHeight = primaryControlSize + bottomInset

    /// Preserves the full-screen overlay position used before capture-bar
    /// measurement was removed. Full-screen pager geometry reports a zero
    /// bottom safe-area inset, so this value must not be derived from that proxy.
    static let fullScreenOverlayClearance: CGFloat = 250

    /// Keeps the Describe editor above the fixed control row. Matching the
    /// row's actual reserved height lets the flexible editor fill the available
    /// space; its own 24 pt bottom padding provides the visual separation.
    static let describeContentBottomClearance = reservedHeight
}

/// Only the width-dependent staging tray reports a height. Capture controls and
/// UIKit-hosted Describe content consume this value without feeding back into it.
struct CaptureChromeLayout: Equatable {
    var toolbarHeight: CGFloat = 0

    var bottomInset: CGFloat {
        max(CaptureControlBarLayout.bottomInset, toolbarHeight + 16)
    }
    var reservedHeight: CGFloat { CaptureControlBarLayout.primaryControlSize + bottomInset }
    var fullScreenOverlayClearance: CGFloat {
        CaptureControlBarLayout.fullScreenOverlayClearance
            + bottomInset - CaptureControlBarLayout.bottomInset
    }
}
