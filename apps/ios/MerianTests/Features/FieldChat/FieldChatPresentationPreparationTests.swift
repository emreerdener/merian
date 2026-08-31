import Foundation
import Testing

@testable import Merian

@MainActor
struct FieldChatPresentationPreparationTests {
    @Test func testConcurrentPresentationRequestsSharePreparationResult() async {
        let viewModel = InsightChatViewModel(source: .explorePost)
        let (preparationGate, gateContinuation) = AsyncStream<Void>.makeStream()
        let (secondRequestStarted, secondRequestContinuation) = AsyncStream<Void>.makeStream()
        var preparationCount = 0
        let preparation: @MainActor () async -> Bool = {
            preparationCount += 1
            for await _ in preparationGate {
                break
            }
            return true
        }

        let firstRequest = Task { @MainActor in
            await viewModel.prepareForPresentation(
                scanId: "post_1",
                using: preparation
            )
        }
        while preparationCount == 0 {
            await Task.yield()
        }

        let secondRequest = Task { @MainActor in
            secondRequestContinuation.yield()
            return await viewModel.prepareForPresentation(
                scanId: "post_1",
                using: preparation
            )
        }
        for await _ in secondRequestStarted {
            break
        }
        secondRequestContinuation.finish()
        gateContinuation.yield()
        gateContinuation.finish()

        let firstResult = await firstRequest.value
        let secondResult = await secondRequest.value

        #expect(firstResult)
        #expect(secondResult)
        #expect(preparationCount == 1)
        #expect(!viewModel.isCheckingAvailability)
    }

    @Test func testPresentationPreparationPublishesLoadingStateBeforeNetworkCompletes() async {
        let viewModel = InsightChatViewModel()
        let (preparationGate, gateContinuation) = AsyncStream<Void>.makeStream()
        var preparationStarted = false

        let request = Task { @MainActor in
            await viewModel.prepareForPresentation(scanId: "scan_1") {
                preparationStarted = true
                for await _ in preparationGate {
                    break
                }
                return true
            }
        }
        while !preparationStarted {
            await Task.yield()
        }

        #expect(viewModel.isCheckingAvailability)

        gateContinuation.yield()
        gateContinuation.finish()
        #expect(await request.value)
        #expect(!viewModel.isCheckingAvailability)
    }


    @Test func testFieldChatReplacesPreparationForChangedSubject() async {
        let viewModel = InsightChatViewModel(source: .explorePost)
        let (firstGate, firstGateContinuation) = AsyncStream<Void>.makeStream()
        var firstPreparationStarted = false
        let firstRequest = Task { @MainActor in
            await viewModel.prepareForPresentation(scanId: "post_1") {
                firstPreparationStarted = true
                for await _ in firstGate {
                    break
                }
                return true
            }
        }
        while !firstPreparationStarted {
            await Task.yield()
        }

        let secondResult = await viewModel.prepareForPresentation(scanId: "post_2") {
            true
        }
        firstGateContinuation.yield()
        firstGateContinuation.finish()
        let firstResult = await firstRequest.value

        #expect(!firstResult)
        #expect(secondResult)
        #expect(!viewModel.isCheckingAvailability)
    }

    @Test func testActivatingReplacementSubjectInvalidatesReadinessCompletion() async {
        let firstSubject = "019facf5-74df-704b-878e-decb347ac1d0"
        let secondSubject = "019facf5-74df-704b-878e-decb347ac1d1"
        var readinessContinuation: CheckedContinuation<String, Never>?
        let endpoint = FieldChatTestSupport.endpoint()
        let dependencies = FieldChatTestSupport.dependencies(
            endpoint: endpoint,
            checkOwnedScanStatus: { _ in
                await withCheckedContinuation { continuation in
                    readinessContinuation = continuation
                }
            }
        )
        let viewModel = InsightChatViewModel(dependencies: dependencies)
        let readiness = Task { @MainActor in
            await viewModel.prepareForPresentation(scanId: firstSubject)
        }
        while readinessContinuation == nil {
            await Task.yield()
        }

        _ = viewModel.activateSubject(scanId: secondSubject)
        #expect(!viewModel.isCheckingAvailability)
        readinessContinuation?.resume(returning: "processing")
        let canPresent = await readiness.value

        #expect(!canPresent)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoadedSubject(secondSubject))
        #expect(!viewModel.isLoadedSubject(firstSubject))
    }

    @Test func testReactivatingCurrentSubjectInvalidatesDifferentPreparation() async {
        let currentSubject = "019facf5-74df-704b-878e-decb347ac1d0"
        let preparingSubject = "019facf5-74df-704b-878e-decb347ac1d1"
        var preparationContinuation: CheckedContinuation<Bool, Never>?
        let viewModel = InsightChatViewModel(source: .explorePost)
        _ = viewModel.activateSubject(scanId: currentSubject)
        let preparation = Task { @MainActor in
            await viewModel.prepareForPresentation(scanId: preparingSubject) {
                await withCheckedContinuation { continuation in
                    preparationContinuation = continuation
                }
            }
        }
        while preparationContinuation == nil {
            await Task.yield()
        }

        _ = viewModel.activateSubject(scanId: currentSubject)
        #expect(!viewModel.isCheckingAvailability)
        preparationContinuation?.resume(returning: true)
        let canPresent = await preparation.value

        #expect(!canPresent)
        #expect(viewModel.isLoadedSubject(currentSubject))
        #expect(!viewModel.isLoadedSubject(preparingSubject))
    }

    @Test func testClearingStateInvalidatesPresentationPreparation() async {
        let subjectId = "019facf5-74df-704b-878e-decb347ac1d0"
        var preparationContinuation: CheckedContinuation<Bool, Never>?
        let viewModel = InsightChatViewModel(source: .explorePost)
        let preparation = Task { @MainActor in
            await viewModel.prepareForPresentation(scanId: subjectId) {
                await withCheckedContinuation { continuation in
                    preparationContinuation = continuation
                }
            }
        }
        while preparationContinuation == nil {
            await Task.yield()
        }

        viewModel.clearLoadedState()
        #expect(!viewModel.isCheckingAvailability)
        preparationContinuation?.resume(returning: true)
        let canPresent = await preparation.value

        #expect(!canPresent)
        #expect(!viewModel.isLoadedSubject(subjectId))
        #expect(viewModel.errorMessage == nil)
    }

    @Test func testCancelledPresentationWaiterCannotCommitSuccessfulResult() async {
        let subjectId = "019facf5-74df-704b-878e-decb347ac1d0"
        var preparationContinuation: CheckedContinuation<Bool, Never>?
        let viewModel = InsightChatViewModel(source: .explorePost)
        let preparation = Task { @MainActor in
            await viewModel.prepareForPresentation(scanId: subjectId) {
                await withCheckedContinuation { continuation in
                    preparationContinuation = continuation
                }
            }
        }
        while preparationContinuation == nil {
            await Task.yield()
        }

        preparation.cancel()
        preparationContinuation?.resume(returning: true)
        let canPresent = await preparation.value

        #expect(!canPresent)
        #expect(!viewModel.isCheckingAvailability)
    }
}
