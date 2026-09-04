import Foundation
import Observation

@MainActor
@Observable
final class InsightChatViewModel {
    static let maxDraftCharacters = 600
    static let stillSyncingMessage =
        "This observation is still syncing. Please try Field chat again in a moment."
    static let interruptedSendMessage =
        "This question did not finish. Tap Retry to continue."
    private static let initialLimits = InsightChatLimits(
        maxUserMessageCharacters: 600,
        maxMessagesPerConversation: 30,
        dailySendLimit: 20,
        sendsRemainingToday: 20
    )

    var messages: [InsightChatMessage] = []
    var pendingUserMessage: PendingInsightChatMessage?
    var draftText = ""
    var errorMessage: String?
    var isLoading = false
    var isSending = false
    var isDeleting = false
    var isSubmittingFeedback = false
    var isSubmittingFeatureFeedback = false
    var isSummarizingNotes = false
    var isLoadingPrompts = false
    var isCheckingAvailability = false
    private(set) var isOffline = false
    var conversationId: String?
    var unavailableScanId: String?
    private(set) var persistedMessageCount = 0
    var suggestedPrompts: [InsightChatPromptSuggestion] = []
    var submittedFeedback: [String: InsightChatFeedbackRating] = [:]
    var notesSummaryDraft: String?
    var limits = InsightChatViewModel.initialLimits

    @ObservationIgnored let source: FieldChatSource
    @ObservationIgnored let dependencies: FieldChatDependencies
    @ObservationIgnored let operations = FieldChatOperationState()

    init(
        source: FieldChatSource = .insightScan,
        dependencies: FieldChatDependencies? = nil
    ) {
        self.source = source
        self.dependencies = dependencies ?? .live(source: source)
    }

    func performFeedback(_ effect: FieldChatFeedbackEffect) {
        dependencies.feedback(effect)
    }

    func copyText(_ text: String) {
        dependencies.copyText(text)
    }

    func trackAction(_ telemetry: FieldChatActionTelemetry) {
        dependencies.trackAction(source, telemetry)
    }

    func updatePersistedMessageCount(_ count: Int) {
        persistedMessageCount = count
    }

    func updateConnectivity(isOnline: Bool) {
        isOffline = !isOnline
    }

    var trimmedDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var draftCharactersRemaining: Int {
        max(0, limits.maxUserMessageCharacters - draftText.count)
    }

    var canSend: Bool {
        !isOffline
            && !isSending
            && pendingUserMessage == nil
            && !trimmedDraft.isEmpty
            && trimmedDraft.count <= limits.maxUserMessageCharacters
            && max(messages.count, persistedMessageCount) + 2 <=
                limits.maxMessagesPerConversation
            && limits.sendsRemainingToday > 0
    }

    func isUnavailable(for scanId: String?) -> Bool {
        guard let scanId else { return true }
        return unavailableScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame
    }

    @discardableResult
    func activateSubject(scanId: String) -> UInt64 {
        let activation = operations.activateSubject(scanId)
        if activation.changed {
            resetSubjectState()
        }
        isCheckingAvailability = operations.isPreparing
        return activation.generation
    }

    func isCurrentSubject(scanId: String, generation: UInt64) -> Bool {
        operations.isCurrentSubject(id: scanId, generation: generation)
    }

    func currentSubjectGeneration(scanId: String) -> UInt64? {
        operations.currentSubjectGeneration(for: scanId)
    }

    func isLoadedSubject(_ scanId: String) -> Bool {
        operations.currentSubjectGeneration(for: scanId) != nil
    }

    private func resetSubjectState() {
        messages = []
        persistedMessageCount = 0
        pendingUserMessage = nil
        draftText = ""
        conversationId = nil
        errorMessage = nil
        unavailableScanId = nil
        submittedFeedback = [:]
        notesSummaryDraft = nil
        suggestedPrompts = []
        limits = Self.initialLimits
        isLoading = false
        isSending = false
        isDeleting = false
        isSubmittingFeedback = false
        isSubmittingFeatureFeedback = false
        isSummarizingNotes = false
        isLoadingPrompts = false
    }

    func clearLoadedState() {
        operations.clearSubject()
        resetSubjectState()
        isCheckingAvailability = false
    }

    func handle(_ error: Error, scanId: String, playHaptic: Bool = false) {
        if playHaptic {
            performFeedback(.error)
        }
        let shouldMarkUnavailable = Self.isDeterministicallyUnavailable(
            error,
            source: source
        )
        if shouldMarkUnavailable {
            errorMessage = source.unavailableMessage
        } else {
            errorMessage = Self.userFacingMessage(for: error, source: source)
        }
        if shouldMarkUnavailable {
            unavailableScanId = scanId
        }
    }

    static func isDeterministicallyUnavailable(
        _ error: Error,
        source: FieldChatSource = .insightScan
    ) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error else {
            return false
        }

        let code = EdgeFunctionErrorPolicy.stableCode(from: error)
        if source == .speciesDictionary {
            return statusCode == 404 && code == "species_not_available"
        }
        if statusCode == 403 { return true }
        if source == .explorePost {
            return statusCode == 404 && code == "post_not_available"
        }
        return statusCode == 400 && code == "unsupported_scan"
    }

    static func userFacingMessage(
        for error: Error,
        source: FieldChatSource = .insightScan
    ) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
                return "Connect to use chat."
            default:
                return "Chat is unavailable right now."
            }
        }

        if case let MerianError.httpError(statusCode, _) = error {
            switch statusCode {
            case 402:
                return "Naturebook Pro is required."
            case 403:
                return source == .insightScan
                    ? "This scan belongs to another account."
                    : source.unavailableMessage
            case 429:
                return "Chat limit reached for today."
            case 404:
                return source == .insightScan
                    ? "This scan is not ready for chat yet."
                    : source.unavailableMessage
            default:
                return "Chat is unavailable right now."
            }
        }

        return "Chat is unavailable right now."
    }

}
