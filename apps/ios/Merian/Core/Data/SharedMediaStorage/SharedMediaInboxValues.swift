import Foundation

struct SharedMediaInboxHandle: Codable, Equatable, Sendable {
    let id: UUID
    let generation: UUID
    let revision: Int64
}

/// Values copied out of one validated transaction; never a free-form file path.
struct SharedMediaInboxSource: Sendable, Equatable {
    let handle: SharedMediaInboxHandle
    let workID: UUID
    let writerEpoch: UUID
    let writerState: String
    let phase: String
    let maximumBytes: Int64
    let expectedBytes: Int64
    let sha256: String?
    let contentType: String?
    let device: Int64?
    let inode: Int64?
    let finalIdentity: String?
    let rootIdentity: String
    let retirementID: UUID?
    let retirementPartialIdentity: String?
    let retirementFinalIdentity: String?
    var token: String { handle.id.uuidString.lowercased() }
    var partialToken: String { token + ".partial" }
}

struct SharedMediaInboxPrepared: Equatable, Sendable {
    let bytes: Int64
    let sha256: String
    let contentType: String
}

struct SharedMediaInboxFileIdentity: Equatable, Sendable {
    let device: Int64
    let inode: Int64
    let bytes: Int64
    let exact: String
}

enum SharedMediaInboxRecovery: Equatable, Sendable {
    case ready(SharedMediaInboxHandle)
    case incomplete(SharedMediaInboxHandle)
    case missing(SharedMediaInboxHandle)
    case conflict(SharedMediaInboxHandle)
}

enum SharedMediaInboxBoundary: Sendable, Equatable {
    case beforeReservationSave, afterReservationSave, beforePreparedSave, afterPreparedSave
    case afterPartialCreate, beforeIdentitySave, afterIdentitySave, duringWrite, afterRename
    case beforeCompletionSave, afterCompletionSave, beforeRetirementSave, afterRetirementSave
    case afterPartialUnlink, afterFinalUnlink, beforeReleaseSave, afterReleaseSave
    case beforeOccupancySave, afterOccupancySave
}
