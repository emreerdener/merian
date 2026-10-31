import Foundation
@testable import Merian
import Testing

struct AnalysisRecoveryPresentationTests {
    private let identity = AnalysisRecoveryPresentation.Identity(ownerID: UUID(), observationID: UUID(), operationID: UUID())

    @Test func interruptedReservationCannotReopenChecking() throws {
        let initial = AnalysisRecoveryPresentation.initial(for: identity)
        let reservation = try initial.reserve(id: UUID())
        let reopened = try AnalysisRecoveryPresentation.decode(reservation.reserved.encoded(), identity: identity)
        #expect(reopened.needsAttention)
        #expect(reopened.chargedMilliseconds == 30_000)
        #expect(throws: AnalysisRecoveryPresentation.Failure.self) { try reopened.reserve(id: UUID()) }
        #expect(initial.chargedMilliseconds == 0)
    }

    @Test func cleanPausesPreserveAccumulatedVisibleTime() throws {
        var saved = AnalysisRecoveryPresentation.initial(for: identity)
        for milliseconds in [7_001, 9_000, 13_999] {
            let reservation = try saved.reserve(id: UUID())
            saved = try reservation.settle(current: reservation.reserved, elapsed: .milliseconds(milliseconds))
            saved = try AnalysisRecoveryPresentation.decode(saved.encoded(), identity: identity)
        }
        #expect(saved.chargedMilliseconds == 30_000)
        #expect(saved.revision == 6)
        #expect(saved.activeReservationID == nil)
        #expect(saved.needsAttention)
        #expect(throws: AnalysisRecoveryPresentation.Failure.self) { try saved.reserve(id: UUID()) }
    }

    @Test(arguments: [0, 1, 29_999, 30_000, 30_001, Int.max])
    func elapsedTimeIsBounded(milliseconds: Int) throws {
        let reservation = try AnalysisRecoveryPresentation.initial(for: identity).reserve(id: UUID())
        let result = try reservation.settle(current: reservation.reserved, elapsed: .milliseconds(milliseconds))
        #expect(result.chargedMilliseconds == min(milliseconds, 30_000))
        #expect(result.needsAttention == (milliseconds >= 30_000))
    }

    @Test func fractionalTimeRoundsUpAndNegativeTimeRejects() throws {
        let reservation = try AnalysisRecoveryPresentation.initial(for: identity).reserve(id: UUID())
        let tiny = try reservation.settle(current: reservation.reserved, elapsed: .nanoseconds(1))
        let fractional = try reservation.settle(current: reservation.reserved, elapsed: .nanoseconds(1_000_001))
        #expect(tiny.chargedMilliseconds == 1)
        #expect(fractional.chargedMilliseconds == 2)
        #expect(throws: AnalysisRecoveryPresentation.Failure.self) {
            try reservation.settle(current: reservation.reserved, elapsed: .nanoseconds(-1))
        }
    }

    @Test func stalePauseCannotRefundLaterReservationEvenWithReusedToken() throws {
        let token = UUID(), first = try AnalysisRecoveryPresentation.initial(for: identity).reserve(id: token)
        let paused = try first.settle(current: first.reserved, elapsed: .seconds(10))
        let second = try paused.reserve(id: token)
        #expect(second.visibleAllowance == .seconds(20))
        #expect(throws: AnalysisRecoveryPresentation.Failure.self) { try first.settle(current: second.reserved, elapsed: .zero) }
        #expect(throws: AnalysisRecoveryPresentation.Failure.self) { try first.settle(current: paused, elapsed: .zero) }
        let exhausted = try second.settle(current: second.reserved, elapsed: .seconds(21))
        #expect(exhausted.chargedMilliseconds == 30_000)
    }

    @Test(arguments: ["owner", "observation", "operation"])
    func foreignIdentityRejects(field: String) throws {
        let value = try AnalysisRecoveryPresentation.initial(for: identity).reserve(id: UUID()).reserved
        let foreign = AnalysisRecoveryPresentation.Identity(ownerID: field == "owner" ? UUID() : identity.ownerID,
            observationID: field == "observation" ? UUID() : identity.observationID,
            operationID: field == "operation" ? UUID() : identity.operationID)
        #expect(throws: (any Error).self) { try AnalysisRecoveryPresentation.decode(value.encoded(), identity: foreign) }
    }

    @Test(arguments: ["unknown", "version", "negative", "overflow", "boolean", "fraction", "activeBudget", "null", "oversize", "duplicate", "revision", "parity"])
    func malformedEncodingRejects(kind: String) throws {
        let value = try AnalysisRecoveryPresentation.initial(for: identity).reserve(id: UUID()).reserved
        let original = try value.encoded()
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        switch kind {
        case "unknown": object["extra"] = 1
        case "version": object["version"] = 2
        case "negative": object["chargedMilliseconds"] = -1
        case "overflow": object["chargedMilliseconds"] = 30_001
        case "boolean": object["revision"] = true
        case "fraction": object["revision"] = 1.5
        case "activeBudget": object["chargedMilliseconds"] = 10
        case "null": object["activeReservation"] = NSNull()
        case "oversize": object["extra"] = String(repeating: "x", count: 513)
        case "revision": object["revision"] = Int64.max
        case "parity": object["revision"] = 2
        default: break
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if kind == "duplicate" {
            let suffix = try #require(String(bytes: original.dropFirst(), encoding: .utf8))
            data = Data(("{\"version\":1," + suffix).utf8)
        }
        #expect(throws: (any Error).self) { try AnalysisRecoveryPresentation.decode(data, identity: identity) }
    }

    @Test func zeroElapsedChecksCannotExhaustInventoryRevisionRunway() throws {
        var saved = AnalysisRecoveryPresentation.initial(for: identity)
        for index in 0..<30 {
            let reservation = try saved.reserve(id: UUID())
            #expect(try reservation.reserved.encoded().count <= AnalysisRecoveryPresentation.maximumBytes)
            saved = try reservation.settle(current: reservation.reserved, elapsed: .zero)
            saved = try AnalysisRecoveryPresentation.decode(saved.encoded(), identity: identity)
            #expect(saved.remainingTransitions == Int64(58 - index * 2))
        }
        #expect(saved.chargedMilliseconds == 0)
        #expect(saved.needsAttention)
        #expect(throws: AnalysisRecoveryPresentation.Failure.self) { try saved.reserve(id: UUID()) }
    }
}
