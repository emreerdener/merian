import Foundation
import SwiftData

/// Owner-private cache. Result bytes stay immutable on LocalAnalysisRecord;
/// authority advances independently and never selects an identification.
@Model
public final class LocalAnalysisStateRecord {
    @Attribute(.unique) public private(set) var id: String
    public private(set) var observationID: String
    public private(set) var ownerAccountID: String
    public private(set) var observationStateRevision: Int
    public private(set) var reviewRevision: Int
    public private(set) var reviewSnapshotData: Data
    public private(set) var displaySnapshotData: Data?

    enum StorageError: Error, Equatable { case invalidState, staleRevision, conflictingRevision, conflictingDisplay }

    init(analysisID: UUID, observationID: String, ownerAccountID: UUID,
         observationStateRevision: Int, reviewRevision: Int, reviewSnapshotData: Data,
         displaySnapshotData: Data? = nil) throws {
        guard UUID(uuidString: observationID) != nil else { throw StorageError.invalidState }
        try Self.validate(observationStateRevision, reviewRevision, reviewSnapshotData, displaySnapshotData)
        self.id = analysisID.uuidString.lowercased()
        self.observationID = observationID
        self.ownerAccountID = ownerAccountID.uuidString.lowercased()
        self.observationStateRevision = observationStateRevision
        self.reviewRevision = reviewRevision
        self.reviewSnapshotData = reviewSnapshotData
        self.displaySnapshotData = displaySnapshotData
    }

    /// Call only inside the account/deletion-fenced admission transaction.
    func update(observationStateRevision: Int, reviewRevision: Int,
                reviewSnapshotData: Data, displaySnapshotData: Data?) throws {
        try Self.validate(observationStateRevision, reviewRevision, reviewSnapshotData, displaySnapshotData)
        guard observationStateRevision >= self.observationStateRevision, reviewRevision >= self.reviewRevision else {
            throw StorageError.staleRevision
        }
        guard reviewRevision != self.reviewRevision || reviewSnapshotData == self.reviewSnapshotData,
              observationStateRevision != self.observationStateRevision || reviewRevision == self.reviewRevision else {
            throw StorageError.conflictingRevision
        }
        if let saved = self.displaySnapshotData, let incoming = displaySnapshotData, saved != incoming {
            throw StorageError.conflictingDisplay
        }
        self.observationStateRevision = observationStateRevision
        self.reviewRevision = reviewRevision
        self.reviewSnapshotData = reviewSnapshotData
        if self.displaySnapshotData == nil { self.displaySnapshotData = displaySnapshotData }
    }

    /// Structural bounds only. Domain authority/display decoders own validation.
    private static func validate(_ observationRevision: Int, _ reviewRevision: Int, _ review: Data, _ display: Data?) throws {
        guard observationRevision > 0, reviewRevision >= 0, reviewRevision <= observationRevision,
              !review.isEmpty, review.count <= 32_768,
              (try? JSONSerialization.jsonObject(with: review)) is [String: Any] else { throw StorageError.invalidState }
        if let display {
            guard !display.isEmpty, display.count <= LocalAnalysisRecord.maximumSnapshotBytes,
                  (try? JSONSerialization.jsonObject(with: display)) is [String: Any] else { throw StorageError.invalidState }
        }
    }
}
