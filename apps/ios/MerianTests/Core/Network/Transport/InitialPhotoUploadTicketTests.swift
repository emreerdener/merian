import Foundation
@testable import Merian
import Testing

@Suite("Inert native photo upload ticket")
struct InitialPhotoUploadTicketTests {
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Role = SharedMediaNativePhotoRoleMapping.Role
    private let backend = UUID(uuidString: "00000000-0000-4000-8000-000000000400")!
    func binding() -> Allocation.BackendBinding {
        .init(generation: backend, configurationDigest: String(repeating: "c", count: 64))
    }
    func destination() throws -> InitialPhotoUploadDestination {
        try .init(backendGeneration: backend, configurationDigest: String(repeating: "c", count: 64),
            endpoint: "https://00000000000000000000000000000000.r2.cloudflarestorage.com", bucket: "synthetic-private")
    }
    func bytes(_ row: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) }
    private func copy(_ value: Allocation, changes: [String: Any]) throws -> Allocation {
        var object = try #require(JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any])
        for (key, change) in changes { object[key] = change }
        return try JSONDecoder().decode(Allocation.self, from: bytes(object))
    }
    // Value-only fixture reuses the independently validated allocation contract;
    // it cannot mint a continuation, storage lock or any transfer authority.
    func allocation(_ role: Role = .source, contentType: String? = nil, boundBackend: Bool = false, phase: Int? = nil) throws -> Allocation {
        let fixture = InitialPhotoAllocationRoleReplyTests(), projection = try fixture.projection()
        var request = try fixture.request()
        if let contentType {
            // Change only the synthetic declaration before constructing the claim.
            // This fixture does not assert SQL profile admission or actual file bytes.
            func canonical(_ object: [String: Any]) throws -> String {
                let data = try JSONSerialization.data(withJSONObject: object,
                    options: [.sortedKeys, .withoutEscapingSlashes])
                return try #require(String(data: data, encoding: .utf8))
            }
            var candidate = try #require(JSONSerialization.jsonObject(with:
                Data(request.allocation.claim.candidateCanonical.utf8)) as? [String: Any])
            let contentText = try #require(candidate["content_canonical"] as? String)
            var content = try #require(JSONSerialization.jsonObject(with:
                Data(contentText.utf8)) as? [String: Any])
            var photos = try #require(content["photos"] as? [[String: Any]])
            var value = try #require(photos[0][role.rawValue] as? [String: Any])
            value["declared_content_type"] = contentType
            photos[0][role.rawValue] = value; content["photos"] = photos
            candidate["content_canonical"] = try canonical(content)
            request = try fixture.request(candidate: canonical(candidate))
        }
        let reserved = try boundBackend ? request.allocation.reservingBackendBinding() : request.allocation.reservingRoleMapping()
        let base = try reserved.enriching(projection.receipt, mapping: .init(entries: projection.entries),
            binding: boundBackend ? binding() : nil)
        if phase == base.version { return base }
        let entry = try #require(projection.entries.first { $0.role == role })
        let candidate = try #require(JSONSerialization.jsonObject(with: Data(base.claim.candidateCanonical.utf8)) as? [String: Any])
        let contentText = try #require(candidate["content_canonical"] as? String)
        let content = try #require(JSONSerialization.jsonObject(with: Data(contentText.utf8)) as? [String: Any])
        let photos = try #require(content["photos"] as? [[String: Any]])
        let value = try #require(photos[0][role.rawValue] as? [String: Any])
        let selection = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry))
        let id = UUID().uuidString
        let transfer: [String: Any] = ["state": "reservedNotStarted", "selection": selection, "pairID": id, "assetID": id,
            "assetGeneration": id, "descriptor": ["version": 1, "file": "synthetic", "parent": "synthetic", "namespace": "synthetic"],
            "byteCount": value["byte_count"]!, "sha256": value["sha256"]!, "contentType": value["declared_content_type"]!]
        let held = try base.reservingTransfer(JSONDecoder().decode(SharedMediaNativePhotoTransferReservation.self, from: bytes(transfer)))
        if phase == held.version { return held }
        let remote = try held.reservingRemoteAttempt()
        if phase == remote.version { return remote }
        return try remote.startingTicketRequest()
    }
    func row(_ allocation: Allocation) throws -> [String: Any] {
        let receipt = try #require(allocation.receipt), transfer = try #require(allocation.transferReservation)
        let contentType = try transfer.declaredContentType(claim: allocation.claim)
        let created = receipt.createdAtMilliseconds + 1_000, expiry = min(created + 600_000, receipt.expiresAtMilliseconds)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let signed = (created / 1000) * 1000, date = formatter.string(from: Date(timeIntervalSince1970: Double(signed) / 1000))
        var url = try #require(URLComponents(string: destination().unsignedURL(scan: allocation.claim.observationID, object: transfer.selection.objectID)))
        url.queryItems = [URLQueryItem(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"),
            .init(name: "X-Amz-Credential", value: "synthetic-access-id/\(date.prefix(8))/auto/s3/aws4_request"),
            .init(name: "X-Amz-Date", value: date), .init(name: "X-Amz-Expires", value: String(((expiry / 1000) * 1000 - signed) / 1000)),
            .init(name: "X-Amz-Signature", value: String(repeating: "a", count: 64)),
            .init(name: "X-Amz-SignedHeaders", value: "cache-control;content-length;content-type;host;if-none-match;x-amz-content-sha256")]
        return ["version": 1, "outcome": "issued", "attempt_id": "00000000-0000-4000-8000-000000000300",
            "scan_id": allocation.claim.observationID.uuidString.lowercased(), "assignment_digest": receipt.assignmentDigest,
            "object_id": transfer.selection.objectID.uuidString.lowercased(), "backend_generation": backend.uuidString.lowercased(),
            "backend_configuration_digest": String(repeating: "c", count: 64), "role": transfer.selection.role.rawValue,
            "byte_count": transfer.byteCount, "content_type": contentType, "sha256": transfer.sha256,
            "created_at_ms": created, "capability_expires_at_ms": expiry, "signed_expires_at_ms": (expiry / 1000) * 1000,
            "url": try #require(url.string), "method": "PUT", "provider_enforcement": "unqualified",
            "headers": ["If-None-Match": "*", "Content-Type": contentType, "Content-Length": String(transfer.byteCount),
                "Cache-Control": "private, no-store", "x-amz-content-sha256": transfer.sha256]]
    }
    private func decode(_ row: [String: Any], _ allocation: Allocation, now: Int64? = nil) throws -> InitialPhotoUploadTicket {
        try .init(data: bytes(row), allocation: allocation, destination: destination(),
            nowMilliseconds: now ?? #require(allocation.receipt).createdAtMilliseconds + 2_000)
    }
    @Test(arguments: Role.allCases)
    func boundPhasesPreserveIdentityAndCannotCrossLegacyBranch(_ role: Role) throws {
        let v6 = try allocation(role, boundBackend: true, phase: 6)
        let fixture = try allocation(role, boundBackend: true, phase: 7)
        let v7 = try v6.reservingTransfer(#require(fixture.transferReservation))
        let v8 = try v7.reservingRemoteAttempt(), v9 = try v8.startingTicketRequest()
        for (before, after) in [(v6, v7), (v7, v8), (v8, v9)] {
            try before.requireSuccessor(after)
            #expect(after.claim == before.claim && after.receipt == before.receipt)
            #expect(after.roleMapping == before.roleMapping && after.backendBinding == before.backendBinding)
            #expect(try after.storageCharge >= before.storageCharge)
            let data = try after.encoded()
            #expect(try Allocation.decode(data, sha256: SharedMediaAcquisitionEncoding.digest(data)) == after)
            #expect(throws: (any Error).self) { try after.requireSuccessor(before) }
            #expect(throws: (any Error).self) {
                _ = try InitialPhotoAllocationRequest(allocation: after, action: .status, projection: .boundRoles)
            }
            #expect(throws: (any Error).self) { _ = try after.reservingBackendBinding() }
            for change: [String: Any] in [["backendBinding": NSNull()], ["version": after.version - 4],
                ["backendBinding": ["generation": UUID().uuidString, "configurationDigest": "invalid"]]] {
                let invalid = try copy(after, changes: change)
                #expect(throws: (any Error).self) { _ = try invalid.encoded() }
            }
            let changed = try copy(after, changes: [
                "backendBinding": ["generation": UUID().uuidString, "configurationDigest": String(repeating: "d", count: 64)]])
            #expect(throws: (any Error).self) { try before.requireSuccessor(changed) }
        }
        #expect(v7.remainingAdvances == 0 && v8.remainingAdvances == 3 && v9.remainingAdvances == 3)
        #expect(throws: (any Error).self) { _ = try v9.startingTicketRequest() }
        let incomplete = try InitialPhotoAllocationRoleReplyTests().request().allocation.reservingBackendBinding()
        #expect(throws: (any Error).self) { _ = try incomplete.reservingTransfer(#require(v7.transferReservation)) }
        for phase in 3...5 {
            let legacy = try allocation(role, phase: phase), data = try legacy.encoded()
            #expect(try Allocation.decode(data, sha256: SharedMediaAcquisitionEncoding.digest(data)).encoded() == data)
            #expect(throws: (any Error).self) { _ = try legacy.reservingBackendBinding() }
            #expect(throws: (any Error).self) { try legacy.requireSuccessor(v9) }
        }
    }

    @Test(arguments: [8, 9])
    func boundMaximumClocksAndClosureKeepMetadataCharge(_ phase: Int) throws {
        let value = try allocation(boundBackend: true, phase: phase)
        let receipt = try #require(value.receipt)
        let maximum = try copy(value, changes: ["receipt": ["assignmentDigest": receipt.assignmentDigest,
            "createdAtMilliseconds": Int64(8_639_999_998_200_000), "expiresAtMilliseconds": Int64(8_640_000_000_000_000)]])
        let id = UUID().uuidString
        var current = maximum
        for (state, closed) in [("bound", false), ("mayHaveIssued", false), ("mayHaveIssued", true)] {
            let next = try copy(current, changes: ["remoteAttempt": ["id": id, "state": state,
                "createdAtMilliseconds": Int64(8_639_999_999_999_999),
                "capabilityExpiresAtMilliseconds": Int64(8_640_000_000_000_000), "writeClosed": closed]])
            try current.requireSuccessor(next)
            #expect(try next.storageCharge == value.storageCharge)
            #expect(try next.storageCharge >= Int64(next.encoded().count) + 64)
            #expect(throws: (any Error).self) { _ = try next.startingTicketRequest() }
            current = next
        }
        #expect(current.remainingAdvances == 0 && current.backendBinding == value.backendBinding)
        #expect(throws: (any Error).self) { try current.requireSuccessor(maximum) }
    }

    @Test(arguments: ["generation", "digest"], [false, true])
    func boundDestinationMismatchRejectsIssuedAndHeld(_ mismatch: String, held: Bool) throws {
        let value = try allocation(boundBackend: true)
        let wire = try held ? ["outcome": "held", "attempt_id": UUID().uuidString.lowercased()] : row(value)
        let wrong = try InitialPhotoUploadDestination(backendGeneration: mismatch == "generation" ? UUID() : backend,
            configurationDigest: String(repeating: mismatch == "digest" ? "d" : "c", count: 64),
            endpoint: "https://00000000000000000000000000000000.r2.cloudflarestorage.com", bucket: "synthetic-private")
        #expect(throws: (any Error).self) {
            _ = try InitialPhotoUploadTicket(data: bytes(wire), allocation: value, destination: wrong,
                nowMilliseconds: #require(value.receipt).createdAtMilliseconds + 2_000)
        }
        for phase in [6, 7, 8] {
            let premature = try allocation(boundBackend: true, phase: phase)
            #expect(throws: (any Error).self) { _ = try decode(wire, premature) }
        }
    }
    @Test(arguments: Role.allCases, [false, true]) func exactRoleAndHeldRemainInert(_ role: Role, boundBackend: Bool) throws {
        let allocation = try allocation(role, boundBackend: boundBackend), row = try row(allocation), result = try decode(row, allocation)
        #expect(result.outcome == .issued && result.attemptID != allocation.claim.attemptID)
        try result.requireMatch(allocation, destination: destination())
        #expect(!String(describing: result).contains("X-Amz") && !String(reflecting: result).contains("https"))
        let held: [String: Any] = ["outcome": "held", "attempt_id": row["attempt_id"]!]
        #expect(try decode(held, allocation).outcome == .held)
        #expect(throws: (any Error).self) { _ = try decode(held.merging(["url": row["url"]!]) { _, new in new }, allocation) }
    }
    @Test(arguments: Role.allCases, ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "image/gif", "public.jpeg"])
    func roleContentTypesPreserveExactFrozenDeclaration(_ role: Role, _ contentType: String) throws {
        let allocation = try allocation(role, contentType: contentType), row = try row(allocation)
        let before = try allocation.encoded()
        let sourceType = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"].contains(contentType)
        if contentType == "image/jpeg" || (role == .source && sourceType) {
            let ticket = try decode(row, allocation)
            #expect(ticket.outcome == .issued)
            try ticket.requireMatch(allocation, destination: destination())
            var changed = row, headers = try #require(row["headers"] as? [String: String])
            headers["Content-Type"] = contentType == "image/png" ? "image/jpeg" : "image/png"
            changed["headers"] = headers
            #expect(throws: (any Error).self) { _ = try decode(changed, allocation) }
        } else {
            #expect(throws: (any Error).self) { _ = try decode(row, allocation) }
        }
        let held: [String: Any] = ["outcome": "held", "attempt_id": row["attempt_id"]!]
        #expect(try decode(held, allocation).outcome == .held)
        #expect(try allocation.encoded() == before)
    }

    @Test func closedFieldsAndImmutableBinding() throws {
        let allocation = try allocation(), row = try row(allocation)
        for key in row.keys {
            var invalid = row; invalid.removeValue(forKey: key)
            #expect(throws: (any Error).self) { _ = try decode(invalid, allocation) }
        }
        for mutation: [String: Any] in [["version": true], ["version": 2], ["scan_id": UUID().uuidString.lowercased()],
            ["object_id": UUID().uuidString.lowercased()], ["attempt_id": "invalid"], ["backend_generation": UUID().uuidString.lowercased()],
            ["backend_configuration_digest": String(repeating: "d", count: 64)], ["assignment_digest": String(repeating: "e", count: 64)],
            ["role": "ai"], ["byte_count": true], ["byte_count": 1.5], ["byte_count": 33_554_433], ["sha256": String(repeating: "f", count: 64)],
            ["content_type": "video/mp4"], ["method": "POST"], ["provider_enforcement": "qualified"], ["owner": "forbidden"],
            ["created_at_ms": 0], ["capability_expires_at_ms": 1], ["signed_expires_at_ms": 1], ["url": String(repeating: "a", count: 4097)]] {
            #expect(throws: (any Error).self) { _ = try decode(row.merging(mutation) { _, new in new }, allocation) }
        }
        var headers = try #require(row["headers"] as? [String: String])
        for key in headers.keys {
            var invalid = row, changed = headers; changed[key] = "wrong"; invalid["headers"] = changed
            #expect(throws: (any Error).self) { _ = try decode(invalid, allocation) }
        }
        headers["Authorization"] = "forbidden"; var invalid = row; invalid["headers"] = headers
        #expect(throws: (any Error).self) { _ = try decode(invalid, allocation) }
    }
    @Test func destinationSignatureAndExpiryCannotChange() throws {
        let allocation = try allocation(), row = try row(allocation), raw = try #require(row["url"] as? String)
        for url in [" " + raw, raw + "#fragment", raw + "&X-Amz-Expires=1", raw + "&X-Amz-Security-Token=forbidden",
                    raw.replacingOccurrences(of: "https://", with: "https://user@"), raw.replacingOccurrences(of: "synthetic-private", with: "other-bucket")] {
            var invalid = row; invalid["url"] = url
            #expect(throws: (any Error).self) { _ = try decode(invalid, allocation) }
        }
        for (key, value) in [("X-Amz-Expires", "601"), ("X-Amz-Expires", "01"), ("X-Amz-Date", "20261301T000000Z"),
            ("X-Amz-SignedHeaders", "host"), ("X-Amz-Credential", "synthetic-access-id/19990101/auto/s3/aws4_request"), ("X-Amz-Signature", "invalid")] {
            var url = try #require(URLComponents(string: raw)); url.queryItems = url.queryItems?.map { $0.name == key ? .init(name: key, value: value) : $0 }
            var invalid = row; invalid["url"] = url.string
            #expect(throws: (any Error).self) { _ = try decode(invalid, allocation) }
        }
        let created = try #require(row["created_at_ms"] as? Int64), expiry = try #require(row["signed_expires_at_ms"] as? Int64)
        for now in [created - 1, expiry, expiry + 1] { #expect(throws: (any Error).self) { _ = try decode(row, allocation, now: now) } }
        #expect(throws: (any Error).self) { _ = try InitialPhotoUploadTicket(data: Data(repeating: 32, count: 8193),
            allocation: allocation, destination: destination(), nowMilliseconds: created) }
        for endpoint in ["http://00000000000000000000000000000000.r2.cloudflarestorage.com", "https://attacker.invalid", "https://00000000000000000000000000000000.r2.cloudflarestorage.com/"] {
            #expect(throws: (any Error).self) { _ = try InitialPhotoUploadDestination(backendGeneration: backend,
                configurationDigest: String(repeating: "c", count: 64), endpoint: endpoint, bucket: "synthetic-private") }
        }
    }
}
