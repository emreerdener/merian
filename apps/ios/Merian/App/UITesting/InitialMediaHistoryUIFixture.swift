#if DEBUG
import Foundation
import Observation
import SwiftData

extension UITestSeedCoordinator {
    static var initialMediaHistoryEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-seedInitialMediaHistory")
    }
}

/// One disposable ordinary initial submission. The retained witness is a test
/// oracle; app records are written only by completion/enrollment/History owners.
@MainActor @Observable final class InitialMediaHistoryUIFixture {
    let container: ModelContainer
    let root: URL
    let reopened: Bool
    let di = AppDIContainer.preview
    let witness: InitialMediaHistoryUISubmission.Witness
    let state: Data
    private let enrollment = ObservationHistoryEnrollmentOwner()
    private(set) var failure = ""
    private(set) var selected = "none"
    private(set) var enrollments = 0
    private(set) var history: IdentificationHistoryViewModel?
    private(set) var busy = false
    var resultPresented = false
    var historyPresented = false
    var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return InitialMediaHistoryUISubmission.digest((try? encoder.encode(witness)) ?? Data())
    }
    var route: QueuedScanContext { .init(id: witness.scan, capturedMediaItems: witness.submitted,
        queueState: .inferencing, timestamp: witness.timestamp) }

    init(progress: (String) -> Void) async throws {
        guard UITestSeedCoordinator.initialMediaHistoryEnabled,
              let raw = ProcessInfo.processInfo.environment["UITestKeychainNamespace"], let namespace = UUID(uuidString: raw),
              let media = ProcessInfo.processInfo.environment["InitialHistoryMedia"], ["photo", "audio", "video"].contains(media),
              let text = ProcessInfo.processInfo.environment["InitialHistoryText"], ["yes", "no"].contains(text) else { throw MerianError.invalidResponse }
        root = URL.applicationSupportDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("initial-media-history-ui-" + namespace.uuidString, isDirectory: true)
        guard root.resolvingSymlinksInPath() == root.standardizedFileURL else { throw MerianError.invalidResponse }
        progress("directory")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var url = root, values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
        let store = root.appendingPathComponent("history.store"), receipt = root.appendingPathComponent("witness.json")
        guard store.resolvingSymlinksInPath() == store.standardizedFileURL else { throw MerianError.invalidResponse }
        reopened = FileManager.default.fileExists(atPath: store.path)
        progress("container")
        let schema = Schema(versionedSchema: CurrentSchema.self)
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: store, cloudKitDatabase: .none)])
        if reopened {
            progress("retained witness")
            witness = try JSONDecoder().decode(InitialMediaHistoryUISubmission.Witness.self, from: Self.read(receipt))
            state = try Self.read(root.appendingPathComponent("synthetic-state.json"))
        } else {
            progress("ordinary submission and terminal completion")
            witness = try await InitialMediaHistoryUISubmission.create(media: media, withText: text == "yes", root: root,
                container: container, di: di, progress: progress)
            progress("synthetic baseline")
            state = try Self.makeState(witness)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try Self.write(encoder.encode(witness), to: receipt)
            try Self.write(state, to: root.appendingPathComponent("synthetic-state.json"))
        }
        guard witness.media == media, witness.withText == (text == "yes"), witness.owner == PublicationConsentUIFixture.owner,
              witness.proof.scanID.uuidString.lowercased() == witness.scan,
              witness.proof.ownerID == witness.owner, witness.proof.generation == witness.generation else { throw MerianError.invalidResponse }
        progress("terminal verification")
        try verify()
    }

    func verify() throws {
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<LocalScanRecord>())
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>()).filter { $0.kind == .scanIngestion }
        guard records.count == 1, let record = records.first, record.id == witness.scan,
              record.speciesId == witness.proof.speciesID,
              try OrdinaryInferenceCompletion.Projection(record) == witness.proof.projection,
              CapturedMediaSnapshot(jsonString: record.capturedMediaJSON).items == witness.submitted,
              try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0,
              jobs.count == 1, jobs[0].subjectId == witness.scan, jobs[0].status == .complete,
              let raw = jobs[0].metadataJSON,
              let metadata = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let saved = metadata[OrdinaryInferenceCompletion.metadataKey],
              try JSONDecoder().decode(OrdinaryInferenceCompletion.Proof.self,
                  from: JSONSerialization.data(withJSONObject: saved, options: [.sortedKeys])) == witness.proof else { throw MerianError.invalidResponse }
        for (path, hash) in witness.retained {
            guard try InitialMediaHistoryUISubmission.digest(Data(contentsOf: InitialMediaHistoryUISubmission.ownedMedia(path))) == hash else { throw MerianError.invalidResponse }
        }
        let analyses = try context.fetch(FetchDescriptor<LocalAnalysisRecord>())
        if let selection = record.selectedAnalysisID {
            guard selection == witness.baseline.uuidString.lowercased(), record.analysisOwnerAccountID == witness.owner.uuidString.lowercased(),
                  analyses.count == 1, let row = analyses.first,
                  row.resultSnapshotData == (try snapshot()), row.snapshotVersion == 3 else { throw MerianError.invalidResponse }
            selected = selection
        } else {
            guard analyses.isEmpty, try OrdinaryInferenceCompletion.retained(for: record, owner: witness.owner, context: context) == witness.proof else { throw MerianError.invalidResponse }
            selected = "none"
        }
    }

    func openResult() {
        do { try verify(); resultPresented = true } catch { failure = "Terminal result changed" }
    }
    func addHistory() async {
        guard !busy, selected == "none" else { return }
        busy = true; defer { busy = false }
        do {
            try verify()
            let baseline = try await enrollment.continueInitialHistory(observation: witness.proof.scanID, owner: witness.owner,
                generation: 1, container: container, cloud: cloud, isCurrent: { true })
            guard baseline == witness.baseline else { throw MerianError.invalidResponse }
            try verify()
        } catch { failure = "Initial History enrollment failed" }
    }
    func openHistory() {
        do {
            try verify(); guard selected != "none" else { throw MerianError.invalidResponse }
            let owner = witness.owner
            let session = try IdentificationHistorySession(observation: witness.scan, container: container, cloud: cloud,
                currentGeneration: { 1 }, sessionIsCurrent: { $0.userID == owner && !$0.isAnonymous })
            history = IdentificationHistoryViewModel(dependencies: session.dependencies); historyPresented = true
        } catch { failure = "Initial History could not open" }
    }

    private var cloud: ObservationHistoryCloudClient {
        var value = ObservationHistoryCloudClient(begin: { [self] owner in
            guard owner == witness.owner else { throw MerianError.invalidResponse }
            return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false))
        }, isCurrent: { [self] lease in lease.session.userID == witness.owner && !lease.session.isAnonymous }, finish: { _ in },
        fetch: { [self] request in
            guard request.observation_id == witness.scan, request.before_ordinal == nil, request.limit == 20 else { throw MerianError.invalidResponse }
            guard let snapshotText = String(bytes: try snapshot(), encoding: .utf8) else { throw MerianError.invalidResponse }
            return try Self.json(["schema_version": 1, "owner_id": witness.owner.uuidString.lowercased(),
                "observation_id": witness.scan, "state_revision": 1, "next_before_ordinal": NSNull(),
                "items": [["ordinal": 1, "snapshot": snapshotText]]])
        })
        value.enroll = { [self] observation in
            guard observation == witness.proof.scanID, enrollments == 0 else { throw MerianError.invalidResponse }
            enrollments += 1
            return try Self.json(["schema_version": 1, "owner_id": witness.owner.uuidString.lowercased(),
                "observation_id": witness.scan, "baseline_analysis_id": witness.baseline.uuidString.lowercased()])
        }
        value.fetchState = { [self] request in
            guard request.observation_id == witness.scan,
                  request.analysis_id == nil || request.analysis_id == witness.baseline.uuidString.lowercased() else { throw MerianError.invalidResponse }
            return state
        }
        return value
    }
    private func snapshot() throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: state) as? [String: Any],
              let analysis = object["analysis"] as? [String: Any], let string = analysis["snapshot"] as? String else { throw MerianError.invalidResponse }
        return Data(string.utf8)
    }
    private static func makeState(_ witness: InitialMediaHistoryUISubmission.Witness) throws -> Data {
        guard let encoded = ProcessInfo.processInfo.environment["InitialHistoryState"], encoded.count < 32_768,
              let bytes = Data(base64Encoded: encoded), bytes.count < 24_576,
              var state = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              var analysis = state["analysis"] as? [String: Any], let text = analysis["snapshot"] as? String,
              var snapshot = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw MerianError.invalidResponse }
        let proof = witness.proof, p = proof.projection
        func jsonValue(_ bytes: Data?) throws -> Any {
            guard let bytes else { return NSNull() }
            return try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
        }
        snapshot["analysis_id"] = witness.baseline.uuidString.lowercased(); snapshot["observation_id"] = witness.scan
        snapshot["result"] = ["scan_id": witness.scan, "species_id": proof.speciesID.lowercased(),
            "ai_confidence_score": p.confidence as Any? ?? NSNull(), "is_biological_subject": p.biological,
            "ai_reasoning": p.reasoning as Any? ?? NSNull(), "inference_tier": p.tier as Any? ?? NSNull(),
            "primary_identification": try jsonValue(p.primary), "identification_provenance": try jsonValue(p.provenance),
            "candidates": try jsonValue(p.candidates), "pet_identification": try jsonValue(p.pet)]
        guard let snapshotText = String(bytes: try json(snapshot), encoding: .utf8) else { throw MerianError.invalidResponse }
        analysis["snapshot"] = snapshotText
        state["analysis"] = analysis; state["owner_id"] = witness.owner.uuidString.lowercased()
        state["observation_id"] = witness.scan; state["selected_analysis_id"] = witness.baseline.uuidString.lowercased()
        return try json(state)
    }
    private static func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private static func write(_ bytes: Data, to file: URL) throws {
        guard bytes.count <= 1_048_576, file.resolvingSymlinksInPath() == file.standardizedFileURL else { throw MerianError.invalidResponse }
        try bytes.write(to: file, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private static func read(_ file: URL) throws -> Data {
        guard file.resolvingSymlinksInPath() == file.standardizedFileURL else { throw MerianError.invalidResponse }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, (1...1_048_576).contains(size.intValue) else { throw MerianError.invalidResponse }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: size.intValue + 1) ?? Data()
        guard bytes.count == size.intValue else { throw MerianError.invalidResponse }; return bytes
    }
}
#endif
