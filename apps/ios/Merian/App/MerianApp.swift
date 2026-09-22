import GoogleSignIn
import SwiftData
import SwiftUI
import UIKit

private struct ConsentRestorationView: View {
    @Environment(ConsentManager.self) private var consentManager
    @State private var showsProgress = false

    var body: some View {
        ZStack {
            // Match LaunchScreen.storyboard so quick account restoration does
            // not introduce another transient surface during cold launch.
            Color.black.ignoresSafeArea()

            if consentManager.canRetryRequiredConsentRestoration {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .accessibilityHidden(true)

                    Text("Naturebook couldn’t verify your saved choices.")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Try again to finish restoring them.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)

                    Button("Try Again") {
                        consentManager.retryRequiredConsentRestoration()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
                .padding(24)
                .frame(maxWidth: 420)
            } else if showsProgress {
                ProgressView()
                    .tint(.white.opacity(0.7))
                    .accessibilityLabel("Restoring your choices")
            }
        }
        .task {
            do {
                try await Task.sleep(for: .milliseconds(350))
                showsProgress = true
            } catch {
                // The restoration view disappeared before feedback was needed.
            }
        }
    }
}

private struct AccountDeletionRecoveryView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Finishing Account Deletion")
                    .font(.headline)
                Text(
                    "Naturebook is confirming your request and securely clearing this device. Keep the app open and connected."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            }
            .padding(24)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Main Execution Point
@main
struct MerianApp: App {
    // MARK: - Lifecycle Hooks
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRunInitialActivePhase = false
    @State private var isShowingManualAppleRevocationNotice =
        ManualAppleRevocationNoticeStore.isPending()
    @State private var isAccountDeletionRecoveryPending: Bool
    @State private var signOutToast: ToastPayload?
    
    // MARK: - App Dependencies
    let diContainer: AppDIContainer
    let lifecycleManager: AppLifecycleManager
    
    // MARK: - SwiftData Container
    let container: ModelContainer?
    let startupStoreState: StartupStoreState
    let startupRecoveryNotice: StartupRecoveryNotice?
    let shouldOpenExploreOnFreshLaunch: Bool
    
    // MARK: - Lifecycle Bootstrapping
    @MainActor
    init() {
        // Test-mode Keychain reads use synthetic storage and cannot establish
        // whether a production recovery proof is absent.
        if !TestExecutionCoordinator.isRunningTests {
            _ = AccountDeletionRecoveryCapabilityStore
                .restoreBarrierBeforeAuthBootstrap()
        }
        _isAccountDeletionRecoveryPending = State(
            initialValue: AccountDeletionLocalCleanupStore.isPending()
        )
        let dependencies = AppDIContainer.shared
        UITestSeedCoordinator.prepareCaptureGoalStoreIfNeeded(
            container: dependencies
        )
        diContainer = dependencies
        lifecycleManager = AppLifecycleManager(container: dependencies)
        UITestSeedCoordinator.prepareRequiredConsentIfNeeded(
            consentManager: dependencies.consentManager
        )
        let appSettings = dependencies.appSettings
        shouldOpenExploreOnFreshLaunch = AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: appSettings.hasCompletedOnboarding
                && dependencies.consentManager.hasCurrentRequiredConsent,
            opensExploreOnLaunch: appSettings.opensExploreOnLaunch
        )

        // Migrate old multiImageScanMode to the new isMultiCaptureEnabled key
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.legacyMultiImageScanMode) != nil {
            let oldVal = UserDefaults.standard.bool(forKey: UserDefaultsKeys.legacyMultiImageScanMode)
            UserDefaults.standard.set(oldVal, forKey: UserDefaultsKeys.isMultiCaptureEnabled)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.legacyMultiImageScanMode)
        }

        let bootstrapOutcome = ModelContainerBootstrapper.bootstrap()
        container = bootstrapOutcome.container
        startupStoreState = bootstrapOutcome.startupStoreState
        startupRecoveryNotice = StartupRecoveryNoticePolicy.combined(
            storeNotice: bootstrapOutcome.startupNotice
        )
        if let container {
            let mainContext = container.mainContext
            dependencies.scanRepository.configure(with: mainContext)
            SpeciesPreferredNameRepository.discardLegacyUnscopedPreferences(
                modelContext: mainContext
            )

            UITestSeedCoordinator.prepareIfNeeded(container: container)
            dependencies.privateScanMapStore.configure(
                modelContainer: container,
                eventStream: dependencies.appEventPublisher
            )
        }

        // Keep app-hosted test sessions hermetic: no analytics startup, no disk-backed
        // production store, and no background sync noise racing the test containers.
        if !TestExecutionCoordinator.isRunningTests {
            // Prepare the app analytics facade without starting PostHog. Startup
            // recovery telemetry is intentionally dropped unless a previously
            // granted account permission has already activated the sink.
            AppTelemetry.initialize()
            if let telemetryEvent = bootstrapOutcome.telemetryEvent {
                AppTelemetry.trackStartupStoreRecovery(
                    outcome: telemetryEvent.outcome,
                    reason: telemetryEvent.reason,
                    properties: telemetryEvent.properties
                )
            }
        }
    }

    // MARK: - Scene Hierarchy
    var body: some Scene {
        WindowGroup {
            let appSettings = diContainer.appSettings
            let consentManager = diContainer.consentManager
            Group {
                if let container {
                    Group {
                        switch AppRootPresentationPolicy.presentation(
                            hasCompletedOnboarding: appSettings.hasCompletedOnboarding,
                            hasCurrentRequiredConsent: consentManager.hasCurrentRequiredConsent,
                            isRestoringRequiredConsent: consentManager.isRestoringRequiredConsent
                        ) {
                        case .workspace:
                            CaptureWorkspaceView(
                                appSettings: appSettings,
                                opensExploreOnFreshLaunch: shouldOpenExploreOnFreshLaunch
                            )
                        case .restoringConsent:
                            ConsentRestorationView()
                        case .onboarding:
                            OnboardingView(
                                dependencies: .live(
                                    appSettings: appSettings,
                                    consentManager: consentManager,
                                    offlineQueueManager:
                                        diContainer.offlineQueueManager,
                                    hardwareOrchestrator:
                                        diContainer.hardwareOrchestrator
                                )
                            )
                        }
                    }
                    .modelContainer(container)
                    .injectAppDependencies(container: diContainer)
                    .environment(\.startupStoreState, startupStoreState)
                    .environment(\.startupRecoveryNotice, startupRecoveryNotice)
                } else {
                    StartupRecoveryNoticeView(
                        notice: startupRecoveryNotice ?? StartupRecoveryNotice(
                            title: "Startup Blocked",
                            message: "Naturebook could not initialize its local library."
                        )
                    )
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color(.systemBackground))
                }
            }
            .overlay {
                if isAccountDeletionRecoveryPending {
                    AccountDeletionRecoveryView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .environment(\.showSignOutConfirmation) {
                signOutToast = .success("Signed out successfully")
            }
            .merianSystemFeedback(
                toast: $signOutToast,
                toastAlignment: .top,
                showsAchievementToasts: false
            )
            .onAppear {
                applyTheme(appSettings.themeMode)
                isShowingManualAppleRevocationNotice =
                    ManualAppleRevocationNoticeStore.isPending()
                guard !TestExecutionCoordinator.isRunningTests,
                      !didRunInitialActivePhase else {
                    return
                }
                didRunInitialActivePhase = true
                Task { @MainActor in
                    guard !AccountDeletionLocalCleanupStore.isPending()
                    else { return }
                    lifecycleManager.handleActivePhase()
                }
            }
            .onChange(of: appSettings.themeMode) { _, newTheme in
                applyTheme(newTheme)
            }
            .onReceive(diContainer.appEventPublisher.publisher) { event in
                guard case .manualAppleRevocationNoticeRequired = event else { return }
                isShowingManualAppleRevocationNotice = true
            }
            .onReceive(diContainer.appEventPublisher.publisher) { event in
                guard case .accountDeletionRecoveryStateChanged = event else {
                    return
                }
                isAccountDeletionRecoveryPending =
                    AccountDeletionLocalCleanupStore.isPending()
            }
            .task(id: isAccountDeletionRecoveryPending) {
                guard isAccountDeletionRecoveryPending,
                      !TestExecutionCoordinator.isRunningTests else {
                    return
                }
                let retryDelays: [Duration] = [
                    .seconds(2), .seconds(5), .seconds(15), .seconds(30)
                ]
                var retryIndex = 0
                while AccountDeletionLocalCleanupStore.isPending() {
                    if await resumeAcceptedAccountDeletionCleanupIfNeeded() {
                        lifecycleManager.handleActivePhase()
                        return
                    }
                    do {
                        try await Task.sleep(
                            for: retryDelays[
                                min(retryIndex, retryDelays.count - 1)
                            ]
                        )
                    } catch {
                        return
                    }
                    retryIndex += 1
                }
            }
            .alert(
                "Finish Sign in with Apple Cleanup",
                isPresented: $isShowingManualAppleRevocationNotice
            ) {
                Button("Open Apple Instructions") {
                    guard let url = URL(
                        string: "https://support.apple.com/102571"
                    ) else { return }
                    UIApplication.shared.open(url)
                }
                Button("I Revoked Access") {
                    ManualAppleRevocationNoticeStore.resolve()
                }
            } message: {
                Text(
                    "Your Naturebook deletion is already continuing. Because this Apple-linked account predates automatic token revocation, open Settings > [your name] > Sign in with Apple > Naturebook, then choose Delete or Stop Using. You can also follow Apple’s web instructions."
                )
            }
            .onOpenURL { url in
                switch MerianOpenURLRoute.classify(
                    url,
                    googleHandled: GIDSignIn.sharedInstance.handle(url)
                ) {
                case .handledByGoogle:
                    return
                case .merianDeepLink:
                    _ = handleMerianDeepLink(url)
                case .externalImageImport:
                    handleExternalImageImportURL(url)
                case .supabaseAuthentication:
                    Task {
                        await diContainer.supabaseManager
                            .handleAuthenticationCallbackURL(url)
                    }
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                _ = handleMerianDeepLink(url)
            }
        }
        // MARK: - Scene Phases
        .onChange(of: scenePhase) { oldPhase, newPhase in
            diContainer.inferenceEngine.handleApplicationActiveStateChange(
                isActive: newPhase == .active
            )
            guard !TestExecutionCoordinator.isRunningTests else { return }

            switch newPhase {
            case .background:
                guard !AccountDeletionLocalCleanupStore.isPending() else {
                    return
                }
                lifecycleManager.handleBackgroundPhase()
            case .inactive:
                guard !AccountDeletionLocalCleanupStore.isPending() else {
                    return
                }
                // Only dismiss modals and pause hardware when transitioning out of the foreground.
                // Prevents wiping deep-link state (like open push notifications) when returning from the background.
                if oldPhase == .active {
                    lifecycleManager.handleInactivePhase()
                }
            case .active:
                Task { @MainActor in
                    guard await resumeAcceptedAccountDeletionCleanupIfNeeded()
                    else { return }
                    lifecycleManager.handleActivePhase()
                    if ManualAppleRevocationNoticeStore.isPending() {
                        isShowingManualAppleRevocationNotice = true
                    }
                }
            @unknown default:
                break
            }
        }
    }

    @MainActor
    private func resumeAcceptedAccountDeletionCleanupIfNeeded() async -> Bool {
        guard AccountDeletionLocalCleanupStore.isPending() else {
            isAccountDeletionRecoveryPending = false
            return true
        }
        isAccountDeletionRecoveryPending = true
        guard let modelContext = container?.mainContext else { return false }
        let completed = await diContainer.supabaseManager
            .resumePendingAccountDeletionLocalCleanup {
                diContainer.scanRepository.purgeAllData(
                    modelContext: modelContext,
                    resetDerivedState:
                        diContainer.privateScanMapStore.resetSensitiveState
                )
            }
        isAccountDeletionRecoveryPending =
            AccountDeletionLocalCleanupStore.isPending()
        return completed
    }

    private func applyTheme(_ themeMode: ThemeMode) {
        // Bypass SwiftUI .preferredColorScheme(nil) modal inheritance bugs by pushing to UIWindow.
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = themeMode.userInterfaceStyle
            }
        }
    }

    private func handleExternalImageImportURL(_ url: URL) {
        Task { @MainActor in
            do {
                _ = try await diContainer.externalImageImportStore.stageIncomingImage(at: url)
                AppTelemetry.trackExternalImageImport(outcome: "received")
                diContainer.appRouteCoordinator.request(
                    .processExternalImageImports,
                    source: .durableExternalImport
                )
            } catch {
                MerianLog.data.error(
                    "External image import could not be copied into the pending inbox: \(error, privacy: .private)"
                )
                let outcome = (error as? ExternalImageImportError) == .unsupportedURL
                    ? "failed_unsupported_type"
                    : "failed_inbox"
                AppTelemetry.trackExternalImageImport(outcome: outcome)
                await diContainer.externalImageImportStore.recordTerminalFailure()
                HapticManager.shared.triggerErrorThump()
                diContainer.appRouteCoordinator.request(
                    .externalImageImportFailed,
                    source: .durableExternalImport
                )
            }
        }
    }

    private func handleMerianDeepLink(_ url: URL) -> Bool {
        guard let route = MerianDeepLinkRoute(url: url) else {
            return false
        }

        switch route {
        case .explorePost(let postId):
            diContainer.appRouteCoordinator.request(
                .explorePost(
                    postId: postId,
                    targetCommentId: nil,
                    targetReplyParentCommentId: nil
                ),
                source: .deepLink
            )
        case .speciesDictionary(let speciesId):
            diContainer.appRouteCoordinator.request(
                .speciesDictionary(speciesId: speciesId),
                source: .deepLink
            )
        case .scan(let scanId):
            diContainer.appRouteCoordinator.request(
                .scan(scanId: scanId),
                source: .deepLink
            )
        case .scansLibrary:
            diContainer.appRouteCoordinator.request(.scansLibrary, source: .deepLink)
        }
        return true
    }
}
