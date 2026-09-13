import Foundation
@testable import Merian
import Testing

@Suite("First Field Trip Achievement Progress Store")
struct FirstFieldTripProgressStoreTests {
    @Test func roundTripsWithinTheNormalizedAccountBoundary() throws {
        let progress = FirstFieldTripAchievementProgress(
            kind: .seasonalChallenge,
            completedAt: "2026-07-18T14:00:00.123Z",
            templateSlug: nil,
            challengeId: "challenge-1"
        )
        let suiteName = "merian.tests.first-field-trip-store.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FirstFieldTripAchievementProgressStore.save(
            progress,
            accountId: "  ACCOUNT-A  ",
            userDefaults: defaults
        )

        #expect(
            FirstFieldTripAchievementProgressStore.load(
                accountId: "account-a",
                userDefaults: defaults
            ) == progress
        )
        #expect(
            FirstFieldTripAchievementProgressStore.load(
                accountId: "account-b",
                userDefaults: defaults
            ) == nil
        )
    }

    @Test func rejectsProgressWithoutAValidAwardProjection() throws {
        let suiteName = "merian.tests.first-field-trip-store.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let invalidDate = FirstFieldTripAchievementProgress(
            kind: .standardOuting,
            completedAt: "not-a-date",
            templateSlug: "backyard_safari",
            challengeId: nil
        )
        let key = FirstFieldTripAchievementProgressStore.key(
            accountId: "account-a"
        )

        FirstFieldTripAchievementProgressStore.save(
            invalidDate,
            accountId: "account-a",
            userDefaults: defaults
        )
        #expect(defaults.data(forKey: key) == nil)

        defaults.set(try JSONEncoder().encode(invalidDate), forKey: key)
        #expect(
            FirstFieldTripAchievementProgressStore.load(
                accountId: "account-a",
                userDefaults: defaults
            ) == nil
        )

        let missingDestination = FirstFieldTripAchievementProgress(
            kind: .seasonalChallenge,
            completedAt: "2026-07-18T14:00:00Z",
            templateSlug: nil,
            challengeId: " \n "
        )
        defaults.set(
            try JSONEncoder().encode(missingDestination),
            forKey: key
        )
        #expect(
            FirstFieldTripAchievementProgressStore.load(
                accountId: "account-a",
                userDefaults: defaults
            ) == nil
        )
    }
}
