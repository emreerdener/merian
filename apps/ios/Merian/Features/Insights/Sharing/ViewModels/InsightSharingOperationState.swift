@MainActor
final class InsightSharingOperationState {
    struct ShareStateRequest: Equatable {
        let token: UInt64
        let revision: UInt64
    }

    private(set) var revision: UInt64 = 0
    private(set) var requestToken: UInt64 = 0

    func beginShareStateRequest() -> ShareStateRequest {
        requestToken &+= 1
        return ShareStateRequest(token: requestToken, revision: revision)
    }

    func isCurrent(_ request: ShareStateRequest) -> Bool {
        request.token == requestToken && request.revision == revision
    }

    func recordMutation() {
        revision &+= 1
    }

    func invalidate() {
        requestToken &+= 1
        revision &+= 1
    }
}
