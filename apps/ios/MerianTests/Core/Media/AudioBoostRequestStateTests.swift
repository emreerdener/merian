import Foundation
import Testing

@testable import Merian

@Suite("Audio boost request ownership")
struct AudioBoostRequestStateTests {
    @Test("Stale completion cannot clear the current request")
    func staleCompletionCannotClearCurrentRequest() {
        var state = AudioBoostRequestState()
        let firstRequest = state.begin(
            isBoostEnabled: true,
            shouldShowReverting: false,
            showsPreparationStatus: true
        )
        let currentRequest = state.begin(
            isBoostEnabled: true,
            shouldShowReverting: false,
            showsPreparationStatus: true
        )

        let staleRequestFinished = state.finish(firstRequest)
        #expect(!staleRequestFinished)
        #expect(state.owns(currentRequest))
        #expect(state.isPreparing)
        #expect(state.showsPreparationStatus)

        let currentRequestFinished = state.finish(currentRequest)
        #expect(currentRequestFinished)
        #expect(!state.isPreparing)
        #expect(!state.showsPreparationStatus)
    }

    @Test("On-off-on overlap retains the newest preparation")
    func onOffOnOverlapRetainsNewestPreparation() {
        var state = AudioBoostRequestState()
        let firstOn = state.begin(
            isBoostEnabled: true,
            shouldShowReverting: false,
            showsPreparationStatus: true
        )
        let off = state.begin(
            isBoostEnabled: false,
            shouldShowReverting: true,
            showsPreparationStatus: false
        )
        let secondOn = state.begin(
            isBoostEnabled: true,
            shouldShowReverting: false,
            showsPreparationStatus: true
        )

        let firstOnFinished = state.finish(firstOn)
        let offFinished = state.finish(off)
        #expect(!firstOnFinished)
        #expect(!offFinished)
        #expect(state.owns(secondOn))
        #expect(state.isPreparing)
        #expect(!state.isReverting)
    }

    @Test("Invalidation rejects every outstanding completion")
    func invalidationRejectsOutstandingCompletion() {
        var state = AudioBoostRequestState()
        let request = state.begin(
            isBoostEnabled: true,
            shouldShowReverting: false,
            showsPreparationStatus: true
        )

        state.invalidate()

        let invalidatedRequestFinished = state.finish(request)
        #expect(!invalidatedRequestFinished)
        #expect(state.activeRequestID == nil)
        #expect(!state.isPreparing)
    }
}
