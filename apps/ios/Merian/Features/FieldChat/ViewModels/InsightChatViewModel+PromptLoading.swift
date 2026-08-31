import Foundation

extension InsightChatViewModel {
    func refreshPromptSuggestionsAfterStateChange(
        scanId: String,
        force: Bool
    ) {
        guard !isOffline, !isUnavailable(for: scanId) else {
            return
        }
        if isLoadingPrompts && !force { return }
        guard let subjectGeneration = currentSubjectGeneration(scanId: scanId) else {
            return
        }
        let requestGeneration = operations.beginPromptRequest()
        isLoadingPrompts = true

        Task { [weak self] in
            await self?.refreshPromptSuggestions(
                scanId: scanId,
                subjectGeneration: subjectGeneration,
                requestGeneration: requestGeneration
            )
        }
    }

    private func refreshPromptSuggestions(
        scanId: String,
        subjectGeneration: UInt64,
        requestGeneration: UInt64
    ) async {
        defer {
            if operations.isCurrentPromptRequest(requestGeneration) {
                isLoadingPrompts = false
            }
        }
        guard !isOffline,
              isCurrentSubject(
                  scanId: scanId,
                  generation: subjectGeneration
              ) else {
            return
        }

        do {
            let response = try await dependencies.endpoint.suggestPrompts(scanId)
            guard operations.isCurrentPromptRequest(requestGeneration),
                  isCurrentSubject(
                      scanId: scanId,
                      generation: subjectGeneration
                  ) else {
                return
            }
            suggestedPrompts = response.prompts
        } catch {
            guard operations.isCurrentPromptRequest(requestGeneration),
                  isCurrentSubject(
                      scanId: scanId,
                      generation: subjectGeneration
                  ) else {
                return
            }
            suggestedPrompts = []
        }
    }

}
