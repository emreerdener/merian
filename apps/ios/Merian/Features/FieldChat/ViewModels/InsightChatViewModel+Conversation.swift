import Foundation

extension InsightChatViewModel {
    func loadIfNeeded(scanId: String, isProActive: Bool) async {
        guard isProActive else {
            clearLoadedState()
            return
        }

        if isLoadedSubject(scanId) {
            if operations.hasLoadedCurrentSubject {
                refreshPromptSuggestionsAfterStateChange(scanId: scanId, force: false)
            } else if !isLoading {
                guard let generation = currentSubjectGeneration(scanId: scanId) else {
                    return
                }
                await loadCurrentSubject(scanId: scanId, generation: generation)
            }
            return
        }
        let generation = activateSubject(scanId: scanId)
        await loadCurrentSubject(scanId: scanId, generation: generation)
    }

    func load(scanId: String) async {
        guard let generation = currentSubjectGeneration(scanId: scanId) else {
            return
        }
        await loadCurrentSubject(scanId: scanId, generation: generation)
    }

    func loadCurrentSubject(
        scanId: String,
        generation: UInt64
    ) async {
        guard isCurrentSubject(scanId: scanId, generation: generation) else {
            return
        }
        guard !isOffline else {
            errorMessage = "Connect to load saved chat."
            return
        }

        let requestGeneration = operations.beginLoadRequest()
        isLoading = true
        errorMessage = nil
        unavailableScanId = nil
        defer {
            if isCurrentSubject(scanId: scanId, generation: generation),
               operations.isCurrentLoadRequest(requestGeneration) {
                isLoading = false
            }
        }

        do {
            let response = try await dependencies.endpoint.load(scanId)
            guard isCurrentSubject(scanId: scanId, generation: generation),
                  operations.isCurrentLoadRequest(requestGeneration),
                  !Task.isCancelled else {
                return
            }
            guard applyIfCurrent(
                response,
                scanId: scanId,
                generation: generation
            ) else {
                return
            }
            refreshPromptSuggestionsAfterStateChange(scanId: scanId, force: false)
        } catch {
            guard isCurrentSubject(scanId: scanId, generation: generation),
                  operations.isCurrentLoadRequest(requestGeneration),
                  !Task.isCancelled else {
                return
            }
            handle(error, scanId: scanId)
        }
    }

    func sendDraft(scanId: String) async {
        await send(trimmedDraft, scanId: scanId)
    }

    func send(_ text: String, scanId: String) async {
        await send(
            text,
            scanId: scanId,
            clientMessageId: dependencies.makeRequestId()
        )
    }

    private func beginSending(_ text: String, clientMessageId: String) {
        performFeedback(.medium)
        isSending = true
        errorMessage = nil
        pendingUserMessage = PendingInsightChatMessage(
            id: clientMessageId,
            text: text,
            createdAt: dependencies.now()
        )
    }

    private func send(
        _ text: String,
        scanId: String,
        clientMessageId: String
    ) async {
        guard let subjectGeneration = currentSubjectGeneration(scanId: scanId) else {
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let requestUuid = UUID(uuidString: clientMessageId),
              !isSending else { return }
        let clientMessageId = requestUuid.uuidString.lowercased()
        let isRetry = pendingUserMessage.map { pendingMessage in
            guard case .failed = pendingMessage.deliveryState,
                  let pendingRequestUuid = UUID(uuidString: pendingMessage.id)
            else {
                return false
            }
            return pendingRequestUuid.uuidString.lowercased() ==
                clientMessageId
        } ?? false
        guard isRetry || pendingUserMessage == nil else { return }
        guard !isOffline else {
            performFeedback(.error)
            errorMessage = "Connect to send."
            return
        }
        guard trimmed.count <= limits.maxUserMessageCharacters else {
            performFeedback(.error)
            errorMessage = "Keep questions under \(limits.maxUserMessageCharacters) characters."
            return
        }
        let requiredMessageSlots = isRetry ? 1 : 2
        guard max(messages.count, persistedMessageCount) +
                requiredMessageSlots <= limits.maxMessagesPerConversation
        else {
            performFeedback(.error)
            errorMessage = "This Field chat has reached its message limit."
            return
        }
        guard isRetry || limits.sendsRemainingToday > 0 else {
            performFeedback(.error)
            errorMessage = "Daily Field chat limit reached."
            return
        }

        beginSending(trimmed, clientMessageId: clientMessageId)
        if trimmed == draftText.trimmingCharacters(in: .whitespacesAndNewlines) {
            draftText = ""
        }
        defer {
            if isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ) {
                isSending = false
                if pendingUserMessage?.id == clientMessageId,
                   pendingUserMessage?.isSending == true {
                    pendingUserMessage?.deliveryState = .failed(Self.interruptedSendMessage)
                }
            }
        }

        do {
            let response = try await dependencies.endpoint.send(
                scanId,
                trimmed,
                clientMessageId
            )
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return
            }
            guard applyIfCurrent(
                response,
                scanId: scanId,
                generation: subjectGeneration
            ) else {
                return
            }
            refreshPromptSuggestionsAfterStateChange(scanId: scanId, force: true)
            performFeedback(.success)
        } catch {
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return
            }
            handle(error, scanId: scanId, playHaptic: true)
            pendingUserMessage = PendingInsightChatMessage(
                id: clientMessageId,
                text: trimmed,
                createdAt: dependencies.now(),
                deliveryState: .failed(Self.userFacingMessage(for: error, source: source))
            )
        }
    }

    func retryFailedMessage(scanId: String) async {
        guard let pendingUserMessage,
              case .failed = pendingUserMessage.deliveryState else { return }
        await send(
            pendingUserMessage.text,
            scanId: scanId,
            clientMessageId: pendingUserMessage.id
        )
    }

    func editFailedMessage(scanId: String? = nil) {
        if let scanId,
           currentSubjectGeneration(scanId: scanId) == nil {
            return
        }
        guard let pendingUserMessage,
              case .failed = pendingUserMessage.deliveryState else { return }
        draftText = pendingUserMessage.text
        self.pendingUserMessage = nil
        errorMessage = nil
        performFeedback(.selection)
    }

    func deleteCurrentConversation(scanId: String) async {
        await deleteConversation(scanId: scanId)
    }

    func deleteConversation(scanId: String) async {
        guard let subjectGeneration = currentSubjectGeneration(scanId: scanId),
              !isDeleting else {
            return
        }
        guard !isOffline else {
            performFeedback(.error)
            errorMessage = "Connect to delete chat."
            return
        }

        isDeleting = true
        errorMessage = nil
        defer {
            if isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ) {
                isDeleting = false
            }
        }

        do {
            let response = try await dependencies.endpoint.delete(scanId)
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return
            }
            guard applyIfCurrent(
                response,
                scanId: scanId,
                generation: subjectGeneration
            ) else {
                return
            }
            performFeedback(.success)
        } catch {
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return
            }
            handle(error, scanId: scanId, playHaptic: true)
        }
    }

    func setDraftText(_ newValue: String, scanId: String? = nil) {
        if let scanId,
           currentSubjectGeneration(scanId: scanId) == nil {
            return
        }
        draftText = String(newValue.prefix(limits.maxUserMessageCharacters))
    }

}
