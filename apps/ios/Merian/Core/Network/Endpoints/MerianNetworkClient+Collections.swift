import Foundation

private struct CollectionSyncRequestPayload: Encodable {
    let collections: [CollectionSyncItemPayload]
}

private struct CollectionSyncItemPayload: Encodable {
    let id: String
    let name: String
    let createdAt: String
    let isDeleted: Bool
    let scanIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case isDeleted = "is_deleted"
        case scanIDs = "scan_ids"
    }
}

extension MerianNetworkClient {
    /// Replaces the authenticated user's remote collection state with the
    /// supplied local snapshot. Successful response bytes are intentionally
    /// ignored because `/sync-collections` defines completion through HTTP 2xx.
    func syncCollections(_ snapshots: [CollectionSyncSnapshot]) async throws {
        let payload = CollectionSyncRequestPayload(
            collections: snapshots.map { snapshot in
                CollectionSyncItemPayload(
                    id: snapshot.id,
                    name: snapshot.name,
                    createdAt: DateUtilities.iso8601Formatter.string(
                        from: snapshot.createdAt
                    ),
                    isDeleted: snapshot.isPendingDeletion,
                    scanIDs: snapshot.scanIDs
                )
            }
        )
        _ = try await performAuthenticatedEncodedJSONPost(
            function: "sync-collections",
            body: payload,
            timeoutInterval: 30,
            // The durable collection task already owns an outer account-work
            // lease. Starting ordinary 401 recovery here would recursively
            // wait for that same task and lease to quiesce.
            allowsUnauthorizedSessionRecovery: false
        )
    }
}
