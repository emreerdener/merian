import Foundation

extension ConsentManager {
    enum AdultConfirmationMethod: String, Codable {
        case selfAttestation = "self_attestation"
    }

    enum AIConsentEventKind: String, Codable {
        case granted
        case revoked
    }

    enum AnalyticsConsentEventKind: String, Codable {
        case granted
        case revoked
    }

    /// Separates a cached analytics choice from permission to operate the SDK.
    /// Authenticated capture is allowed only after the active account's latest
    /// server state survives the synchronization identity and storage fences.
    enum AnalyticsCloudAuthorityState: Equatable {
        case localOnly
        case awaitingRemote(userId: UUID)
        case resolvedRemote(userId: UUID, granted: Bool)

        func allowsCapture(for sessionUserId: UUID?) -> Bool {
            switch (self, sessionUserId) {
            case (.localOnly, nil):
                return true
            case let (.resolvedRemote(resolvedUserId, true), sessionUserId?):
                return resolvedUserId == sessionUserId
            default:
                return false
            }
        }
    }

    /// Prevents a completed user from being routed through the approval screen
    /// while the restored account's required consent is still being fetched.
    enum RequiredConsentRestorationState: Equatable {
        case awaitingInitialSession
        case reconciling(userId: UUID)
        case waitingToRetry(userId: UUID, attempt: Int)
        case retryRequired(userId: UUID)
        case resolved
    }

    private enum LocalLedgerCodingKeys: String, CodingKey {
        case activeUserId
        case termsReceipts
        case aiConsentEvents
        case adultEligibilityReceipts
        case analyticsConsentEvents
        case requiredConsentReapprovalUserIds
    }

    struct AdultEligibilityReceipt: Codable, Equatable {
        let id: UUID
        var ownerUserId: UUID?
        var syncedUserId: UUID?
        let policyVersion: String
        let confirmedAt: Date
        let confirmationMethod: AdultConfirmationMethod
        let confirmationText: String
        let platform: String
        let appVersion: String
        let appBuild: String
        var recordedAt: Date?
    }

    struct TermsAcceptanceReceipt: Codable, Equatable {
        let id: UUID
        var ownerUserId: UUID?
        var syncedUserId: UUID?
        let termsVersion: String
        let acceptedAt: Date
        let acceptanceText: String
        let platform: String
        let appVersion: String
        let appBuild: String
        var recordedAt: Date?
    }

    struct AIConsentEvent: Codable, Equatable {
        let id: UUID
        var ownerUserId: UUID?
        var syncedUserId: UUID?
        let provider: String
        let disclosureVersion: String
        let eventKind: AIConsentEventKind
        let occurredAt: Date
        let disclosureText: String
        let actionText: String
        let platform: String
        let appVersion: String
        let appBuild: String
        var recordedAt: Date?
        /// Event this device had observed when the action was created. Grants
        /// require this head; revocations may be rebased to the server head.
        var causalParentId: UUID?
        /// Server-issued monotonic ordering value. Never derived from a device
        /// clock or predicted for an offline event.
        var consentRevision: Int64?
        /// A rejected offline grant remains immutable local evidence but is
        /// excluded from current permission and future upload attempts.
        var supersededByEventId: UUID?
        var supersededByRevision: Int64?
    }

    struct AnalyticsConsentEvent: Codable, Equatable {
        let id: UUID
        var ownerUserId: UUID?
        var syncedUserId: UUID?
        let provider: String
        let disclosureVersion: String
        let eventKind: AnalyticsConsentEventKind
        let occurredAt: Date
        let disclosureText: String
        let actionText: String
        let platform: String
        let appVersion: String
        let appBuild: String
        var recordedAt: Date?
        var causalParentId: UUID?
        var consentRevision: Int64?
        var supersededByEventId: UUID?
        var supersededByRevision: Int64?
    }

    struct AnalyticsRevocationIntent: Codable, Equatable {
        var event: AnalyticsConsentEvent
    }

    struct AnalyticsRevocationJournal: Codable, Equatable {
        static let currentFormatVersion = 1

        let formatVersion: Int
        var intents: [AnalyticsRevocationIntent]

        init(intents: [AnalyticsRevocationIntent]) {
            formatVersion = Self.currentFormatVersion
            self.intents = intents
        }
    }

    struct LocalLedger: Codable, Equatable {
        var activeUserId: UUID?
        var termsReceipts: [TermsAcceptanceReceipt]
        var aiConsentEvents: [AIConsentEvent]
        var adultEligibilityReceipts: [AdultEligibilityReceipt]
        var analyticsConsentEvents: [AnalyticsConsentEvent]
        var requiredConsentReapprovalUserIds: Set<UUID>

        static let empty = LocalLedger(
            activeUserId: nil,
            termsReceipts: [],
            aiConsentEvents: [],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: [],
            requiredConsentReapprovalUserIds: []
        )

        init(
            activeUserId: UUID?,
            termsReceipts: [TermsAcceptanceReceipt],
            aiConsentEvents: [AIConsentEvent],
            adultEligibilityReceipts: [AdultEligibilityReceipt],
            analyticsConsentEvents: [AnalyticsConsentEvent],
            requiredConsentReapprovalUserIds: Set<UUID> = []
        ) {
            self.activeUserId = activeUserId
            self.termsReceipts = termsReceipts
            self.aiConsentEvents = aiConsentEvents
            self.adultEligibilityReceipts = adultEligibilityReceipts
            self.analyticsConsentEvents = analyticsConsentEvents
            self.requiredConsentReapprovalUserIds =
                requiredConsentReapprovalUserIds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(
                keyedBy: LocalLedgerCodingKeys.self
            )
            activeUserId = try container.decodeIfPresent(
                UUID.self,
                forKey: .activeUserId
            )
            termsReceipts = try container.decodeIfPresent(
                [TermsAcceptanceReceipt].self,
                forKey: .termsReceipts
            ) ?? []
            aiConsentEvents = try container.decodeIfPresent(
                [AIConsentEvent].self,
                forKey: .aiConsentEvents
            ) ?? []
            adultEligibilityReceipts = try container.decodeIfPresent(
                [AdultEligibilityReceipt].self,
                forKey: .adultEligibilityReceipts
            ) ?? []
            analyticsConsentEvents = try container.decodeIfPresent(
                [AnalyticsConsentEvent].self,
                forKey: .analyticsConsentEvents
            ) ?? []
            requiredConsentReapprovalUserIds = try container.decodeIfPresent(
                Set<UUID>.self,
                forKey: .requiredConsentReapprovalUserIds
            ) ?? []
        }
    }

    struct RemoteState {
        let adultEligibilityReceipt: AdultEligibilityReceipt?
        let termsReceipt: TermsAcceptanceReceipt?
        let aiConsentEvent: AIConsentEvent?
        let analyticsConsentEvent: AnalyticsConsentEvent?
        let aiConsentStreamHead: AIConsentEvent?
        let analyticsConsentStreamHead: AnalyticsConsentEvent?
    }
}
