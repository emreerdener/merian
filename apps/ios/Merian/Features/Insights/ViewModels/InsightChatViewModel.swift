import Foundation
import Network
import Observation

struct PendingInsightChatMessage: Identifiable, Equatable {
    let id: String
    let text: String
    let createdAt: Date
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
    var isOffline = false
    var conversationId: String?
    var unavailableScanId: String?
    var limits = InsightChatLimits(
        maxUserMessageCharacters: 600,
        maxMessagesPerConversation: 30,
        dailySendLimit: 20,
        sendsRemainingToday: 20
    )

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let monitorQueue = DispatchQueue(label: "com.merian.insight-chat.network")
    @ObservationIgnored private var loadedScanId: String?

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
            && !trimmedDraft.isEmpty
            && trimmedDraft.count <= limits.maxUserMessageCharacters
            && messages.count < limits.maxMessagesPerConversation
            && limits.sendsRemainingToday > 0
    }

    func isUnavailable(for scanId: String?) -> Bool {
        guard let scanId else { return true }
        return unavailableScanId == scanId
    }

    func loadIfNeeded(scanId: String, isProActive: Bool) async {
        guard isProActive else {
            clearLoadedState()
            return
        }

        guard loadedScanId != scanId else { return }
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
        defer { isLoading = false }

        do {
            apply(try await MerianNetworkClient.shared.loadInsightChat(scanId: scanId))
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
            errorMessage = "Connect to send."
            return
        }
        guard trimmed.count <= limits.maxUserMessageCharacters else {
            errorMessage = "Keep questions under \(limits.maxUserMessageCharacters) characters."
            return
        }

        isSending = true
        errorMessage = nil
        let clientMessageId = UUID().uuidString
        pendingUserMessage = PendingInsightChatMessage(
            id: clientMessageId,
            text: trimmed,
            createdAt: Date()
        )
        if trimmed == draftText.trimmingCharacters(in: .whitespacesAndNewlines) {
            draftText = ""
        }
        defer {
            pendingUserMessage = nil
            isSending = false
        }

        do {
            apply(try await MerianNetworkClient.shared.sendInsightChatMessage(
                scanId: scanId,
                messageText: trimmed,
                clientMessageId: clientMessageId
            ))
        } catch {
            handle(error, scanId: scanId)
            if draftText.isEmpty {
                draftText = trimmed
            }
        }
    }

    func deleteCurrentConversation(scanId: String) async {
        await deleteConversation(scanId: scanId)
    }

    func deleteConversation(scanId: String) async {
        guard !isOffline else {
            errorMessage = "Connect to delete chat."
            return
        }

        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            apply(try await MerianNetworkClient.shared.deleteInsightChat(scanId: scanId))
        } catch {
            handle(error, scanId: scanId)
        }
    }

    func setDraftText(_ newValue: String) {
        draftText = String(newValue.prefix(limits.maxUserMessageCharacters))
    }

    func suggestionChips(for speciesData: SpeciesData, timestamp: Date?) -> [String] {
        let allChips = Self.suggestionChips(for: speciesData, timestamp: timestamp)
        let sentTexts = Set(
            messages.filter { $0.role == .user }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            + [pendingUserMessage?.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()].compactMap { $0 }
        )
        return allChips.filter { chip in
            !sentTexts.contains(chip.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    static func suggestionChips(for speciesData: SpeciesData, timestamp: Date?) -> [String] {
        let speciesName = displayName(for: speciesData)
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

    private func apply(_ response: InsightChatResponse) {
        conversationId = response.conversationId
        messages = response.messages
        pendingUserMessage = nil
        limits = response.limits
        unavailableScanId = nil
    }

    private func clearLoadedState() {
        loadedScanId = nil
        messages = []
        pendingUserMessage = nil
        conversationId = nil
        errorMessage = nil
        unavailableScanId = nil
    }

    private func handle(_ error: Error, scanId: String) {
        errorMessage = Self.userFacingMessage(for: error)
        if Self.isDeterministicallyUnavailable(error) {
            unavailableScanId = scanId
        }
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
