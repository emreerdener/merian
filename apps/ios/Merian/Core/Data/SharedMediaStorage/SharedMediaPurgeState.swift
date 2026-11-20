import Foundation
import SwiftData

/// The cursor is a versioned destructive-lifecycle record, never an ordinary
/// observation cursor or a reusable file capability.
struct SharedMediaPurgeState: Codable, Equatable, Sendable {
    enum Stage: String, Codable, Sendable { case draining, releasing, complete }
    let version: Int
    let id: UUID
    let stage: Stage
    init(id: UUID, stage: Stage) { version = 1; self.id = id; self.stage = stage }

    var phase: String { stage == .complete ? "purgedP1" : "purgingP1" }
    func encoded() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= SharedMediaStoragePolicy.maximumTokenBytes,
              let value = String(data: bytes, encoding: .utf8) else { throw SharedMediaStorageFailure.invalid }
        return value
    }
    @MainActor static func read(_ row: SharedMediaInventoryRecord) throws -> Self {
        guard row.modeRaw == SharedMediaStorageMode.p1InboxQualification.rawValue,
              row.cursor.utf8.count <= SharedMediaStoragePolicy.maximumTokenBytes else { throw SharedMediaStorageFailure.conflict }
        let result = try JSONDecoder().decode(Self.self, from: Data(row.cursor.utf8))
        guard result.version == 1, result.phase == row.phaseRaw,
              try result.encoded() == row.cursor else { throw SharedMediaStorageFailure.conflict }
        return result
    }
    @MainActor func install(_ row: SharedMediaInventoryRecord) throws {
        row.phaseRaw = phase; row.cursor = try encoded()
    }

    /// Do not replace the global liability predicate: the inventory tombstone
    /// deliberately remains present and blocks ordinary identity replacement.
    @MainActor static func requireEmptyGraph(_ context: ModelContext) throws {
        for type in CurrentSchema.models where
            SharedMediaStorageLookup.photoTypes.contains(ObjectIdentifier(type)) ||
            SharedMediaStorageLookup.inboxTypes.contains(ObjectIdentifier(type)) ||
            (SharedMediaStorageLookup.ledgerTypes.contains(ObjectIdentifier(type)) &&
             ObjectIdentifier(type) != ObjectIdentifier(SharedMediaInventoryRecord.self)) {
            guard try SharedMediaStorageLookup.count(context, type) == 0 else { throw SharedMediaStorageFailure.inUse }
        }
    }
}

enum SharedMediaPurgeBoundary: Sendable {
    case beforeIntentSave, afterIntentSave, beforeDrainSave, afterDrainSave
    case beforeRetirementSave, afterRetirementSave, beforeReleaseSave, afterReleaseSave
    case beforeTerminalSave, afterTerminalSave
}
