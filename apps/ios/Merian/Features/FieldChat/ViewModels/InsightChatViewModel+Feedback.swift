import Foundation

extension InsightChatViewModel {
    func submitFeedback(
        scanId: String,
        messageId: String,
        rating: InsightChatFeedbackRating,
        note: String? = nil
    ) async -> Bool {
        guard let subjectGeneration = currentSubjectGeneration(scanId: scanId),
              !isSubmittingFeedback else {
            return false
        }
        guard !isOffline else {
            performFeedback(.error)
            errorMessage = "Connect to send feedback."
            return false
        }

        isSubmittingFeedback = true
        defer {
            if isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ) {
                isSubmittingFeedback = false
            }
        }

        do {
            let response = try await dependencies.endpoint.submitFeedback(
                scanId,
                messageId,
                rating,
                note
            )
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return false
            }
            submittedFeedback[response.messageId] = response.rating
            performFeedback(.success)
            return true
        } catch {
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return false
            }
            handle(error, scanId: scanId, playHaptic: true)
            return false
        }
    }

    func submitFeatureFeedback(
        scanId: String,
        sentiment: InsightChatFeatureFeedbackSentiment?,
        note: String
    ) async -> Bool {
        guard let subjectGeneration = currentSubjectGeneration(scanId: scanId),
              !isSubmittingFeatureFeedback else {
            return false
        }
        guard source == .insightScan else { return false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentiment != nil || !trimmedNote.isEmpty else { return false }
        guard !isOffline else {
            performFeedback(.error)
            errorMessage = "Connect to send feedback."
            return false
        }

        isSubmittingFeatureFeedback = true
        defer {
            if isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ) {
                isSubmittingFeatureFeedback = false
            }
        }

        do {
            guard let submitFeatureFeedback = dependencies.endpoint.submitFeatureFeedback else {
                return false
            }
            _ = try await submitFeatureFeedback(
                scanId,
                sentiment,
                trimmedNote.isEmpty ? nil : trimmedNote
            )
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return false
            }
            performFeedback(.success)
            return true
        } catch {
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return false
            }
            handle(error, scanId: scanId, playHaptic: true)
            return false
        }
    }

    func summarizeForFieldNotes(scanId: String) async -> Bool {
        guard let subjectGeneration = currentSubjectGeneration(scanId: scanId),
              !isSummarizingNotes else {
            return false
        }
        guard source == .insightScan else { return false }
        guard !isOffline else {
            performFeedback(.error)
            errorMessage = "Connect to summarize chat."
            return false
        }
        guard !messages.isEmpty else { return false }

        isSummarizingNotes = true
        defer {
            if isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ) {
                isSummarizingNotes = false
            }
        }

        do {
            guard let summarizeNotes = dependencies.endpoint.summarizeNotes else {
                return false
            }
            let response = try await summarizeNotes(scanId)
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return false
            }
            notesSummaryDraft = response.summaryText
            performFeedback(.success)
            return true
        } catch {
            guard isCurrentSubject(
                scanId: scanId,
                generation: subjectGeneration
            ), !Task.isCancelled else {
                return false
            }
            handle(error, scanId: scanId, playHaptic: true)
            return false
        }
    }

}
