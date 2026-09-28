import SwiftUI

/// Presentation-only bridge for the shared capture clearance value.
private struct CaptureChromeLayoutKey: EnvironmentKey {
    static let defaultValue = CaptureChromeLayout()
}

extension EnvironmentValues {
    var captureChromeLayout: CaptureChromeLayout {
        get { self[CaptureChromeLayoutKey.self] }
        set { self[CaptureChromeLayoutKey.self] = newValue }
    }
}

struct CaptureToolbarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
