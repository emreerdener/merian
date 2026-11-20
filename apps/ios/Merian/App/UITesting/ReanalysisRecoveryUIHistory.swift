#if DEBUG
import Foundation
import Observation
import SwiftData

/// Synthetic server state only. App selection/review records are changed solely
/// by the existing History services, receipts and reconciliation owners.
@MainActor @Observable final class ReanalysisRecoveryUIHistory {
    struct Ledger: Codable {
        let witness: ReanalysisRecoveryUIResult.Witness
        var available = false
        var chargedWhenAvailable: Int?
        var selected: String
        var revision: Int
        var reviewRevision = 0
        var rejectedOperation: UUID?
        var latestReview: Data?
        var cleared = true
        var selectionRequests: [String: Data] = [:]
        var selectionReceipts: [String: Data] = [:]
        var reviewRequests: [String: Data] = [:]
        var reviewReceipts: [String: Data] = [:]
    }
    private(set) var ledger: Ledger
    private(set) var generation: UInt64 = 0
    private(set) var failure = ""
    private let file: URL
    let root: URL
    let container: ModelContainer
    private let baseline: ObservationHistoryCloudClient
    private let delivery = ObservationAnalysisReviewDeliveryOwner()
    var witness: ReanalysisRecoveryUIResult.Witness { ledger.witness }
    var isDelivering: Bool { delivery.isRunning }

    static func file(in root: URL) -> URL { root.appendingPathComponent("synthetic-recovery-server.json") }
    init(witness: ReanalysisRecoveryUIResult.Witness?, identity: OfflineQueueWork.Reanalysis, media: String,
         root: URL, container: ModelContainer, baseline: ObservationHistoryCloudClient) throws {
        guard UITestSeedCoordinator.reanalysisRecoveryRestartEnabled,
              UITestSeedCoordinator.reanalysisRecoverySuccessEnabled else { throw MerianError.invalidResponse }
        self.root = root; self.container = container; self.baseline = baseline; file = Self.file(in: root)
        guard file.resolvingSymlinksInPath() == file.standardizedFileURL else { throw MerianError.invalidResponse }
        if FileManager.default.fileExists(atPath: file.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let length = attributes[.size] as? NSNumber, (1...1_048_576).contains(length.intValue) else { throw MerianError.invalidResponse }
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            let bytes = try handle.read(upToCount: length.intValue + 1) ?? Data()
            guard bytes.count == length.intValue else { throw MerianError.invalidResponse }
            ledger = try JSONDecoder().decode(Ledger.self, from: bytes)
        } else {
            guard let witness,
                  let state = try JSONSerialization.jsonObject(with: witness.baselineState) as? [String: Any],
                  state["selected_analysis_id"] as? String == identity.sourceAnalysisID.uuidString.lowercased() else {
                throw MerianError.invalidResponse
            }
            ledger = Ledger(witness: witness, selected: identity.sourceAnalysisID.uuidString.lowercased(),
                revision: try ObservationHistoryPage.integer(state["state_revision"]))
            try persist(ledger)
        }
        try ReanalysisRecoveryUIResult.validate(ledger.witness, identity: identity, media: media)
        guard snapshots[ledger.selected] != nil, ledger.revision > 0, ledger.reviewRevision >= 0,
              ledger.available ? ledger.chargedWhenAvailable == 30_000 : ledger.chargedWhenAvailable == nil,
              Set(ledger.selectionRequests.keys) == Set(ledger.selectionReceipts.keys),
              Set(ledger.reviewRequests.keys) == Set(ledger.reviewReceipts.keys) else { throw MerianError.invalidResponse }
    }

    var snapshots: [String: Data] {
        var rows = witness.snapshots
        if ledger.available { rows[witness.child.uuidString.lowercased()] = witness.result }
        return rows
    }
    var cloud: ObservationHistoryCloudClient {
        var cloud = baseline
        cloud.fetch = { [self] request in
            guard request.observation_id == witness.observation.uuidString.lowercased(),
                  request.before_ordinal == nil, request.limit == 20 else { throw MerianError.invalidResponse }
            let items: [[String: Any]] = try snapshots.values.map { bytes in
                guard let row = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let snapshotText = String(bytes: bytes, encoding: .utf8) else { throw MerianError.invalidResponse }
                return ["ordinal": try ObservationHistoryPage.integer(row["ordinal"]), "snapshot": snapshotText]
            }.sorted { ($0["ordinal"] as? Int ?? 0) > ($1["ordinal"] as? Int ?? 0) }
            return try Self.json(["schema_version": 1, "owner_id": witness.owner.uuidString.lowercased(),
                "observation_id": request.observation_id,
                "state_revision": ledger.revision, "next_before_ordinal": NSNull(), "items": items])
        }
        cloud.fetchState = { [self] request in
            guard request.observation_id == witness.observation.uuidString.lowercased() else { throw MerianError.invalidResponse }
            return try state(request.analysis_id ?? ledger.selected)
        }
        cloud.select = { [self] request in try select(request) }
        return cloud
    }

    func makeAvailable() throws {
        let identity = OfflineQueueWork.Reanalysis(observationID: witness.observation, sourceAnalysisID: witness.source,
            analysisID: witness.child, ownerID: witness.owner)
        let budget = try ObservationReanalysisRecoveryPresentationStore.read(identity, container: container, isCurrent: { true })
        guard budget.value.chargedMilliseconds == 30_000, budget.value.activeReservationID == nil,
              !ledger.available else { throw MerianError.invalidResponse }
        var next = ledger; next.available = true; next.chargedWhenAvailable = budget.value.chargedMilliseconds; try commit(next)
    }

    func verifyTerminal() throws {
        guard ledger.available else { throw MerianError.invalidResponse }
        try ReanalysisRecoveryUIResult.verifyTerminal(witness, container: container, root: root)
        let parent = try ObservationHistorySyncService.enrolledScan(witness.observation.uuidString, context: ModelContext(container))
        guard parent.selectedAnalysisID == ledger.selected else { throw MerianError.invalidResponse }
        let reviews = try ModelContext(container).fetch(FetchDescriptor<OfflineJobRecord>()).filter { $0.kind == .observationAnalysisReviewSync }
        guard reviews.count == ledger.reviewRequests.count else { throw MerianError.invalidResponse }
        for job in reviews {
            let intent = try ObservationAnalysisReviewPersistence.restore(job), key = intent.request.operationID.uuidString.lowercased()
            guard intent.isComplete, try intent.request.encoded() == ledger.reviewRequests[key],
                  let bytes = ledger.reviewReceipts[key],
                  intent.receipt == (try ObservationAnalysisReviewReceipt.decode(bytes, request: intent.request)) else { throw MerianError.invalidResponse }
        }
    }

    func hasTerminalReceipt() throws -> Bool {
        try ModelContext(container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(witness.child)) != nil
    }

    func open() throws -> IdentificationHistoryViewModel {
        try verifyTerminal()
        let owner = witness.owner
        let session = try IdentificationHistorySession(observation: witness.observation.uuidString.lowercased(),
            container: container, cloud: cloud, reviewWake: { [self] in wake() }, reviewGeneration: { [self] in generation },
            currentGeneration: { 1 }, sessionIsCurrent: { $0.userID == owner && !$0.isAnonymous })
        return IdentificationHistoryViewModel(dependencies: session.dependencies)
    }

    private func state(_ target: String) throws -> Data {
        guard let snapshot = snapshots[target],
              var state = try JSONSerialization.jsonObject(with: witness.baselineState) as? [String: Any],
              var analysis = state["analysis"] as? [String: Any] else { throw MerianError.invalidResponse }
        state["selected_analysis_id"] = ledger.selected; state["state_revision"] = ledger.revision
        guard let snapshotText = String(bytes: snapshot, encoding: .utf8) else { throw MerianError.invalidResponse }
        analysis["snapshot"] = snapshotText
        analysis["review_revision"] = target == witness.child.uuidString.lowercased() ? ledger.reviewRevision : 0
        if target == witness.child.uuidString.lowercased(), let bytes = ledger.latestReview {
            let request = try ObservationAnalysisReviewRequest.decode(bytes)
            guard var authority = analysis["review_snapshot"] as? [String: Any] else { throw MerianError.invalidResponse }
            authority["ai_identification_review"] = ["version": 1, "revision": ledger.reviewRevision,
                "state": ledger.cleared ? "clear" : "ai_rejected", "origin_scan_id": witness.observation.uuidString.lowercased(),
                "origin_identification": NSNull(), "operation_id": request.operationID.uuidString.lowercased(),
                "operation_digest": String(repeating: ledger.cleared ? "b" : "a", count: 32), "community": NSNull()] as [String: Any]
            authority["confirmed_species_identity_revision"] = ledger.reviewRevision
            analysis["review_snapshot"] = authority
        }
        state["analysis"] = analysis
        return try Self.json(state)
    }

    private func select(_ request: ObservationHistorySelectionRequest) throws -> Data {
        try request.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(request)
        guard ledger.available, request.observation_id == witness.observation.uuidString.lowercased(),
              snapshots[request.analysis_id] != nil, ledger.reviewRequests[request.operation_id] == nil else { throw MerianError.invalidResponse }
        if let saved = ledger.selectionRequests[request.operation_id] {
            guard saved == bytes, let receipt = ledger.selectionReceipts[request.operation_id] else { throw MerianError.invalidResponse }
            return receipt
        }
        guard request.expected_observation_revision == ledger.revision,
              request.expected_review_revision == (request.analysis_id == witness.child.uuidString.lowercased() ? ledger.reviewRevision : 0),
              ledger.selectionRequests.count < 8 else { throw MerianError.invalidResponse }
        let receipt = try encoder.encode(ObservationHistorySelectionReceipt(schema_version: 1, operation_id: request.operation_id,
            observation_id: request.observation_id, previous_analysis_id: ledger.selected, selected_analysis_id: request.analysis_id,
            observation_revision: ledger.revision + 1, review_revision: request.expected_review_revision))
        var next = ledger; next.selected = request.analysis_id; next.revision += 1
        next.selectionRequests[request.operation_id] = bytes; next.selectionReceipts[request.operation_id] = receipt
        try commit(next); return receipt
    }

    private func submit(_ request: ObservationAnalysisReviewRequest, owner: UUID) throws -> ObservationAnalysisReviewReceipt {
        let bytes = try request.encoded(), key = request.operationID.uuidString.lowercased()
        guard ledger.available, owner == witness.owner, request.observationID == witness.observation,
              request.analysisID == witness.child, ledger.selectionRequests[key] == nil else { throw MerianError.invalidResponse }
        if let saved = ledger.reviewRequests[key] {
            guard saved == bytes, let receipt = ledger.reviewReceipts[key] else { throw MerianError.invalidResponse }
            return try ObservationAnalysisReviewReceipt.decode(receipt, request: request)
        }
        guard ledger.selected == witness.child.uuidString.lowercased(), request.expectedObservationRevision == ledger.revision,
              request.expectedReviewRevision == ledger.reviewRevision, ledger.reviewRequests.count < 2,
              var row = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw MerianError.invalidResponse }
        var next = ledger
        switch request.decision {
        case .reject:
            guard ledger.latestReview == nil else { throw MerianError.invalidResponse }
            next.rejectedOperation = request.operationID; next.cleared = false
        case let .undo(operation):
            guard ledger.rejectedOperation == operation, !ledger.cleared else { throw MerianError.invalidResponse }
            next.cleared = true
        default: throw MerianError.invalidResponse
        }
        row["outcome"] = "applied"; row["observation_revision"] = ledger.revision + 1; row["review_revision"] = ledger.reviewRevision + 1
        let data = try Self.json(row), receipt = try ObservationAnalysisReviewReceipt.decode(data, request: request)
        next.revision += 1; next.reviewRevision += 1; next.latestReview = bytes
        next.reviewRequests[key] = bytes; next.reviewReceipts[key] = data
        try commit(next); return receipt
    }

    private func wake() {
        let cloud = cloud, container = container, owner = witness.owner
        let service = ObservationAnalysisReviewDeliveryService(cloud: cloud, submit: { [self] request, suppliedOwner, validate in
            try validate(); let receipt = try submit(request, owner: suppliedOwner); try validate(); return receipt
        })
        delivery.start(operation: { [self] current in
            await ObservationAnalysisReviewDrain(cloud: cloud, deliver: service.deliver)
                .run(ownerID: owner, container: container, isCurrent: current, didStart: {},
                     requestRetry: { [weak self] in self?.failure = "Synthetic review requires unexpected retry" })
        }, didFinish: { [self] in generation &+= 1 })
    }

    private func commit(_ next: Ledger) throws { try persist(next); ledger = next }
    private func persist(_ value: Ledger) throws {
        guard file.resolvingSymlinksInPath() == file.standardizedFileURL else { throw MerianError.invalidResponse }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= 1_048_576 else { throw MerianError.invalidResponse }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
#endif
