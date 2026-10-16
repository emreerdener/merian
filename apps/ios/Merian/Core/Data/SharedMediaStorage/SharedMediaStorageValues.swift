import Foundation

enum SharedMediaStorageFailure: Error, Equatable {
    case unavailable, busy, invalid, conflict, stale, closed, capacity, inUse
}

enum SharedMediaStorageMode: String, Sendable { case observation, qualification, p1Qualification }
enum SharedMediaStoragePool: String, Sendable {
    case observed, durable, acquisition, preparation, transfer
}

struct SharedMediaStorageReservation: Equatable, Sendable {
    let id: UUID
    let packageID: UUID
    let accountID: UUID
    let pool: SharedMediaStoragePool
    let bytes: Int64
}

struct SharedMediaStorageCharge: Sendable {
    let packageID: UUID?
    let pool: SharedMediaStoragePool
    let materialized: Int64
    let reserved: Int64
}

struct SharedMediaStorageObservation: Sendable {
    let id: UUID
    let namespace: String
    let token: String
    let bytes: Int64
    let physicalIdentity: String
}

struct SharedMediaStorageSnapshot: Equatable, Sendable {
    let generation: UUID
    let revision: Int64
    let phase: String
    let cursor: String
}
