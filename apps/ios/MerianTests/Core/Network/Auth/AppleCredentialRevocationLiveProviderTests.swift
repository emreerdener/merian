import AuthenticationServices
import Foundation
@testable import Merian
import XCTest

@MainActor
private final class AppleRevocationNotificationProbe {
    private(set) var invocationCount = 0

    func recordInvocation() {
        invocationCount += 1
    }
}

@MainActor
final class AppleRevocationLiveProviderTests: XCTestCase {
    func testCredentialStateMappingFailsClosedWithoutClearingAuthorizedState() {
        XCTAssertEqual(
            AppleCredentialRevocationLiveProvider.lookupResult(
                for: .authorized
            ),
            .authorized
        )
        XCTAssertEqual(
            AppleCredentialRevocationLiveProvider.lookupResult(
                for: .revoked
            ),
            .revoked
        )
        XCTAssertEqual(
            AppleCredentialRevocationLiveProvider.lookupResult(
                for: .notFound
            ),
            .notFound
        )
        XCTAssertEqual(
            AppleCredentialRevocationLiveProvider.lookupResult(
                for: .transferred
            ),
            .transferred
        )
        XCTAssertEqual(
            AppleCredentialRevocationLiveProvider.lookupResult(
                for: .authorized,
                lookupFailed: true
            ),
            .lookupFailed
        )
    }

    func testStartingAndStoppingObservationOwnsExactlyOneRegistration() {
        let notificationCenter = NotificationCenter()
        let replacedProbe = AppleRevocationNotificationProbe()
        let activeProbe = AppleRevocationNotificationProbe()
        let provider = AppleCredentialRevocationLiveProvider(
            notificationCenter: notificationCenter
        )

        provider.startObserving {
            replacedProbe.recordInvocation()
        }
        provider.startObserving {
            activeProbe.recordInvocation()
        }

        notificationCenter.post(
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        XCTAssertEqual(replacedProbe.invocationCount, 0)
        XCTAssertEqual(activeProbe.invocationCount, 1)

        provider.stopObserving()
        notificationCenter.post(
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        XCTAssertEqual(activeProbe.invocationCount, 1)
    }

    func testProviderDeinitRemovesObservationRegistration() {
        let notificationCenter = NotificationCenter()
        let probe = AppleRevocationNotificationProbe()
        var provider: AppleCredentialRevocationLiveProvider? =
            AppleCredentialRevocationLiveProvider(
                notificationCenter: notificationCenter
            )
        provider?.startObserving {
            probe.recordInvocation()
        }
        weak let releasedProvider = provider

        provider = nil
        XCTAssertNil(releasedProvider)
        notificationCenter.post(
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )

        XCTAssertEqual(probe.invocationCount, 0)
    }

    func testBackgroundNotificationEntersMainActorHandler() async {
        let notificationCenter = NotificationCenter()
        let probe = AppleRevocationNotificationProbe()
        let provider = AppleCredentialRevocationLiveProvider(
            notificationCenter: notificationCenter
        )
        provider.startObserving {
            probe.recordInvocation()
        }

        await Task.detached {
            notificationCenter.post(
                name: ASAuthorizationAppleIDProvider
                    .credentialRevokedNotification,
                object: nil
            )
        }.value
        await waitUntil { probe.invocationCount == 1 }

        XCTAssertEqual(probe.invocationCount, 1)
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<2_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for notification delivery.", file: file, line: line)
    }
}
