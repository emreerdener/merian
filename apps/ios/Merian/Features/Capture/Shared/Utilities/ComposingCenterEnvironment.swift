import SwiftUI

extension EnvironmentValues {
    var composingCenter: CGFloat {
        get { self[ComposingCenterKey.self] }
        set { self[ComposingCenterKey.self] = newValue }
    }
}

private struct ComposingCenterKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0.5
}
