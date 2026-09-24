#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
final class AudioComparisonTestFixture {
    let assignment: any DebugAudioComparisonBinding
    init(prompt: Bool = false) {
        if prompt { assignment = DebugAudioPromptComparisonSlot.slot2.assignment }
        else { assignment = DebugAudioComparisonSlot.slot1.assignment }
    }
    var records: [String] = []
    lazy var capture = IdentificationComparisonCapture(assignment: assignment) { [unowned self] in records.append($0) }

    var events: [String] {
        records.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["event"] as? String }
    }

    func response(receipt: [String: Any]? = nil, replay: String? = nil, status: Int = 200) throws -> HTTPURLResponse {
        let diagnostics: [String: Any] = [
            "version": 1, "provider": "gemini", "requestedModel": "gemini-2.5-pro",
            "returnedModel": "gemini-2.5-pro", "backendBundleSha256": String(repeating: "b", count: 64)
        ]
        var headers = [
            assignment.responseHeader: String(decoding: try JSONSerialization.data(withJSONObject: receipt ?? assignment.receipt), as: UTF8.self),
            "X-Merian-Identification": String(decoding: try JSONSerialization.data(withJSONObject: diagnostics), as: UTF8.self),
            "Server-Timing": "provider;dur=10.1, edge_total;dur=20.2"
        ]
        headers["X-Merian-Idempotent-Replay"] = replay
        return try #require(HTTPURLResponse(url: URL(string: "https://example.invalid/identify-multimodal")!, statusCode: status, httpVersion: nil, headerFields: headers))
    }

    @discardableResult
    func receive(response: HTTPURLResponse? = nil, current: Bool = true, fixed: Bool = true) throws -> String {
        let response = try response ?? self.response()
        let measurement = try #require(IdentificationBenchmarkRecord.make(response: response, appInfo: [:], fixedAudioContext: fixed))
        capture.receive(response: response, measurement: measurement, isCurrentInitialAttempt: current)
        return measurement
    }
}

@MainActor
@Suite("Identification Comparison Capture")
struct IdentificationComparisonCaptureTests {
    @Test func exactReceiptJoinsMeasurementAndOneShotFinalizationAndRender() throws {
        let fixture = AudioComparisonTestFixture()
        let text = try fixture.receive()
        let id = fixture.assignment.scanId
        fixture.capture.recordFirstRender(scanId: "synthetic-wrong-scan")
        fixture.capture.finalize(scanId: "synthetic-wrong-scan", confidenceScore: 0.9, isBiological: true, persistence: .saved)
        #expect(fixture.events == ["receipt"])
        fixture.capture.recordFirstRender(scanId: id)
        fixture.capture.finalize(scanId: id, confidenceScore: 0.9, isBiological: true, persistence: .saved)
        fixture.capture.recordFirstRender(scanId: id)
        fixture.capture.finalize(scanId: id, confidenceScore: 0.9, isBiological: true, persistence: .saved)
        #expect(fixture.events == ["receipt", "rendered", "finalized"])
        for record in fixture.records {
            let value = try #require(JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any])
            #expect(value["measurementSha256"] as? String == DebugAudioComparisonAssignment.digest(Data(text.utf8)))
            #expect(record.utf8.count + IdentificationComparisonCapture.marker.utf8.count < 1_024)
            #expect(!record.contains(id))
            #expect(!record.contains("sourceWavSha256"))
        }
    }

    @Test(arguments: [false, true]) func malformedReceiptMissingProofReplayAndStaleAttemptsCannotComplete(prompt: Bool) throws {
        for key in AudioComparisonTestFixture(prompt: prompt).assignment.receipt.keys {
            let fixture = AudioComparisonTestFixture(prompt: prompt)
            var receipt = fixture.assignment.receipt
            receipt[key] = "synthetic-wrong-value"
            try fixture.receive(response: fixture.response(receipt: receipt))
            fixture.capture.finalize(scanId: fixture.assignment.scanId, confidenceScore: 0.9, isBiological: true, persistence: .saved)
            fixture.capture.recordFirstRender(scanId: fixture.assignment.scanId)
            #expect(fixture.records.isEmpty)
        }
        for failure in ["replay", "retry", "stale", "ordinary", "failure", "extra"] {
            let fixture = AudioComparisonTestFixture(prompt: prompt)
            var receipt = fixture.assignment.receipt
            if failure == "extra" { receipt["rawContent"] = "synthetic-private" }
            let response = try fixture.response(receipt: receipt, replay: failure == "replay" ? "stored" : nil, status: failure == "failure" ? 503 : 200)
            try fixture.receive(response: response, current: !["retry", "stale"].contains(failure), fixed: failure != "ordinary")
            #expect(fixture.records.isEmpty)
        }
        for key in (prompt ? ["version", "slot", "block", "repeat"] : ["version", "slot"]) {
            var receipt = AudioComparisonTestFixture(prompt: prompt).assignment.receipt
            receipt[key] = true
            #expect(!AudioComparisonTestFixture(prompt: prompt).assignment.acceptsReceipt(String(decoding: try JSONSerialization.data(withJSONObject: receipt), as: UTF8.self)))
        }
    }

    @Test(arguments: [false, true]) func responseAdoptionRechecksTheLiveOwnerOnTheMainActor(prompt: Bool) throws {
        let fixture = AudioComparisonTestFixture(prompt: prompt)
        let telemetry = (prompt ? DebugIdentificationReplayProfile.audioPromptComparison(slot: .slot2) : .audioComparison(slot: .slot1)).makeTelemetry()
        let body: [String: Any] = [
            "user_id": "synthetic-owner", "client_scan_id": fixture.assignment.scanId,
            "geoprivacy": "private", "mimeType": "image/webp", "deviceLocale": "en", "deviceTimeZone": "UTC",
            "currentMonth": 1, "timeOfDay": "12:00 PM", "audioBase64s": ["AA=="],
            "audioMediaItems": [IdentifyAudioMediaItem.audio(sourceIndex: 0).jsonObject],
            "ownerMediaTimeline": [IdentifyOwnerMediaTimelineItem.audio(audioInputIndex: 0, sourceIndex: 0).jsonObject],
            fixture.assignment.requestKey: fixture.assignment.handle
        ]
        var current = true
        let context = try #require(IdentificationMeasurementContext.fixedAudio(
            body: JSONSerialization.data(withJSONObject: body), telemetry: telemetry,
            validateAttempt: { if !current { throw CancellationError() } }, comparisonCapture: fixture.capture
        ))
        #expect(context.isCurrent())
        current = false // Owner changed between the timing snapshot and header adoption.
        let response = try fixture.response()
        let measurement = try #require(IdentificationBenchmarkRecord.make(response: response, appInfo: [:], fixedAudioContext: true))
        context.recordComparisonResponse(response: response, measurement: measurement, isInitialAttempt: true)
        #expect(fixture.records.isEmpty)
    }

    @Test func secondHTTPResponseInvalidatesProofAndNoMatchRemainsExplicit() throws {
        let repeated = AudioComparisonTestFixture()
        try repeated.receive()
        try repeated.receive(current: false)
        repeated.capture.finalize(scanId: repeated.assignment.scanId, confidenceScore: 0.9, isBiological: true, persistence: .saved)
        repeated.capture.recordFirstRender(scanId: repeated.assignment.scanId)
        #expect(repeated.events == ["receipt"])
        let noMatch = AudioComparisonTestFixture()
        try noMatch.receive()
        noMatch.capture.finalize(scanId: noMatch.assignment.scanId, confidenceScore: 0, isBiological: false, persistence: .completedWithoutRecord)
        #expect(noMatch.records.last?.contains("completed_without_record") == true)
        #expect(noMatch.events == ["receipt", "finalized"])
    }

    @Test(arguments: ["named", "unresolved", "human", "non_biological"])
    func promptProofBindsActualSubjectAndScoreWithoutLoggingNames(kind: String) throws {
        let fixture = AudioComparisonTestFixture(prompt: true)
        try fixture.receive()
        let species = SpeciesData(
            scanId: fixture.assignment.scanId,
            commonName: kind == "unresolved" ? "Unidentified Wildlife" : kind == "human" ? "Human" : "Synthetic subject",
            scientificName: kind == "named" ? "Syntheticus testus" : kind == "human" ? "Homo sapiens" : "",
            insightData: InsightData(aiReasoning: "Synthetic observation", hazardType: "none"),
            confidenceScore: 0.91, isBiological: kind != "non_biological", inferenceTier: "pro"
        )
        // Incomplete or mismatched handoffs cannot manufacture a finalized proof.
        fixture.capture.finalize(scanId: species.scanId, confidenceScore: 0.91, isBiological: species.isBiological, persistence: .saved)
        fixture.capture.finalize(scanId: species.scanId, confidenceScore: 0.5, isBiological: species.isBiological, persistence: .saved, species: species)
        #expect(fixture.events == ["receipt"])
        fixture.capture.finalize(scanId: species.scanId, confidenceScore: 0.91, isBiological: species.isBiological, persistence: .saved, species: species)
        fixture.capture.recordFirstRender(scanId: fixture.assignment.scanId)
        #expect(fixture.events == ["receipt", "finalized", "rendered"])
        let value = try #require(JSONSerialization.jsonObject(with: Data(fixture.records[1].utf8)) as? [String: Any])
        let expected = ["named": "identified_non_human", "unresolved": "unidentified_non_human", "human": "human", "non_biological": "non_biological"]
        #expect(value["subjectState"] as? String == expected[kind])
        #expect(value["version"] as? String == "identification_audio_prompt_comparison_v1")
        #expect(value["planSha256"] as? String == DebugAudioPromptComparisonPlan.sha256)
        if kind == "named" {
            #expect(value["scientificNameSha256"] as? String == DebugAudioComparisonAssignment.digest(Data("syntheticus testus".utf8)))
        } else { #expect(value["scientificNameSha256"] == nil) }
        for record in fixture.records {
            #expect(record.utf8.count + fixture.assignment.logMarker.utf8.count < 1_024)
            #expect(!record.contains(species.scanId ?? "synthetic-missing"))
            #expect(!record.contains("Syntheticus") && !record.contains("Homo sapiens"))
        }
    }

    @Test func renderProofIsExactAndClearedByReplacementAndAuth() throws {
        for transition in ["reset", "auth", "published", "quiescence"] {
            let fixture = AudioComparisonTestFixture()
            try fixture.receive()
            let owner = InferencePresentationCoordinator()
            owner.armComparisonRender(fixture.capture, scanId: fixture.assignment.scanId)
            #expect(owner.consumeComparisonRender(scanId: "synthetic-other") == nil)
            switch transition {
            case "reset": owner.reset()
            case "auth": owner.clearForAuthTransitionAdmission()
            case "published": owner.clearForPublishedResult()
            default: owner.finishAuthTransitionQuiescence()
            }
            #expect(owner.consumeComparisonRender(scanId: fixture.assignment.scanId) == nil)
        }
        let fixture = AudioComparisonTestFixture()
        let owner = InferencePresentationCoordinator()
        owner.armComparisonRender(fixture.capture, scanId: fixture.assignment.scanId)
        #expect(owner.consumeComparisonRender(scanId: fixture.assignment.scanId) === fixture.capture)
        #expect(owner.consumeComparisonRender(scanId: fixture.assignment.scanId) == nil)
    }

    @Test(arguments: [false, true]) func sourceGuardRejectsChangedBytesAndWrongQueueIdentity(prompt: Bool) throws {
        let bytes = Data([1, 2, 3, 4])
        let frozen: any DebugAudioComparisonBinding = AudioComparisonTestFixture(prompt: prompt).assignment
        let synthetic: any DebugAudioComparisonBinding
        if prompt {
            let binding = DebugAudioPromptComparisonSlot.slot2.assignment
            synthetic = DebugAudioPromptComparisonAssignment(
                slot: binding.slot, block: binding.block, repeatIndex: binding.repeatIndex, caseId: binding.caseId, arm: binding.arm,
                sourceWavSha256: DebugAudioPromptComparisonAssignment.digest(bytes), sourceByteLength: bytes.count,
                processedWavSha256: binding.processedWavSha256, providerRequestSha256: binding.providerRequestSha256,
                policySha256: binding.policySha256, confidenceSha256: binding.confidenceSha256, scanId: binding.scanId
            )
        } else {
            let binding = DebugAudioComparisonSlot.slot1.assignment
            synthetic = DebugAudioComparisonAssignment(
                slot: binding.slot, caseId: binding.caseId, arm: binding.arm,
                sourceWavSha256: DebugAudioComparisonAssignment.digest(bytes), sourceByteLength: bytes.count,
                processedWavSha256: binding.processedWavSha256, providerRequestSha256: binding.providerRequestSha256,
                policySha256: binding.policySha256, confidenceSha256: binding.confidenceSha256, scanId: binding.scanId
            )
        }
        var payload: [String: Any] = ["client_scan_id": synthetic.scanId, "audioBase64s": [bytes.base64EncodedString()]]
        try synthetic.addHandle(to: &payload)
        #expect((payload[synthetic.requestKey] as? [String: Any])?["slot"] as? Int == synthetic.slot)
        payload["client_scan_id"] = "synthetic-other"
        #expect(throws: (any Error).self) { try synthetic.addHandle(to: &payload) }
        #expect(!synthetic.matchesSource(Data([1, 2, 3, 5])))
        #expect(!synthetic.matchesSource(bytes + Data([5])))
        #expect(!frozen.matchesSource(bytes))
    }

    @Test(arguments: [false, true]) func comparisonIDsCannotUpsertQueuedOrSavedRecords(prompt: Bool) throws {
        let schema = Schema([OfflineQueuedScan.self, LocalScanRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let id = AudioComparisonTestFixture(prompt: prompt).assignment.scanId
        #expect(!DebugAudioComparisonAdmission.isAvailable(scanId: id, context: nil))
        #expect(DebugAudioComparisonAdmission.isAvailable(scanId: id, context: context))
        let queued = OfflineQueuedScan(id: id)
        context.insert(queued)
        try context.save()
        #expect(!DebugAudioComparisonAdmission.isAvailable(scanId: id, context: context))
        context.delete(queued)
        try context.save()
        context.insert(LocalScanRecord(id: id, speciesId: "synthetic-species", scientificName: "Synthetic taxon", commonName: "Synthetic subject"))
        try context.save()
        #expect(!DebugAudioComparisonAdmission.isAvailable(scanId: id, context: context))
        #expect(DebugAudioComparisonAdmission.isAvailable(scanId: DebugAudioComparisonSlot.slot2.assignment.scanId, context: context))
    }
}
#endif
