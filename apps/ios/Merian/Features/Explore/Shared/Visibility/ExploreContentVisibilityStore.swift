import Combine
import Foundation
import Observation

/// Immediate, account-scoped suppression. Durable visibility is enforced by the server.
@MainActor
@Observable
final class ExploreContentVisibilityStore {
    struct Context: Equatable, Sendable {
        let viewerID: UUID?
        let generation: UInt64
        let accountGeneration: UInt64
    }

    private(set) var viewerID: UUID?
    private var accountGeneration: UInt64 = 0
    private(set) var generation: UInt64 = 0
    private(set) var reportedPostIDs: Set<String> = []
    @ObservationIgnored var didInvalidate: () -> Void = {}
    @ObservationIgnored let changes = PassthroughSubject<Context, Never>()

    var context: Context { Context(viewerID: viewerID, generation: generation, accountGeneration: accountGeneration) }

    func activate(viewerID: UUID?) {
        guard self.viewerID != viewerID else { return }
        self.viewerID = viewerID
        accountGeneration &+= 1
        reportedPostIDs.removeAll()
        generation &+= 1
        didInvalidate()
        changes.send(context)
    }

    func isVisible(postID: String) -> Bool {
        !reportedPostIDs.contains(postID.lowercased())
    }

    @discardableResult
    func hide(postID: String, for viewerID: UUID?) -> Bool {
        guard viewerID != nil, self.viewerID == viewerID,
              reportedPostIDs.insert(postID.lowercased()).inserted else { return false }
        generation &+= 1
        didInvalidate()
        changes.send(context)
        return true
    }
}
