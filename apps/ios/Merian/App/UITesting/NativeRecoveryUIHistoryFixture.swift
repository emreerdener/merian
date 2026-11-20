#if DEBUG
import Foundation
import SwiftData

private func nativeRecoveryRequired<T>(_ value: T?) throws -> T {
    guard let value else { throw SharedMediaStorageFailure.invalid }; return value
}

/// Synthetic documents for the explicit rendered History continuation. All
/// durable state is still produced by native and enrollment owners. This does
/// not confer server authority or enable any ordinary-app network path.
@MainActor
final class NativeRecoveryUIHistoryFixture {
    private struct Recovery: Decodable {
        let reference: String, provenance: String, receipt: String, projection: String
    }
    private let resultFixture: Data
    private let recoveryFixture: Recovery
    private let stateFixture: Data
    private let baselineID = UUID()
    private let enrollmentOwner = ObservationHistoryEnrollmentOwner()
    private let sessionGeneration: UInt64 = 1
    private var acquisition: InitialCompletionDocuments.CpmAcquisition?
    private(set) var enrollments = 0
    private(set) var completionReads = 0
    let routes = AppRouteCoordinator()

    init() throws {
        guard UITestSeedCoordinator.nativeRecoveryHistoryEnabled,
              let encoded = ProcessInfo.processInfo.environment["NativeRecoveryHistoryFixtures"],
              encoded.utf8.count <= 32768, let bytes = Data(base64Encoded: encoded),
              bytes.count <= 24576, bytes.base64EncodedString() == encoded,
              let packet = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(packet.keys) == ["result", "recovery", "state"],
              let result = packet["result"] as? String else { throw SharedMediaStorageFailure.invalid }
        resultFixture = Data(result.utf8)
        recoveryFixture = try JSONDecoder().decode(Recovery.self, from: JSONSerialization.data(withJSONObject: nativeRecoveryRequired(packet["recovery"])))
        stateFixture = try JSONSerialization.data(withJSONObject: nativeRecoveryRequired(packet["state"]))
    }

    func allocate(_ prepared: SharedMediaNativeReceivingIntent.Prepared, owner: SharedMediaNativeOriginalOwner) async throws {
        _ = try await owner.allocateAppPhotoRoles(prepared, backendBinding: true, authorizeCreate: { value, validate in
            try validate()
            guard let admission = value.photoAdmission else { throw SharedMediaStorageFailure.closed }
            return .init(recipient: admission.expectedProcessorPermission, validate: {})
        }) { request, validate, settle in
            try validate(); try settle()
            let entries = try SharedMediaNativePhotoRoleMapping.references(request.allocation.claim).enumerated().map { index, reference in
                SharedMediaNativePhotoRoleMapping.Entry(photoOrdinal: index / 3,
                    role: SharedMediaNativePhotoRoleMapping.Role.allCases[index % 3], referenceID: reference, objectID: UUID())
            }
            return .allocated(.init(receipt: .init(assignmentDigest: String(repeating: "a", count: 64),
                createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001), entries: entries,
                backendBinding: .init(generation: UUID(uuidString: "00000000-0000-4000-8000-000000000400")!,
                    configurationDigest: String(repeating: "c", count: 64))))
        }
    }

    func complete(_ candidate: SharedMediaNativeReceivedCandidate, owner: SharedMediaNativeOriginalOwner,
                  container: ModelContainer, validate: @escaping NativeReceivedStatusTransport.Validator) async throws -> NativeHistoryAssociation? {
        try validate()
        guard let initial = try await owner.discoverAppInitialContinuation(candidate) else { throw SharedMediaStorageFailure.closed }
        let observationID = initial.prepared.observationID
        return try await CaptureNativeRecoveryModel.completeInitialHistory(candidate, owner: owner,
            isCurrent: { (try? validate()) != nil }, readAdmission: { [self] allocation, check in
                try check(); return try originalAcknowledgement(allocation)
            }, readCompletion: { [self] admission, check in
                try check(); completionReads += 1
                let value = try completionAcquisition(admission)
                acquisition = value
                return value
            }, enroll: { [self] observation in
                try validate()
                guard observation == observationID else { throw SharedMediaStorageFailure.conflict }
                try await enroll(ownerID: candidate.profile.ownerID, observationID: observation,
                    acquisition: nativeRecoveryRequired(acquisition), container: container, validate: validate)
            })
    }

    func open(_ association: NativeHistoryAssociation, container: ModelContainer) throws {
        try association.validate()
        guard try selection(container) == baselineID.uuidString.lowercased() else { throw SharedMediaStorageFailure.conflict }
        let rows = try ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>())
        guard rows.count == 1, rows.first?.id == association.observationID.uuidString.lowercased(),
              rows.first?.analysisOwnerAccountID == association.ownerID.uuidString.lowercased() else { throw SharedMediaStorageFailure.conflict }
        routes.request(.scan(scanId: association.observationID.uuidString.lowercased()), source: .internalUserAction)
        guard routes.pendingRequests.count == 1,
              routes.pendingRequests.first?.route == .scan(scanId: association.observationID.uuidString.lowercased()) else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    func selection(_ container: ModelContainer) throws -> String {
        let rows = try ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>())
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first?.selectedAnalysisID ?? "none"
    }

    private func enroll(ownerID: UUID, observationID: UUID, acquisition: InitialCompletionDocuments.CpmAcquisition,
                        container: ModelContainer, validate: @escaping NativeReceivedStatusTransport.Validator) async throws {
        try validate()
        let observation = observationID.uuidString.lowercased(), baseline = baselineID.uuidString.lowercased()
        func originalField(_ key: String) throws -> Any {
            guard let bytes = try acquisition.result.applicationFieldJSON(key) else { return NSNull() }
            return try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
        }
        let projection = try nativeRecoveryRequired(JSONSerialization.jsonObject(with: acquisition.record.projection) as? [String: Any])
        let association = projection["species_association"] as? [String: Any]
        var state = try nativeRecoveryRequired(JSONSerialization.jsonObject(with: stateFixture) as? [String: Any])
        state["owner_id"] = ownerID.uuidString.lowercased(); state["observation_id"] = observation
        state["selected_analysis_id"] = baseline
        var analysis = try nativeRecoveryRequired(state["analysis"] as? [String: Any])
        let sourceSnapshot = try nativeRecoveryRequired(analysis["snapshot"] as? String)
        var snapshot = try nativeRecoveryRequired(JSONSerialization.jsonObject(with: Data(sourceSnapshot.utf8)) as? [String: Any])
        snapshot["observation_id"] = observation; snapshot["analysis_id"] = baseline
        snapshot["result"] = ["scan_id": observation, "species_id": association?["species_id"] ?? NSNull(),
            "primary_identification": try originalField("primary_identification"),
            "identification_provenance": try JSONSerialization.jsonObject(with: acquisition.result.applicationProvenance()),
            "is_biological_subject": try originalField("is_biological_subject"), "candidates": try originalField("candidates"),
            "pet_identification": try originalField("pet_identification"), "ai_confidence_score": try originalField("confidence_score"),
            "ai_reasoning": try originalField("ai_reasoning"), "inference_tier": try originalField("inference_tier")] as [String: Any]
        guard let snapshotText = String(bytes: try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
                                        encoding: .utf8) else { throw MerianError.invalidResponse }
        analysis["snapshot"] = snapshotText
        state["analysis"] = analysis
        let stateData = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        let receipt = try JSONSerialization.data(withJSONObject: ["schema_version": 1, "owner_id": ownerID.uuidString.lowercased(),
            "observation_id": observation, "baseline_analysis_id": baseline])
        let current: @MainActor () -> Bool = { (try? validate()) != nil }
        var acquired = 0, released = 0
        var cloud = ObservationHistoryCloudClient(begin: { expected in
            try validate()
            guard expected == ownerID else { throw SharedMediaStorageFailure.stale }
            acquired += 1
            return AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: ownerID, isAnonymous: false))
        }, isCurrent: { lease in
            lease.session.userID == ownerID && !lease.session.isAnonymous && current()
        }, finish: { _ in released += 1 }, fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.enroll = { [self] requested in
            guard requested == observationID, enrollments == 0 else { throw SharedMediaStorageFailure.conflict }
            enrollments += 1; return receipt
        }
        cloud.fetchState = { request in
            guard request.observation_id == observation, request.analysis_id == nil else { throw SharedMediaStorageFailure.conflict }
            return stateData
        }
        let selected = try await enrollmentOwner.continueInitialHistory(observation: observationID,
            owner: ownerID, generation: sessionGeneration, container: container, cloud: cloud, isCurrent: current)
        try validate()
        guard selected == baselineID, acquired == 1, released == 1, enrollments == 1,
              try selection(container) == baseline else { throw SharedMediaStorageFailure.conflict }
    }

    private func completionAcquisition(_ admission: InitialCompletionDocuments.CpmAdmission,
                                       reasoning: String? = nil) throws -> InitialCompletionDocuments.CpmAcquisition {
        let record = try completionRecord(admission)
        let reference = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(record.reference).object)
        var result = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(resultFixture).object)
        for key in ["scan_id", "invocation_id", "submission_digest", "config_digest", "funding_binding_digest"] { result[key] = reference[key] }
        var data = try nativeRecoveryRequired(result["data"]?.object)
        data["scan_id"] = reference["scan_id"]
        if let reasoning { data["ai_reasoning"] = .string(reasoning) }
        result["data"] = .object(data)
        let resultBytes = try InitialAnalysisCanonical.encode(.object(result))
        let digest = SharedMediaAcquisitionEncoding.digest(Data("merian.initial-analysis.result.v1\n".utf8) + resultBytes)
        let retained = try InitialRetainedResult(reference: record.reference, result: resultBytes, provenance: record.originalProvenance,
            resultDigest: digest, provenanceDigest: SharedMediaAcquisitionEncoding.digest(Data("merian.initial-analysis.result-provenance.v1\n".utf8) + record.originalProvenance),
            expectedReference: record.reference, originalProvenance: record.originalProvenance)
        var r = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(record.receipt).object)
        var p = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(record.projection).object)
        r["result_digest"] = .string(digest); p["result_digest"] = .string(digest)
        let projection = try InitialAnalysisCanonical.encode(.object(p))
        r["completion_projection_digest"] = .string(SharedMediaAcquisitionEncoding.digest(Data("merian.initial-analysis.completion-projection.v1\n".utf8) + projection))
        return try .init(result: retained,
            documents: .init(receipt: InitialAnalysisCanonical.encode(.object(r)), projection: projection), admission: admission)
    }

    private func completionRecord(_ admission: InitialCompletionDocuments.CpmAdmission) throws -> InitialCompletionDocuments.CpmRecoveryRecord {
        let fixture = recoveryFixture
        let a = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(admission.admission).object)
        var r = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(Data(fixture.receipt.utf8)).object)
        var p = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(Data(fixture.projection.utf8)).object)
        for (key, value) in a { r[key] = value }
        r["operation_id"] = a["scan_id"]
        p["owner_id"] = a["owner_id"]; p["scan_id"] = a["scan_id"]
        var capture = try nativeRecoveryRequired(p["capture_context"]?.object)
        capture["submission_digest"] = a["submission_digest"]; p["capture_context"] = .object(capture)
        let projection = try InitialAnalysisCanonical.encode(.object(p))
        r["completion_projection_digest"] = .string(SharedMediaAcquisitionEncoding.digest(
            Data("merian.initial-analysis.completion-projection.v1\n".utf8) + projection))
        var reference = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(Data(fixture.reference.utf8)).object)
        for key in reference.keys where key != "invocation_id" { reference[key] = r[key] }
        return try .init(reference: InitialAnalysisCanonical.encode(.object(reference)),
            originalProvenance: Data(fixture.provenance.utf8),
            documents: .init(receipt: InitialAnalysisCanonical.encode(.object(r)), projection: projection), admission: admission)
    }

    func originalAcknowledgement(_ allocation: SharedMediaNativePhotoAllocation) throws -> Data {
        typealias CanonicalValue = InitialAnalysisCanonical.Value
        let original = try InitialCompletionDocuments.CpmBinding.saved(allocation)
        let candidate = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(Data(original.candidateCanonical.utf8)).object)
        let contentText = try nativeRecoveryRequired(candidate["content_canonical"]?.string)
        let content = try nativeRecoveryRequired(InitialAnalysisCanonical.parse(Data(contentText.utf8)).object)
        let contexts = try nativeRecoveryRequired(content["contexts"]?.array)
        let contextBytes = try InitialAnalysisCanonical.encode(.array(contexts))
        let hash = String(repeating: "c", count: 64)
        let admission = try InitialAnalysisCanonical.encode(.object([
            "version": .integer(1), "owner_id": .string(original.ownerID), "scan_id": .string(original.scanID),
            "route": .string("identify-multimodal"), "input_schema_version": .integer(2),
            "submission_digest": .string(original.contentDigest), "config_digest": .string(hash),
            "funding_binding_id": .string(UUID().uuidString.lowercased()), "funding_binding_digest": .string(hash),
            "funding_binding_version": .integer(1), "ordered_description_count": .integer(Int64(contexts.count)),
            "ordered_description_digest": .string(SharedMediaAcquisitionEncoding.digest(
                Data("merian.initial-analysis.cpm-photo-contexts.v1\n".utf8) + contextBytes))
        ]))
        return try InitialAnalysisCanonical.encode(CanonicalValue.object([
            "version": .integer(1), "variant": .string("cpm_completion_admission_v1"), "authority": .string("none"),
            "owner_id": .string(original.ownerID), "scan_id": .string(original.scanID),
            "candidate_digest": .string(original.candidateDigest), "assignment_digest": .string(original.assignmentDigest),
            "backend_generation": .string(original.backendGeneration), "backend_configuration_digest": .string(original.backendConfigurationDigest),
            "admission_receipt_id": .string(UUID().uuidString.lowercased()), "admission_receipt_digest": .string(hash),
            "admission_canonical": .string(try nativeRecoveryRequired(String(data: admission, encoding: .utf8)))
        ]))
    }

}
#endif
