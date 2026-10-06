import CoreFoundation
import Foundation

/// Enrolled native subset of the closed immutable Field Chat protocol. No inferred IDs.
struct ProtectedInsightChatRequest: Equatable, Sendable {
    struct Selection: Equatable, Sendable {
        let analysisID: UUID
        let stateRevision: Int
        let reviewRevision: Int
        init(analysisID: UUID, stateRevision: Int, reviewRevision: Int) throws {
            guard (1...2_147_483_646).contains(stateRevision), (0...stateRevision).contains(reviewRevision) else {
                throw MerianError.invalidResponse
            }
            self.analysisID = analysisID; self.stateRevision = stateRevision; self.reviewRevision = reviewRevision
        }
        var object: [String: Any] {
            ["analysis_id": analysisID.uuidString.lowercased(), "state_revision": stateRevision, "review_revision": reviewRevision]
        }
    }
    let observationID: UUID
    let conversationID: UUID
    let clientMessageID: UUID
    let messageText: String
    let selection: Selection

    init(observationID: UUID, conversationID: UUID, clientMessageID: UUID, messageText: String, selection: Selection) throws {
        // ECMAScript trim/UTF-16 bounds; never normalize Unicode or change saved text on recovery.
        let trim = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        guard !messageText.isEmpty, messageText.utf16.count <= 600,
              messageText.utf8.elementsEqual(messageText.trimmingCharacters(in: trim).utf8) else { throw MerianError.invalidResponse }
        self.observationID = observationID; self.conversationID = conversationID; self.clientMessageID = clientMessageID
        self.messageText = messageText; self.selection = selection
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.observationID == rhs.observationID && lhs.conversationID == rhs.conversationID
            && lhs.clientMessageID == rhs.clientMessageID && lhs.selection == rhs.selection
            && lhs.messageText.utf8.elementsEqual(rhs.messageText.utf8)
    }
    func encoded() throws -> Data {
        let row: [String: Any] = ["action": "send", "context_version": 1,
            "scan_id": observationID.uuidString.lowercased(), "conversation_id": conversationID.uuidString.lowercased(),
            "client_message_id": clientMessageID.uuidString.lowercased(), "message_text": messageText, "displayed_ticket": selection.object]
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 8192 else { throw MerianError.invalidResponse }
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        let row = try ProtectedInsightChatWire.object(data, limit: 8192)
        guard Set(row.keys) == ["action", "context_version", "scan_id", "conversation_id", "client_message_id", "message_text", "displayed_ticket"],
              row["action"] as? String == "send", try ProtectedInsightChatWire.integer(row["context_version"]) == 1,
              let text = row["message_text"] as? String, let ticket = row["displayed_ticket"] as? [String: Any],
              Set(ticket.keys) == ["analysis_id", "state_revision", "review_revision"] else { throw MerianError.invalidResponse }
        return try Self(observationID: ProtectedInsightChatWire.uuid(row["scan_id"]),
            conversationID: ProtectedInsightChatWire.uuid(row["conversation_id"]), clientMessageID: ProtectedInsightChatWire.uuid(row["client_message_id"]),
            messageText: text, selection: Selection(analysisID: ProtectedInsightChatWire.uuid(ticket["analysis_id"]),
                stateRevision: ProtectedInsightChatWire.integer(ticket["state_revision"]), reviewRevision: ProtectedInsightChatWire.integer(ticket["review_revision"])))
    }
}

enum ProtectedInsightChatWire {
    static func object(_ data: Data, limit: Int) throws -> [String: Any] {
        guard data.count <= limit, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MerianError.invalidResponse }
        return row
    }
    static func uuid(_ raw: Any?) throws -> UUID {
        guard let text = raw as? String, let id = UUID(uuidString: text), text == id.uuidString.lowercased() else { throw MerianError.invalidResponse }
        return id
    }
    static func integer(_ raw: Any?) throws -> Int {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, (0...2_147_483_646).contains(value.doubleValue),
              value.doubleValue.rounded() == value.doubleValue else { throw MerianError.invalidResponse }
        return value.intValue
    }
}
