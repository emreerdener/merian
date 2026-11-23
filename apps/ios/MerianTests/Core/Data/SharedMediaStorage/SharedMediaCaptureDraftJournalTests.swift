import Foundation
@testable import Merian
import Testing

struct SharedMediaCaptureDraftJournalTests {
    typealias Journal = SharedMediaCaptureDraftJournal

    func fixture() throws -> Journal {
        let request = try CaptureDraftSourceRequestTests().request()
        let source = try SharedMediaCaptureDraftSourceInput(retained: request), item = UUID()
        return .init(format: .v1, profile: request.profile, rootBindingSHA256: request.rootBindingSHA256,
            scanID: source.scanID, generation: source.submissionGeneration, revision: 0, phase: .editing,
            sources: [.init(itemID: item, input: source, state: .pending)],
            items: [.description(id: UUID(), text: "Synthetic field note"), .photo(id: item, source: source.id,
                recipe: .init(format: .cameraStill, isPro: false, cropDisplaySize: nil,
                    quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: 0.4))],
            frozenObservation: nil, frozenContext: nil)
    }

    @Test func pendingIdentityAndOrderedNotesSurviveExactRoundTrip() throws {
        let value = try fixture(), bytes = try value.encoded()
        let restored = try Journal.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes))
        #expect(restored == value)
        #expect(restored.sources.first?.state == .pending)
        #expect(restored.items.first == value.items.first)
        #expect(restored.frozenObservation == nil)
    }

    @Test(arguments: ["unknown", "revision", "generation", "role", "membership", "released", "freeze", "sourceAlias"])
    func malformedRecoveryCannotInventMembershipOrSubmission(_ mutation: String) throws {
        let value = try fixture()
        var object = try #require(JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any])
        var sources = try #require(object["sources"] as? [[String: Any]])
        var source = sources[0], input = try #require(source["input"] as? [String: Any])
        switch mutation {
        case "unknown": object["localFilePath"] = "/unowned"
        case "revision": object["revision"] = -1
        case "generation": object["generation"] = UUID().uuidString
        case "role": input["role"] = "prepared_image"
        case "membership": object["items"] = []
        case "released": object["phase"] = "released"
        case "freeze": object["phase"] = "submitting"
        case "sourceAlias": input["mediaID"] = input["id"]
        default: Issue.record("Unknown mutation")
        }
        source["input"] = input; sources[0] = source; object["sources"] = sources
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: (any Error).self) {
            try Journal.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes))
        }
    }

    @Test func boundedDecodeRejectsOversizeBeforeParsing() throws {
        let bytes = Data(repeating: 32, count: Journal.maximumBytes + 1)
        #expect(throws: (any Error).self) { try Journal.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes)) }
        let valid = try fixture().encoded()
        #expect(throws: (any Error).self) { try Journal.decode(valid, sha256: String(repeating: "0", count: 64)) }
    }

    @Test(arguments: [Journal.Phase.editing, .discarding])
    func notesCannotOutliveTheFinalPhysicalItem(_ phase: Journal.Phase) throws {
        let base = try fixture(), source = try #require(base.sources.first)
        let notesOnly = Journal(format: .v1, profile: base.profile, rootBindingSHA256: base.rootBindingSHA256,
            scanID: base.scanID, generation: base.generation, revision: 1, phase: phase,
            sources: [.init(itemID: source.itemID, input: source.input, state: .releasedWithoutReservationV1)],
            items: [.description(id: UUID(), text: "Synthetic supplementary note")], frozenObservation: nil, frozenContext: nil)
        #expect(throws: (any Error).self) { try notesOnly.encoded() }
        let terminal = Journal(format: .v1, profile: base.profile, rootBindingSHA256: base.rootBindingSHA256,
            scanID: base.scanID, generation: base.generation, revision: 1, phase: .released,
            sources: notesOnly.sources, items: [], frozenObservation: nil, frozenContext: nil)
        #expect(throws: Never.self) { try terminal.encoded() }
    }
}

extension SharedMediaCaptureDraftJournalTests {
    @Test func largestEscapedNotesFitBothEditingAndFrozenJournal() throws {
        let base = try fixture(), source = try #require(base.sources.first)
        let photo = try #require(base.items.last)
        guard case let .photo(_, _, recipe) = photo else { Issue.record("Missing photo"); return }
        let notes = [8191, 8191, 8191, 7423].map { String(repeating: "\u{0001}", count: $0) + "x" }
        #expect(notes.reduce(0) { $0 + $1.utf16.count } == 32_000)
        let items: [Journal.Item] = [photo] + notes.map { .description(id: UUID(), text: $0) }
        let input = source.input
        let nodes: [CaptureInitialEvidencePlan.Node] = [.image(source: .init(mediaID: input.mediaID,
            contentType: input.contentType, byteCount: Int(input.byteCount), sha256: input.sha256),
            prepared: .init(mediaID: UUID(), contentType: "image/jpeg", byteCount: 48, sha256: String(repeating: "a", count: 64)),
            focus: nil, preparation: try .init(recipe: recipe))] + notes.map { .description($0) }
        let plan = try CaptureInitialEvidencePlan(ownerID: base.profile.ownerID, scanID: base.scanID,
            generation: base.generation, items: nodes)
        let frozen = Journal(format: .v1, profile: base.profile, rootBindingSHA256: base.rootBindingSHA256,
            scanID: base.scanID, generation: base.generation, revision: 1, phase: .submitting,
            sources: [.init(itemID: source.itemID, input: input, state: .ready)], items: items,
            frozenObservation: .init(bytes: try plan.encoded()), frozenContext: try SharedMediaCaptureSubmissionContextTests.context(plan))
        let bytes = try frozen.encoded()
        #expect(bytes.count > 131_072)
        #expect(try Journal.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes)) == frozen)
        let excess = Journal(format: .v1, profile: base.profile, rootBindingSHA256: base.rootBindingSHA256,
            scanID: base.scanID, generation: base.generation, revision: 1, phase: .editing,
            sources: base.sources, items: items + [.description(id: UUID(), text: "x")], frozenObservation: nil, frozenContext: nil)
        #expect(throws: (any Error).self) { try excess.encoded() }
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var context = try #require(object["frozenContext"] as? [String: Any])
        context["locationName"] = String(repeating: "x", count: Int(PhotoPreparationPolicy.metadata) + 1)
        object["frozenContext"] = context
        let invalid = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: (any Error).self) { try Journal.decode(invalid, sha256: SharedMediaAcquisitionEncoding.digest(invalid)) }
    }
}
