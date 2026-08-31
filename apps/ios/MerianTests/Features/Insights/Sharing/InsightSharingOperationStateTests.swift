import Testing

@testable import Merian

@MainActor
struct InsightSharingOperationStateTests {
    @Test func mutationInvalidatesRefreshWithoutAdvancingRequestToken() {
        let operations = InsightSharingOperationState()
        let request = operations.beginShareStateRequest()

        #expect(operations.isCurrent(request))
        operations.recordMutation()

        #expect(!operations.isCurrent(request))
        #expect(operations.requestToken == request.token)
        #expect(operations.revision == request.revision + 1)
    }

    @Test func replacementAndResetInvalidateOlderRefreshes() {
        let operations = InsightSharingOperationState()
        let first = operations.beginShareStateRequest()
        let second = operations.beginShareStateRequest()

        #expect(!operations.isCurrent(first))
        #expect(operations.isCurrent(second))

        operations.invalidate()

        #expect(!operations.isCurrent(second))
        #expect(operations.requestToken == second.token + 1)
        #expect(operations.revision == second.revision + 1)
    }
}
