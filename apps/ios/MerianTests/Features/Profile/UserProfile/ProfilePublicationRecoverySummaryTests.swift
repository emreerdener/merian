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

    func testRecoveryNoticeDismissalSignatureChangesWithPublishedTotals() {
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

        XCTAssertEqual(summary.overviewDismissalSignature, "41:34:5:5")
        XCTAssertNotEqual(
            summary.overviewDismissalSignature,
            changedSummary.overviewDismissalSignature
        )
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
