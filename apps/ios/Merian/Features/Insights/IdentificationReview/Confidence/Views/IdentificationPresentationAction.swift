import SwiftUI

private struct IdentificationPresentationActionKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    var openIdentification: (@MainActor () -> Void)? {
        get { self[IdentificationPresentationActionKey.self] }
        set { self[IdentificationPresentationActionKey.self] = newValue }
    }
}
