import Foundation
import Testing
@testable import Merian

@Suite("Inactive initial photo role projection")
struct InitialPhotoAllocationRoleReplyTests {
    typealias Reply = InitialPhotoAllocationRoleReply
    typealias Allocation = SharedMediaNativePhotoAllocation
    private func bytes(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    private func digest(_ domain: String, _ text: String) -> String {
        SharedMediaAcquisitionEncoding.digest(Data((domain + "\n" + text).utf8))
    }
    // Value-only fixture. This does not create an admitted native graph or grant.
    func request(candidate: String = Self.candidate, receipt: Allocation.Receipt? = nil) throws -> InitialPhotoAllocationRequest {
        let content = try #require(try object(candidate)["content_canonical"] as? String)
        let c = try object(content), id = "00000000-0000-4000-8000-000000000001"
        let fields: [String: Any] = ["profile": ["ownerID": id, "inventoryID": id, "generation": id,
            "storeIdentity": "synthetic", "physicalBinding": "synthetic", "receiptDigest": String(repeating: "a", count: 64)],
            "packageID": c["package_id"]!, "draftGeneration": id, "operationID": id,
            "observationID": c["scan_id"]!, "attemptID": id,
            "preparedSHA256": String(repeating: "a", count: 64), "receivedSHA256": String(repeating: "b", count: 64),
            "candidateCanonical": candidate, "candidateDigest": digest("merian.initial-analysis.cpm-photo-candidate.v1", candidate),
            "contentDigest": digest("merian.initial-analysis.cpm-photo-content.v1", content)]
        var allocation = Allocation(claim: try JSONDecoder().decode(Allocation.Claim.self, from: bytes(fields)))
        if let receipt { allocation = try allocation.settling(receipt) }
        return try .init(allocation: allocation, action: .status)
    }
    func projection() throws -> Reply.Projection {
        guard case .allocated(let value) = try Reply(data: Data(Self.golden.utf8), request: request()) else { throw MerianError.invalidResponse }
        return value
    }
    @Test func independentGoldenAndLegacyDenial() throws {
        let value = try projection()
        #expect(value.entries.map(\.role) == [.source, .ai, .display])
        #expect(value.entries.map(\.photoOrdinal) == [0, 0, 0])
        #expect(Set(value.entries.map(\.objectID)).count == 3)
        #expect(try Reply(data: Data(Self.golden.utf8), request: request(receipt: value.receipt), saved: value) == .allocated(value))
        #expect(throws: (any Error).self) { _ = try InitialPhotoAllocationReply(data: Data(Self.golden.utf8), request: request()) }
        var legacy = try object(Self.golden); legacy["version"] = 1; legacy.removeValue(forKey: "role_mapping")
        #expect(try InitialPhotoAllocationReply(data: bytes(legacy), request: request()) == .allocated(value.receipt))
        #expect(throws: (any Error).self) { _ = try Reply(data: bytes(legacy), request: request()) }
        #expect((try object(String(decoding: request().body, as: UTF8.self)))["version"] as? Int == 1)
    }
    @Test(arguments: ["order", "count", "duplicate", "reference", "ordinal", "boolean", "fraction", "uppercase", "private", "version", "authority", "digest", "clock"])
    func malformedMappingAndAssociationRejected(_ fault: String) throws {
        var row = try object(Self.golden), mapping = try #require(row["role_mapping"] as? [[String: Any]])
        switch fault {
        case "order": mapping.reverse()
        case "count": mapping.removeLast()
        case "duplicate": mapping[1]["object_id"] = mapping[0]["object_id"]
        case "reference": mapping[0]["reference_id"] = row["scan_id"]
        case "ordinal": mapping[0]["photo_ordinal"] = 1
        case "boolean": mapping[0]["photo_ordinal"] = false
        case "fraction": mapping[0]["photo_ordinal"] = 0.5
        case "uppercase": mapping[0]["object_id"] = "AAAAAAAA-0000-4000-8000-000000000001"
        case "private": mapping[0]["storage_key"] = "forbidden"
        case "version": row["version"] = 1
        case "authority": row["authority"] = "upload"
        case "digest": row["candidate_digest"] = String(repeating: "0", count: 64)
        case "clock": row["expires_at_ms"] = 1
        default: throw MerianError.invalidResponse
        }
        row["role_mapping"] = mapping
        #expect(throws: (any Error).self) { _ = try Reply(data: bytes(row), request: request()) }
    }
    @Test func savedIdentityAndClocksCannotChangeAndHoldsDoNotClearMapping() throws {
        let saved = try projection(), request = try request(receipt: saved.receipt)
        for key in ["assignment_digest", "created_at_ms", "object_id"] {
            var row = try object(Self.golden)
            if key == "assignment_digest" { row[key] = String(repeating: "b", count: 64) }
            else if key == "created_at_ms" {
                row[key] = saved.receipt.createdAtMilliseconds + 1; row["expires_at_ms"] = saved.receipt.expiresAtMilliseconds + 1
            } else {
                var mapping = try #require(row["role_mapping"] as? [[String: Any]])
                mapping[0][key] = "00000000-0000-4000-8000-000000000999"; row["role_mapping"] = mapping
            }
            #expect(throws: (any Error).self) { _ = try Reply(data: bytes(row), request: request, saved: saved) }
        }
        for reason in ["not_found", "expired", "cancelled"] {
            var row = try object(Self.golden)
            for key in ["assignment_digest", "created_at_ms", "expires_at_ms", "role_mapping"] { row.removeValue(forKey: key) }
            row["outcome"] = "terminal_held"; row["reason"] = reason
            let held = try #require(InitialPhotoAllocationReply.HeldReason(rawValue: reason))
            #expect(try Reply(data: bytes(row), request: request, saved: saved) == .held(held))
            row["role_mapping"] = []
            #expect(throws: (any Error).self) { _ = try Reply(data: bytes(row), request: request, saved: saved) }
        }
    }
    @Test func byteLimitIsCheckedBeforeDecoding() throws {
        #expect(Reply.maximumBytes == 2048)
        #expect(throws: (any Error).self) { _ = try Reply(data: Data(repeating: 32, count: 2049), request: request()) }
    }
    @Test func sixOrderedRolesPreserveMultiplicityAtMaximumClocks() throws {
        var candidate = try object(Self.candidate)
        var content = try object(#require(candidate["content_canonical"] as? String))
        var photos = try #require(content["photos"] as? [[String: Any]])
        var second = photos[0]; second["ordinal"] = 1
        var row = try object(Self.golden), mapping = try #require(row["role_mapping"] as? [[String: Any]])
        for (index, role) in Reply.Role.allCases.enumerated() {
            let reference = String(format: "00000000-0000-4000-8000-00000000010%d", index)
            var declaration = try #require(second[role.rawValue] as? [String: Any])
            declaration["reference_id"] = reference; second[role.rawValue] = declaration
            mapping.append(["photo_ordinal": 1, "role": role.rawValue, "reference_id": reference,
                "object_id": String(format: "00000000-0000-4000-8000-00000000030%d", index)])
        }
        photos.append(second); content["photos"] = photos
        candidate["content_canonical"] = String(decoding: try bytes(content), as: UTF8.self)
        let request = try request(candidate: String(decoding: bytes(candidate), as: UTF8.self))
        row["candidate_digest"] = request.allocation.claim.candidateDigest
        row["content_digest"] = request.allocation.claim.contentDigest; row["role_mapping"] = mapping
        row["created_at_ms"] = Int64(8_639_999_998_200_000); row["expires_at_ms"] = Int64(8_640_000_000_000_000)
        let encoded = try bytes(row)
        #expect(encoded.count <= Reply.maximumBytes)
        guard case .allocated(let value) = try Reply(data: encoded, request: request) else { throw MerianError.invalidResponse }
        #expect(value.entries.count == 6 && Set(value.entries.map(\.objectID)).count == 6)
        #expect(value.entries.map(\.photoOrdinal) == [0, 0, 0, 1, 1, 1])
        #expect(value.entries.map(\.role) == [.source, .ai, .display, .source, .ai, .display])
        let reserved = try request.allocation.reservingRoleMapping()
        let enriched = try reserved.enriching(value.receipt, mapping: .init(entries: value.entries))
        #expect(try reserved.storageCharge == Int64(enriched.encoded().count) + 64)
        #expect(enriched.roleMapping?.entries.count == 6)
    }
    private static let candidate = #"{"admission":{"client_protocol":3,"expected_processor_permission":"google_gemini","identification_protocol":6},"content_canonical":"{\"contexts\":[{\"text_utf8_base64\":\"IO+7v2EAZcyB8J+mrQo=\"}],\"contract\":\"client_prepared_media_v1\",\"kind\":\"initial_photo\",\"package_id\":\"00000000-0000-4000-8000-000000000002\",\"photos\":[{\"ai\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000004\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"display\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000005\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"ordinal\":0,\"recipe\":{\"camera_vertical_center_bits\":null,\"crop_display_size_bits\":null,\"format\":\"nativeStillImageV1\",\"is_pro\":false,\"offset_x_bits\":\"8000000000000000\",\"offset_y_bits\":\"0000000000000000\",\"quarter_turns\":0,\"scale_bits\":\"3ff0000000000000\"},\"source\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000003\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}}],\"resource_profile\":\"P1-L1\",\"scan_id\":\"00000000-0000-4000-8000-000000000001\",\"version\":1}","variant":"client_prepared_photo","version":1}"#
    private static let golden = #"{"version":2,"variant":"client_prepared_photo","authority":"none","scan_id":"00000000-0000-4000-8000-000000000001","package_id":"00000000-0000-4000-8000-000000000002","candidate_digest":"d6386c57a8e3d67c5cb8566fc46dfa59378613ccd0494c85669905df25b2d57a","content_digest":"d75caa6fdc3c9f374149c666cb2bb3b153934bc6dc4040589fa418ee7e41c806","outcome":"allocated","assignment_digest":"eb616665a5a98638d564ef78f6aa08899551c0f09b4284fe36bf4c1afa0f7886","created_at_ms":1793140000000,"expires_at_ms":1793141800000,"role_mapping":[{"photo_ordinal":0,"role":"source","reference_id":"00000000-0000-4000-8000-000000000003","object_id":"00000000-0000-4000-8000-000000000200"},{"photo_ordinal":0,"role":"ai","reference_id":"00000000-0000-4000-8000-000000000004","object_id":"00000000-0000-4000-8000-000000000201"},{"photo_ordinal":0,"role":"display","reference_id":"00000000-0000-4000-8000-000000000005","object_id":"00000000-0000-4000-8000-000000000202"}]}"#
}
