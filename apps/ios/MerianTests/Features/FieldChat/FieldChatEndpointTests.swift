import Foundation
import Testing

@testable import Merian

@MainActor
struct FieldChatEndpointTests {
    @Test func injectedEndpointOwnsLoadSendFeedbackDeleteAndEffects() async {
        let subjectId = "019facf5-74df-704b-878e-decb347ac1d0"
        let requestId = "019facf5-778f-7602-9b75-31101508b2b7"
        var loadedSubjects: [String] = []
        var sentValues: [(String, String, String)] = []
        var feedbackValues: [(String, String, InsightChatFeedbackRating)] = []
        var deletedSubjects: [String] = []
        var effects: [FieldChatFeedbackEffect] = []

        let endpoint = FieldChatTestSupport.endpoint(
            source: .explorePost,
            load: {
                loadedSubjects.append($0)
                return FieldChatTestSupport.response(subjectId: $0)
            },
            send: {
                sentValues.append(($0, $1, $2))
                return FieldChatTestSupport.response(
                    subjectId: $0,
                    sendsRemainingToday: 19
                )
            },
            delete: {
                deletedSubjects.append($0)
                return FieldChatTestSupport.response(subjectId: $0)
            },
            submitFeedback: { subjectId, messageId, rating, _ in
                feedbackValues.append((subjectId, messageId, rating))
                return InsightChatFeedbackResponse(
                    ok: true,
                    subjectId: subjectId,
                    rating: rating,
                    messageId: messageId
                )
            }
        )
        let dependencies = FieldChatTestSupport.dependencies(
            endpoint: endpoint,
            feedback: { effects.append($0) },
            makeRequestId: { requestId }
        )
        let viewModel = InsightChatViewModel(
            source: .explorePost,
            dependencies: dependencies
        )
        _ = viewModel.activateSubject(scanId: subjectId)

        await viewModel.load(scanId: subjectId)
        viewModel.setDraftText("  What habitat does it prefer?  ", scanId: subjectId)
        await viewModel.sendDraft(scanId: subjectId)
        _ = await viewModel.submitFeedback(
            scanId: subjectId,
            messageId: "message-1",
            rating: .helpful
        )
        await viewModel.deleteCurrentConversation(scanId: subjectId)

        #expect(loadedSubjects == [subjectId])
        #expect(sentValues.count == 1)
        #expect(sentValues.first?.0 == subjectId)
        #expect(sentValues.first?.1 == "What habitat does it prefer?")
        #expect(sentValues.first?.2 == requestId)
        #expect(feedbackValues.first?.0 == subjectId)
        #expect(feedbackValues.first?.1 == "message-1")
        #expect(feedbackValues.first?.2 == .helpful)
        #expect(deletedSubjects == [subjectId])
        #expect(effects.contains(.medium))
        #expect(effects.filter { $0 == .success }.count == 3)
    }

    @Test func staleLoadCannotReplaceNewSubject() async {
        let firstSubject = "019facf5-74df-704b-878e-decb347ac1d0"
        let secondSubject = "019facf5-74df-704b-878e-decb347ac1d1"
        let (firstGate, firstGateContinuation) = AsyncStream<Void>.makeStream()
        var firstLoadStarted = false
        let endpoint = FieldChatTestSupport.endpoint(load: { subjectId in
            if subjectId == firstSubject {
                firstLoadStarted = true
                for await _ in firstGate {
                    break
                }
                return FieldChatTestSupport.response(
                    subjectId: subjectId,
                    sendsRemainingToday: 11
                )
            }
            return FieldChatTestSupport.response(
                subjectId: subjectId,
                sendsRemainingToday: 7
            )
        })
        let viewModel = InsightChatViewModel(
            dependencies: FieldChatTestSupport.dependencies(endpoint: endpoint)
        )
        _ = viewModel.activateSubject(scanId: firstSubject)
        let firstLoad = Task { @MainActor in
            await viewModel.load(scanId: firstSubject)
        }
        while !firstLoadStarted {
            await Task.yield()
        }

        _ = viewModel.activateSubject(scanId: secondSubject)
        await viewModel.load(scanId: secondSubject)
        firstGateContinuation.yield()
        firstGateContinuation.finish()
        await firstLoad.value

        #expect(viewModel.isCurrentSubject(
            scanId: secondSubject,
            generation: viewModel.currentSubjectGeneration(scanId: secondSubject) ?? 0
        ))
        #expect(viewModel.limits.sendsRemainingToday == 7)
    }

    @Test func staleSendCannotMutateReplacementSubject() async {
        let firstSubject = "019facf5-74df-704b-878e-decb347ac1d0"
        let secondSubject = "019facf5-74df-704b-878e-decb347ac1d1"
        let (sendGate, sendGateContinuation) = AsyncStream<Void>.makeStream()
        var sendStarted = false
        var effects: [FieldChatFeedbackEffect] = []
        let endpoint = FieldChatTestSupport.endpoint(send: { subjectId, _, _ in
            sendStarted = true
            for await _ in sendGate {
                break
            }
            return FieldChatTestSupport.response(
                subjectId: subjectId,
                sendsRemainingToday: 3
            )
        })
        let viewModel = InsightChatViewModel(
            dependencies: FieldChatTestSupport.dependencies(
                endpoint: endpoint,
                feedback: { effects.append($0) }
            )
        )
        _ = viewModel.activateSubject(scanId: firstSubject)
        let send = Task { @MainActor in
            await viewModel.send("What did I find?", scanId: firstSubject)
        }
        while !sendStarted {
            await Task.yield()
        }

        _ = viewModel.activateSubject(scanId: secondSubject)
        sendGateContinuation.yield()
        sendGateContinuation.finish()
        await send.value

        #expect(viewModel.pendingUserMessage == nil)
        #expect(viewModel.limits.sendsRemainingToday == 20)
        #expect(effects == [.medium])
    }

    @Test func cancelledSendBecomesRetryableForTheCurrentSubject() async {
        let subjectId = "019facf5-74df-704b-878e-decb347ac1d0"
        let requestId = "019facf5-778f-7602-9b75-31101508b2b7"
        let (sendGate, sendGateContinuation) = AsyncStream<Void>.makeStream()
        var sendStarted = false
        let endpoint = FieldChatTestSupport.endpoint(send: { subjectId, _, _ in
            sendStarted = true
            for await _ in sendGate {
                break
            }
            try Task.checkCancellation()
            return FieldChatTestSupport.response(subjectId: subjectId)
        })
        let viewModel = InsightChatViewModel(
            dependencies: FieldChatTestSupport.dependencies(
                endpoint: endpoint,
                makeRequestId: { requestId }
            )
        )
        _ = viewModel.activateSubject(scanId: subjectId)

        let send = Task { @MainActor in
            await viewModel.send("What did I find?", scanId: subjectId)
        }
        while !sendStarted {
            await Task.yield()
        }

        send.cancel()
        sendGateContinuation.finish()
        await send.value

        #expect(!viewModel.isSending)
        #expect(viewModel.pendingUserMessage?.id == requestId)
        #expect(viewModel.pendingUserMessage?.text == "What did I find?")
        #expect(
            viewModel.pendingUserMessage?.deliveryState ==
                .failed(InsightChatViewModel.interruptedSendMessage)
        )
    }

    @Test func connectivityChangeBeforeScheduledPromptLoadClearsLoadingState() async {
        let subjectId = "019facf5-74df-704b-878e-decb347ac1d0"
        var promptRequestCount = 0
        let endpoint = FieldChatTestSupport.endpoint(suggestPrompts: { subjectId in
            promptRequestCount += 1
            return InsightChatPromptSuggestionsResponse(
                subjectId: subjectId,
                conversationId: nil,
                prompts: []
            )
        })
        let viewModel = InsightChatViewModel(
            dependencies: FieldChatTestSupport.dependencies(endpoint: endpoint)
        )
        _ = viewModel.activateSubject(scanId: subjectId)

        viewModel.refreshPromptSuggestionsAfterStateChange(
            scanId: subjectId,
            force: true
        )
        viewModel.updateConnectivity(isOnline: false)
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(promptRequestCount == 0)
        #expect(!viewModel.isLoadingPrompts)
        #expect(viewModel.suggestedPrompts.isEmpty)
    }

    @Test func latestPromptRefreshWinsWhenResponsesFinishOutOfOrder() async {
        let subjectId = "019facf5-74df-704b-878e-decb347ac1d0"
        var promptContinuations: [
            CheckedContinuation<InsightChatPromptSuggestionsResponse, Never>
        ] = []
        let endpoint = FieldChatTestSupport.endpoint(suggestPrompts: { subjectId in
            await withCheckedContinuation { continuation in
                promptContinuations.append(continuation)
            }
        })
        let viewModel = InsightChatViewModel(
            dependencies: FieldChatTestSupport.dependencies(endpoint: endpoint)
        )
        _ = viewModel.activateSubject(scanId: subjectId)

        viewModel.refreshPromptSuggestionsAfterStateChange(
            scanId: subjectId,
            force: true
        )
        while promptContinuations.count < 1 {
            await Task.yield()
        }
        viewModel.refreshPromptSuggestionsAfterStateChange(
            scanId: subjectId,
            force: true
        )
        while promptContinuations.count < 2 {
            await Task.yield()
        }

        let newestPrompts = [
            InsightChatPromptSuggestion(
                text: "Which current trait matters most?",
                category: "evidence"
            )
        ]
        promptContinuations[1].resume(returning: InsightChatPromptSuggestionsResponse(
            subjectId: subjectId,
            conversationId: nil,
            prompts: newestPrompts
        ))
        while viewModel.suggestedPrompts != newestPrompts {
            await Task.yield()
        }
        promptContinuations[0].resume(returning: InsightChatPromptSuggestionsResponse(
            subjectId: subjectId,
            conversationId: nil,
            prompts: [
                InsightChatPromptSuggestion(
                    text: "This stale prompt must not replace the latest result.",
                    category: "generic"
                )
            ]
        ))
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(viewModel.suggestedPrompts == newestPrompts)
        #expect(!viewModel.isLoadingPrompts)
    }

    @Test func liveEndpointFactoryRetainsAllThreeSourceFamilies() {
        #expect(FieldChatEndpoint.live(source: .insightScan).source == .insightScan)
        #expect(FieldChatEndpoint.live(source: .explorePost).source == .explorePost)
        #expect(FieldChatEndpoint.live(source: .speciesDictionary).source == .speciesDictionary)
    }
}
