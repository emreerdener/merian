import Testing

@testable import Merian

@MainActor
struct FieldChatWelcomePromptsTests {
    private let fallback = ["Features?", "Habitat?", "Lookalikes?"]
    private let generated = ["How does it flower?", "What pollinates it?", "How does it spread?"]

    @Test func waitsForGeneratedQuestionsThenKeepsTheRevealedSet() {
        let model = FieldChatWelcomePromptsModel()
        model.update(candidates: fallback, isLoading: true, isVisible: true)
        #expect(model.displayedPrompts == nil)
        model.update(candidates: generated, isLoading: false, isVisible: true)
        #expect(model.displayedPrompts == generated)
        model.update(candidates: ["A later question?"], isLoading: false, isVisible: true)
        #expect(model.displayedPrompts == generated)
    }

    @Test func completedFailureUsesFallbackImmediately() {
        let model = FieldChatWelcomePromptsModel()
        model.update(candidates: fallback, isLoading: true, isVisible: true)
        model.update(candidates: fallback, isLoading: false, isVisible: true)
        #expect(model.displayedPrompts == fallback)
    }

    @Test func timeoutRevealsFallbackAndLateResultsCannotReplaceIt() async {
        let model = FieldChatWelcomePromptsModel()
        model.update(candidates: fallback, isLoading: true, isVisible: true)
        await model.waitForFallback(wait: {})
        #expect(model.displayedPrompts == fallback)
        model.update(candidates: generated, isLoading: false, isVisible: true)
        #expect(model.displayedPrompts == fallback)
    }

    @Test func generatedQuestionsWinWhenTheyArriveBeforeTheDeadline() async {
        let model = FieldChatWelcomePromptsModel()
        model.update(candidates: fallback, isLoading: true, isVisible: true)
        await model.waitForFallback {
            model.update(candidates: generated, isLoading: false, isVisible: true)
        }
        #expect(model.displayedPrompts == generated)
    }

    @Test func hiddenWelcomeCanAcceptNewResultsUntilQuestionsAreActuallyShown() async {
        let model = FieldChatWelcomePromptsModel()
        model.update(candidates: fallback, isLoading: true, isVisible: false)
        await model.waitForFallback(wait: {})
        #expect(model.displayedPrompts == nil)
        model.update(candidates: generated, isLoading: false, isVisible: false)
        #expect(model.displayedPrompts == nil)
        model.update(candidates: generated, isLoading: false, isVisible: true)
        #expect(model.displayedPrompts == generated)
        model.update(candidates: fallback, isLoading: false, isVisible: false)
        model.update(candidates: fallback, isLoading: false, isVisible: true)
        #expect(model.displayedPrompts == generated)
    }

    @Test func emptyCandidatesDoNotCommitAnEmptyWelcome() async {
        let model = FieldChatWelcomePromptsModel()
        model.update(candidates: [], isLoading: true, isVisible: true)
        await model.waitForFallback(wait: {})
        #expect(model.displayedPrompts == nil)
        model.update(candidates: fallback, isLoading: true, isVisible: true)
        #expect(model.displayedPrompts == fallback)
    }

    @Test func readyCachedQuestionsDoNotWaitAndRemainLimitedToThree() async {
        let model = FieldChatWelcomePromptsModel()
        model.update(candidates: generated + ["Fourth?"], isLoading: false, isVisible: true)
        var waited = false
        await model.waitForFallback { waited = true }
        #expect(!waited)
        #expect(model.displayedPrompts == generated)
    }

    @Test func dismissedSubjectCannotRevealAfterItsCancelledTimerReturns() async {
        let old = FieldChatWelcomePromptsModel()
        old.update(candidates: fallback, isLoading: true, isVisible: true)
        var continuation: CheckedContinuation<Void, Never>?
        let timer = Task {
            await old.waitForFallback {
                await withCheckedContinuation { continuation = $0 }
            }
        }
        while continuation == nil { await Task.yield() }
        timer.cancel()
        let replacement = FieldChatWelcomePromptsModel()
        replacement.update(candidates: generated, isLoading: false, isVisible: true)
        continuation?.resume()
        await timer.value
        #expect(old.displayedPrompts == nil)
        #expect(replacement.displayedPrompts == generated)
    }
}
