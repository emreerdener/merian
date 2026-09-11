import Foundation

enum ManualAppleRevocationNoticeStore {
    static func isPending(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.bool(
            forKey: UserDefaultsKeys.pendingManualAppleRevocationNotice
        )
    }

    @MainActor
    static func record(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) {
        let eventSender = eventSender ?? AppDIContainer.shared.appEventPublisher
        userDefaults.set(
            true,
            forKey: UserDefaultsKeys.pendingManualAppleRevocationNotice
        )
        eventSender.send(.manualAppleRevocationNoticeRequired)
    }

    static func resolve(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(
            forKey: UserDefaultsKeys.pendingManualAppleRevocationNotice
        )
    }
}
