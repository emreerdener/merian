import Foundation
import Network
import Observation

struct PendingInsightChatMessage: Identifiable, Equatable {
    enum DeliveryState: Equatable {
        case sending
        case failed(String)
    }

    let id: String
    let text: String
    let createdAt: Date
    var deliveryState: DeliveryState = .sending

    var isSending: Bool {
        if case .sending = deliveryState { return true }
        return false
    }
}

@MainActor
@Observable
final class InsightChatViewModel {
    static let maxDraftCharacters = 600

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
    var isOffline = false
    var conversationId: String?
    var unavailableScanId: String?
    var suggestedPrompts: [InsightChatPromptSuggestion] = []
    var submittedFeedback: [String: InsightChatFeedbackRating] = [:]
    var notesSummaryDraft: String?
    var limits = InsightChatLimits(
        maxUserMessageCharacters: 600,
        maxMessagesPerConversation: 30,
        dailySendLimit: 20,
        sendsRemainingToday: 20
    )

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let monitorQueue = DispatchQueue(label: "com.merian.insight-chat.network")
    @ObservationIgnored private var loadedScanId: String?
    @ObservationIgnored private var promptRequestGeneration = 0

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
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
            && messages.count < limits.maxMessagesPerConversation
            && limits.sendsRemainingToday > 0
    }

    func isUnavailable(for scanId: String?) -> Bool {
        guard let scanId else { return true }
        return unavailableScanId == scanId
    }

    func prepareForPresentation(scanId: String) async -> Bool {
        guard !isUnavailable(for: scanId) else {
            errorMessage = "Field chat isn't available for this scan."
            return false
        }
        guard !isOffline else {
            errorMessage = "Connect to use Field chat."
            return false
        }
        guard !isCheckingAvailability else { return false }

        isCheckingAvailability = true
        defer { isCheckingAvailability = false }

        do {
            let status = try await MerianNetworkClient.shared.checkScanStatus(scanId: scanId)
            guard status == "found" else {
                markUnavailable(
                    scanId: scanId,
                    message: "Field chat isn't available for this scan."
                )
                return false
            }
            errorMessage = nil
            unavailableScanId = nil
            return true
        } catch {
            handle(error, scanId: scanId)
            return false
        }
    }

    func markUnavailable(scanId: String, message: String? = nil) {
        unavailableScanId = scanId
        errorMessage = message ?? "Field chat isn't available for this scan."
    }

    func loadIfNeeded(scanId: String, isProActive: Bool) async {
        guard isProActive else {
            clearLoadedState()
            return
        }

        guard loadedScanId != scanId else {
            refreshPromptSuggestionsAfterStateChange(scanId: scanId, force: false)
            return
        }
        loadedScanId = scanId
        await load(scanId: scanId)
    }

    func load(scanId: String) async {
        guard !isOffline else {
            errorMessage = "Connect to load saved chat."
            return
        }

        isLoading = true
        errorMessage = nil
        unavailableScanId = nil
        defer { isLoading = false }

        do {
            apply(try await MerianNetworkClient.shared.loadInsightChat(scanId: scanId))
            refreshPromptSuggestionsAfterStateChange(scanId: scanId, force: false)
        } catch {
            loadedScanId = nil
            handle(error, scanId: scanId)
        }
    }

    func sendDraft(scanId: String) async {
        await send(trimmedDraft, scanId: scanId)
    }

    func send(_ text: String, scanId: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isOffline else {
            HapticManager.shared.triggerErrorThump()
            errorMessage = "Connect to send."
            return
        }
        guard trimmed.count <= limits.maxUserMessageCharacters else {
            HapticManager.shared.triggerErrorThump()
            errorMessage = "Keep questions under \(limits.maxUserMessageCharacters) characters."
            return
        }

        let clientMessageId = UUID().uuidString
        beginSending(trimmed, clientMessageId: clientMessageId)
        if trimmed == draftText.trimmingCharacters(in: .whitespacesAndNewlines) {
            draftText = ""
        }

        do {
            apply(try await MerianNetworkClient.shared.sendInsightChatMessage(
                scanId: scanId,
                messageText: trimmed,
                clientMessageId: clientMessageId
            ))
            isSending = false
            refreshPromptSuggestionsAfterStateChange(scanId: scanId, force: true)
            HapticManager.shared.triggerSuccessPulse()
        } catch {
            handle(error, scanId: scanId, playHaptic: true)
            pendingUserMessage = PendingInsightChatMessage(
                id: clientMessageId,
                text: trimmed,
                createdAt: Date(),
                deliveryState: .failed(Self.userFacingMessage(for: error))
            )
            isSending = false
        }
    }

    func retryFailedMessage(scanId: String) async {
        guard let pendingUserMessage,
              case .failed = pendingUserMessage.deliveryState else { return }
        await send(pendingUserMessage.text, scanId: scanId)
    }

    func editFailedMessage() {
        guard let pendingUserMessage,
              case .failed = pendingUserMessage.deliveryState else { return }
        draftText = pendingUserMessage.text
        self.pendingUserMessage = nil
        errorMessage = nil
        HapticManager.shared.triggerSelectionPulse()
    }

    func deleteCurrentConversation(scanId: String) async {
        await deleteConversation(scanId: scanId)
    }

    func deleteConversation(scanId: String) async {
        guard !isOffline else {
            HapticManager.shared.triggerErrorThump()
            errorMessage = "Connect to delete chat."
            return
        }

        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            apply(try await MerianNetworkClient.shared.deleteInsightChat(scanId: scanId))
            HapticManager.shared.triggerSuccessPulse()
        } catch {
            handle(error, scanId: scanId, playHaptic: true)
        }
    }

    func setDraftText(_ newValue: String) {
        draftText = String(newValue.prefix(limits.maxUserMessageCharacters))
    }

    func submitFeedback(
        scanId: String,
        messageId: String,
        rating: InsightChatFeedbackRating,
        note: String? = nil
    ) async -> Bool {
        guard !isOffline else {
            HapticManager.shared.triggerErrorThump()
            errorMessage = "Connect to send feedback."
            return false
        }

        isSubmittingFeedback = true
        defer { isSubmittingFeedback = false }

        do {
            let response = try await MerianNetworkClient.shared.submitInsightChatFeedback(
                scanId: scanId,
                messageId: messageId,
                rating: rating,
                note: note
            )
            submittedFeedback[response.messageId] = response.rating
            HapticManager.shared.triggerSuccessPulse()
            return true
        } catch {
            handle(error, scanId: scanId, playHaptic: true)
            return false
        }
    }

    func submitFeatureFeedback(
        scanId: String,
        sentiment: InsightChatFeatureFeedbackSentiment?,
        note: String
    ) async -> Bool {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentiment != nil || !trimmedNote.isEmpty else { return false }
        guard !isOffline else {
            HapticManager.shared.triggerErrorThump()
            errorMessage = "Connect to send feedback."
            return false
        }

        isSubmittingFeatureFeedback = true
        defer { isSubmittingFeatureFeedback = false }

        do {
            _ = try await MerianNetworkClient.shared.submitInsightChatFeatureFeedback(
                scanId: scanId,
                sentiment: sentiment,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            HapticManager.shared.triggerSuccessPulse()
            return true
        } catch {
            handle(error, scanId: scanId, playHaptic: true)
            return false
        }
    }

    func summarizeForFieldNotes(scanId: String) async -> Bool {
        guard !isOffline else {
            HapticManager.shared.triggerErrorThump()
            errorMessage = "Connect to summarize chat."
            return false
        }
        guard !messages.isEmpty else { return false }

        isSummarizingNotes = true
        defer { isSummarizingNotes = false }

        do {
            let response = try await MerianNetworkClient.shared.summarizeInsightChatForFieldNotes(scanId: scanId)
            notesSummaryDraft = response.summaryText
            HapticManager.shared.triggerSuccessPulse()
            return true
        } catch {
            handle(error, scanId: scanId, playHaptic: true)
            return false
        }
    }

    func suggestionChips(
        for speciesData: SpeciesData,
        timestamp: Date?,
        displayName: String? = nil
    ) -> [String] {
        let fallbackChips = Self.suggestionChips(
            for: speciesData,
            timestamp: timestamp,
            displayName: displayName
        )
        let sentTexts = Set(sentAndPendingPromptTexts)
        var seen = Set<String>()
        var chips: [String] = []

        for prompt in suggestedPrompts.map(\.text) + fallbackChips {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty,
                  !sentTexts.contains(key),
                  seen.insert(key).inserted else {
                continue
            }
            chips.append(trimmed)
            if chips.count == 3 { break }
        }

        return chips
    }

    var sentAndPendingPromptTexts: [String] {
        messages.filter { $0.role == .user }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            + [pendingUserMessage?.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()].compactMap { $0 }
    }

    static func suggestionChips(
        for speciesData: SpeciesData,
        timestamp: Date?,
        displayName: String? = nil
    ) -> [String] {
        let speciesName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? Self.displayName(for: speciesData)
        var candidates: [String] = []

        if let comparisonName = comparisonPromptName(for: speciesData) {
            candidates.append("How do I tell it apart from \(comparisonName)?")
        }

        if speciesData.insightData.isHazardous {
            let hazard = hazardLabel(speciesData.insightData.hazardType)
            candidates.append("What should I know about its \(hazard) risk?")
        }

        if speciesData.isInvasive {
            candidates.append("Why is \(speciesName) invasive here?")
        }

        if let traitPhrase = visualTraitPhrase(from: speciesData.aiReasoning) {
            candidates.append("Which \(traitPhrase) traits support this ID?")
        }

        if hasHabitatContext(speciesData) {
            candidates.append("Does this habitat fit \(speciesName)?")
        }

        let monthDate = timestamp ?? Date()
        let month = monthFormatter.string(from: monthDate)
        candidates.append("Is \(speciesName) typical in \(month)?")

        if speciesData.confidenceScore >= 0.8 {
            candidates.append("What makes this a strong match?")
        } else if speciesData.confidenceScore < 0.7 {
            candidates.append("What makes this ID uncertain?")
        } else {
            candidates.append("What traits support this ID?")
        }

        candidates.append("What should I look for nearby?")
        candidates.append("What traits support this ID?")

        return uniquePrompts(candidates).prefix(3).map { $0 }
    }

    static func comparisonPrompt(for speciesData: SpeciesData) -> String? {
        comparisonPromptName(for: speciesData).map { "How do I tell it apart from \($0)?" }
    }

    static func hasLookalikeContext(_ speciesData: SpeciesData) -> Bool {
        comparisonPromptName(for: speciesData) != nil
    }

    func category(forPrompt prompt: String) -> String {
        let key = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let suggestedPrompt = suggestedPrompts.first(where: {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }) {
            return suggestedPrompt.category
        }
        return Self.localPromptCategory(for: prompt)
    }

    static func shouldOfferConfidenceReview(for speciesData: SpeciesData) -> Bool {
        let bands = MerianConfig.confidenceBands(forInferenceTier: speciesData.inferenceTier)
        return speciesData.confidenceScore < bands.strong || hasLookalikeContext(speciesData)
    }

    private func apply(_ response: InsightChatResponse) {
        conversationId = response.conversationId
        messages = response.messages
        pendingUserMessage = nil
        limits = response.limits
        unavailableScanId = nil
        errorMessage = nil
    }

    private func clearLoadedState() {
        loadedScanId = nil
        messages = []
        pendingUserMessage = nil
        conversationId = nil
        errorMessage = nil
        unavailableScanId = nil
        submittedFeedback = [:]
        notesSummaryDraft = nil
        suggestedPrompts = []
        isLoadingPrompts = false
    }

    private func refreshPromptSuggestionsAfterStateChange(
        scanId: String,
        force: Bool
    ) {
        guard !isOffline, unavailableScanId != scanId else {
            return
        }
        if isLoadingPrompts && !force { return }
        isLoadingPrompts = true

        Task { [weak self] in
            await self?.refreshPromptSuggestions(scanId: scanId)
        }
    }

    private func refreshPromptSuggestions(scanId: String) async {
        guard !isOffline else { return }

        promptRequestGeneration += 1
        let requestGeneration = promptRequestGeneration
        isLoadingPrompts = true
        defer {
            if promptRequestGeneration == requestGeneration {
                isLoadingPrompts = false
            }
        }

        do {
            let response = try await MerianNetworkClient.shared.suggestInsightChatPrompts(scanId: scanId)
            guard promptRequestGeneration == requestGeneration else { return }
            suggestedPrompts = response.prompts
        } catch {
            guard promptRequestGeneration == requestGeneration else { return }
            suggestedPrompts = []
        }
    }

    private func handle(_ error: Error, scanId: String, playHaptic: Bool = false) {
        if playHaptic {
            HapticManager.shared.triggerErrorThump()
        }
        errorMessage = Self.userFacingMessage(for: error)
        if Self.isDeterministicallyUnavailable(error) {
            unavailableScanId = scanId
        }
    }

    private func beginSending(_ text: String, clientMessageId: String) {
        HapticManager.shared.triggerMediumPulse()
        isSending = true
        errorMessage = nil
        pendingUserMessage = PendingInsightChatMessage(
            id: clientMessageId,
            text: text,
            createdAt: Date()
        )
    }

    static func isDeterministicallyUnavailable(_ error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, message) = error else {
            return false
        }

        if statusCode == 403 || statusCode == 404 { return true }
        if statusCode == 400 && message.contains("unsupported_scan") { return true }
        return false
    }

    static func userFacingMessage(for error: Error) -> String {
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
                return "Merian Pro is required."
            case 403:
                return "This scan belongs to another account."
            case 429:
                return "Chat limit reached for today."
            case 404:
                return "This scan is not ready for chat yet."
            default:
                return "Chat is unavailable right now."
            }
        }

        return "Chat is unavailable right now."
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    private static func comparisonPromptName(for speciesData: SpeciesData) -> String? {
        if let candidate = speciesData.candidates?.first {
            return candidate.commonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? candidate.scientificName
        }

        let lookalike = speciesData.similarSpecies?.filteredEntries(
            excludingScientificName: speciesData.scientificName,
            excludingCommonName: speciesData.commonName
        ).first
        return lookalike?.displayCommonName(comparedTo: speciesData.commonName)
            ?? lookalike?.scientificName
    }

    private static func displayName(for speciesData: SpeciesData) -> String {
        let commonName = speciesData.commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !commonName.isEmpty, commonName.caseInsensitiveCompare("not applicable") != .orderedSame {
            return commonName
        }
        let scientificName = speciesData.scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        return scientificName.nilIfEmpty ?? "this species"
    }

    private static func hazardLabel(_ hazardType: String) -> String {
        let normalized = hazardType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        return normalized.nilIfEmpty ?? "hazard"
    }

    private static func hasHabitatContext(_ speciesData: SpeciesData) -> Bool {
        if speciesData.habitatDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil {
            return true
        }
        let ecologyType = speciesData.ecologyType.trimmingCharacters(in: .whitespacesAndNewlines)
        return !ecologyType.isEmpty && ecologyType.caseInsensitiveCompare("unknown") != .orderedSame
    }

    private static func hasObservedTraits(_ speciesData: SpeciesData) -> Bool {
        if speciesData.colors?.isEmpty == false { return true }
        if speciesData.lifeStage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if speciesData.reproductiveCondition?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if speciesData.sexEvidence?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if speciesData.estimatedSizeCm != nil || speciesData.individualCount != nil { return true }
        return false
    }

    private static func visualTraitPhrase(from reasoning: String?) -> String? {
        guard let normalizedReasoning = reasoning?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalizedReasoning.isEmpty else {
            return nil
        }

        let traitGroups: [(label: String, keywords: [String])] = [
            ("leaf", ["leaf", "leaves", "foliage"]),
            ("flower", ["flower", "flowers", "petal", "petals", "bloom", "blooms"]),
            ("wing", ["wing", "wings"]),
            ("color", ["color", "colors", "colored", "colour", "hue"]),
            ("pattern", ["pattern", "patterns", "stripe", "stripes", "spot", "spots", "marking", "markings"]),
            ("stem", ["stem", "stems", "branch", "branches"]),
            ("cap", ["cap", "caps", "mushroom"]),
            ("gill", ["gill", "gills"]),
            ("fruit", ["fruit", "fruits", "berry", "berries"]),
            ("body", ["body", "abdomen", "thorax", "leg", "legs"])
        ]

        let matchedLabels = traitGroups.compactMap { group -> String? in
            group.keywords.contains { normalizedReasoning.contains($0) } ? group.label : nil
        }

        switch matchedLabels.count {
        case 0:
            return nil
        case 1:
            return matchedLabels[0]
        default:
            return matchedLabels.prefix(2).joined(separator: " and ")
        }
    }

    private static func localPromptCategory(for prompt: String) -> String {
        let normalized = prompt.lowercased()
        if normalized.contains("tell it apart") { return "lookalike_compare" }
        if normalized.contains("risk") { return "hazard" }
        if normalized.contains("invasive") { return "invasive" }
        if normalized.contains("traits support") { return "evidence" }
        if normalized.contains("habitat") { return "habitat" }
        if normalized.contains("typical in") { return "season" }
        if normalized.contains("strong match") || normalized.contains("uncertain") {
            return "confidence"
        }
        return "generic"
    }

    private static func uniquePrompts(_ prompts: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []

        for prompt in prompts {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(trimmed)
        }

        return unique
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
