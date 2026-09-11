import Combine
import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Manual Apple revocation notice store")
struct ManualAppleRevocationNoticeStoreTests {
    @Test func noticePersistsUntilExplicitResolution() throws {
        let suiteName =
            "merian.tests.apple-revocation-notice.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let eventPublisher = AppEventPublisher()
        var receivedNotice = false
        var noticeWasDurableBeforeEvent = false
        let cancellable = eventPublisher.publisher.sink { event in
            if case .manualAppleRevocationNoticeRequired = event {
                receivedNotice = true
                noticeWasDurableBeforeEvent = defaults.bool(
                    forKey: UserDefaultsKeys.pendingManualAppleRevocationNotice
                )
            }
        }
        defer { cancellable.cancel() }

        ManualAppleRevocationNoticeStore.record(
            userDefaults: defaults,
            eventSender: eventPublisher
        )

        #expect(
            ManualAppleRevocationNoticeStore.isPending(userDefaults: defaults)
        )
        #expect(receivedNotice)
        #expect(noticeWasDurableBeforeEvent)

        ManualAppleRevocationNoticeStore.resolve(userDefaults: defaults)

        #expect(
            !ManualAppleRevocationNoticeStore.isPending(userDefaults: defaults)
        )
    }
}
