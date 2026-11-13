import CryptoKit
import Foundation

/// Closed immutable completion documents. This is consistency validation only;
/// the future authenticated delivery owner must bind the saved original request.
/// No network, persistence, current-account lookup or spending authority lives here.
struct InitialCompletionDocuments: Sendable {
    let receipt: Data
    let projection: Data

    private typealias Value = InitialAnalysisCanonical.Value
    private static let schema = try? InitialAnalysisCanonical.parse(Data(InitialCompletionSchema.canonical.utf8))
    static let statusResponseMaximumBytes = 2_541_568

    /// Decode only after authenticated, saved-operation-fenced transport. The
    /// original reference/provenance are discovered by the fixed private reader;
    /// inner result/receipt checks remain their existing owners' responsibility.
    static func statusAcquisition(_ bytes: Data, admission: CpmAdmission) throws -> CpmAcquisition? {
        let value = try InitialAnalysisCanonical.parseCompletionStatus(bytes)
        guard let rule = schema?.object?["status_response"], matches(value, rule: rule),
              let fields = value.object, let original = fields["admission_canonical"]?.string,
              Data(original.utf8) == admission.admission else { throw InitialAnalysisCanonical.Invalid.document }
        let payloadKeys = Set(fields.keys).subtracting(["version", "outcome", "admission_canonical"])
        if fields["outcome"]?.string == "pending" {
            guard payloadKeys.allSatisfy({ fields[$0]?.isNull == true }) else { throw InitialAnalysisCanonical.Invalid.document }
            return nil
        }
        guard fields["outcome"]?.string == "found",
              payloadKeys.allSatisfy({ fields[$0]?.string != nil }),
              let reference = fields["reference_canonical"]?.string,
              let provenance = fields["original_provenance_canonical"]?.string,
              let result = fields["result_canonical"]?.string,
              let resultDigest = fields["result_digest"]?.string,
              let provenanceDigest = fields["provenance_digest"]?.string,
              let receipt = fields["receipt_canonical"]?.string,
              let projection = fields["projection_canonical"]?.string else { throw InitialAnalysisCanonical.Invalid.document }
        let referenceBytes = Data(reference.utf8), provenanceBytes = Data(provenance.utf8)
        let retained = try InitialRetainedResult(reference: referenceBytes, result: Data(result.utf8),
            provenance: provenanceBytes, resultDigest: resultDigest, provenanceDigest: provenanceDigest,
            expectedReference: referenceBytes, originalProvenance: provenanceBytes)
        let documents = try Self(receipt: Data(receipt.utf8), projection: Data(projection.utf8))
        return try CpmAcquisition(result: retained, documents: documents, admission: admission)
    }

    init(receipt: Data, projection: Data) throws {
        guard receipt.count <= 16_384, projection.count <= 65_536 else { throw InitialAnalysisCanonical.Invalid.document }
        let r = try Self.document(receipt, kind: "receipt", limit: 16_384)
        let p = try Self.document(projection, kind: "projection", limit: 65_536)
        guard let context = p["capture_context"]?.object, let media = p["media"]?.object,
              let settlement = p["settlement"]?.object else { throw InitialAnalysisCanonical.Invalid.document }
        let cpm = media["kind"]?.string == "cpm_adoption_v1"
        guard Self.same(r["operation_id"], r["scan_id"]),
              ["owner_id", "scan_id", "result_evidence_id", "result_digest"].allSatisfy({ Self.same(r[$0], p[$0]) }),
              Self.same(r["submission_digest"], context["submission_digest"]),
              Self.same(r["finalized_media_binding_digest"], media["receipt_digest"]),
              r["input_schema_version"]?.integer == (cpm ? 2 : 1),
              context["source"]?.string == (cpm ? "cpm_absent_v1" : "legacy_input_v1"),
              p["credit_consumed"]?.boolean == (settlement["outcome"]?.string == "consumed_durable_result"),
              settlement["settled_at"]?.isNull == (settlement["outcome"]?.string == "none"),
              p["timestamp_basis"]?.string != "completion" || Self.same(p["scan_timestamp"], p["completed_at"]),
              !cpm || (p["timestamp_basis"]?.string == "completion" && p["geoprivacy"]?.string == "private")
        else { throw InitialAnalysisCanonical.Invalid.document }
        try Self.timestamp(p["completed_at"])
        try Self.timestamp(p["scan_timestamp"])
        if settlement["settled_at"]?.isNull != true { try Self.timestamp(settlement["settled_at"]) }
        guard let items = media["items"]?.array, !items.isEmpty, !cpm || items.count <= 2 else {
            throw InitialAnalysisCanonical.Invalid.document
        }
        var ids = Set<String>()
        for (index, value) in items.enumerated() {
            guard let item = value.object, let id = item["media_id"]?.string,
                  let kind = item["kind"]?.string, let mime = item["content_type"]?.string,
                  let bytes = item["byte_count"]?.integer,
                  item["ordinal"]?.integer == Int64(index), ids.insert(id).inserted,
                  kind == "video" || item["poster_media_id"]?.isNull == true,
                  kind != "audio" || mime == "audio/wav", kind != "video" || mime == "video/mp4",
                  kind != "image" || mime.hasPrefix("image/"),
                  !cpm || (kind == "image" && mime == "image/jpeg" && bytes <= 4_194_304)
            else { throw InitialAnalysisCanonical.Invalid.document }
        }
        let domain = Data("merian.initial-analysis.completion-projection.v1\n".utf8)
        let digest = SHA256.hash(data: domain + projection).map { String(format: "%02x", $0) }.joined()
        guard r["completion_projection_digest"]?.string == digest else { throw InitialAnalysisCanonical.Invalid.document }
        self.receipt = receipt
        self.projection = projection
    }

    /// Original independently saved allocation facts. This value grants no I/O.
    struct CpmBinding: Decodable, Sendable {
        let ownerID: String, scanID: String, candidateCanonical: String
        let candidateDigest: String, contentDigest: String, assignmentDigest: String
        let backendGeneration: String, backendConfigurationDigest: String

        // Keep the persisted coding vocabulary local to its encoded value.
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case ownerID = "owner_id"
            case scanID = "scan_id"
            case candidateCanonical = "candidate_canonical"
            case candidateDigest = "candidate_digest"
            case contentDigest = "content_digest"
            case assignmentDigest = "assignment_digest"
            case backendGeneration = "backend_generation"
            case backendConfigurationDigest = "backend_configuration_digest"
        }

        static func saved(_ allocation: SharedMediaNativePhotoAllocation) throws -> Self {
            _ = try allocation.encoded()
            guard let receipt = allocation.receipt, let backend = allocation.backendBinding else {
                throw InitialAnalysisCanonical.Invalid.document
            }
            return Self(ownerID: allocation.claim.profile.ownerID.uuidString.lowercased(),
                        scanID: allocation.claim.observationID.uuidString.lowercased(),
                        candidateCanonical: allocation.claim.candidateCanonical,
                        candidateDigest: allocation.claim.candidateDigest,
                        contentDigest: allocation.claim.contentDigest,
                        assignmentDigest: receipt.assignmentDigest,
                        backendGeneration: backend.generation.uuidString.lowercased(),
                        backendConfigurationDigest: backend.configurationDigest)
        }
    }

    /// First trust still requires an authenticated response and the receiving
    /// owner's atomic original-operation pin. Full assignment/funding validation
    /// belongs to the private server reader; native correlates its saved facts.
    struct CpmAdmission: Equatable, Sendable {
        let acknowledgement: Data
        let admission: Data

        init(acknowledgement: Data, original: CpmBinding) throws {
            let ack = try InitialCompletionDocuments.document(acknowledgement,
                kind: "cpm_admission_acknowledgement", limit: 8192, jsonbLimit: false)
            guard let text = ack["admission_canonical"]?.string else { throw InitialAnalysisCanonical.Invalid.document }
            let bytes = Data(text.utf8)
            let admission = try InitialCompletionDocuments.document(bytes, kind: "admission", limit: 4096, jsonbLimit: false)
            let candidateBytes = Data(original.candidateCanonical.utf8)
            guard candidateBytes.count <= 1_048_576,
                  let candidate = try InitialAnalysisCanonical.parse(candidateBytes).object,
                  let contentText = candidate["content_canonical"]?.string,
                  let content = try InitialAnalysisCanonical.parse(Data(contentText.utf8)).object,
                  let contexts = content["contexts"]?.array,
                  content["scan_id"]?.string == original.scanID,
                  InitialCompletionDocuments.hash("merian.initial-analysis.cpm-photo-candidate.v1\n", candidateBytes) == original.candidateDigest,
                  InitialCompletionDocuments.hash("merian.initial-analysis.cpm-photo-content.v1\n", Data(contentText.utf8)) == original.contentDigest,
                  ack["owner_id"]?.string == original.ownerID,
                  ack["scan_id"]?.string == original.scanID,
                  ack["candidate_digest"]?.string == original.candidateDigest,
                  ack["assignment_digest"]?.string == original.assignmentDigest,
                  ack["backend_generation"]?.string == original.backendGeneration,
                  ack["backend_configuration_digest"]?.string == original.backendConfigurationDigest,
                  admission["owner_id"]?.string == original.ownerID,
                  admission["scan_id"]?.string == original.scanID,
                  admission["submission_digest"]?.string == original.contentDigest,
                  admission["input_schema_version"]?.integer == 2,
                  admission["route"]?.string != "identify-describe",
                  admission["ordered_description_count"]?.integer == Int64(contexts.count),
                  admission["ordered_description_digest"]?.string == InitialCompletionDocuments.hash(
                    "merian.initial-analysis.cpm-photo-contexts.v1\n", try InitialAnalysisCanonical.encode(.array(contexts)))
            else { throw InitialAnalysisCanonical.Invalid.document }
            self.acknowledgement = acknowledgement
            self.admission = bytes
        }
    }

    /// Bounded restart identity, not proof of a validated AI result. The future
    /// pin owner must first authenticate and validate the complete delivery.
    /// This value grants no persistence, application, enrollment or cleanup.
    /// Only byte/schema consistency. The retained caller must authenticate the
    /// original acquisition; this value cannot grant execution or application.
    struct CpmAcquisition: Sendable {
        let record: CpmRecoveryRecord
        let result: InitialRetainedResult
        init(result: InitialRetainedResult, documents: InitialCompletionDocuments, admission: CpmAdmission) throws {
            guard let receipt = try InitialAnalysisCanonical.parse(documents.receipt).object,
                  receipt["result_digest"]?.string == result.resultDigest else { throw InitialAnalysisCanonical.Invalid.document }
            record = try .init(reference: result.reference, originalProvenance: result.provenance,
                documents: documents, admission: admission)
            self.result = result
        }
    }

    struct CpmRecoveryRecord: Equatable, Sendable {
        let bytes: Data
        let reference: Data
        let originalProvenance: Data
        let receipt: Data
        let projection: Data

        /// The only planned successor is a retained completion pin. Application
        /// is deliberately absent and must reserve its own reviewed successor.
        static var maximumBytes: Int {
            get throws {
                let uuid = String(repeating: "0", count: 36), sha = String(repeating: "f", count: 64)
                let reference = Value.object(Dictionary(uniqueKeysWithValues: referenceKeys.map {
                    ($0, Value.string($0.hasSuffix("_id") ? uuid : sha))
                }))
                return try encode(reference: reference, provenance: Data(repeating: 0, count: 65_536),
                    receipt: Data(repeating: 0, count: 16_384), projection: Data(repeating: 0, count: 65_536),
                    admissionDigest: sha, resultDigest: sha, provenanceDigest: sha).count
            }
        }
        private static let referenceKeys = ["owner_id", "scan_id", "invocation_id", "result_evidence_id",
                                            "submission_digest", "config_digest", "funding_binding_digest"]

        init(reference: Data, originalProvenance: Data, documents: InitialCompletionDocuments,
             admission: CpmAdmission) throws {
            guard reference.count <= 4096, originalProvenance.count <= 65_536,
                  let ref = try InitialAnalysisCanonical.parse(reference).object,
                  Set(ref.keys) == Set(Self.referenceKeys),
                  let rules = InitialCompletionDocuments.schema?.object?["receipt"]?.object?["properties"]?.object,
                  let r = try InitialAnalysisCanonical.parse(documents.receipt).object,
                  let a = try InitialAnalysisCanonical.parse(admission.admission).object,
                  let resultDigest = r["result_digest"]?.string,
                  let provenance = try InitialAnalysisCanonical.parse(originalProvenance).object,
                  !provenance.isEmpty else { throw InitialAnalysisCanonical.Invalid.document }
            for key in Self.referenceKeys {
                guard let value = ref[key], let rule = rules[key == "invocation_id" ? "scan_id" : key],
                      InitialCompletionDocuments.matches(value, rule: rule),
                      key == "invocation_id" || InitialCompletionDocuments.same(value, r[key]) else {
                    throw InitialAnalysisCanonical.Invalid.document
                }
            }
            for (key, value) in a {
                guard InitialCompletionDocuments.same(value, r[key]) else { throw InitialAnalysisCanonical.Invalid.document }
            }
            let encoded = try Self.encode(reference: .object(ref), provenance: originalProvenance,
                receipt: documents.receipt, projection: documents.projection,
                admissionDigest: InitialCompletionDocuments.hash("", admission.acknowledgement),
                resultDigest: resultDigest,
                provenanceDigest: InitialCompletionDocuments.hash("merian.initial-analysis.result-provenance.v1\n", originalProvenance))
            guard encoded.count <= (try Self.maximumBytes) else { throw InitialAnalysisCanonical.Invalid.document }
            bytes = encoded; self.reference = reference; self.originalProvenance = originalProvenance
            receipt = documents.receipt; projection = documents.projection
        }

        static func decode(_ bytes: Data, admission: CpmAdmission) throws -> Self {
            guard bytes.count <= (try maximumBytes), let row = try InitialAnalysisCanonical.parse(bytes).object,
                  Set(row.keys) == ["version", "state", "admission_sha256", "reference", "result_digest",
                                    "provenance_digest", "provenance_base64", "receipt_base64", "projection_base64"],
                  row["version"]?.integer == 1, row["state"]?.string == "completion_pinned",
                  let reference = row["reference"] else { throw InitialAnalysisCanonical.Invalid.document }
            let documents = try InitialCompletionDocuments(receipt: binary(row["receipt_base64"], maximum: 16_384),
                projection: binary(row["projection_base64"], maximum: 65_536))
            let value = try Self(reference: InitialAnalysisCanonical.encode(reference),
                originalProvenance: binary(row["provenance_base64"], maximum: 65_536), documents: documents, admission: admission)
            guard value.bytes == bytes else { throw InitialAnalysisCanonical.Invalid.document }
            return value
        }

        private static func binary(_ value: Value?, maximum: Int) throws -> Data {
            guard let text = value?.string, text.utf8.count <= 4 * ((maximum + 2) / 3),
                  let data = Data(base64Encoded: text), data.count <= maximum,
                  data.base64EncodedString() == text else { throw InitialAnalysisCanonical.Invalid.document }
            return data
        }
        private static func encode(reference: Value, provenance: Data, receipt: Data, projection: Data,
                                   admissionDigest: String, resultDigest: String, provenanceDigest: String) throws -> Data {
            try InitialAnalysisCanonical.encode(.object([
                "version": .integer(1), "state": .string("completion_pinned"),
                "admission_sha256": .string(admissionDigest), "reference": reference,
                "result_digest": .string(resultDigest), "provenance_digest": .string(provenanceDigest),
                "provenance_base64": .string(provenance.base64EncodedString()),
                "receipt_base64": .string(receipt.base64EncodedString()),
                "projection_base64": .string(projection.base64EncodedString())
            ]))
        }
    }

    private static func hash(_ domain: String, _ bytes: Data) -> String {
        SHA256.hash(data: Data(domain.utf8) + bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func same(_ lhs: Value?, _ rhs: Value?) -> Bool {
        guard let lhs, let rhs, let a = try? InitialAnalysisCanonical.encode(lhs),
              let b = try? InitialAnalysisCanonical.encode(rhs) else { return false }
        return a == b
    }

    private static func document(_ data: Data, kind: String, limit: Int, jsonbLimit: Bool = true) throws -> [String: Value] {
        guard data.count <= limit else { throw InitialAnalysisCanonical.Invalid.document }
        let value = try InitialAnalysisCanonical.parse(data)
        guard !jsonbLimit || data.count + InitialAnalysisCanonical.jsonbSpacing(value) <= limit,
              let rule = schema?.object?[kind], matches(value, rule: rule), let object = value.object else {
            throw InitialAnalysisCanonical.Invalid.document
        }
        return object
    }

    private static func matches(_ value: Value, rule: Value) -> Bool {
        guard let r = rule.object else { return false }
        if value.isNull { return r["nullable"]?.boolean == true }
        switch r["type"]?.string {
        case "object":
            guard let fields = value.object, let properties = r["properties"]?.object,
                  Set(fields.keys) == Set(properties.keys) else { return false }
            return properties.allSatisfy { key, child in
                guard let field = fields[key] else { return false }
                return matches(field, rule: child)
            }
        case "array":
            guard let items = value.array, let maximum = r["max_items"]?.integer,
                  items.count <= maximum, let child = r["items"] else { return false }
            return items.allSatisfy { matches($0, rule: child) }
        case "boolean": return value.boolean != nil
        case "integer":
            guard let number = value.integer, let minimum = r["minimum"]?.integer,
                  let maximum = r["maximum"]?.integer else { return false }
            return number >= minimum && number <= maximum
        case "string":
            guard let text = value.string, let maximum = r["max_bytes"]?.integer,
                  text.utf8.count <= maximum else { return false }
            if let choices = r["enum"]?.array, !choices.contains(where: { same(value, $0) }) { return false }
            if let pattern = r["pattern"]?.string {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.range == NSRange(text.startIndex..., in: text) else { return false }
            }
            return true
        default: return false
        }
    }

    private static func timestamp(_ value: Value?) throws {
        guard let text = value?.string else { throw InitialAnalysisCanonical.Invalid.document }
        // The schema limits spelling to UTC with at most six fractional digits.
        // Check the Gregorian calendar directly; retain the original microseconds.
        let fields = text.prefix(19).split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard fields.count == 6, fields[0] >= 0, (1...12).contains(fields[1]),
              (0...23).contains(fields[3]), (0...59).contains(fields[4]), (0...59).contains(fields[5]) else {
            throw InitialAnalysisCanonical.Invalid.document
        }
        let year = fields[0]
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[fields[1] - 1]).contains(fields[2]) else { throw InitialAnalysisCanonical.Invalid.document }
    }
}
