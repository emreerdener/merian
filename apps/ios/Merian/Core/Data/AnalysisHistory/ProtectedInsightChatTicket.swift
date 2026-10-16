import CryptoKit
import Foundation

/// The loaded selected identification, never a historical preview or freshly substituted selection.
struct ProtectedInsightChatTicket: Equatable, Sendable {
    let ownerID: UUID
    let observationID: UUID
    let selection: ProtectedInsightChatRequest.Selection
    private let resultDigest: Data
    private let authorityDigest: Data

    init(entry: ObservationHistoryListingService.Entry, context: ObservationHistoryListingService.Context, observationID: UUID) throws {
        guard [1, 2, 3].contains(entry.result.version), context.pendingOperation == nil, context.selected == entry.result.analysisID,
              let authority = entry.authority, let revision = entry.reviewRevision,
              let envelope = try JSONSerialization.jsonObject(with: entry.result.bytes) as? [String: Any],
              envelope["observation_id"] as? String == observationID.uuidString.lowercased(),
              envelope["analysis_id"] as? String == entry.result.analysisID.uuidString.lowercased() else { throw ObservationHistoryError.unavailable }
        ownerID = context.owner; self.observationID = observationID
        selection = try .init(analysisID: entry.result.analysisID, stateRevision: context.revision, reviewRevision: revision)
        resultDigest = Data(SHA256.hash(data: entry.result.bytes)); authorityDigest = Data(SHA256.hash(data: authority.data))
    }
    func request(conversationID: UUID, clientMessageID: UUID, normalizedText: String) throws -> ProtectedInsightChatRequest {
        try .init(observationID: observationID, conversationID: conversationID, clientMessageID: clientMessageID,
                  messageText: normalizedText, selection: selection)
    }
}
