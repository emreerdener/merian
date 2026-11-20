import Foundation

/// Private tagged photo/audio handoff metadata. No phase is upload, funding or dispatch authority.
struct ObservationSourceReservationWork: Equatable, Sendable {
    static let maximumBytes = 4_194_304
    enum State: String, Sendable { case staged, running, unknown, observed, conflict }
    let preparation: ObservationSourceReservationPreparation
    let request: ObservationSourceReservationRequest
    let state: State
    let generation: Int
    let reply: ObservationSourceReservationReply?
    var identity: OfflineQueueWork.Reanalysis { preparation.identity }

    init(preparation: ObservationReanalysisPreparationIntent, request: ObservationSourceReservationRequest,
         state: State = .staged, generation: Int = 0, reply: ObservationSourceReservationReply? = nil) throws {
        try self.init(preparation: .photo(preparation), request: request, state: state, generation: generation, reply: reply)
    }

    init(preparation: ObservationSourceReservationPreparation, request: ObservationSourceReservationRequest,
         state: State = .staged, generation: Int = 0, reply: ObservationSourceReservationReply? = nil) throws {
        try preparation.validate(request)
        let validGeneration = state == .staged ? generation == 0 : generation > 0
        guard (0...1_000_000).contains(generation), validGeneration else { throw MerianError.invalidResponse }
        if state == .observed {
            guard let reply, reply.request == request, reply.ownerID == preparation.identity.ownerID else { throw MerianError.invalidResponse }
        } else { guard reply == nil else { throw MerianError.invalidResponse } }
        self.preparation = preparation; self.request = request; self.state = state
        self.generation = generation; self.reply = reply
    }

    func storedData() throws -> Data {
        let row: [String: Any] = ["version": preparation.version, "phase": "source_reservation",
            "preparation_base64": try preparation.storedData().base64EncodedString(),
            "input_base64": request.input.base64EncodedString(), "candidate_base64": request.body.base64EncodedString(),
            "state": state.rawValue, "generation": generation,
            "reply_base64": reply.map { $0.data.base64EncodedString() as Any } ?? NSNull()]
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["version", "phase", "preparation_base64", "input_base64", "candidate_base64", "state", "generation", "reply_base64"],
              row["phase"] as? String == "source_reservation",
              let raw = row["state"] as? String, let state = State(rawValue: raw) else { throw MerianError.invalidResponse }
        let preparation = try ObservationSourceReservationPreparation.decode(bytes(row["preparation_base64"], maximum: 1_048_576),
            version: ObservationHistoryPage.integer(row["version"]))
        let request = try ObservationSourceReservationRequest(savedInput: bytes(row["input_base64"], maximum: 1_044_480),
            savedBody: bytes(row["candidate_base64"], maximum: ObservationSourceReservationRequest.maximumBytes))
        let reply: ObservationSourceReservationReply?
        if row["reply_base64"] is NSNull { reply = nil } else {
            reply = try .init(data: bytes(row["reply_base64"], maximum: ObservationSourceReservationReply.maximumBytes),
                request: request, ownerID: preparation.identity.ownerID)
        }
        return try .init(preparation: preparation, request: request, state: state,
            generation: ObservationHistoryPage.integer(row["generation"]), reply: reply)
    }

    private static func bytes(_ value: Any?, maximum: Int) throws -> Data {
        guard let text = value as? String, text.utf8.count <= ((maximum + 2) / 3) * 4,
              let bytes = Data(base64Encoded: text), bytes.count <= maximum,
              bytes.base64EncodedString() == text else { throw MerianError.invalidResponse }
        return bytes
    }
}
