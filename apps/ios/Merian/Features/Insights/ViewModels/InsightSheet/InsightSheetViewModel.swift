import SafariServices
import SwiftData
import SwiftUI

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
        appSettings: AppSettings? = nil
    ) {
        self.queuedContext = queuedContext
        self.inferenceEngine = inferenceEngine
        self.appSettings = appSettings ?? AppSettings.shared
        self.cachedActiveMedia = queuedContext?.capturedMediaSnapshot.activeScanMedia
    }

    var toastActionTitle: String?
    var toastAction: (() -> Void)?

    /// Wipes all memory-retained states that persist across SwiftUI sheet presentations since `activeSheet == .insight` evaluates to identical IDs natively.
    func reset() {
        sharedExploreStateRevision = 0
        sharedExploreStateRequestToken = 0
        boundFieldNotesScanId = nil
        state = UIState()
        toastActionTitle = nil
        toastAction = nil
        activeLocalRecord = nil
        activeLocalRecordId = nil
        toolbarRecordSnapshot = nil
        queuedContext = nil
        cachedActiveMedia = nil
    }

    // MARK: - Internal Cached State
    /// An in-memory cache of the successfully decoded `ActiveScanMedia` representing the user's media.
    /// Safely decoded exactly once within lifecycle mappings (`init` and `fetchLocalRecord`) to prevent
    /// main-thread thrashing on layout changes where the framework routinely interrogates boundary sizes.
    var cachedActiveMedia: ActiveScanMedia?
    @ObservationIgnored var sharedExploreStateRevision: UInt64 = 0
    @ObservationIgnored var sharedExploreStateRequestToken: UInt64 = 0
    @ObservationIgnored var boundFieldNotesScanId: String?
    @ObservationIgnored var appSettings: AppSettings

    // MARK: - Interface State
    struct UIState: Equatable {
        var showCelebration = false
        var showBottomBarTools = false
        var isCommonNameScrolledPast = false
        var isFieldNotesSheetPresented = false
        var isFlagIssuePresented = false
        var isIdentificationFlagPresented = false
        var showDeleteConfirmation = false
        var showSaveSuccessAlert = false
        var showNewCollectionAlert = false
        var isCandidateSwipePresented = false
        var showPaywall = false
        var toastMessage: String?
        var newCollectionName = ""
        var preferredCommonName: String?
        var isNamePickerPresented = false
        var isSafariPresented = false
        var selectedWikiURL: URL?
        var isSavingPhotos = false
        var isSharingToExplore = false
        var isUpdatingExplorePostContent = false
        var isUpdatingExploreFieldNotes = false
        var showExploreOnboarding = false
        var sharedExplorePostId: String?
        var sharedExploreHashtags: [String] = []
        var sharedExploreLocationSharing: ExplorePostLocationSharing?
        var exploreFieldNotesArePublic = false
        var showExploreSheet = false
        var fieldNotesText = ""
        var dismissedFieldNotesCardScanId: String?
    }

    var state = UIState()

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
