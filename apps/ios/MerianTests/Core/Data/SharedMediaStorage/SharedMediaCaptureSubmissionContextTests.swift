import Foundation
@testable import Merian
import Testing

@Suite("Capture submission frozen context")
struct SharedMediaCaptureSubmissionContextTests {
    static func context(_ plan: CaptureInitialEvidencePlan, timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws -> SharedMediaCaptureSubmissionContext {
        try .init(plan: plan, funding: .init(accountId: plan.ownerID, scanId: plan.scanID.uuidString,
            source: .complimentaryPro, createdAt: timestamp), timestamp: timestamp,
            telemetry: .init(subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
                gpsElevation: nil, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil,
                timeOfDay: nil, timestamp: nil, zoomFactor: 2, estimatedSizeCm: nil),
            blurScore: 0.25, preferredGoal: nil)
    }

    private func plan(notes: String = "Synthetic field note") throws -> CaptureInitialEvidencePlan {
        try .init(ownerID: UUID(), scanID: UUID(), generation: UUID(), items: [
            .audio(.init(source: .init(mediaID: UUID(), contentType: "audio/wav", byteCount: 48,
                sha256: String(repeating: "a", count: 64)), preparedMediaID: UUID())), .description(notes)])
    }

    @Test func roundTripFreezesExistingQueueContextAndFunding() throws {
        let plan = try plan(), value = try Self.context(plan)
        let data = try JSONEncoder().encode(value)
        let saved = try JSONDecoder().decode(SharedMediaCaptureSubmissionContext.self, from: data)
        try saved.validate(plan: plan)
        #expect(saved == value)
        #expect(saved.initialFieldNotes == "Synthetic field note")
        #expect(saved.telemetry.zoomFactor == 2 && saved.telemetry.timeOfDay == nil)
        #expect(saved.telemetry.estimatedSizeCm == nil && saved.telemetry.gpsLatitude == nil)
        #expect(try saved.metadata(plan: plan).funding.scanId == plan.scanID.uuidString.lowercased())
    }

    @Test func changedIdentityNotesAndFundingCannotBeReconstructedAsReplay() throws {
        let plan = try plan(), value = try Self.context(plan)
        let other = try CaptureInitialEvidencePlan(ownerID: plan.ownerID, scanID: UUID(), generation: UUID(), items: plan.items)
        #expect(throws: (any Error).self) { try value.validate(plan: other) }
        var items = plan.items; items[1] = .description("Different synthetic note")
        let changed = try CaptureInitialEvidencePlan(ownerID: plan.ownerID, scanID: plan.scanID, generation: plan.generation, items: items)
        #expect(throws: (any Error).self) { try value.validate(plan: changed) }
        #expect(throws: (any Error).self) { try Self.context(plan, timestamp: Date(timeIntervalSince1970: .infinity)) }
    }

    @Test func editableNotesUseTheExistingSeedWhileEvidenceKeepsExactText() throws {
        let original = try plan(notes: "  First synthetic note\n")
        let plan = try CaptureInitialEvidencePlan(ownerID: original.ownerID, scanID: original.scanID,
            generation: original.generation, items: original.items + [.description("\nSecond synthetic note  ")])
        let value = try Self.context(plan)
        #expect(value.initialFieldNotes == InitialFieldNotesSeed.make(contexts: [
            .init(freeText: "  First synthetic note\n"), .init(freeText: "\nSecond synthetic note  ")]))
        #expect(value.initialFieldNotes == "First synthetic note\n\nSecond synthetic note")
        if case .description(let exact) = plan.items[1] { #expect(exact == "  First synthetic note\n") }
        else { Issue.record("Description evidence was lost") }
    }
}
