import Foundation

/// Immutable local desired state passed from SwiftData persistence to the
/// collection-sync transport boundary.
struct CollectionSyncSnapshot: Equatable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
    let isPendingDeletion: Bool
    let scanIDs: [String]
}
