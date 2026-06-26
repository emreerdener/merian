import Foundation
import Network
import Observation

@MainActor
@Observable
final class InsightChatViewModel {
    static let maxDraftCharacters = 600

    var messages: [InsightChatMessage] = []
    var draftText = ""
    var errorMessage: String?
    var isLoading = false
    var isSending = false
    var isDeleting = false
    var isOffline = false
    var conversationId: String?
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

    func loadIfNeeded(scanId: String, isProActive: Bool) async {
        guard isProActive else {
            loadedScanId = nil
            messages = []
            conversationId = nil
            errorMessage = nil
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
            errorMessage = userFacingMessage(for: error)
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
        if trimmed == draftText.trimmingCharacters(in: .whitespacesAndNewlines) {
            draftText = ""
        }
        defer { isSending = false }

        do {
            apply(try await MerianNetworkClient.shared.sendInsightChatMessage(
                scanId: scanId,
                messageText: trimmed,
                clientMessageId: clientMessageId
            ))
        } catch {
            errorMessage = userFacingMessage(for: error)
            if draftText.isEmpty {
                draftText = trimmed
            }
        }
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
            errorMessage = userFacingMessage(for: error)
        }
    }

    func setDraftText(_ newValue: String) {
        draftText = String(newValue.prefix(limits.maxUserMessageCharacters))
    }

    func suggestionChips(for speciesData: SpeciesData, timestamp: Date?) -> [String] {
        Self.suggestionChips(for: speciesData, timestamp: timestamp)
    }

    static func suggestionChips(for speciesData: SpeciesData, timestamp: Date?) -> [String] {
        var chips: [String] = []

        if let candidate = speciesData.candidates?.first {
            let name = candidate.commonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? candidate.scientificName
            chips.append("How do I tell it apart from \(name)?")
        } else if let lookalike = speciesData.similarSpecies?.filteredEntries(
            excludingScientificName: speciesData.scientificName,
            excludingCommonName: speciesData.commonName
        ).first {
            let name = lookalike.commonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? lookalike.scientificName
            chips.append("How do I tell it apart from \(name)?")
        }

        let monthDate = timestamp ?? Date()
        let month = monthFormatter.string(from: monthDate)
        chips.append("Is it typical to see this in \(month)?")

        if speciesData.insightData.isHazardous {
            chips.append("What should I know about the hazard?")
        } else {
            chips.append("What habitat should I look for nearby?")
        }

        if chips.count < 3 {
            chips.append("What traits support this ID?")
        }

        return Array(chips.prefix(3))
    }

    private func apply(_ response: InsightChatResponse) {
        conversationId = response.conversationId
        messages = response.messages
        limits = response.limits
    }

    private func userFacingMessage(for error: Error) -> String {
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
