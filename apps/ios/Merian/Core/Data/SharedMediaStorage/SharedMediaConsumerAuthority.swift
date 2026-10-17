import Foundation

/// Structural classification only. Direct ownership still requires a fresh ledger join.
/// Missing or malformed shared authority never returns a legacy projection.
enum SharedMediaConsumerAuthority: Equatable, Sendable {
    case legacy
    case direct(UUID)
    case historyProjection

    enum RecordKind: Equatable, Sendable { case queue, scan, analysis }

    static func classify(raw: String, consumerID: UUID?, record: RecordKind) throws -> Self {
        switch (raw, consumerID) {
        case ("legacy", nil): return .legacy
        case let ("sharedDirectV1", .some(id)): return .direct(id)
        case ("sharedHistoryProjectionV1", nil) where record == .scan: return .historyProjection
        default: throw SharedMediaStorageFailure.conflict
        }
    }
}

/// Execution identity survives ownership transfer (initial scan to baseline child).
/// Reanalysis uses its existing intent/attempt/erasure authority, not an initial generation.
enum SharedMediaConsumerExecution: Equatable, Sendable {
    case ordinary(UUID)
    case reanalysis

    static func classify(raw: String, generation: UUID?) throws -> Self {
        switch (raw, generation) {
        case let ("ordinaryV1", .some(value)): return .ordinary(value)
        case ("reanalysisV1", nil): return .reanalysis
        default: throw SharedMediaStorageFailure.conflict
        }
    }
}
