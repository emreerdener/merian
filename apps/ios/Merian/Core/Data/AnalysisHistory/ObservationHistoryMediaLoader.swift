import Foundation
import Supabase
import SwiftData

struct ObservationHistoryMediaRequest: Encodable, Sendable {
    let observation_id: String
    let analysis_id: String
    let media_id: String
    var resolution_protocol: Int = 1
}

// The completed-media endpoint deliberately retains the existing ephemeral
// ticket envelope and bounded, no-cache, redirect-denying transport.
typealias ObservationHistoryMediaTicket = ObservationHistoryPhotoTicket

@MainActor
struct ObservationHistoryMediaLoader {
    var account = ObservationHistoryCloudClient.live
    var resolve: (ObservationHistoryMediaRequest) async throws -> ObservationHistoryMediaTicket = { request in
        try await SupabaseManager.shared.client.functions.invoke("resolve-history-media", options: .init(body: request))
    }
    var download: @Sendable (ObservationHistoryMediaTicket) async throws -> Data = { ticket in
        try await PrivateHistoryPhotoTransport.download(ticket)
    }
    var now: () -> Date = Date.init

    func load(source: ObservationCompositionSource, artifact: ObservationVideoProvenance.Artifact,
              container: ModelContainer, isCurrent: @escaping @MainActor () -> Bool) async throws -> Data {
        guard source.artifacts.filter({ $0.mediaID == artifact.mediaID }) == [artifact] else {
            throw ObservationHistoryError.invalidSnapshot
        }
        let lease = try account.begin(source.ownerID)
        defer { account.finish(lease) }
        func validate() throws {
            try Task.checkCancellation()
            guard isCurrent(), lease.session.userID == source.ownerID, account.isCurrent(lease) else {
                throw ObservationHistoryError.accountChanged
            }
            try source.validate(container: container)
        }
        try validate()
        let request = ObservationHistoryMediaRequest(observation_id: source.observationID.uuidString.lowercased(),
            analysis_id: source.analysisID.uuidString.lowercased(), media_id: artifact.mediaID.uuidString.lowercased(),
            resolution_protocol: source.resolutionProtocol)
        let ticket = try await resolve(request)
        try validate()
        try ticket.validateMedia(owner: source.ownerID, request: request, artifact: artifact, now: now(), source: source)
        let bytes = try await download(ticket)
        try validate()
        guard bytes.count == artifact.byteCount else { throw ObservationHistoryError.invalidSnapshot }
        let digest = await PrivateHistoryPhotoTransport.digest(bytes)
        try validate()
        guard digest == artifact.sha256 else { throw ObservationHistoryError.invalidSnapshot }
        return bytes
    }
}

extension ObservationHistoryPhotoTicket {
    func validateMedia(owner: UUID, request: ObservationHistoryMediaRequest,
                       artifact: ObservationVideoProvenance.Artifact, now: Date,
                       source: ObservationCompositionSource? = nil) throws {
        let expiry = Double(expires_at_ms) / 1000
        let types = ["image/jpeg", "image/png", "image/heic", "image/webp", "audio/wav", "video/mp4"]
            + ([2, 3].contains(request.resolution_protocol) ? ["image/heif", "audio/mp4"] : [])
        let fullOriginal = request.resolution_protocol == 3 && source?.ownerID == owner
            && source?.observationID.uuidString.lowercased() == request.observation_id
            && source?.analysisID.uuidString.lowercased() == request.analysis_id
            && source?.isRetainedOriginalImage(artifact) == true
        let cap = content_type == "video/mp4" ? 12_582_912 : content_type.hasPrefix("audio/") ? 2_700_000
            : fullOriginal ? 33_554_432 : 5_242_880
        guard [1, 2, 3].contains(request.resolution_protocol), schema_version == 1, owner_id == owner.uuidString.lowercased(),
              observation_id == request.observation_id, analysis_id == request.analysis_id, media_id == request.media_id,
              media_id == artifact.mediaID.uuidString.lowercased(), types.contains(content_type),
              content_type == artifact.contentType, byte_count == artifact.byteCount, sha256 == artifact.sha256,
              (content_type == "audio/wav" ? 46 : 1)...cap ~= byte_count,
              expiry > now.timeIntervalSince1970, expiry <= now.timeIntervalSince1970 + 31,
              url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443,
              let host = url.host, host.range(of: "^[0-9a-f]{32}\\.r2\\.cloudflarestorage\\.com$", options: .regularExpression) != nil else {
            throw ObservationHistoryError.invalidSnapshot
        }
    }
}
