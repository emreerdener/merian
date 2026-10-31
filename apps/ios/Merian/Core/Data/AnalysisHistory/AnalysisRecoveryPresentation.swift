import Foundation

/// Presentation accounting only. This value cannot authorize execution, retry,
/// settlement, cancellation, or media release. The existing operation owner
/// must persist each exact transition before acknowledging it to presentation.
struct AnalysisRecoveryPresentation: Equatable, Sendable {
    static let maximumBytes = 512
    static let visibleLimitMilliseconds = 30_000
    // Bound durable writes as well as time. Owners reserve this inventory
    // revision runway with the byte liability; no per-timer-tick saves.
    static let maximumTransitions: Int64 = 60

    struct Identity: Equatable, Sendable {
        let ownerID: UUID
        let observationID: UUID
        let operationID: UUID
    }

    enum Failure: Error { case invalid, stale, needsAttention }

    let identity: Identity
    let revision: Int64
    let chargedMilliseconds: Int
    let activeReservationID: UUID?

    /// A decoded active reservation has no live clock and is Needs attention.
    /// Only its original, still-live Reservation can settle unused time.
    var needsAttention: Bool {
        activeReservationID != nil || chargedMilliseconds == Self.visibleLimitMilliseconds || remainingTransitions == 0
    }

    var remainingTransitions: Int64 { Self.maximumTransitions - revision }

    private init(identity: Identity, revision: Int64, chargedMilliseconds: Int, activeReservationID: UUID?) {
        self.identity = identity; self.revision = revision
        self.chargedMilliseconds = chargedMilliseconds; self.activeReservationID = activeReservationID
    }

    static func initial(for identity: Identity) -> Self {
        .init(identity: identity, revision: 0, chargedMilliseconds: 0, activeReservationID: nil)
    }

    /// Persist reserved (with an exact predecessor comparison) BEFORE starting
    /// the visible monotonic clock. Losing this in-memory receipt spends all
    /// remaining presentation time; reopening never manufactures a new budget.
    func reserve(id: UUID) throws -> Reservation {
        guard !needsAttention else { throw Failure.needsAttention }
        guard remainingTransitions >= 2 else { throw Failure.invalid }
        return Reservation(predecessor: self, reserved: .init(identity: identity, revision: revision + 1,
            chargedMilliseconds: Self.visibleLimitMilliseconds, activeReservationID: id))
    }

    struct Reservation: Equatable, Sendable {
        let predecessor: AnalysisRecoveryPresentation
        let reserved: AnalysisRecoveryPresentation

        fileprivate init(predecessor: AnalysisRecoveryPresentation, reserved: AnalysisRecoveryPresentation) {
            self.predecessor = predecessor; self.reserved = reserved
        }

        var visibleAllowance: Duration {
            .milliseconds(AnalysisRecoveryPresentation.visibleLimitMilliseconds - predecessor.chargedMilliseconds)
        }

        /// Use ContinuousClock elapsed time from the acknowledged visible start,
        /// not a wall-clock date. The owner must CAS current to this successor.
        /// A stale pause cannot refund a newer reservation or another operation.
        func settle(current: AnalysisRecoveryPresentation, elapsed: Duration) throws -> AnalysisRecoveryPresentation {
            guard current == reserved else { throw Failure.stale }
            guard elapsed >= .zero else { throw Failure.invalid }
            let charged: Int
            if elapsed >= visibleAllowance {
                charged = AnalysisRecoveryPresentation.visibleLimitMilliseconds
            } else {
                // elapsed is nonnegative and below 30s; this conversion cannot
                // overflow. Round any visible fraction upward, never downward.
                let parts = elapsed.components
                let milliseconds = parts.seconds * 1_000 + (parts.attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
                charged = predecessor.chargedMilliseconds + Int(milliseconds)
            }
            return .init(identity: reserved.identity, revision: reserved.revision + 1,
                chargedMilliseconds: charged, activeReservationID: nil)
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(version: 1, owner: identity.ownerID.uuidString.lowercased(),
            observation: identity.observationID.uuidString.lowercased(), operation: identity.operationID.uuidString.lowercased(),
            revision: revision, chargedMilliseconds: chargedMilliseconds,
            activeReservation: activeReservationID?.uuidString.lowercased()))
        guard data.count <= Self.maximumBytes else { throw Failure.invalid }
        return data
    }

    static func decode(_ data: Data, identity: Identity) throws -> Self {
        guard data.count <= maximumBytes else { throw Failure.invalid }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1, (0...maximumTransitions).contains(envelope.revision),
              (0...visibleLimitMilliseconds).contains(envelope.chargedMilliseconds),
              envelope.owner == identity.ownerID.uuidString.lowercased(),
              envelope.observation == identity.observationID.uuidString.lowercased(),
              envelope.operation == identity.operationID.uuidString.lowercased() else { throw Failure.invalid }
        var active: UUID?
        if let text = envelope.activeReservation {
            guard let id = UUID(uuidString: text), id.uuidString.lowercased() == text,
                  envelope.chargedMilliseconds == visibleLimitMilliseconds,
                  envelope.revision % 2 == 1 else { throw Failure.invalid }
            active = id
        } else {
            guard envelope.revision % 2 == 0 else { throw Failure.invalid }
        }
        guard envelope.revision != 0 || (envelope.chargedMilliseconds == 0 && active == nil) else { throw Failure.invalid }
        let result = Self(identity: identity, revision: envelope.revision,
            chargedMilliseconds: envelope.chargedMilliseconds, activeReservationID: active)
        // One bounded canonical representation: rejects unknown/duplicate keys,
        // explicit nulls, alternate UUID spellings and lossy numeric forms.
        guard try result.encoded() == data else { throw Failure.invalid }
        return result
    }

    private struct Envelope: Codable {
        let version: Int
        let owner: String
        let observation: String
        let operation: String
        let revision: Int64
        let chargedMilliseconds: Int
        let activeReservation: String?
    }
}
