import Photos
import StoreKit
import UIKit

@MainActor
struct CameraSettingsDependencies {
    let photoLibraryAuthorizationStatus: @MainActor ()
        -> PHAuthorizationStatus
    let setLiveInferencePaused: @MainActor (_ isPaused: Bool) -> Void

    static var live: Self {
        return Self(
            photoLibraryAuthorizationStatus: {
                PHPhotoLibrary.authorizationStatus(for: .addOnly)
            },
            setLiveInferencePaused: { isPaused in
                CameraManager.shared.isLiveInferencePaused = isPaused
            }
        )
    }
}

@MainActor
struct GeoprivacySettingsDependencies {
    let updatePreference: @MainActor (_ optionID: String) async -> Void

    static func live(supabase: SupabaseManager) -> Self {
        let expectedUserID = supabase.currentUser?.id

        return Self(
            updatePreference: { optionID in
                guard let expectedUserID,
                      let accountWorkLease = try? supabase
                    .beginUnownedAccountBoundWork() else { return }
                defer {
                    supabase.finishAccountBoundWork(accountWorkLease)
                }
                guard accountWorkLease.session.userID == expectedUserID else {
                    return
                }

                let userID = accountWorkLease.session.userID
                do {
                    try await supabase.client.from("users")
                        .update(["default_geoprivacy": optionID])
                        .eq("id", value: userID)
                        .execute()
                    guard supabase.isAccountBoundWorkLeaseCurrent(
                        accountWorkLease
                    ) else { return }
                } catch {
                    MerianLog.network.error(
                        "Failed to update geoprivacy preference: \(error, privacy: .private)"
                    )
                }
            }
        )
    }
}

@MainActor
struct SettingsPreferenceActions {
    let reconcileHardwareConstraints: @MainActor () -> Void

    static func live(hardwareOrchestrator: HardwareOrchestrator) -> Self {
        Self(
            reconcileHardwareConstraints: {
                hardwareOrchestrator.evaluateConstraints()
            }
        )
    }

    func updateExpeditionMode(
        _ isEnabled: Bool,
        persist: @MainActor (_ isEnabled: Bool) -> Void
    ) {
        persist(isEnabled)
        reconcileHardwareConstraints()
    }
}

@MainActor
struct CommunitySettingsDependencies {
    let requestAppStoreReview: @MainActor () -> Void
    let presentShareSheet: @MainActor () -> Void

    static var live: Self {
        Self(
            requestAppStoreReview: {
                guard let scene = UIApplication.shared.connectedScenes.first
                    as? UIWindowScene else { return }
                SKStoreReviewController.requestReview(in: scene)
            },
            presentShareSheet: {
                AppShareContent.presentShareSheet()
            }
        )
    }
}

#if DEBUG
@MainActor
struct SettingsDeveloperDependencies {
    let previewAnalyzingState: @MainActor () -> Void
    let reevaluateDailyUsage: @MainActor () -> Void

    static var live: Self {
        Self(
            previewAnalyzingState: {
                let container = AppDIContainer.shared
                container.inferenceEngine.simulateAnalyzing()
                container.appRouteCoordinator.request(
                    .debugPreviewAnalyzing,
                    source: .debug
                )
            },
            reevaluateDailyUsage: {
                UsageManager.shared.evaluateDailyRefresh()
            }
        )
    }
}
#endif
