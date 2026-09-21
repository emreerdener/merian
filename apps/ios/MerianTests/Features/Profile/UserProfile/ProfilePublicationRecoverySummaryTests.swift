import Foundation
import XCTest

@testable import Merian

final class ProfilePublicationRecoverySummaryTests: XCTestCase {
    func testRecoveryNoticeIsHiddenWhenUnavailableScansAreAllPrivate() {
        let stats = ProfileSocialStats(
            followerCount: 0,
            followingCount: 0,
            visiblePublishedPostCount: 0,
            publicationIntentCount: 0,
            recoveryNeededPostCount: 5,
            degradedPostCount: 0,
            quarantinedPostCount: 5
        )

        XCTAssertNil(ProfilePublicationRecoverySummary.publishedOnly(from: stats))
    }

    func testRecoveryNoticeOnlyTalliesPublishedScans() throws {
        let stats = ProfileSocialStats(
            followerCount: 0,
            followingCount: 0,
            visiblePublishedPostCount: 2,
            publicationIntentCount: 3,
            recoveryNeededPostCount: 5,
            degradedPostCount: 0,
            quarantinedPostCount: 5
        )

        let summary = try XCTUnwrap(
            ProfilePublicationRecoverySummary.publishedOnly(from: stats)
        )

        XCTAssertEqual(summary.recoveryNeededCount, 3)
        XCTAssertEqual(summary.quarantinedCount, 3)
    }

    func testRecoveryNoticeUsesUserFacingCopy() {
        let summary = ProfilePublicationRecoverySummary(
            publicationIntentCount: 41,
            visibleCount: 34,
            recoveryNeededCount: 5,
            quarantinedCount: 5
        )

        XCTAssertEqual(
            summary.userFacingTitle,
            "5 published scans need attention"
        )
        XCTAssertEqual(
            summary.userFacingMessage,
            "Their media isn’t available, so they’re temporarily hidden from Explore. "
                + "Your posts and activity are safe."
        )
        XCTAssertEqual(
            summary.userFacingEmptyMessage,
            "Your published scans are temporarily hidden until their media is available again."
        )
    }

    func testRecoveryNoticeUsesSingularLanguage() {
        let summary = ProfilePublicationRecoverySummary(
            publicationIntentCount: 1,
            visibleCount: 0,
            recoveryNeededCount: 1,
            quarantinedCount: 1
        )

        XCTAssertEqual(
            summary.userFacingTitle,
            "1 published scan needs attention"
        )
        XCTAssertEqual(
            summary.userFacingMessage,
            "Its media isn’t available, so it’s temporarily hidden from Explore. "
                + "Your posts and activity are safe."
        )
    }

    func testRecoveryNoticeDismissalSignatureChangesWithUnavailableCount() {
        let summary = ProfilePublicationRecoverySummary(
            publicationIntentCount: 41,
            visibleCount: 34,
            recoveryNeededCount: 5,
            quarantinedCount: 5
        )
        let changedSummary = ProfilePublicationRecoverySummary(
            publicationIntentCount: 42,
            visibleCount: 34,
            recoveryNeededCount: 6,
            quarantinedCount: 6
        )

        XCTAssertEqual(summary.overviewDismissalSignature, "5")
        XCTAssertNotEqual(
            summary.overviewDismissalSignature,
            changedSummary.overviewDismissalSignature
        )
    }

    func testDismissalSurvivesReloadAndUnrelatedPublicationChanges() throws {
        let suiteName = "ProfileRecoveryReloadTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let owner = UUID().uuidString
        // Simulate a dismissal from the previous app version.
        ProfileRecoveryNoticePreferences.dismiss(
            signature: "41:34:5:5", ownerUserID: owner, defaults: defaults
        )
        let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let summary = ProfilePublicationRecoverySummary(
            publicationIntentCount: 50, visibleCount: 48,
            recoveryNeededCount: 5, quarantinedCount: 2
        )
        XCTAssertTrue(ProfileRecoveryNoticePreferences.isDismissed(
            summary: summary,
            signature: ProfileRecoveryNoticePreferences.dismissedSignature(
                ownerUserID: owner, defaults: reloadedDefaults
            )
        ))
        ProfileRecoveryNoticePreferences.reconcile(
            stats: nil, ownerUserID: owner, defaults: reloadedDefaults
        )
        XCTAssertEqual(ProfileRecoveryNoticePreferences.dismissedSignature(
            ownerUserID: owner, defaults: reloadedDefaults
        ), "41:34:5:5")
    }

    func testResolvedMediaLowersDismissalAndNewUnavailableMediaReopensNotice() throws {
        let suiteName = "ProfileRecoveryCountTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let owner = UUID().uuidString
        ProfileRecoveryNoticePreferences.dismiss(
            signature: "5", ownerUserID: owner, defaults: defaults
        )

        func reconcile(_ count: Int) {
            ProfileRecoveryNoticePreferences.reconcile(
                stats: ProfileSocialStats(
                    followerCount: 0, followingCount: 0,
                    visiblePublishedPostCount: 10 - count,
                    publicationIntentCount: 10,
                    recoveryNeededPostCount: count,
                    degradedPostCount: 0, quarantinedPostCount: count
                ),
                ownerUserID: owner, defaults: defaults
            )
        }

        func isDismissed(_ count: Int) -> Bool {
            ProfileRecoveryNoticePreferences.isDismissed(
                summary: ProfilePublicationRecoverySummary(
                    publicationIntentCount: 10, visibleCount: 10 - count,
                    recoveryNeededCount: count, quarantinedCount: count
                ),
                signature: ProfileRecoveryNoticePreferences.dismissedSignature(
                    ownerUserID: owner, defaults: defaults
                )
            )
        }

        XCTAssertTrue(isDismissed(5))
        XCTAssertFalse(isDismissed(6))
        reconcile(3)
        XCTAssertTrue(isDismissed(3))
        reconcile(4)
        XCTAssertFalse(isDismissed(4))
        // Reloading must not silently acknowledge the additional unavailable media.
        reconcile(4)
        XCTAssertFalse(isDismissed(4))
        reconcile(0)
        XCTAssertNil(ProfileRecoveryNoticePreferences.dismissedSignature(
            ownerUserID: owner, defaults: defaults
        ))
        XCTAssertFalse(isDismissed(1))
    }

    func testRecoveryNoticeDismissalIsAccountScopedAndClearable() throws {
        let suiteName = "ProfilePublicationRecoveryOverviewPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstOwnerID = UUID().uuidString
        let secondOwnerID = UUID().uuidString
        let signature = "41:34:5:5"

        ProfileRecoveryNoticePreferences.dismiss(
            signature: signature,
            ownerUserID: firstOwnerID,
            defaults: defaults
        )

        XCTAssertEqual(
            ProfileRecoveryNoticePreferences.dismissedSignature(
                ownerUserID: firstOwnerID.uppercased(),
                defaults: defaults
            ),
            signature
        )
        XCTAssertNil(
            ProfileRecoveryNoticePreferences.dismissedSignature(
                ownerUserID: secondOwnerID,
                defaults: defaults
            )
        )

        ProfileRecoveryNoticePreferences.clear(
            ownerUserID: firstOwnerID,
            defaults: defaults
        )
        XCTAssertNil(
            ProfileRecoveryNoticePreferences.dismissedSignature(
                ownerUserID: firstOwnerID,
                defaults: defaults
            )
        )
    }
}
