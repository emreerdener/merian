#if DEBUG
import CryptoKit
import Foundation
import SwiftData

/// Independent, immutable synthetic-server witness. It never writes app records.
@MainActor enum ReanalysisRecoveryUIResult {
    struct Witness: Codable {
        let version: Int
        let media: String
        let owner: UUID
        let observation: UUID
        let source: UUID
        let child: UUID
        let request: Data
        let result: Data
        let baselineState: Data
        let snapshots: [String: Data]
        let originalFingerprint: String
        let mediaHashes: [String: String]
    }

    static func create(media: String, identity: OfflineQueueWork.Reanalysis, root: URL,
                       container: ModelContainer, cloud: ObservationHistoryCloudClient,
                       fingerprint: String) async throws -> Witness {
        guard UITestSeedCoordinator.reanalysisRecoveryRestartEnabled,
              UITestSeedCoordinator.reanalysisRecoverySuccessEnabled else { throw MerianError.invalidResponse }
        let context = ModelContext(container); context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<LocalAnalysisRecord>())
        let snapshots = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.resultSnapshotData) })
        guard records.count == 2, let source = snapshots[identity.sourceAnalysisID.uuidString.lowercased()],
              let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: identity.analysisID.uuidString.lowercased())),
              let metadata = job.metadataJSON else { throw MerianError.invalidResponse }
        let request: Data
        switch media {
        case "photo": request = try ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: { true }).intent.request.body
        case "audio": request = try ObservationAudioExecutionIntent.Work.decode(Data(metadata.utf8)).intent.request.body
        case "video": request = try ObservationVideoExecutionWork.decode(Data(metadata.utf8)).request.body
        default: throw MerianError.invalidResponse
        }
        guard let input = try JSONSerialization.jsonObject(with: request) as? [String: Any],
              var result = try JSONSerialization.jsonObject(with: source) as? [String: Any],
              var identification = result["result"] as? [String: Any] else { throw MerianError.invalidResponse }
        for key in ["observation_id", "analysis_id", "source_analysis_id", "request_digest", "evidence_manifest"] { result[key] = input[key] }
        result["schema_version"] = media == "photo" ? 2 : (media == "audio" ? 4 : 5)
        result["ordinal"] = 3; result["completed_at_ms"] = 1_780_000_000_000 as Int64
        identification["scan_id"] = identity.observationID.uuidString.lowercased()
        identification["common_name"] = "Recovered Butterfly"
        result["result"] = identification
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
        let stateRequest = ObservationHistoryStateRequest(observation_id: identity.observationID.uuidString.lowercased(),
            analysis_id: identity.sourceAnalysisID.uuidString.lowercased())
        let state = try await cloud.fetchState(stateRequest)
        _ = try ObservationHistoryState.decode(state, request: stateRequest, ownerID: identity.ownerID)
        let witness = Witness(version: 1, media: media, owner: identity.ownerID, observation: identity.observationID,
            source: identity.sourceAnalysisID, child: identity.analysisID, request: request, result: bytes,
            baselineState: state, snapshots: snapshots, originalFingerprint: fingerprint,
            mediaHashes: try mediaHashes(root: root, child: identity.analysisID))
        try validate(witness, identity: identity, media: media)
        return witness
    }

    static func validate(_ witness: Witness, identity: OfflineQueueWork.Reanalysis, media: String) throws {
        guard witness.version == 1, witness.media == media, witness.owner == identity.ownerID,
              witness.observation == identity.observationID, witness.source == identity.sourceAnalysisID,
              witness.child == identity.analysisID, witness.snapshots.count == 2,
              witness.snapshots[witness.child.uuidString.lowercased()] == nil,
              witness.snapshots[witness.source.uuidString.lowercased()] != nil,
              witness.originalFingerprint.count == 64 else { throw MerianError.invalidResponse }
        let result: ObservationHistoryPage.Result
        switch media {
        case "photo": result = try ObservationReanalysisResult.decode(witness.result, matching: ObservationReanalysisRequest(savedBody: witness.request))
        case "audio": result = try ObservationReanalysisResult.decode(witness.result, matching: ObservationAudioReanalysisRequest(savedBody: witness.request))
        case "video": result = try ObservationReanalysisResult.decode(witness.result, matching: ObservationVideoReanalysisRequest(savedBody: witness.request))
        default: throw MerianError.invalidResponse
        }
        guard let input = try JSONSerialization.jsonObject(with: witness.request) as? [String: Any],
              input["observation_id"] as? String == identity.observationID.uuidString.lowercased(),
              input["analysis_id"] as? String == identity.analysisID.uuidString.lowercased(),
              input["source_analysis_id"] as? String == identity.sourceAnalysisID.uuidString.lowercased(),
              let snapshot = try JSONSerialization.jsonObject(with: result.bytes) as? [String: Any],
              try ObservationHistoryPage.integer(snapshot["ordinal"]) == 3,
              result.analysisID == identity.analysisID else { throw MerianError.invalidResponse }
    }

    /// Intent-only qualification: the real pending erasure receipt must survive;
    /// this batch never calls teardown deletion or claims filesystem cleanup.
    static func verifyTerminal(_ witness: Witness, container: ModelContainer, root: URL) throws {
        let context = ModelContext(container); context.autosaveEnabled = false
        let child = witness.child.uuidString.lowercased()
        let records = try context.fetch(FetchDescriptor<LocalAnalysisRecord>())
        var expected = witness.snapshots; expected[child] = witness.result
        guard records.count == 3, records.allSatisfy({ $0.ownerAccountID == witness.owner.uuidString.lowercased()
                  && $0.observationID == witness.observation.uuidString.lowercased() && expected[$0.id] == $0.resultSnapshotData }),
              Set(records.map(\.id)) == Set(expected.keys),
              try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1,
              try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0,
              try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: child)) == nil,
              let receipt = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(witness.child)),
              receipt.status == .pending,
              try ObservationReanalysisErasureReceipt.restore(receipt) == .init(parentID: witness.observation, childID: witness.child),
              try mediaHashes(root: root, child: witness.child) == witness.mediaHashes else { throw MerianError.invalidResponse }
    }

    static func mediaHashes(root: URL, child: UUID) throws -> [String: String] {
        let directory = root.appendingPathComponent("ReanalysisQueue/" + child.uuidString.lowercased(), isDirectory: true)
        guard directory.resolvingSymlinksInPath() == directory.standardizedFileURL else { throw MerianError.invalidResponse }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard (1...7).contains(files.count) else { throw MerianError.invalidResponse }
        return try Dictionary(uniqueKeysWithValues: files.map { file in
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard file.resolvingSymlinksInPath() == file.standardizedFileURL,
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, (1...12_582_912).contains(size.intValue) else { throw MerianError.invalidResponse }
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            let data = try handle.read(upToCount: size.intValue + 1) ?? Data()
            guard data.count == size.intValue else { throw MerianError.invalidResponse }
            return (file.lastPathComponent, digest(data))
        })
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
