import Foundation
import Testing

@testable import Merian

@MainActor
struct FieldChatViewModelStateTests {
    @Test func testDraftTextIsCappedForDuplicateSafeSendPayloads() {
        let viewModel = InsightChatViewModel()
        viewModel.setDraftText(String(repeating: "x", count: 700))

        #expect(viewModel.draftText.count == 600)
        #expect(viewModel.trimmedDraft.count == 600)
    }

    @Test func testFailedPendingMessageBlocksNewSendsUntilRecovered() {
        let viewModel = InsightChatViewModel()
        viewModel.setDraftText("Can I ask another?")
        viewModel.pendingUserMessage = PendingInsightChatMessage(
            id: "pending1",
            text: "Original failed question",
            createdAt: Date(),
            deliveryState: .failed("Chat is unavailable right now.")
        )

        #expect(!viewModel.canSend)

        viewModel.editFailedMessage()

        #expect(viewModel.pendingUserMessage == nil)
        #expect(viewModel.draftText == "Original failed question")

        let conversationId = "019facf5-71fc-70ca-83e4-698b55d1e260"
        let subjectId = "019facf5-74df-704b-878e-decb347ac1d0"
        let interruptedRequestId =
            "019FACF5-778F-7602-9B75-31101508B2B7"
        let interrupted = InsightChatMessage(
            id: "019facf5-7a48-7531-b258-2fa37f0d7aed",
            conversationId: conversationId,
            scanId: subjectId,
            role: .user,
            text: "Which traits support this ID?",
            clientMessageId: interruptedRequestId,
            model: nil,
            isRefusal: false,
            refusalReason: nil,
            createdAt: Date()
        )
        let recovered = InsightChatViewModel.reconcileThread([interrupted])
        #expect(recovered.messages.isEmpty)
        #expect(
            recovered.pendingMessage?.id ==
                interruptedRequestId.lowercased()
        )
        #expect(
            recovered.pendingMessage?.deliveryState ==
                .failed(InsightChatViewModel.interruptedSendMessage)
        )

        let assistant = InsightChatMessage(
            id: "019facf5-7d16-7f2e-bab0-7a31290e2a75",
            conversationId: conversationId,
            scanId: subjectId,
            role: .assistant,
            text: "The saved evidence supports two visible traits.",
            clientMessageId: interruptedRequestId.lowercased(),
            model: "gemini-2.5-flash",
            isRefusal: false,
            refusalReason: nil,
            createdAt: Date()
        )
        let duplicateAssistant = InsightChatMessage(
            id: "019facf5-7fbd-77f7-96a5-4613baf49695",
            conversationId: conversationId,
            scanId: subjectId,
            role: .assistant,
            text: "Duplicate answer",
            clientMessageId: interruptedRequestId,
            model: "gemini-2.5-flash",
            isRefusal: false,
            refusalReason: nil,
            createdAt: Date()
        )
        let orphanAssistant = InsightChatMessage(
            id: "019facf5-824a-7530-8a69-68f31ea9fd5d",
            conversationId: conversationId,
            scanId: subjectId,
            role: .assistant,
            text: "Orphan answer",
            clientMessageId:
                "019facf5-8484-7c80-a7fc-93a2932e0ad8",
            model: "gemini-2.5-flash",
            isRefusal: false,
            refusalReason: nil,
            createdAt: Date()
        )
        let recoveredPastOrphan = InsightChatViewModel.reconcileThread(
            [interrupted, orphanAssistant]
        )
        #expect(recoveredPastOrphan.messages.isEmpty)
        #expect(
            recoveredPastOrphan.pendingMessage?.id ==
                interruptedRequestId.lowercased()
        )
        let completed = InsightChatViewModel.reconcileThread(
            [
                interrupted,
                assistant,
                duplicateAssistant,
                orphanAssistant
            ]
        )
        #expect(
            completed.messages.map(\.id) == [
                interrupted.id,
                assistant.id
            ]
        )
        #expect(completed.pendingMessage == nil)

        viewModel.messages = (0 ..< 29).map { index in
            InsightChatMessage(
                id: "message-\(index)",
                conversationId: conversationId,
                scanId: subjectId,
                role: .assistant,
                text: "Saved answer \(index)",
                clientMessageId: nil,
                model: nil,
                isRefusal: false,
                refusalReason: nil,
                createdAt: Date()
            )
        }
        #expect(!viewModel.canSend)
        viewModel.messages.removeLast()
        viewModel.updateConnectivity(isOnline: true)
        #expect(viewModel.canSend)
    }

    @Test func connectivityProjectionControlsSending() {
        let viewModel = InsightChatViewModel()
        viewModel.draftText = "What did I find?"

        viewModel.updateConnectivity(isOnline: false)
        #expect(viewModel.isOffline)
        #expect(!viewModel.canSend)

        viewModel.updateConnectivity(isOnline: true)
        #expect(!viewModel.isOffline)
        #expect(viewModel.canSend)
    }


    @Test func testForbiddenChatErrorExplainsAccountOwnership() {
        let message = InsightChatViewModel.userFacingMessage(
            for: MerianError.httpError(statusCode: 403, message: #"{"error":"Forbidden"}"#)
        )

        #expect(message == "This scan belongs to another account.")
    }

    @Test func testOnlyTerminalScanErrorsHideChatEntry() {
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 403, message: #"{"error":"Forbidden"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 404, message: #"{"code":"scan_not_ready"}"#)
        ))
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 400, message: #"{"code":"unsupported_scan"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 404, message: #"{"code":"message_not_found"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 404, message: #"{"code":"conversation_not_found"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 429, message: #"{"code":"daily_limit_reached"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.edgeFunctionUnavailable
        ))
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(
                statusCode: 404,
                message: #"{"code":"post_not_available"}"#
            ),
            source: .explorePost
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(
                statusCode: 404,
                message: #"{"code":"message_not_found"}"#
            ),
            source: .explorePost
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(
                statusCode: 404,
                message: #"{"error":"route not found"}"#
            ),
            source: .explorePost
        ))
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(
                statusCode: 404,
                message: #"{"code":"species_not_available"}"#
            ),
            source: .speciesDictionary
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(
                statusCode: 404,
                message: #"{"code":"message_not_found"}"#
            ),
            source: .speciesDictionary
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(
                statusCode: 403,
                message: #"{"error":"Forbidden"}"#
            ),
            source: .speciesDictionary
        ))
        #expect(
            InsightChatViewModel.userFacingMessage(
                for: MerianError.httpError(
                    statusCode: 404,
                    message: #"{"code":"species_not_available"}"#
                ),
                source: .speciesDictionary
            ) == "This species isn't available for Field chat."
        )
        #expect(
            InsightChatViewModel.userFacingMessage(for: MerianError.edgeFunctionUnavailable)
                == "Chat is unavailable right now."
        )
    }

    @Test func testTransientOwnedScanReadinessKeepsChatEntryRetryable() {
        let viewModel = InsightChatViewModel()

        let canPresent = viewModel.applyOwnedScanReadinessStatus(
            "not_found",
            scanId: "scan_1"
        )

        #expect(!canPresent)
        #expect(!viewModel.isUnavailable(for: "scan_1"))
        #expect(viewModel.errorMessage == InsightChatViewModel.stillSyncingMessage)
    }

    @Test func testMarkUnavailableStoresScanScopedChatUnavailableState() {
        let viewModel = InsightChatViewModel()

        viewModel.markUnavailable(scanId: "scan_1")

        #expect(viewModel.isUnavailable(for: "scan_1"))
        #expect(!viewModel.isUnavailable(for: "scan_2"))
        #expect(viewModel.errorMessage == "Field chat isn't available for this scan.")
    }

    @Test func testMarkAvailableClearsRecoveredScanUnavailableState() {
        let viewModel = InsightChatViewModel()
        viewModel.markUnavailable(scanId: "scan_1")

        viewModel.markAvailable(scanId: "scan_1")

        #expect(!viewModel.isUnavailable(for: "scan_1"))
        #expect(viewModel.errorMessage == nil)
    }


    @Test func testFieldChatRejectsStaleSubjectCompletion() {
        let viewModel = InsightChatViewModel()
        let firstScanId = "019fb00a-fb11-7765-93c8-35429f3750a1"
        let secondScanId = "019fb00a-fbd1-7b77-bf88-fd7110114081"
        let firstGeneration = viewModel.activateSubject(scanId: firstScanId)
        viewModel.setDraftText("Private note for the first scan", scanId: firstScanId)

        let secondGeneration = viewModel.activateSubject(scanId: secondScanId)
        let staleResponse = InsightChatResponse(
            subjectId: firstScanId,
            conversationId: nil,
            messages: [],
            limits: InsightChatLimits(
                maxUserMessageCharacters: 600,
                maxMessagesPerConversation: 30,
                dailySendLimit: 20,
                sendsRemainingToday: 19
            )
        )
        let currentResponse = InsightChatResponse(
            subjectId: secondScanId,
            conversationId: nil,
            messages: [],
            limits: InsightChatLimits(
                maxUserMessageCharacters: 600,
                maxMessagesPerConversation: 30,
                dailySendLimit: 20,
                sendsRemainingToday: 18
            )
        )

        #expect(!viewModel.applyIfCurrent(
            staleResponse,
            scanId: firstScanId,
            generation: firstGeneration
        ))
        #expect(viewModel.draftText.isEmpty)
        #expect(viewModel.limits.sendsRemainingToday == 20)
        #expect(viewModel.applyIfCurrent(
            currentResponse,
            scanId: secondScanId,
            generation: secondGeneration
        ))
        #expect(viewModel.limits.sendsRemainingToday == 18)
    }

}

