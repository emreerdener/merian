import Combine
import Observation
import PhotosUI
import SwiftUI

@Observable
@MainActor
final class CaptureWorkspaceViewModel {

    // MARK: - Types
    enum ActiveSheet: String, Identifiable, Sendable {
        case insight, paywall, scans, profile, explore, achievement, notificationPrompt
        var id: String { rawValue }
    }

    enum PresentationStyle: Sendable, Equatable {
        case sheet
    }

    struct PresentedRoute: Identifiable, Equatable {
        let id: UUID
        let destination: ActiveSheet
        let style: PresentationStyle
        let routeRequestID: UUID?
    }

    // MARK: - Dependencies
    @ObservationIgnored let diContainer: AppDIContainer
    @ObservationIgnored let dependencies: CaptureWorkspaceDependencies
    @ObservationIgnored let operationState = CaptureWorkspaceOperationState()
    @ObservationIgnored let scanOperationState = CaptureScanOperationState()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - UI & Navigation State
    var activePresentation: PresentedRoute?
    var isRootPresentationDismissing: Bool {
        operationState.isDismissingPresentation
    }
    var activeSheet: ActiveSheet? {
        get { activePresentation?.destination }
        set {
            guard let newValue else {
                dismissActivePresentation()
                return
            }
            guard activePresentation?.destination != newValue else { return }
            if activePresentation != nil || operationState.isDismissingPresentation {
                // Local presentation changes are latest-wins, but never mount
                // during the previous sheet's interactive dismissal window.
                operationState.queueLocalSheet(newValue)
                dismissActivePresentation()
                return
            }
            activePresentation = PresentedRoute(
                id: UUID(),
                destination: newValue,
                style: .sheet,
                routeRequestID: operationState.applyingRouteRequestID
            )
        }
    }
    var pendingExplorePostId: String?
    var pendingSpeciesDictionaryRoute: SpeciesDictionaryRoute?
    var pendingCommunityIdentificationRequestId: String?
    var pendingExploreTargetCommentId: String?
    var pendingExploreTargetReplyParentCommentId: String?
    var pendingCaptureGoalDestination: CaptureGoalDestination?
    var pendingExploreShowsFieldTrips = false
    var pendingScansRecoveryContext: ExploreMediaRecoveryRouteContext?
    var pendingScansShowsNonBiologicalCollection = false
    var pendingAchievementAward: AwardPayload?
    var explorePresentationIdentity = UUID()
    var offlineToastMessage: ToastPayload?
    var imageToCrop: IdentifiableImage?
    var editingCropIndex: Int?
    /// All content staged for the next combined submission — images, optional audio (reserved),
    /// and optional describe description. Replaces the previous four parallel image arrays.
    var stagedCapture = StagedCapture()
    var selectedPhotoItems: [PhotosPickerItem] = []
    var isCheckingScanAdmission = false
    /// Set in the same MainActor mutation that stages an eligible single capture.
    /// This keeps the manual Identify toolbar from appearing before the async
    /// auto-submit observer begins its admission check. A failed attempt clears
    /// the flag while preserving staged media so the toolbar can become the
    /// explicit recovery path.
    private(set) var isAutomaticStagedSubmissionPending = false

    // MARK: - Refinement Flow
    /// The historical scan actively chosen by the user to be appended with new photographic context.
    /// Drives the multi-image composition path in `submitStagedCapture`.
    var baseRefinementContext: RefinementScanContext?
    var refinementInitialDescriptionDraft: String?
    var refinementSubjectId: String?
    var isStagingRefinement: Bool = false
    /// Set to `.describe` when reanalysis is triggered so `CaptureWorkspaceView` navigates to the
    /// Describe page immediately after the insight sheet dismisses. Consumed and cleared by
    /// `CaptureWorkspaceView.onChange(of: viewModel.requestedCaptureMode)`.
    var requestedCaptureMode: CaptureMode?

    // MARK: - Composing Zone
    /// Vertical center of the on-screen composing zone as a fraction of screen height (0–1).
    /// Set by CaptureWorkspaceView once layout is measured. The capture pipeline uses this to
    /// center the auto-crop on the region the user actually frames their subject in,
    /// rather than the geometric center of the full sensor image.
    var composingZoneVerticalCenter: CGFloat = 0.5
    // MARK: - Camera & Scanning State
    var isCapturing: Bool = false
    var isVideoRecording: Bool = false
    var videoRecordingProgress: Double = 0
    var flashOpacity: Double = 0.0

    // MARK: - Asynchronous Jobs
    @ObservationIgnored var preFetchTask: Task<EnvironmentContext, Never>?
    /// Tracks the scanId of the most recently submitted scan. Used by the async telemetry
    /// Task in `submitStagedCapture` to detect when a newer scan has superseded this one and
    /// skip calling `analyze()` — prevents a stale Task from re-triggering live inference
    /// after the engine has already moved on to a subsequent capture.
    @ObservationIgnored var pendingAnalyzeScanId: String?

    func updateAutomaticStagedSubmissionPending(_ isPending: Bool) {
        isAutomaticStagedSubmissionPending = isPending
    }

    var isMultiCaptureFunctionallyEnabled: Bool {
        diContainer.appSettings.isMultiCaptureEnabled
            && diContainer.revenueCatManager.canStartProScan
    }

    var stagedCaptureLimit: Int {
        (isMultiCaptureFunctionallyEnabled || baseRefinementContext != nil) ? stagedCaptureCapacity : 1
    }

    var availableStagedCaptureSlots: Int {
        stagedCapture.availableSlots(limit: stagedCaptureLimit)
    }

    var hasAvailableStagedCaptureSlot: Bool {
        !stagedCapture.isAtCapacity(limit: stagedCaptureLimit)
    }

    var shouldShowMediaModeToggle: Bool {
        hasAvailableStagedCaptureSlot || baseRefinementContext != nil
    }

    var shouldShowViewfinderHints: Bool {
        hasAvailableStagedCaptureSlot
    }

    var describePromptFlow: DescribePromptFlow {
        if baseRefinementContext != nil {
            return .reanalysis(subjectId: refinementSubjectId)
        }
        return .standard
    }

    var describePromptMediaContext: DescribePromptMediaContext {
        let activeMediaKinds = [
            stagedCapture.hasVisualMedia,
            !stagedCapture.audios.isEmpty,
            !stagedCapture.observationContexts.isEmpty
        ].filter { $0 }.count

        guard activeMediaKinds == 1 else {
            return activeMediaKinds == 0 ? .none : .mixed
        }
        if stagedCapture.hasVisualMedia { return .photo }
        if !stagedCapture.audios.isEmpty { return .audio }
        return .description
    }

    var appEvents: AnyPublisher<AppEvent, Never> {
        diContainer.appEventPublisher.publisher
    }

    // MARK: - Lifecycle
    convenience init(initialActiveSheet: ActiveSheet? = nil) {
        self.init(
            diContainer: AppDIContainer.shared,
            preparedImageLoader: CaptureWorkspaceDependencies.livePreparedImageLoader,
            prewarmHeadersOnInit: true,
            initialActiveSheet: initialActiveSheet
        )
    }

    convenience init(
        diContainer: AppDIContainer,
        preparedImageLoader: @escaping PreparedStagedImageLoader,
        preparedHistoricalAudioLoader: @escaping PreparedHistoricalAudioLoader =
            CaptureWorkspaceDependencies.livePreparedHistoricalAudioLoader,
        prewarmHeadersOnInit: Bool = true,
        initialActiveSheet: ActiveSheet? = nil,
        externalImageImportStore: ExternalImageImportStore? = nil
    ) {
        self.init(
            diContainer: diContainer,
            dependencies: .live(
                diContainer: diContainer,
                preparedImageLoader: preparedImageLoader,
                preparedHistoricalAudioLoader: preparedHistoricalAudioLoader,
                externalImageImportStore: externalImageImportStore
            ),
            prewarmHeadersOnInit: prewarmHeadersOnInit,
            initialActiveSheet: initialActiveSheet
        )
    }

    init(
        diContainer: AppDIContainer,
        dependencies: CaptureWorkspaceDependencies,
        prewarmHeadersOnInit: Bool = true,
        initialActiveSheet: ActiveSheet? = nil
    ) {
        self.diContainer = diContainer
        self.dependencies = dependencies
        self.activePresentation = initialActiveSheet.map {
            PresentedRoute(
                id: UUID(),
                destination: $0,
                style: .sheet,
                routeRequestID: nil
            )
        }

        // The live dependency warms the separate Auth and pinned inference sessions while
        // the user composes; tests can inject a deterministic no-op or recording closure.
        if prewarmHeadersOnInit {
            Task { [prewarmConnections = dependencies.prewarmConnections] in
                await prewarmConnections()
            }
        }

        // The app event bus is synchronous and actor-isolated. Framework
        // publishers use a separate asynchronous bridge at their boundaries.
        diContainer.appEventPublisher.publisher
            .sink { [weak self] event in
                guard case .appDidResumeAfterTimeout = event, let self else { return }
                let now = Date()
                self.diContainer.appRouteCoordinator.advanceSession(now: now)
                guard !self.diContainer.appRouteCoordinator.shouldSuppressTimeoutReset(now: now) else {
                    MerianLog.general.debug(
                        "Skipped session timeout reset because an explicit route is pending or was just applied."
                    )
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.handleSessionTimeoutReset(now: now)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Background Reset Policy

    /// Controls whether the staging state is preserved when the app enters the
    /// background. Staged content survives a brief background trip; an empty
    /// workspace resets to the default camera state after the session timeout.
    private var shouldPreserveStagingOnBackground: Bool {
        !stagedCapture.isEmpty
    }

    private func handleSessionTimeoutReset(now: Date = Date()) {
        if operationState.consumeExternalRouteTimeoutProtection(now: now) {
            MerianLog.general.debug(
                "Skipped session timeout reset because an external route was just opened."
            )
            return
        }

        resetModalsForSessionTimeout()
    }

    private func resetModalsForSessionTimeout() {
        activeSheet = nil
        operationState.clearPendingLocalSheet()
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
        pendingScansRecoveryContext = nil
        imageToCrop = nil
        editingCropIndex = nil

        guard !shouldPreserveStagingOnBackground else { return }
        clearStagedCaptureAndCropState(discardStagedMediaFiles: true)
        selectedPhotoItems.removeAll()
        cancelRefinementStaging()
    }
}
