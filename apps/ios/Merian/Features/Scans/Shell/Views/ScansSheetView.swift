import SwiftData
import SwiftUI

struct ScansSheetView: View {
    let recoveryContext: ExploreMediaRecoveryRouteContext?

    init(
        recoveryContext: ExploreMediaRecoveryRouteContext? = nil,
        initiallyShowsNonBiologicalScans: Bool = false
    ) {
        self.recoveryContext = recoveryContext
        let initialNavigation = ScansSheetInitialNavigation(
            initiallyShowsNonBiologicalScans:
                initiallyShowsNonBiologicalScans
        )
        _navigationPath = State(
            initialValue: NavigationPath(initialNavigation.routes)
        )
        _activeTab = State(initialValue: initialNavigation.activeTab)
        _shellViewModel = State(initialValue: ScansShellViewModel())
    }

    @State private var searchManager = ScansManager()
    @State private var shellViewModel: ScansShellViewModel

    @Query(sort: \LocalScanRecord.timestamp, order: .reverse)
    private var rawRecords: [LocalScanRecord]
    @Query(
        filter: #Predicate<ScanCollection> { !$0.isPendingDeletion },
        sort: \ScanCollection.createdAt,
        order: .reverse
    )
    private var collections: [ScanCollection]

    @Environment(\.modelContext) private var modelContext
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var navigationPath = NavigationPath()
    @State private var activeTab: ScansTab = .library
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    @State private var newlyCreatedCollection: ScanCollection?
    @State private var hiddenSmartCollectionIDs =
        SmartCollectionPreferences.hiddenIDs()
    @State private var scanToDelete: String?
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false
    @State private var showSelectionLimitAlert = false
    @State private var isSearchFocused = false

    private var biologicalRecords: [LocalScanRecord] {
        rawRecords.filter { $0.isBiological == true }
    }

    private var filterCategories: [String] {
        searchManager.orderedCategoryFilters
    }

    private var prefetchThumbnailSize: Int {
        let screenWidth = UIScreen.main.bounds.width
        let gridColumns = appSettings.gridColumns
        let spacing = CGFloat(2 * (gridColumns - 1))
        let cellWidth = (screenWidth - spacing) / CGFloat(gridColumns)
        return Int(cellWidth * UIScreen.main.scale)
    }

    var body: some View {
        navigationStack
            .onAppear(perform: handleAppear)
            .onChange(of: appSettings.hasUnseenScan) { _, isSet in
                handleUnseenScanBadgeChange(isSet)
            }
            .onChange(of: rawRecords) { _, _ in
                handleRawRecordsChange()
            }
            .onChange(of: shellViewModel.exploreMediaIncidentSummary) { _, summary in
                searchManager.setUnavailableExploreMediaScanIDs(
                    summary.unavailablePublishedScanIDs
                )
                shellViewModel
                    .synchronizeUnavailableMediaOverviewPreference()
            }
            .onChange(of: shellViewModel.currentExploreMediaOwnerID) { _, _ in
                shellViewModel
                    .synchronizeUnavailableMediaOverviewPreference()
            }
            .onChange(of: offlineQueueManager.unsyncedItemsCount) { _, _ in
                handleOfflineQueueCountChange()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onReceive(shellViewModel.libraryEvents) { event in
                guard case .scanLibraryChanged = event else { return }
                handleLibraryDidUpdate()
            }
            .task(id: queuedRefreshTaskID) { @MainActor in
                await shellViewModel.refreshQueuedScansUntilCancelled(
                    modelContainer: modelContext.container,
                    offlineQueueManager: offlineQueueManager
                )
            }
            .task(id: exploreMediaIncidentRefreshID) { @MainActor in
                await refreshExploreMediaIncidents()
            }
    }

    private var navigationStack: some View {
        NavigationStack(path: $navigationPath) {
            tabPager
                .modifier(
                    ScansSheetPresentationModifier(
                        searchManager: searchManager,
                        activeTab: $activeTab,
                        isSearchFocused: $isSearchFocused,
                        showNewCollectionAlert: $showNewCollectionAlert,
                        newCollectionName: $newCollectionName,
                        scanToDelete: $scanToDelete,
                        showDeleteConfirmation: $showDeleteConfirmation,
                        showBatchDeleteConfirmation:
                            $showBatchDeleteConfirmation,
                        showSelectionLimitAlert: $showSelectionLimitAlert,
                        toastMessage: $searchManager.toastMessage,
                        isDownloading: $searchManager.isDownloading,
                        modelContext: modelContext,
                        onBatchDelete: handleBatchDelete,
                        onCollectionCreated: {
                            newlyCreatedCollection = $0
                        }
                    )
                )
                .toolbar {
                    ScansSheetToolbar(
                        searchManager: searchManager,
                        activeTab: $activeTab,
                        dismiss: dismiss,
                        onNewCollection: {
                            showNewCollectionAlert = true
                        },
                        onShare: shareSelectedScans,
                        onDownload: downloadSelectedScans,
                        onDelete: {
                            showBatchDeleteConfirmation = true
                        }
                    )
                }
                .toolbarBackground(
                    searchManager.isSelectionMode ? .visible : .hidden,
                    for: .navigationBar
                )
                .toolbarBackground(
                    searchManager.isSelectionMode ? .visible : .hidden,
                    for: .bottomBar
                )
                .navigationTitle(
                    activeTab == .collections ? "Collections" : "Scans"
                )
                .navigationDestination(for: ScanInsightRoute.self) { route in
                    localInsightDestination(for: route)
                }
                .navigationDestination(
                    for: QueuedScanInsightRoute.self
                ) { route in
                    queuedInsightDestination(for: route)
                }
                .navigationDestination(
                    for: SpeciesDictionaryRoute.self
                ) { route in
                    SpeciesDictionaryPageContentView(
                        scientificName: route.scientificName,
                        speciesId: route.speciesId,
                        entryPoint: route.entryPoint,
                        showsCloseButton: false
                    )
                }
                .navigationDestination(
                    for: ScansNavigationRoute.self,
                    destination: scansNavigationDestination
                )
        }
    }

    private var tabPager: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    libraryTab
                    collectionsTab
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(
                id: Binding(
                    get: { activeTab },
                    set: { if let value = $0 { activeTab = value } }
                )
            )
            .task(id: navigationPath.isEmpty) { @MainActor in
                guard navigationPath.isEmpty else { return }
                await Task.yield()
                guard navigationPath.isEmpty else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    scrollProxy.scrollTo(activeTab, anchor: .center)
                }
            }
        }
    }

    private var libraryTab: some View {
        ScansLibraryTabContent(
            searchManager: searchManager,
            filterCategories: filterCategories,
            queuedScans: shellViewModel.queuedScans,
            unavailableMediaScanCount: shellViewModel
                .exploreMediaIncidentSummary
                .unavailablePublishedScanCount,
            isUnavailableMediaOverviewVisible: shellViewModel
                .isUnavailableMediaOverviewVisible,
            isExploreMediaIncidentRefreshRunning: shellViewModel
                .isExploreMediaIncidentRefreshRunning,
            onRefreshExploreMediaIncidents:
                refreshExploreMediaIncidentsNow,
            onDismissUnavailableMediaOverview:
                dismissUnavailableMediaOverview,
            isSearchFocused: $isSearchFocused,
            onScanSelected: { record in
                navigationPath.append(
                    ScanInsightRoute(scanId: record.id)
                )
            },
            onQueuedScanSelected: { queuedScan in
                navigationPath.append(
                    QueuedScanInsightRoute(queuedScan: queuedScan)
                )
            },
            showSelectionLimitAlert: $showSelectionLimitAlert,
            scanToDelete: $scanToDelete,
            showDeleteConfirmation: $showDeleteConfirmation
        )
    }

    private var collectionsTab: some View {
        ScansCollectionsTabContent(
            searchManager: searchManager,
            isSearchFocused: isSearchFocused,
            scans: rawRecords,
            collections: collections,
            hiddenSmartCollectionIDs: hiddenSmartCollectionIDs,
            onHideSmartCollection: hideSmartCollection,
            newlyCreatedCollection: $newlyCreatedCollection
        )
    }

    @ViewBuilder
    private func scansNavigationDestination(
        for route: ScansNavigationRoute
    ) -> some View {
        switch route {
        case .nonBiologicalScans:
            NonBiologicalScansView(scans: rawRecords)
        case .privateScanMap:
            PrivateScanMapView { scanID in
                navigationPath.append(ScanInsightRoute(scanId: scanID))
            }
        }
    }

    private func localInsightDestination(
        for route: ScanInsightRoute
    ) -> some View {
        LocalScanInsightLoader(scanId: route.scanId) {
            InsightSheetView(
                isPresented: pushedDestinationBinding,
                initialScanId: route.scanId,
                inferenceEngine: inferenceEngine,
                presentationStyle: .embeddedInScansLibrary
            )
        }
    }

    private func queuedInsightDestination(
        for route: QueuedScanInsightRoute
    ) -> some View {
        InsightSheetView(
            isPresented: pushedDestinationBinding,
            queuedScan: route.queuedScan,
            inferenceEngine: inferenceEngine,
            presentationStyle: .embeddedInScansLibrary
        )
    }

    private var pushedDestinationBinding: Binding<Bool> {
        Binding(
            get: { true },
            set: { isPresented in
                if !isPresented, !navigationPath.isEmpty {
                    navigationPath.removeLast()
                }
            }
        )
    }

    private var queuedRefreshTaskID: String {
        shellViewModel.queuedRefreshTaskID(
            offlineQueueManager: offlineQueueManager
        )
    }

    private var exploreMediaIncidentRefreshID: String {
        shellViewModel.exploreMediaIncidentRefreshID(
            recoveryContext: recoveryContext,
            isOnline: offlineQueueManager.isOnline,
            scenePhaseKey: String(describing: scenePhase)
        )
    }

    private func handleAppear() {
        searchManager.bindSettings(appSettings)
        shellViewModel.applyInitialRecoveryFilterIfNeeded(
            recoveryContext: recoveryContext,
            searchManager: searchManager
        )
        shellViewModel.synchronizeUnavailableMediaOverviewPreference()
        refreshLibraryAndQueue()
        shellViewModel.kickQueuedScanPipelineIfNeeded(
            reason: "onAppear",
            offlineQueueManager: offlineQueueManager
        )
        shellViewModel.clearUnseenScanBadge(in: appSettings)
    }

    private func handleUnseenScanBadgeChange(_ isSet: Bool) {
        guard isSet else { return }
        shellViewModel.clearUnseenScanBadge(in: appSettings)
    }

    private func handleRawRecordsChange() {
        searchManager.allScans = biologicalRecords
        searchManager.performSearch(query: searchManager.searchQuery)
        refreshThumbnailPipeline()
    }

    private func handleOfflineQueueCountChange() {
        shellViewModel.refreshQueuedScans(in: modelContext.container)
        shellViewModel.syncStateFromStore(
            searchManager: searchManager,
            modelContext: modelContext
        )
        refreshThumbnailPipeline()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        refreshLibraryAndQueue()
        Task { await refreshExploreMediaIncidents() }
        shellViewModel.kickQueuedScanPipelineIfNeeded(
            reason: "scenePhase",
            offlineQueueManager: offlineQueueManager
        )
    }

    private func handleLibraryDidUpdate() {
        refreshLibraryAndQueue()
        Task { await refreshExploreMediaIncidents() }
        shellViewModel.kickQueuedScanPipelineIfNeeded(
            reason: "libraryDidUpdate",
            offlineQueueManager: offlineQueueManager
        )
    }

    private func refreshLibraryAndQueue() {
        shellViewModel.syncStateFromStore(
            searchManager: searchManager,
            modelContext: modelContext
        )
        shellViewModel.refreshQueuedScans(in: modelContext.container)
        refreshThumbnailPipeline()
    }

    private func refreshThumbnailPipeline() {
        shellViewModel.refreshThumbnailPipeline(
            records: searchManager.allScans,
            maxDimension: prefetchThumbnailSize,
            modelContainer: modelContext.container,
            isOnline: offlineQueueManager.isOnline
        )
    }

    private func refreshExploreMediaIncidents() async {
        await shellViewModel.refreshExploreMediaIncidents(
            recoveryContext: recoveryContext,
            searchManager: searchManager,
            isOnline: { offlineQueueManager.isOnline }
        )
    }

    private func refreshExploreMediaIncidentsNow() {
        shellViewModel.resetExploreMediaIncidentRefreshThrottle()
        Task { @MainActor in
            await refreshExploreMediaIncidents()
        }
    }

    private func dismissUnavailableMediaOverview() {
        withAnimation(.easeInOut(duration: 0.2)) {
            shellViewModel.dismissUnavailableMediaOverview()
        }
    }

    private func shareSelectedScans() {
        guard !searchManager.isDownloading else { return }
        let selectedScans = shellViewModel.selectedRecords(
            searchManager: searchManager,
            modelContext: modelContext
        )
        Task { await searchManager.batchShare(scans: selectedScans) }
    }

    private func downloadSelectedScans() {
        guard !searchManager.isDownloading else { return }
        let selectedScans = shellViewModel.selectedRecords(
            searchManager: searchManager,
            modelContext: modelContext
        )
        Task { await searchManager.batchSaveMedia(scans: selectedScans) }
    }

    private func handleBatchDelete() {
        shellViewModel.deleteSelectedRecords(
            searchManager: searchManager,
            modelContext: modelContext
        )
    }

    private func hideSmartCollection(_ snapshot: SmartCollectionSnapshot) {
        hiddenSmartCollectionIDs = SmartCollectionPreferences.hide(
            id: snapshot.id
        )
    }
}

private struct QueuedScanInsightRoute: Hashable {
    let queuedScan: QueuedScanContext

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.queuedScan.id == rhs.queuedScan.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(queuedScan.id)
    }
}
