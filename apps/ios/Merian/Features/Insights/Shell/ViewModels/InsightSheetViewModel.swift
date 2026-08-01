import SafariServices
import SwiftData
import SwiftUI

enum InsightExplorePresentationTarget: Equatable {
    case automatic
    case post
    case communityRequest
}

enum CandidateSwipePresentationSource: Equatable {
    case standard
    case identificationConcern
}

/// Defines the unified local state graph and primary business logic orchestrating the `InsightSheetView` presentation and data actions.
@MainActor
@Observable
final class InsightSheetViewModel {

    // MARK: - Init

    /// Allows `InsightSheetView` to seed queued scan state at `@State`
    /// initialization time before the sheet finishes wiring dependencies.
    init(
        queuedContext: QueuedScanContext? = nil,
        inferenceEngine: InferenceEngine? = nil,
        appSettings: AppSettings? = nil,
        fieldTripContributionLoader: @escaping (String) async throws -> [FieldTripScanContribution] = {
            try await MerianNetworkClient.shared.getFieldTripScanContributions(scanId: $0)
        },
        fieldTripAuthenticationResolver: @MainActor @escaping () -> Bool = {
            SupabaseManager.shared.isAuthenticated
        },
        fieldTripAvailabilityResolver: @MainActor @escaping () -> Bool = {
            FeatureFlags.isEnabled(.fieldTrips)
        },
        fieldTripEventsAvailabilityResolver: @MainActor @escaping () -> Bool = {
            FieldTripEventsAvailability.isEnabled
        }
    ) {
        self.queuedContext = queuedContext
        self.inferenceEngine = inferenceEngine
        self.appSettings = appSettings ?? AppSettings.shared
        self.fieldTripContributionLoader = fieldTripContributionLoader
        self.fieldTripAuthenticationResolver = fieldTripAuthenticationResolver
        self.fieldTripAvailabilityResolver = fieldTripAvailabilityResolver
        self.fieldTripEventsAvailabilityResolver = fieldTripEventsAvailabilityResolver
        self.cachedActiveMedia = queuedContext?.capturedMediaSnapshot.activeScanMedia
    }

    var toastActionTitle: String?
    var toastAction: (() -> Void)?

    /// Wipes all memory-retained states that persist across SwiftUI sheet presentations since `activeSheet == .insight` evaluates to identical IDs natively.
    func reset() {
        scanBoundActionGeneration &+= 1
        sharedExploreStateRevision &+= 1
        sharedExploreStateRequestToken &+= 1
        fieldTripContributionRequestToken &+= 1
        boundFieldNotesScanId = nil
        state = UIState()
        toastActionTitle = nil
        toastAction = nil
        activeLocalRecord = nil
        activeLocalRecordId = nil
        toolbarRecordSnapshot = nil
        queuedContext = nil
        cachedActiveMedia = nil
        fieldTripScanContributions = []
        isLoadingFieldTripScanContributions = false
    }

    // MARK: - Internal Cached State
    /// An in-memory cache of the successfully decoded `ActiveScanMedia` representing the user's media.
    /// Safely decoded exactly once within lifecycle mappings (`init` and `fetchLocalRecord`) to prevent
    /// main-thread thrashing on layout changes where the framework routinely interrogates boundary sizes.
    var cachedActiveMedia: ActiveScanMedia?
    @ObservationIgnored var scanBoundActionGeneration: UInt64 = 0
    @ObservationIgnored var sharedExploreStateRevision: UInt64 = 0
    @ObservationIgnored var sharedExploreStateRequestToken: UInt64 = 0
    @ObservationIgnored var boundFieldNotesScanId: String?
    @ObservationIgnored var fieldTripContributionRequestToken: UInt64 = 0
    @ObservationIgnored var appSettings: AppSettings
    @ObservationIgnored private var fieldTripContributionLoader: (String) async throws -> [FieldTripScanContribution]
    @ObservationIgnored private var fieldTripAuthenticationResolver: @MainActor () -> Bool
    @ObservationIgnored private var fieldTripAvailabilityResolver: @MainActor () -> Bool
    @ObservationIgnored private var fieldTripEventsAvailabilityResolver: @MainActor () -> Bool

    // MARK: - Interface State
    struct UIState: Equatable {
        var showBottomBarTools = false
        var isCommonNameScrolledPast = false
        var isTopScrollEdgeEffectHidden = true
        var isFieldNotesSheetPresented = false
        var fieldNotesPresentationScanId: String?
        var fieldNotesPresentationGeneration: UInt64?
        var isFlagIssuePresented = false
        var showDeleteConfirmation = false
        var showMediaSaveAlert = false
        var lastMediaSaveResult = MediaSaveResult()
        var showNewCollectionAlert = false
        var isInsightChatSheetPresented = false
        var isCandidateSwipePresented = false
        var candidateSwipePresentationSource: CandidateSwipePresentationSource = .standard
        var candidateSwipePresentationScanId: String?
        var candidateSwipePresentationGeneration: UInt64?
        var candidateSwipeEnginePresentationGeneration: UInt64?
        var showPaywall = false
        var toastMessage: String?
        var newCollectionName = ""
        var preferredCommonName: String?
        var isNamePickerPresented = false
        var isSafariPresented = false
        var selectedWikiURL: URL?
        var safariPresentationScanId: String?
        var safariPresentationGeneration: UInt64?
        var isSavingMedia = false
        var isAudioBoostEnabled = false
        var audioBoostActionToken: UUID?
        var isSharingToExplore = false
        var isUpdatingExplorePostContent = false
        var isUpdatingExploreFieldNotes = false
        var isRequestingCommunityIdentification = false
        var isExplorePostComposerPresented = false
        var explorePostComposerPresentationScanId: String?
        var explorePostComposerPresentationGeneration: UInt64?
        var explorePostComposerPresentationPostId: String?
        var isCommunityRequestSheetPresented = false
        var communityRequestPresentationScanId: String?
        var communityRequestPresentationGeneration: UInt64?
        var communityRequestPresentationRequestId: String?
        var showExploreOnboarding = false
        var exploreOnboardingPresentationScanId: String?
        var exploreOnboardingPresentationGeneration: UInt64?
        var sharedExplorePostId: String?
        var sharedCommunityIdentificationRequestId: String?
        var sharedCommunityIdentificationStatus: CommunityIdentificationRequestStatus?
        var isExploreFeedVisible = false
        var sharedExploreHashtags: [String] = []
        var sharedExploreLocationSharing: ExplorePostLocationSharing?
        var exploreFieldNotesArePublic = false
        var showExploreSheet = false
        var explorePresentationTarget: InsightExplorePresentationTarget = .automatic
        var explorePresentationScanId: String?
        var explorePresentationGeneration: UInt64?
        var fieldNotesText = ""
        var dismissedFieldNotesCardScanId: String?
    }

    var state = UIState()

    private(set) var fieldTripScanContributions: [FieldTripScanContribution] = []
    private(set) var isLoadingFieldTripScanContributions = false

    func invalidateFieldTripScanContributions() {
        fieldTripContributionRequestToken &+= 1
        fieldTripScanContributions = []
        isLoadingFieldTripScanContributions = false
    }

    func loadFieldTripScanContributions(
        scanId: String?,
        expectedGeneration: UInt64? = nil
    ) async {
        guard expectedGeneration == nil ||
                expectedGeneration == scanBoundActionGeneration,
              let scanId,
              persistentScanId?
                .caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        fieldTripContributionRequestToken &+= 1
        let requestToken = fieldTripContributionRequestToken
        fieldTripScanContributions = []

        guard fieldTripAvailabilityResolver(),
              fieldTripAuthenticationResolver(),
              queuedContext == nil,
              inferenceEngine?.speciesData?.isBiological == true,
              !scanId.isEmpty else {
            isLoadingFieldTripScanContributions = false
            return
        }

        isLoadingFieldTripScanContributions = true
        defer {
            if requestToken == fieldTripContributionRequestToken {
                isLoadingFieldTripScanContributions = false
            }
        }

        do {
            let contributions = try await fieldTripContributionLoader(scanId)
            guard requestToken == fieldTripContributionRequestToken,
                  expectedGeneration == nil ||
                    expectedGeneration == scanBoundActionGeneration,
                  persistentScanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame else {
                return
            }
            fieldTripScanContributions = contributions.filter {
                $0.sourceKind == .standardOuting || fieldTripEventsAvailabilityResolver()
            }
        } catch {
            guard requestToken == fieldTripContributionRequestToken else { return }
            fieldTripScanContributions = []
            MerianLog.general.debug(
                "Insight Field trip contributions unavailable: \(error, privacy: .private)"
            )
        }
    }

    func presentCandidateSwipe(
        source: CandidateSwipePresentationSource = .standard,
        expectedScanId: String? = nil,
        expectedGeneration: UInt64? = nil
    ) {
        if let expectedGeneration,
           expectedGeneration != scanBoundActionGeneration {
            return
        }
        let targetScanId = expectedScanId ?? presentedSpeciesScanId
        guard let targetScanId else { return }
        if expectedScanId != nil,
           !isPresentingLocalRecord(
               scanId: targetScanId,
               generation: expectedGeneration
           ) {
            return
        }
        guard presentedSpeciesScanId?
            .caseInsensitiveCompare(targetScanId) == .orderedSame else {
            return
        }
        state.candidateSwipePresentationSource = source
        state.candidateSwipePresentationScanId = targetScanId
        state.candidateSwipePresentationGeneration = scanBoundActionGeneration
        state.candidateSwipeEnginePresentationGeneration =
            inferenceEngine?.scanPresentationGeneration
        state.isCandidateSwipePresented = true
    }

    func bindSettings(_ appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    // MARK: - SwiftData Status
    var activeLocalRecord: LocalScanRecord?
    var activeLocalRecordId: String?
    var toolbarRecordSnapshot: InsightToolbarRecordSnapshot?

    // MARK: - Image Engine Dependencies
    var inferenceEngine: InferenceEngine?

    // MARK: - Queued Scan Context
    /// Non-nil when Insight is presenting a queued scan from `LibraryView` rather than a live
    /// foreground inference result. Stored as a value-type `QueuedScanContext` — never a live
    /// `OfflineQueuedScan` reference — so queue deletion and in-place result handoff cannot
    /// detach data still needed by computed properties.
    var queuedContext: QueuedScanContext?
}
