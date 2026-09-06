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

enum ScanAdmissionPreviewResult: Sendable, Equatable {
    case available(ScanAdmissionPreview)
    case connectivityUnavailable
    case unavailable
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

    nonisolated static let previewRequestTimeout: TimeInterval = 2

    private static let allowedPlans = Set([
        "free",
        "pro_paid",
        "pro_trial",
        "pro_complimentary"
    ])

#if DEBUG
    var overridingPreview: ((Bool) async throws -> ScanAdmissionPreview?)?
#endif

    private init() {}

    func preview(flashFallbackEligible: Bool) async -> ScanAdmissionPreviewResult {
#if DEBUG
        if let overridingPreview {
            do {
                guard let preview = try await overridingPreview(flashFallbackEligible),
                      !Task.isCancelled,
                      Self.isValid(preview) else {
                    return .unavailable
                }
                return .available(preview)
            } catch {
                return Self.result(for: error)
            }
        }
        if TestExecutionCoordinator.isRunningTests {
            return .available(ScanAdmissionPreview(
                decision: .allowed,
                effectivePlan: "pro_paid",
                dailyLimit: nil,
                dailyRemaining: nil
            ))
        }
#endif

        let supabaseManager = SupabaseManager.shared
        guard let accountWorkLease = try? supabaseManager
                .beginUnownedAccountBoundWork(),
              let userID = supabaseManager.currentUser?.id,
              let session = supabaseManager.client.auth.currentSession,
              session.user.id == userID,
              let supabaseURL = SecureTransportPolicy.httpsURL(
                from: MerianEnvironment.supabaseUrl
              ) else {
            return .unavailable
        }
        defer { supabaseManager.finishAccountBoundWork(accountWorkLease) }

        let networkClient = MerianNetworkClient.shared
        let postgrest = PostgrestClient(
            url: supabaseURL
                .appendingPathComponent("rest")
                .appendingPathComponent("v1"),
            headers: [
                "Authorization": "Bearer \(session.accessToken)",
                "apikey": MerianEnvironment.supabaseAnonKey
            ],
            fetch: { request in
                try await networkClient
                    .performPinnedScanAdmissionPreviewRequest(
                        request,
                        timeoutInterval: Self.previewRequestTimeout
                    )
            },
            retryEnabled: false
        )

        do {
            let rows: [ScanAdmissionPreview] = try await postgrest
                .rpc(
                    "get_my_scan_admission_preview",
                    params: ScanAdmissionPreviewParameters(
                        pFlashFallbackEligible: flashFallbackEligible
                    )
                )
                .execute()
                .value
            guard !Task.isCancelled,
                  supabaseManager.isAccountBoundWorkLeaseCurrent(
                    accountWorkLease
                  ),
                  rows.count == 1,
                  Self.isValid(rows[0]) else {
                return .unavailable
            }
            return .available(rows[0])
        } catch {
            MerianLog.auth.debug(
                "Scan admission preview unavailable; kind=\(MerianLog.errorKind(error), privacy: .public)."
            )
            return Self.result(for: error)
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

    nonisolated private static func result(for error: Error) -> ScanAdmissionPreviewResult {
        guard !Task.isCancelled, !(error is CancellationError) else {
            return .unavailable
        }
        return ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(error)
            ? .connectivityUnavailable
            : .unavailable
    }
}
