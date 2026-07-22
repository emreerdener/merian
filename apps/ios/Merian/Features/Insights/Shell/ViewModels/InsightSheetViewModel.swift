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
            FieldTripsAvailability.isEnabled
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
        sharedExploreStateRevision = 0
        sharedExploreStateRequestToken = 0
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
        var isFlagIssuePresented = false
        var showDeleteConfirmation = false
        var showSaveSuccessAlert = false
        var showNewCollectionAlert = false
        var isInsightChatSheetPresented = false
        var isCandidateSwipePresented = false
        var candidateSwipePresentationSource: CandidateSwipePresentationSource = .standard
        var showPaywall = false
        var toastMessage: String?
        var newCollectionName = ""
        var preferredCommonName: String?
        var isNamePickerPresented = false
        var isSafariPresented = false
        var selectedWikiURL: URL?
        var isSavingPhotos = false
        var isAudioBoostEnabled = false
        var audioBoostActionToken: UUID?
        var isSharingToExplore = false
        var isUpdatingExplorePostContent = false
        var isUpdatingExploreFieldNotes = false
        var isRequestingCommunityIdentification = false
        var isExplorePostComposerPresented = false
        var isCommunityRequestSheetPresented = false
        var showExploreOnboarding = false
        var sharedExplorePostId: String?
        var sharedCommunityIdentificationRequestId: String?
        var sharedCommunityIdentificationStatus: CommunityIdentificationRequestStatus?
        var isExploreFeedVisible = false
        var sharedExploreHashtags: [String] = []
        var sharedExploreLocationSharing: ExplorePostLocationSharing?
        var exploreFieldNotesArePublic = false
        var showExploreSheet = false
        var explorePresentationTarget: InsightExplorePresentationTarget = .automatic
        var fieldNotesText = ""
        var dismissedFieldNotesCardScanId: String?
    }

    var state = UIState()

    private(set) var fieldTripScanContributions: [FieldTripScanContribution] = []
    private(set) var isLoadingFieldTripScanContributions = false

    func loadFieldTripScanContributions(scanId: String?) async {
        fieldTripContributionRequestToken &+= 1
        let requestToken = fieldTripContributionRequestToken
        fieldTripScanContributions = []

        guard fieldTripAvailabilityResolver(),
              fieldTripAuthenticationResolver(),
              queuedContext == nil,
              inferenceEngine?.speciesData?.isBiological == true,
              let scanId,
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
                  persistentScanId == scanId else { return }
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

    func presentCandidateSwipe(source: CandidateSwipePresentationSource = .standard) {
        state.candidateSwipePresentationSource = source
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
    /// Non-nil when the sheet is presenting a queued scan from `LibraryView` rather than a
    /// live inference result. Stored as a value-type `QueuedScanContext` — never a live
    /// `OfflineQueuedScan` reference — so computed properties cannot access a zombie `@Model`
    /// during SwiftUI's sheet dismissal animation after `context.delete()` fires.
    var queuedContext: QueuedScanContext?
}
