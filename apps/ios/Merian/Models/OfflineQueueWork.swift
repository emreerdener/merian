import Foundation

/// Routing authority is persisted on the queue row, independently of mutable job JSON.
enum OfflineQueueWork: Equatable, Sendable {
    struct Reanalysis: Equatable, Sendable {
        let observationID: UUID
        let sourceAnalysisID: UUID
        let analysisID: UUID
        let ownerID: UUID
    }
    case ordinary
    case reanalysis(Reanalysis)
    case invalid

    static func classify(kind: String, childID: String, parentID: String?, sourceID: String?, ownerID: String?) -> Self {
        if kind == "ordinary" {
            return parentID == nil && sourceID == nil && ownerID == nil ? .ordinary : .invalid
        }
        guard kind == "reanalysis", let child = canonicalUUID(childID),
              let parent = canonicalUUID(parentID), let source = canonicalUUID(sourceID),
              let owner = canonicalUUID(ownerID), Set([child, parent, source]).count == 3 else { return .invalid }
        return .reanalysis(.init(observationID: parent, sourceAnalysisID: source, analysisID: child, ownerID: owner))
    }

    private static func canonicalUUID(_ text: String?) -> UUID? {
        guard let text, let value = UUID(uuidString: text), value.uuidString.lowercased() == text else { return nil }
        return value
    }
}
