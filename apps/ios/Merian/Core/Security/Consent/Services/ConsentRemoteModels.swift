import Foundation

enum ConsentRemoteWire {
    struct AdultEligibilityReceiptInsert: Encodable, Equatable {
        let id: UUID
        let user_id: UUID
        let policy_version: String
        let confirmed_at: String
        let confirmation_method: String
        let confirmation_text: String
        let platform: String
        let app_version: String
        let app_build: String
    }

    struct TermsReceiptInsert: Encodable, Equatable {
        let id: UUID
        let user_id: UUID
        let terms_version: String
        let accepted_at: String
        let acceptance_text: String
        let platform: String
        let app_version: String
        let app_build: String
    }

    struct AIConsentEventAppend: Encodable, Equatable {
        let p_id: UUID
        let p_disclosure_version: String
        let p_event_kind: String
        let p_occurred_at: String
        let p_disclosure_text: String
        let p_action_text: String
        let p_platform: String
        let p_app_version: String
        let p_app_build: String
        let p_causal_parent_id: UUID?
    }

    struct AnalyticsConsentEventAppend: Encodable, Equatable {
        let p_id: UUID
        let p_disclosure_version: String
        let p_event_kind: String
        let p_occurred_at: String
        let p_disclosure_text: String
        let p_action_text: String
        let p_platform: String
        let p_app_version: String
        let p_app_build: String
        let p_causal_parent_id: UUID?
    }

    struct ConsentAppendResult: Decodable, Equatable {
        let accepted: Bool
        let event_revision: Int64?
        let accepted_parent_id: UUID?
        let authoritative_revision: Int64
        let authoritative_event_id: UUID?
        let recorded_at: String?
    }

    struct AdultEligibilityReceipt: Decodable, Equatable {
        let id: UUID
        let user_id: UUID
        let policy_version: String
        let confirmed_at: String
        let confirmation_method: String
        let confirmation_text: String
        let platform: String
        let app_version: String
        let app_build: String
        let recorded_at: String
    }

    struct TermsReceipt: Decodable, Equatable {
        let id: UUID
        let user_id: UUID
        let terms_version: String
        let accepted_at: String
        let acceptance_text: String
        let platform: String
        let app_version: String
        let app_build: String
        let recorded_at: String
    }

    struct AIConsentEvent: Decodable, Equatable {
        let id: UUID
        let user_id: UUID
        let provider: String
        let disclosure_version: String
        let event_kind: String
        let occurred_at: String
        let disclosure_text: String
        let action_text: String
        let platform: String
        let app_version: String
        let app_build: String
        let recorded_at: String
        let causal_parent_id: UUID?
        let consent_revision: Int64
    }

    struct AnalyticsConsentEvent: Decodable, Equatable {
        let id: UUID
        let user_id: UUID
        let provider: String
        let disclosure_version: String
        let event_kind: String
        let occurred_at: String
        let disclosure_text: String
        let action_text: String
        let platform: String
        let app_version: String
        let app_build: String
        let recorded_at: String
        let causal_parent_id: UUID?
        let consent_revision: Int64
    }

    struct RemoteRows: Equatable {
        let adultEligibilityReceipts: [AdultEligibilityReceipt]
        let termsReceipts: [TermsReceipt]
        let aiConsentEvents: [AIConsentEvent]
        let analyticsConsentEvents: [AnalyticsConsentEvent]
        let aiConsentStreamHeads: [AIConsentEvent]
        let analyticsConsentStreamHeads: [AnalyticsConsentEvent]
    }

    static let adultEligibilityReceiptColumns =
        "id,user_id,policy_version,confirmed_at,confirmation_method,"
        + "confirmation_text,platform,app_version,app_build,recorded_at"

    static let termsReceiptColumns =
        "id,user_id,terms_version,accepted_at,acceptance_text,platform,"
        + "app_version,app_build,recorded_at"

    static let consentEventColumns =
        "id,user_id,provider,disclosure_version,event_kind,occurred_at,"
        + "disclosure_text,action_text,platform,app_version,app_build,"
        + "recorded_at,causal_parent_id,consent_revision"
}
