import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
extension CaptureTerminalAcceptanceTests {
    func recoverPhotoChild(source: ObservationReanalysisSource, container: ModelContainer,
        cloud: ObservationHistoryCloudClient, baselineState: [String: Any], withText: Bool) async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ObservationReanalysisFileStore(documents: root)
        let bytes = try ObservationReanalysisProducerTests().image()
        let choices: [ObservationReanalysisPreparationPlan.Choice] = withText
            ? [.description("  Child e\u{301} 🐾\n"), .photo(.added(bytes))] : [.photo(.added(bytes))]
        let plan = try ObservationReanalysisPreparationPlan(source: source, choices: choices)
        let producer = ObservationReanalysisProducer(files: files, ownership: .init(), account: cloud)
        let prepared = try await producer.stage(plan, container: container, action: .submit, isCurrent: { true })
        guard case let .submitted(submitted) = prepared else { Issue.record("Photo submission was not retained"); return }
        let draft = submitted.draft
        let proof = try submitted.preparation.verified(source: source)
        let submittedPhotos = try await files.readPhotos(draft: draft, validateBeforeRead: {}, validateBeforeReturn: {})
        try #require(submittedPhotos.count == 1)
        let submittedBytes = submittedPhotos.map(\.bytes)
        typealias Store = ObservationReanalysisExecutionStore
        let start = Date()
        let saved = try Store.bindAndAdmit(draft, processor: .gemini, now: start,
            container: container, isCurrent: { true }, submissionProof: proof)
        let request = saved.intent.request
        var (_, snapshot) = try ObservationReanalysisResultTests().fixture()
        let input = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        for key in ["observation_id", "analysis_id", "source_analysis_id", "request_digest", "evidence_manifest"] {
            snapshot[key] = input[key]
        }
        var identification = try #require(snapshot["result"] as? [String: Any])
        identification["scan_id"] = source.observationID.uuidString.lowercased()
        snapshot["result"] = identification
        let resultBytes = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        _ = try ObservationReanalysisResult.decode(resultBytes, matching: request)
        var events: [String] = [], recovered: Data?
        let dependencies = ObservationReanalysisExecutor.Dependencies(recover: { intent, validate in
            try validate(); #expect(intent.request.body == request.body); events.append("recover"); return recovered
        }, authorize: { intent, validate in
            try validate(); events.append("authorize")
            return IdentificationDispatchAuthorization(recipient: intent.request.processor, validate: validate)
        }, read: { draft, validate in
            events.append("read")
            return try await files.readPhotos(draft: draft, validateBeforeRead: validate, validateBeforeReturn: validate)
        }, upload: { upload, owner, validate in
            try validate(); #expect(owner == source.ownerID); events.append("upload")
            let prepared = try upload.prepare()
            return .init(observationID: prepared.observationID, analysisID: prepared.analysisID, items: prepared.references)
        }, analyze: { intent, authorization in
            try authorization.validate(); #expect(intent.request.body == request.body); events.append("analyze")
            throw URLError(.networkConnectionLost)
        })
        var executor = ObservationReanalysisExecutor(dependencies: dependencies, account: cloud, now: { start })
        _ = try await executor.execute(saved, admission: .initial, container: container, isCurrent: { true })
        let waiting = try Store.read(saved.intent.identity, container: container, isCurrent: { true })
        #expect(waiting.intent.request.body == request.body && waiting.status == .waiting)
        #expect(events == ["recover", "authorize", "read", "upload", "analyze"])
        let parent = try ObservationHistorySyncService.enrolledScan(source.observationID.uuidString, context: ModelContext(container))
        #expect(parent.selectedAnalysisID == source.analysisID.uuidString.lowercased())
        recovered = resultBytes
        executor.now = { waiting.nextRun ?? start }
        let outcome = try await executor.execute(waiting, admission: .dueRetry, container: container, isCurrent: { true })
        guard case .completed = outcome else { Issue.record("Photo recovery did not complete"); return }
        #expect(events == ["recover", "authorize", "read", "upload", "analyze", "recover"])
        #expect(try await files.readPhotos(draft: draft, validateBeforeRead: {}, validateBeforeReturn: {}).map(\.bytes) == submittedBytes)
        try await exerciseCompletedChildActions(source: source, child: request.analysisID,
            resultBytes: resultBytes, container: container, cloud: cloud, baselineState: baselineState)
        #expect(try await files.readPhotos(draft: draft, validateBeforeRead: {}, validateBeforeReturn: {}).map(\.bytes) == submittedBytes)
    }
}
