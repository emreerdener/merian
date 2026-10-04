import CryptoKit
import Foundation
import Supabase
import SwiftData

struct ObservationHistoryPhotoRequest: Encodable, Sendable {
    let observation_id: String
    let analysis_id: String
    let media_id: String
    let reader_protocol = 8
}

/// Short-lived delivery value. It must never enter a model, cache key or log.
struct ObservationHistoryPhotoTicket: Decodable, Sendable {
    let schema_version: Int
    let owner_id: String
    let observation_id: String
    let analysis_id: String
    let media_id: String
    let content_type: String
    let byte_count: Int
    let sha256: String
    let url: URL
    let expires_at_ms: Int64

    func validate(owner: UUID, request: ObservationHistoryPhotoRequest, photo: ObservationHistoryPhotoReference, now: Date) throws {
        let expiry = Double(expires_at_ms) / 1000
        guard schema_version == 1, owner_id == owner.uuidString.lowercased(),
              observation_id == request.observation_id, analysis_id == request.analysis_id, media_id == request.media_id,
              content_type == photo.contentType, byte_count == photo.byteCount, sha256 == photo.sha256,
              expiry > now.timeIntervalSince1970, expiry <= now.timeIntervalSince1970 + 31,
              url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443,
              let host = url.host, host.range(of: "^[0-9a-f]{32}\\.r2\\.cloudflarestorage\\.com$", options: .regularExpression) != nil else {
            throw ObservationHistoryError.invalidSnapshot
        }
    }
}

@MainActor
struct ObservationHistoryPhotoLoader {
    var account = ObservationHistoryCloudClient.live
    var resolve: (ObservationHistoryPhotoRequest) async throws -> ObservationHistoryPhotoTicket = { request in
        try await SupabaseManager.shared.client.functions.invoke("resolve-history-photo", options: .init(body: request))
    }
    var download: @Sendable (ObservationHistoryPhotoTicket) async throws -> Data = { ticket in
        try await PrivateHistoryPhotoTransport.download(ticket)
    }

    func load(observationID: String, analysisID: UUID, mediaID: UUID, container: ModelContainer) async throws -> Data {
        let (owner, photo) = try reference(observationID: observationID, analysisID: analysisID, mediaID: mediaID, container: container)
        let lease = try account.begin(owner)
        defer { account.finish(lease) }
        guard lease.session.userID == owner, account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        let request = ObservationHistoryPhotoRequest(observation_id: observationID.lowercased(),
            analysis_id: analysisID.uuidString.lowercased(), media_id: mediaID.uuidString.lowercased())
        let ticket = try await resolve(request)
        try Task.checkCancellation()
        guard account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        try ticket.validate(owner: owner, request: request, photo: photo, now: Date())
        let before = try reference(observationID: observationID, analysisID: analysisID, mediaID: mediaID, container: container)
        guard before.0 == owner, before.1 == photo else { throw ObservationHistoryError.accountChanged }
        let bytes = try await download(ticket)
        try Task.checkCancellation()
        guard account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        let after = try reference(observationID: observationID, analysisID: analysisID, mediaID: mediaID, container: container)
        guard after.0 == owner, after.1 == photo else { throw ObservationHistoryError.accountChanged }
        guard bytes.count == photo.byteCount else { throw ObservationHistoryError.invalidSnapshot }
        // Hashing runs outside MainActor even for an injected transport.
        let digest = await PrivateHistoryPhotoTransport.digest(bytes)
        try Task.checkCancellation()
        guard account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        let final = try reference(observationID: observationID, analysisID: analysisID, mediaID: mediaID, container: container)
        guard final.0 == owner, final.1 == photo else { throw ObservationHistoryError.accountChanged }
        guard digest == photo.sha256 else { throw ObservationHistoryError.invalidSnapshot }
        return bytes
    }

    private func reference(observationID: String, analysisID: UUID, mediaID: UUID, container: ModelContainer) throws -> (UUID, ObservationHistoryPhotoReference) {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(observationID, context: context)
            guard let ownerText = scan.analysisOwnerAccountID, let owner = UUID(uuidString: ownerText) else { throw ObservationHistoryError.unavailable }
            let id = analysisID.uuidString.lowercased()
            var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
            query.fetchLimit = 1
            guard let record = try context.fetch(query).first, record.ownerAccountID == ownerText,
                  record.observationID == scan.id, record.snapshotVersion == 2 else { throw ObservationHistoryError.unavailable }
            let raw = try JSONSerialization.jsonObject(with: record.resultSnapshotData) as? [String: Any]
            let ordinal = try ObservationHistoryPage.integer(raw?["ordinal"])
            let result = try ObservationHistoryPage.snapshot(record.resultSnapshotData, observationID: observationID.lowercased(), ordinal: ordinal)
            guard result.analysisID == analysisID, let photo = result.photos.first(where: { $0.mediaID == mediaID }) else { throw ObservationHistoryError.invalidSnapshot }
            return (owner, photo)
        }
    }
}

/// Dedicated ephemeral transport: no public-media cache or repair path. Redirects
/// are rejected so a signed capability cannot escape its validated storage host.
private final class HistoryPhotoRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum PrivateHistoryPhotoTransport {
    nonisolated static func digest(_ bytes: Data) async -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func download(_ ticket: ObservationHistoryPhotoTicket) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: HistoryPhotoRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: ticket.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            let (stream, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.mimeType == ticket.content_type,
                  http.expectedContentLength == Int64(ticket.byte_count) else { throw ObservationHistoryError.unavailable }
            var bytes = Data(); bytes.reserveCapacity(ticket.byte_count)
            for try await byte in stream {
                guard bytes.count < ticket.byte_count else { throw ObservationHistoryError.invalidSnapshot }
                bytes.append(byte)
            }
            try Task.checkCancellation()
            guard bytes.count == ticket.byte_count else { throw ObservationHistoryError.invalidSnapshot }
            return bytes
        } catch is CancellationError { throw CancellationError() }
        catch { throw ObservationHistoryError.unavailable } // Do not propagate signed URLs in NSError.
    }
}
