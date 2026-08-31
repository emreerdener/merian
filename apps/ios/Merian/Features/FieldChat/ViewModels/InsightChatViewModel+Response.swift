import Foundation

extension InsightChatViewModel {
    @discardableResult
    func applyIfCurrent(
        _ response: InsightChatResponse,
        scanId: String,
        generation: UInt64
    ) -> Bool {
        guard isCurrentSubject(scanId: scanId, generation: generation),
              response.subjectId?
                .caseInsensitiveCompare(scanId) == .orderedSame else {
            return false
        }
        apply(response)
        return true
    }

    private func apply(_ response: InsightChatResponse) {
        let reconciled = Self.reconcileThread(response.messages)
        conversationId = response.conversationId
        updatePersistedMessageCount(response.messages.count)
        messages = reconciled.messages
        pendingUserMessage = reconciled.pendingMessage
        limits = response.limits
        unavailableScanId = nil
        errorMessage = nil
        operations.markCurrentSubjectLoaded()
    }

    static func reconcileThread(
        _ sourceMessages: [InsightChatMessage]
    ) -> (
        messages: [InsightChatMessage],
        pendingMessage: PendingInsightChatMessage?
    ) {
        func canonicalRequestId(_ value: String?) -> String? {
            guard let value, let uuid = UUID(uuidString: value) else {
                return nil
            }
            return uuid.uuidString.lowercased()
        }

        let userRequestIds = Set(
            sourceMessages.compactMap { message in
                message.role == .user
                    ? canonicalRequestId(message.clientMessageId)
                    : nil
            }
        )
        let assistantRequestIds = Set(
            sourceMessages.compactMap { message in
                message.role == .assistant
                    ? canonicalRequestId(message.clientMessageId)
                    : nil
            }
        )
        var seenAssistantRequestIds = Set<String>()
        var visibleMessages: [InsightChatMessage] = []
        var unansweredUserMessages: [(
            message: InsightChatMessage,
            requestId: String
        )] = []

        for (index, message) in sourceMessages.enumerated() {
            let requestId = canonicalRequestId(message.clientMessageId)
            switch message.role {
            case .assistant:
                if let requestId {
                    guard userRequestIds.contains(requestId),
                          seenAssistantRequestIds.insert(requestId).inserted
                    else {
                        continue
                    }
                }
                visibleMessages.append(message)
            case .user:
                let hasBoundAssistant = requestId.map {
                    assistantRequestIds.contains($0)
                } ?? false
                let nextMessage = sourceMessages.indices.contains(index + 1)
                    ? sourceMessages[index + 1]
                    : nil
                let hasAdjacentLegacyAssistant =
                    nextMessage?.role == .assistant &&
                    nextMessage?.clientMessageId == nil
                if requestId == nil ||
                    hasBoundAssistant ||
                    hasAdjacentLegacyAssistant {
                    visibleMessages.append(message)
                } else if let requestId {
                    unansweredUserMessages.append((message, requestId))
                }
            }
        }

        guard let unansweredUserMessage = unansweredUserMessages.last else {
            return (visibleMessages, nil)
        }
        return (
            visibleMessages,
            PendingInsightChatMessage(
                id: unansweredUserMessage.requestId,
                text: unansweredUserMessage.message.text,
                createdAt: unansweredUserMessage.message.createdAt,
                deliveryState: .failed(interruptedSendMessage)
            )
        )
    }

}
