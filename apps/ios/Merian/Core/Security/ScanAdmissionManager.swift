import Foundation
import Supabase

enum ScanAdmissionDecision: String, Codable, Sendable {
    case allowed
    case dailyQuotaExhausted = "daily_quota_exhausted"
    case proRequired = "pro_required"
}

struct ScanAdmissionPreview: Decodable, Sendable, Equatable {
    let decision: ScanAdmissionDecision
    let effectivePlan: String
    let dailyLimit: Int?
    let dailyRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case decision
        case effectivePlan = "effective_plan"
        case dailyLimit = "daily_limit"
        case dailyRemaining = "daily_remaining"
    }
}

private struct ScanAdmissionPreviewParameters: Encodable, Sendable {
    let pFlashFallbackEligible: Bool

    enum CodingKeys: String, CodingKey {
        case pFlashFallbackEligible = "p_flash_fallback_eligible"
    }
}

/// Reads the caller-scoped, non-reserving quota preview used by Capture UX.
/// The Identify reservation remains the only authorization boundary.
@MainActor
final class ScanAdmissionManager {
    static let shared = ScanAdmissionManager()

    private static let allowedPlans = Set([
        "free",
        "pro_paid",
        "pro_trial",
        "pro_complimentary"
    ])

#if DEBUG
    var overridingPreview: ((Bool) async -> ScanAdmissionPreview?)?
#endif

    private init() {}

    func preview(flashFallbackEligible: Bool) async -> ScanAdmissionPreview? {
#if DEBUG
        if let overridingPreview {
            return await overridingPreview(flashFallbackEligible)
        }
        if TestExecutionCoordinator.isRunningTests {
            return ScanAdmissionPreview(
                decision: .allowed,
                effectivePlan: "pro_paid",
                dailyLimit: nil,
                dailyRemaining: nil
            )
        }
#endif

        let supabaseManager = SupabaseManager.shared
        guard let userID = supabaseManager.currentUser?.id else { return nil }

        do {
            let rows: [ScanAdmissionPreview] = try await supabaseManager.client
                .rpc(
                    "get_my_scan_admission_preview",
                    params: ScanAdmissionPreviewParameters(
                        pFlashFallbackEligible: flashFallbackEligible
                    )
                )
                .execute()
                .value
            guard !Task.isCancelled,
                  supabaseManager.currentUser?.id == userID,
                  rows.count == 1,
                  Self.isValid(rows[0]) else {
                return nil
            }
            return rows[0]
        } catch {
            MerianLog.auth.debug(
                "Scan admission preview unavailable: \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }

#if DEBUG
    func resetForTesting() {
        overridingPreview = nil
    }
#endif

    private static func isValid(_ preview: ScanAdmissionPreview) -> Bool {
        guard allowedPlans.contains(preview.effectivePlan) else { return false }

        switch preview.decision {
        case .allowed:
            if let dailyLimit = preview.dailyLimit,
               let dailyRemaining = preview.dailyRemaining {
                return dailyLimit > 0 && dailyRemaining > 0 &&
                    dailyRemaining <= dailyLimit
            }
            return preview.dailyLimit == nil && preview.dailyRemaining == nil
        case .dailyQuotaExhausted:
            guard let dailyLimit = preview.dailyLimit,
                  let dailyRemaining = preview.dailyRemaining else {
                return false
            }
            return dailyLimit > 0 && dailyRemaining == 0
        case .proRequired:
            return preview.dailyLimit == nil && preview.dailyRemaining == nil
        }
    }
}
