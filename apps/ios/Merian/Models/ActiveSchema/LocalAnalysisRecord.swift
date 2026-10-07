import Foundation
import SwiftData

/// Owner-private immutable result storage. Normal app history sync remains disabled.
/// The parent owns a one-way cascade relationship, like captured-media entries.
/// These bytes are an opaque transport snapshot, never identification/review authority.
/// ObservationHistorySyncService owns gated account/deletion/replay admission.
/// A future live completion producer must prove durable protected evidence.
@Model
public final class LocalAnalysisRecord {
    @Attribute(.unique) public private(set) var id: String
    public private(set) var observationID: String
    public private(set) var ownerAccountID: String
    public private(set) var completedAt: Date?
    public private(set) var snapshotVersion: Int
    public private(set) var resultSnapshotData: Data

    /// Mutable owner authority and immutable display cache have a separate lifecycle.
    @Relationship(deleteRule: .cascade) public var state: LocalAnalysisStateRecord?

    public static let maximumSnapshotBytes = 1_048_576
    public static let supportedSnapshotVersion = 1

    enum StorageError: Error, Equatable {
        case invalidSnapshot
        case unsupportedVersion
        case invalidObservation
        case invalidCompletionDate
    }

    /// Structural storage validation only; this does not attest server completion.
    init(
        analysisID: UUID,
        observationID: String,
        ownerAccountID: UUID,
        completedAt: Date?,
        snapshotVersion: Int = supportedSnapshotVersion,
        resultSnapshotData: Data
    ) throws {
        guard [1, 2, 3, 4].contains(snapshotVersion) else {
            throw StorageError.unsupportedVersion
        }
        guard !resultSnapshotData.isEmpty,
              resultSnapshotData.count <= Self.maximumSnapshotBytes,
              (try? JSONSerialization.jsonObject(with: resultSnapshotData)) is [String: Any] else {
            throw StorageError.invalidSnapshot
        }
        guard !observationID.isEmpty else { throw StorageError.invalidObservation }
        // Import time is preserved inside V3 bytes; it is never completion.
        guard (snapshotVersion == 3) == (completedAt == nil),
              completedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true else {
            throw StorageError.invalidCompletionDate
        }
        self.id = analysisID.uuidString.lowercased()
        self.observationID = observationID
        self.ownerAccountID = ownerAccountID.uuidString.lowercased()
        self.completedAt = completedAt
        self.snapshotVersion = snapshotVersion
        self.resultSnapshotData = resultSnapshotData
    }
}
