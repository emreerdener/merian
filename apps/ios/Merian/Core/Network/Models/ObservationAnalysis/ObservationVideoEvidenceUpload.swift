import Foundation

/// Prepared metadata only. No transport, queue or byte-verification capability.
struct ObservationVideoEvidenceUploadRequest: Equatable, Sendable {
    static let readerVersion = 12
    static let maximumBytes = 4_096
    let identity: ObservationVideoSourceIdentity
    let inventory: ObservationVideoCohortInventory
    let body: Data

    init(input: Data) throws {
        identity = try ObservationVideoSourceIdentity(input: input)
        inventory = try ObservationVideoCohortInventory(input: input)
        let fields = identity.fields.merging(["items": inventory.items.map(Self.fields)]) { _, new in new }
        body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        guard body.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
    }

    init(savedBody: Data, input: Data) throws {
        let expected = try Self(input: input)
        try expected.validate(Self.object(savedBody, maximum: Self.maximumBytes))
        identity = expected.identity; inventory = expected.inventory; body = savedBody
    }

    fileprivate func validate(_ row: [String: Any]) throws {
        guard Set(row.keys) == Set(identity.fields.keys).union(["items"]),
              let items = row["items"] as? [[String: Any]] else { throw MerianError.invalidResponse }
        try identity.validate(row)
        try inventory.validate(items: JSONSerialization.data(withJSONObject: items))
        for (item, expected) in zip(items, inventory.items) {
            guard item["media_id"] as? String == expected.artifact.mediaID.uuidString.lowercased() else { throw MerianError.invalidResponse }
        }
    }

    private static func fields(_ item: ObservationVideoCohortInventory.Item) -> [String: Any] {
        ["role": item.role.rawValue, "index": item.index.map { $0 as Any } ?? NSNull(),
         "media_id": item.artifact.mediaID.uuidString.lowercased(), "content_type": item.artifact.contentType,
         "byte_count": item.artifact.byteCount, "sha256": item.artifact.sha256]
    }

    fileprivate static func object(_ data: Data, maximum: Int) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= maximum, !data.contains(0), String(data: data, encoding: .utf8) != nil,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MerianError.invalidResponse }
        return row
    }
}

/// Closed whole-inventory snapshot; matching metadata is not authenticated storage authority.
struct ObservationVideoEvidenceReceipt: Equatable, Sendable {
    static let maximumBytes = 8_192
    enum State: String, Sendable { case allocated, ready }
    struct Item: Equatable, Sendable {
        let metadata: ObservationVideoCohortInventory.Item
        let objectID: UUID
        let readyAt: String?
    }
    let request: ObservationVideoEvidenceUploadRequest
    let ownerID: UUID
    let state: State
    let expiresAt: String
    let items: [Item]
    let data: Data

    init(data: Data, request: ObservationVideoEvidenceUploadRequest, ownerID: UUID, previous: Self? = nil) throws {
        let row = try ObservationVideoEvidenceUploadRequest.object(data, maximum: Self.maximumBytes)
        guard Set(row.keys) == Set(request.identity.fields.keys).union(["items", "owner_id", "state", "expires_at"]),
              row["owner_id"] as? String == ownerID.uuidString.lowercased(),
              let rawState = row["state"] as? String, let state = State(rawValue: rawState),
              let rows = row["items"] as? [[String: Any]], rows.count == request.inventory.items.count else { throw MerianError.invalidResponse }
        let expiry = try Self.timestamp(row["expires_at"])
        var metadata = row
        metadata.removeValue(forKey: "owner_id"); metadata.removeValue(forKey: "state"); metadata.removeValue(forKey: "expires_at")
        metadata["items"] = rows.map { $0.filter { !["object_id", "ready_at"].contains($0.key) } }
        try request.validate(metadata)
        var seen = Set([ownerID, request.identity.observationID, request.identity.sourceAnalysisID, request.identity.analysisID]
            + request.inventory.items.map { $0.artifact.mediaID })
        var items: [Item] = []
        for (row, expected) in zip(rows, request.inventory.items) {
            guard Set(row.keys) == Set(["role", "index", "media_id", "content_type", "byte_count", "sha256", "object_id", "ready_at"]) else { throw MerianError.invalidResponse }
            let object = try ObservationHistoryPage.uuid(row["object_id"])
            guard row["object_id"] as? String == object.uuidString.lowercased(), seen.insert(object).inserted else { throw MerianError.invalidResponse }
            let ready = row["ready_at"] is NSNull ? nil : try Self.timestamp(row["ready_at"])
            if let ready, ready >= expiry { throw MerianError.invalidResponse }
            items.append(Item(metadata: expected, objectID: object, readyAt: ready))
        }
        guard (state == .ready) == items.allSatisfy({ $0.readyAt != nil }) else { throw MerianError.invalidResponse }
        if let previous {
            guard previous.ownerID == ownerID, previous.request.identity == request.identity,
                  previous.request.inventory == request.inventory, previous.expiresAt == expiry,
                  zip(previous.items, items).allSatisfy({ old, new in
                      old.objectID == new.objectID && (old.readyAt == nil || old.readyAt == new.readyAt)
                  }) else { throw MerianError.invalidResponse }
        }
        self.request = request; self.ownerID = ownerID; self.state = state
        expiresAt = expiry; self.items = items; self.data = data
    }

    static func allocation(data: Data, request: ObservationVideoEvidenceUploadRequest, ownerID: UUID) throws -> Self {
        let result = try Self(data: data, request: request, ownerID: ownerID)
        guard result.items.allSatisfy({ $0.readyAt == nil }) else { throw MerianError.invalidResponse }
        return result
    }

    private static func timestamp(_ value: Any?) throws -> String {
        guard let value = value as? String, value.utf8.count == 24,
              value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"#, options: .regularExpression) != nil,
              !value.hasPrefix("0000") else { throw MerianError.invalidResponse }
        // Proleptic Gregorian arithmetic matches the server for years 0001–9999,
        // independent of Foundation locale/calendar historical cutovers.
        let parts = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard parts.count == 7, (1...9999).contains(parts[0]), (1...12).contains(parts[1]),
              parts[3] < 24, parts[4] < 60, parts[5] < 60 else { throw MerianError.invalidResponse }
        let leap = parts[0] % 4 == 0 && (parts[0] % 100 != 0 || parts[0] % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[parts[1] - 1]).contains(parts[2]) else { throw MerianError.invalidResponse }
        return value
    }
}
