import Combine
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ScansManager {
    #if DEBUG
    typealias SearchDebugEvent = ScansLibrarySearchDebugEvent
    #endif

    var searchQuery = ""
    var filteredScans: [LocalScanRecord] = []
    /// True only while an actual search or filter task is in flight.
    var isFiltering = false
    var activeCategoryFilter = "All"
    var filters = ScanLibraryFilters() {
        didSet {
            guard oldValue != filters else { return }
            performSearch(query: searchQuery, category: activeCategoryFilter)
        }
    }

    private(set) var unavailableExploreMediaScanIDs: Set<String> = []
    var isSelectionMode = false
    var selectedScans: Set<String> = []
    var isDownloading = false
    var toastMessage: ToastPayload?

    var sortOption: ScanSortOption = .newest {
        didSet {
            guard oldValue != sortOption else { return }
            performSearch(query: searchQuery)
        }
    }

    let maxBatchSelectionLimit = 20

    var allScans: [LocalScanRecord] = [] {
        didSet {
            searchCoordinator.replaceRecords(allScans, replacing: oldValue)
        }
    }

    private(set) var filterOptions = ScanLibraryFilterOptions()
    private(set) var orderedCategoryFilters =
        ["All"] + SearchCategoryBucket.libraryFilterPriority.map(\.title)

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var appSettings: AppSettings
    @ObservationIgnored private let dependencies: ScansLibraryDependencies
    @ObservationIgnored private let searchCoordinator: ScansLibrarySearchCoordinator

    #if DEBUG
    @ObservationIgnored var debugEventHandler: ((SearchDebugEvent) -> Void)? {
        didSet {
            searchCoordinator.debugEventHandler = debugEventHandler
        }
    }
    #endif

    init(
        appSettings: AppSettings? = nil,
        sharedPostIDProvider: @escaping (String) -> String? = {
            ScansLibraryDependencies.liveSharedPostID(for: $0)
        },
        eventStream: (any AppEventStreaming)? = nil
    ) {
        let dependencies = ScansLibraryDependencies.live(
            sharedPostID: { scanID in sharedPostIDProvider(scanID) },
            eventStream: eventStream
        )
        self.appSettings = appSettings ?? AppSettings.shared
        self.dependencies = dependencies
        searchCoordinator = ScansLibrarySearchCoordinator(
            sharedPostID: dependencies.sharedPostID
        )
        configureSearchCoordinator()
        observeEvents()
    }

    init(
        appSettings: AppSettings? = nil,
        dependencies: ScansLibraryDependencies
    ) {
        self.appSettings = appSettings ?? AppSettings.shared
        self.dependencies = dependencies
        searchCoordinator = ScansLibrarySearchCoordinator(
            sharedPostID: dependencies.sharedPostID
        )
        configureSearchCoordinator()
        observeEvents()
    }

    func bindSettings(_ appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    var hasActiveFilters: Bool {
        activeCategoryFilter != "All" || filters.hasAdvancedFilters
    }

    var activeFilterCount: Int {
        filters.activeAdvancedFilterCount + (activeCategoryFilter == "All" ? 0 : 1)
    }

    func clearFilters() {
        activeCategoryFilter = "All"
        filters.clear()
        performSearch(query: searchQuery)
    }

    func setUnavailableExploreMediaScanIDs(_ scanIDs: Set<String>) {
        guard unavailableExploreMediaScanIDs != scanIDs else { return }
        unavailableExploreMediaScanIDs = scanIDs

        if filters.explorePostFilters.contains(.unavailableMedia) {
            performSearch(query: searchQuery, category: activeCategoryFilter)
        }
    }

    func performSearch(query: String, category: String? = nil) {
        let trimmedText = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if let category {
            activeCategoryFilter = category
        } else if !trimmedText.isEmpty {
            activeCategoryFilter = "All"
        }

        isFiltering = true
        searchCoordinator.performSearch(
            query: query,
            category: activeCategoryFilter,
            filters: filters,
            unavailableExploreMediaScanIDs: unavailableExploreMediaScanIDs,
            sortOption: sortOption
        )
    }

    func toggleSelection(for scanID: String) -> Bool {
        guard !isDownloading else { return true }

        if selectedScans.contains(scanID) {
            selectedScans.remove(scanID)
            return true
        }

        guard selectedScans.count < maxBatchSelectionLimit else { return false }
        selectedScans.insert(scanID)
        return true
    }

    func selectAll() {
        guard !isDownloading else { return }

        let maximumScans = Array(filteredScans.prefix(maxBatchSelectionLimit))
        if selectedScans.count == maximumScans.count {
            selectedScans.removeAll()
        } else {
            selectedScans = Set(maximumScans.map(\.id))
        }
    }

    func exitSelectionMode() {
        guard !isDownloading else { return }

        isSelectionMode = false
        selectedScans.removeAll()
    }

    func getSelectedLocalRecords() -> [LocalScanRecord] {
        filteredScans.filter { selectedScans.contains($0.id) }
    }

    func batchShare(scans: [LocalScanRecord]) async {
        guard !isDownloading, !scans.isEmpty else { return }
        await dependencies.batchShare(scans)
    }

    func triggerSelectionFeedback() {
        dependencies.triggerSelectionFeedback()
    }

    func triggerMediumFeedback() {
        dependencies.triggerMediumFeedback()
    }

    func triggerLightFeedback() {
        dependencies.triggerLightFeedback()
    }

    func triggerErrorFeedback() {
        dependencies.triggerErrorFeedback()
    }

    func batchSaveMedia(scans: [LocalScanRecord]) async {
        guard !isDownloading, !scans.isEmpty else { return }
        isDownloading = true

        let result = await dependencies.batchSaveMedia(scans)

        isDownloading = false
        exitSelectionMode()
        if result.totalSaved > 0 {
            dependencies.triggerSuccessFeedback()
            showToast(.success(result.successMessage))
        } else {
            dependencies.triggerErrorFeedback()
            showToast(.error("No photos or videos could be saved"))
        }
    }

    func shareToExplore(scanId: String, modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let scan = try? modelContext.fetch(descriptor).first else {
            dependencies.triggerErrorFeedback()
            showToast(.warning("This scan is no longer available."))
            return
        }

        guard scan.isExploreShareEligible else {
            dependencies.triggerErrorFeedback()
            showToast(.warning("Reanalyze this scan before sharing to Explore."))
            return
        }

        do {
            let postID = try await dependencies.shareToExplore(scan)
            dependencies.storeSharedPostID(postID, scanId)
            dependencies.sendExploreShareChanged(scanId, postID)
            dependencies.triggerSuccessFeedback()
            showToast(.success("Shared to Explore"))
        } catch {
            dependencies.triggerErrorFeedback()
            showToast(.error(dependencies.exploreShareErrorMessage(error)))
        }
    }

    #if DEBUG
    func waitForCurrentSearchCompletionForTesting() async -> SearchDebugEvent? {
        await searchCoordinator.waitForCurrentSearchCompletionForTesting()
    }
    #endif

    private func configureSearchCoordinator() {
        searchCoordinator.setHandlers(
            onFilterIndexUpdated: { [weak self] options, categories in
                guard let self else { return }
                filterOptions = options
                orderedCategoryFilters = categories
            },
            onSearchCompleted: { [weak self] scans, _ in
                guard let self else { return }
                withAnimation {
                    self.filteredScans = scans
                    self.isFiltering = false
                }
            }
        )
    }

    private func observeEvents() {
        dependencies.events
            .sink { [weak self] event in
                switch event {
                case .scanSearchIndexInvalidated(let scanID),
                     .exploreShareStateChanged(let scanID, _):
                    self?.handleSearchIndexInvalidation(scanID: scanID)
                case .exploreShareStateReconciled:
                    self?.handleExploreShareStateReconciliation()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func handleSearchIndexInvalidation(scanID: String) {
        guard searchCoordinator.forceReindex(scanID: scanID) else { return }
        performSearch(query: searchQuery, category: activeCategoryFilter)
    }

    private func handleExploreShareStateReconciliation() {
        searchCoordinator.refreshExploreShareState()
        performSearch(query: searchQuery, category: activeCategoryFilter)
    }

    private func showToast(_ toast: ToastPayload) {
        toastMessage = toast
    }
}
