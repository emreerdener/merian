import Foundation
import Testing

@testable import Merian

@Suite("Account Deletion Recovery Validation")
struct AccountDeletionRecoveryValidationTests {
    @Test(arguments: [String(repeating: "A", count: 43), String(repeating: "0", count: 43),
                      String(repeating: "_", count: 42) + "-", String(repeating: "z", count: 43)])
    func acceptsExactBase64URLSyntax(value: String) {
        #expect(AccountDeletionRecoveryValidation.isValidCapability(value))
    }

    @Test(arguments: ["", String(repeating: "A", count: 42), String(repeating: "A", count: 44),
                      String(repeating: "A", count: 42) + "=", String(repeating: "A", count: 42) + "/",
                      String(repeating: "A", count: 42) + "+", String(repeating: "A", count: 42) + " ",
                      String(repeating: "A", count: 41) + "é", String(repeating: "A", count: 42) + "\n"])
    func rejectsMalformedProofWithoutTrimming(value: String) {
        #expect(!AccountDeletionRecoveryValidation.isValidCapability(value))
    }

    @Test(arguments: [-301.0, -300.0, -299.0, 0.0, 1.0])
    func expiryKeepsTheStrictFiveMinuteTolerance(offset: TimeInterval) {
        let now = AccountDeletionTestSupport.now
        let expiry = DateUtilities.iso8601Formatter.string(from: now.addingTimeInterval(offset))
        var clockReads = 0
        let accepted = AccountDeletionRecoveryValidation.isValidExpiry(expiry) {
            clockReads += 1
            return now
        }
        #expect(accepted == (offset > -300))
        #expect(clockReads == 1)
    }

    @Test(arguments: ["2099-01-01T00:00:00Z", "2099-01-01T00:00:00.123456+00:00"])
    func acceptsBothExistingISOFormats(value: String) {
        #expect(AccountDeletionRecoveryValidation.isValidTimestamp(value))
        #expect(AccountDeletionRecoveryValidation.isValidExpiry(value, now: { AccountDeletionTestSupport.now }))
    }

    @Test(arguments: [nil, "", "2030-01-01", String(repeating: "A", count: 20),
                      "2099-01-01T00:00:00.12345678901234567890+00:00"] as [String?])
    func malformedOrOutOfBoundsTimestampsNeverReadTheClock(value: String?) {
        #expect(!AccountDeletionRecoveryValidation.isValidTimestamp(value))
        let valid = AccountDeletionRecoveryValidation.isValidExpiry(value) {
            Issue.record("Invalid timestamp must fail before reading the clock")
            return AccountDeletionTestSupport.now
        }
        #expect(!valid)
    }

    @Test func aReplayTimestampNeedNotBeAnUnexpiredCapability() {
        let expired = AccountDeletionTestSupport.expiredTimestamp
        #expect(AccountDeletionRecoveryValidation.isValidTimestamp(expired))
        #expect(!AccountDeletionRecoveryValidation.isValidExpiry(expired, now: { AccountDeletionTestSupport.now }))
    }
}
