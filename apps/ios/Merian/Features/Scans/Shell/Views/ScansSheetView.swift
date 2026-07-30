import SwiftData
import SwiftUI

enum ScansTab {
    case library
    case collections
}

struct ScansSheetView: View {
    // MARK: - App State Engines
    @State private var searchManager = ScansManager()

    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var rawRecords: [LocalScanRecord]
    private var allRecords: [LocalScanRecord] {
        rawRecords.filter { $0.isBiological == true }
    }
    @Query(filter: #Predicate<ScanCollection> { !$0.isDeleted }, sort: \ScanCollection.createdAt, order: .reverse) private var collections: [ScanCollection]

    /// Manually-managed queue list, bypassing `@Query` for live updates while the sheet is open.
    ///
    /// SwiftData's `@Query` in a presented `.sheet` does not reliably re-evaluate when
    /// `ModelContext.save()` fires while the app is backgrounded — the sheet's render cycle
    /// is paused and the save notification may be dropped before the view processes it.
    /// On foreground return the pending overlay would remain stuck until the user closes and
    /// reopens the sheet.
    ///
    /// Driving this array from `OfflineQueueManager.unsyncedItemsCount` (an `@Observable`
    /// property) guarantees delivery: `@Observable` change notifications are queued and
    /// processed on the next active render pass regardless of when the mutation happened.
    ///
    /// **Value-type snapshots**: `QueuedScanSnapshot` (not `OfflineQueuedScan`) prevents the
    /// fatal "backing data detached from context" crash. `LazyVGrid` accesses tile data lazily —
    /// if the `@Model` backing is torn down by `context.delete()` before the grid renders a row,
    /// accessing an unfaulted attribute crashes. Copying the needed data into a value type at
    /// fetch time means SwiftData deletions never affect what the grid has already captured.
    @State private var queuedScans: [QueuedScanSnapshot] = []
    @State private var lastQueuedPipelineKickAt = Date.distantPast
    @State private var exploreMediaIncidents: [ExploreMediaIncident] = []
    @State private var lastExploreMediaIncidentRefreshAt = Date.distantPast
    @State private var isExploreMediaIncidentRefreshRunning = false
    @State private var needsTrailingExploreMediaIncidentRefresh = false

    @Environment(\.modelContext) private var modelContext
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Navigation Control
    @State private var navigationPath = NavigationPath()
    @State private var activeTab: ScansTab = .library
    
    // MARK: - Component State
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    @State private var newlyCreatedCollection: ScanCollection?
    @State private var hiddenSmartCollectionIDs = SmartCollectionPreferences.hiddenIDs()
    
    @State private var scanToDelete: String?
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false
    @State private var showSelectionLimitAlert = false
    @State private var isSearchFocused = false
    @State private var isNonBiologicalScansPresented = false
    
    private var filterCategories: [String] {
        searchManager.orderedCategoryFilters
    }

    private var prefetchThumbnailSize: Int {
        let screenWidth = UIScreen.main.bounds.width
        let gridColumns = appSettings.gridColumns
        let cellWidth = (screenWidth - CGFloat(2 * (gridColumns - 1))) / CGFloat(gridColumns)
        return Int(cellWidth * UIScreen.main.scale)
    }
    
    // MARK: - Core View Builder
    var body: some View {
        navigationStack
        .onReceive(AppEventPublisher.shared.publisher) { event in
            handleAppEvent(event)
        }
        .onAppear {
            handleAppear()
        }
        // If a scan completes while this sheet is already visible, the badge fires but
        // the user is already looking at their library — clear it immediately.
        .onChange(of: appSettings.hasUnseenScan) { _, isSet in
            handleUnseenScanBadgeChange(isSet)
        }
        .onChange(of: rawRecords) { _, _ in
            handleRawRecordsChange()
        }
        .onChange(of: offlineQueueManager.unsyncedItemsCount) { _, _ in
            // `@Observable` change notifications are queued and delivered on the next active
            // render pass — reliable even when the app was backgrounded when the scan
            // completed and the @Query save notification was never processed by the sheet.
            handleOfflineQueueCountChange()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onReceive(ScanLibraryEvents.libraryDidUpdatePublisher()) { _ in
            handleLibraryDidUpdate()
        }
        .task(id: queuedRefreshTaskID) { @MainActor in
            await refreshQueuedScansUntilCancelled()
        }
        .task(id: exploreMediaIncidentRefreshID) { @MainActor in
            await refreshExploreMediaIncidents()
        }
    }

    private var navigationStack: some View {
        NavigationStack(path: $navigationPath) {
            tabPager
            .modifier(ScansSheetModifiers(
                searchManager: searchManager, activeTab: $activeTab, isSearchFocused: $isSearchFocused,
                showNewCollectionAlert: $showNewCollectionAlert,
                newCollectionName: $newCollectionName, scanToDelete: $scanToDelete,
                showDeleteConfirmation: $showDeleteConfirmation, showBatchDeleteConfirmation: $showBatchDeleteConfirmation,
                showSelectionLimitAlert: $showSelectionLimitAlert, toastMessage: $searchManager.toastMessage,
                isDownloading: $searchManager.isDownloading, dismiss: dismiss, modelContext: modelContext,
                onBatchDelete: handleBatchDelete, onCollectionCreated: { newlyCreatedCollection = $0 }
            ))
            .toolbar {
                ScansSheetToolbar(
                    searchManager: searchManager, activeTab: $activeTab,
                    dismiss: dismiss,
                    onNewCollection: { showNewCollectionAlert = true },
                    onShare: shareSelectedScans,
                    onDownload: downloadSelectedScans,
                    onDelete: { showBatchDeleteConfirmation = true }
                )
            }
            .toolbarBackground(searchManager.isSelectionMode ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(searchManager.isSelectionMode ? .visible : .hidden, for: .bottomBar)
            .navigationDestination(for: ScanInsightRoute.self) { route in
                localInsightDestination(for: route)
            }
            .navigationDestination(for: QueuedScanInsightRoute.self) { route in
                queuedInsightDestination(for: route)
            }
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false
                )
            }
            .navigationDestination(isPresented: $isNonBiologicalScansPresented) {
                NonBiologicalScansView()
            }
        }
    }

    private var tabPager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                LibraryTabContent(
                    searchManager: searchManager,
                    filterCategories: filterCategories,
                    queuedScans: queuedScans,
                    exploreMediaIncidents: exploreMediaIncidents,
                    isSearchFocused: $isSearchFocused,
                    onScanSelected: { record in
                        navigationPath.append(ScanInsightRoute(scanId: record.id))
                    },
                    onQueuedScanSelected: { queuedScan in
                        navigationPath.append(QueuedScanInsightRoute(queuedScan: queuedScan))
                    },
                    showSelectionLimitAlert: $showSelectionLimitAlert,
                    scanToDelete: $scanToDelete,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
                CollectionsTabContent(
                    searchManager: searchManager,
                    isSearchFocused: isSearchFocused,
                    collections: collections,
                    hiddenSmartCollectionIDs: hiddenSmartCollectionIDs,
                    onHideSmartCollection: hideSmartCollection,
                    newlyCreatedCollection: $newlyCreatedCollection
                )
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding(
            get: { activeTab },
            set: { if let val = $0 { activeTab = val } }
        ))
    }

    private func localInsightDestination(for route: ScanInsightRoute) -> some View {
        InsightSheetView(
            isPresented: Binding(
                get: { true },
                set: { isPresented in
                    if !isPresented {
                        if !navigationPath.isEmpty {
                            navigationPath.removeLast()
                        }
                    }
                }
            ),
            initialScanId: route.scanId,
            inferenceEngine: inferenceEngine,
            presentationStyle: .embeddedInScansLibrary
        )
    }

    private func queuedInsightDestination(for route: QueuedScanInsightRoute) -> some View {
        InsightSheetView(
            isPresented: Binding(
                get: { true },
                set: { isPresented in
                    if !isPresented, !navigationPath.isEmpty {
                        navigationPath.removeLast()
                    }
                }
            ),
            queuedScan: route.queuedScan,
            inferenceEngine: inferenceEngine,
            presentationStyle: .embeddedInScansLibrary
        )
    }

    private func handleAppEvent(_ event: AppEvent) {
        if case .requestOpenNonBiologicalScansIntent = event {
            activeTab = .collections
            // Dispatch async to allow the tab change to render before pushing the navigation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNonBiologicalScansPresented = true
            }
        }
    }

    private func hideSmartCollection(_ snapshot: SmartCollectionSnapshot) {
        hiddenSmartCollectionIDs = SmartCollectionPreferences.hide(id: snapshot.id)
    }

    private func handleAppear() {
        searchManager.bindSettings(appSettings)
        refreshLibraryAndQueue()
        if !queuedScans.isEmpty {
            kickQueuedScanPipeline(reason: "onAppear")
        }
        appSettings.hasUnseenScan = false
        AppIconBadgeCoordinator.updateAppIconBadge()
    }

    private func handleUnseenScanBadgeChange(_ isSet: Bool) {
        guard isSet else { return }
        appSettings.hasUnseenScan = false
        AppIconBadgeCoordinator.updateAppIconBadge()
    }

    private func handleRawRecordsChange() {
        syncStateLocally()
        refreshThumbnailPipeline()
    }

    private func handleOfflineQueueCountChange() {
        refreshQueuedScans()
        syncStateFromStore()
        refreshThumbnailPipeline()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        refreshLibraryAndQueue()
        Task { await refreshExploreMediaIncidents() }
        if !queuedScans.isEmpty {
            kickQueuedScanPipeline(reason: "scenePhase")
        }
    }

    private func handleLibraryDidUpdate() {
        refreshLibraryAndQueue()
        Task { await refreshExploreMediaIncidents() }
        if !queuedScans.isEmpty {
            kickQueuedScanPipeline(reason: "libraryDidUpdate")
        }
    }

    @MainActor
    private func refreshQueuedScansUntilCancelled() async {
        guard !queuedScans.isEmpty else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            refreshQueuedScans()
        }
    }

    private func refreshLibraryAndQueue() {
        syncStateFromStore()
        refreshQueuedScans()
        refreshThumbnailPipeline()
    }

    private func shareSelectedScans() {
        let selectedScans = selectedLocalRecordsFromStore()
        Task { await searchManager.batchShare(scans: selectedScans) }
    }

    private func downloadSelectedScans() {
        let selectedScans = selectedLocalRecordsFromStore()
        Task { await searchManager.batchSavePhotos(scans: selectedScans) }
    }
    
    // MARK: - Data Refresh

    /// Synchronizes native SwiftData reactive arrays with the offline search manager engine.
    private func syncStateLocally() {
        searchManager.allScans = allRecords
        searchManager.performSearch(query: searchManager.searchQuery)
    }

    /// Fires leading thumbnail work before LazyVGrid renders, filling the first visible
    /// screen (6 rows × 3 columns on the largest supported iPhone) with no gray placeholders.
    private func prefetchLeadingThumbnails(from records: [LocalScanRecord]) {
        let slice = Array(records.prefix(18).map(\.scanThumbnailPresentation))
        let imageRecords = slice.map { presentation in
            (imagePath: presentation.imagePath, fallbackUrl: presentation.fallbackImageUrl)
        }

        LocalImageLoader.shared.prefetch(records: imageRecords, maxDimension: prefetchThumbnailSize)
        AudioSpectrogramThumbnailLoader.shared.prefetch(
            audioPaths: slice.compactMap(\.audioPath),
            maxDimension: prefetchThumbnailSize
        )
    }

    private func refreshThumbnailPipeline() {
        let records = searchManager.allScans
        LocalScanMediaRecoveryResolver.registerRecoveryMappings(for: records)
        prefetchLeadingThumbnails(from: records)
        enqueueRecoverableCloudImages(from: records)

        let backfillCandidates = records.compactMap(ScanThumbnailBackfillCandidate.init(record:))
        guard !backfillCandidates.isEmpty else { return }

        let container = modelContext.container
        Task(priority: .utility) {
            await ScanThumbnailBackfillActor.shared.backfill(records: backfillCandidates, modelContainer: container)
        }
    }

    private func enqueueRecoverableCloudImages(from records: [LocalScanRecord]) {
        guard offlineQueueManager.isOnline else { return }

        var seenSourceUrls: Set<String> = []
        var recoveries: [(sourceUrl: URL, localUrl: URL)] = []
        for record in records {
            let mediaPaths = [
                record.coverImagePath
            ].compactMap { $0 } + record.capturedMediaSnapshot.thumbnailImagePaths

            for mediaPath in mediaPaths {
                guard let sourceUrl = URL(string: mediaPath),
                      sourceUrl.scheme?.lowercased() == "https",
                      seenSourceUrls.insert(sourceUrl.absoluteString).inserted,
                      let localUrl = LocalScanMediaRecoveryResolver
                          .existingLocalImageURL(for: sourceUrl) else {
                    continue
                }
                recoveries.append((sourceUrl: sourceUrl, localUrl: localUrl))
            }
        }

        guard !recoveries.isEmpty else { return }
        Task(priority: .utility) {
            for recovery in recoveries {
                await CloudScanImageRepairActor.shared.enqueue(
                    sourceUrl: recovery.sourceUrl,
                    localUrl: recovery.localUrl
                )
            }
        }
    }

    private func kickQueuedScanPipeline(reason: String) {
        let now = Date()
        guard now.timeIntervalSince(lastQueuedPipelineKickAt) >= 2 else {
            return
        }

        lastQueuedPipelineKickAt = now
        MerianLog.data.debug(
            "ScansSheetView.kickQueuedScanPipeline: kicking reason=\(reason, privacy: .public)"
        )
        offlineQueueManager.syncPendingScans()
        offlineQueueManager.replayInferenceForUploadedScans()
    }

    private var queuedRefreshTaskID: String {
        queuedScans.map(\.id).sorted().joined(separator: "|")
    }

    private var exploreMediaIncidentRefreshID: String {
        let userId = SupabaseManager.shared.currentUser?.id.uuidString.lowercased() ?? "guest"
        return "\(userId)|\(offlineQueueManager.isOnline)|\(scenePhase)"
    }

    @MainActor
    private func refreshExploreMediaIncidents() async {
        guard offlineQueueManager.isOnline,
              SupabaseManager.shared.isAuthenticated else {
            exploreMediaIncidents = []
            lastExploreMediaIncidentRefreshAt = .distantPast
            needsTrailingExploreMediaIncidentRefresh = false
            return
        }

        if isExploreMediaIncidentRefreshRunning {
            // Do not drop a repair/foreground trigger while a request is in
            // flight. The driver below performs one trailing refresh after
            // the coalescing window.
            needsTrailingExploreMediaIncidentRefresh = true
            return
        }
        isExploreMediaIncidentRefreshRunning = true
        defer {
            isExploreMediaIncidentRefreshRunning = false
            // A replacement SwiftUI `.task(id:)` can begin before a cancelled
            // predecessor reaches this defer. If it registered a trailing
            // request, hand that request to a fresh driver instead of losing
            // the auth/connectivity transition.
            if needsTrailingExploreMediaIncidentRefresh,
               offlineQueueManager.isOnline,
               SupabaseManager.shared.isAuthenticated {
                Task { @MainActor in
                    await refreshExploreMediaIncidents()
                }
            }
        }

        repeat {
            needsTrailingExploreMediaIncidentRefresh = false

            // Queue persistence emits several library updates during one
            // upload / inference handoff. Media-health incidents are an
            // independent, read-only surface, so coalesce those events
            // instead of issuing one identical request per queue transition.
            let elapsed = Date().timeIntervalSince(
                lastExploreMediaIncidentRefreshAt
            )
            let coalescingDelay = max(0, 5 - elapsed)
            if coalescingDelay > 0 {
                do {
                    try await Task.sleep(for: .seconds(coalescingDelay))
                } catch {
                    return
                }
            }
            // Triggers received while waiting are served by the request that
            // is about to start; only triggers received during that request
            // require a trailing refresh.
            needsTrailingExploreMediaIncidentRefresh = false

            guard offlineQueueManager.isOnline,
                  SupabaseManager.shared.isAuthenticated,
                  let expectedOwnerId = SupabaseManager.shared.currentUser?.id else {
                exploreMediaIncidents = []
                lastExploreMediaIncidentRefreshAt = .distantPast
                return
            }
            lastExploreMediaIncidentRefreshAt = Date()

            do {
                let incidents = try await MerianNetworkClient.shared
                    .getExploreMediaIncidents()
                // Never project one account's private recovery queue into a
                // newly signed-in account after an in-flight auth transition.
                guard offlineQueueManager.isOnline,
                      SupabaseManager.shared.isAuthenticated,
                      SupabaseManager.shared.currentUser?.id == expectedOwnerId else {
                    exploreMediaIncidents = []
                    lastExploreMediaIncidentRefreshAt = .distantPast
                    return
                }
                exploreMediaIncidents = incidents
            } catch {
                guard !Task.isCancelled else { return }
                MerianLog.network.error(
                    "ScansSheetView: failed to refresh Explore media incidents: \(error.localizedDescription, privacy: .private)"
                )
            }
        } while needsTrailingExploreMediaIncidentRefresh && !Task.isCancelled
    }

    /// Fetches the current `OfflineQueuedScan` list directly from the model context and
    /// converts it to `[QueuedScanSnapshot]` — value-type copies that are immune to
    /// SwiftData object deletion.
    ///
    /// Called on `onAppear` and whenever `offlineQueueManager.unsyncedItemsCount` changes.
    /// By fetching directly rather than relying on `@Query` auto-refresh, this bypasses the
    /// SwiftData sheet `@Query` notification drop that occurs when saves happen while the
    /// app is backgrounded.
    ///
    /// Converting to `QueuedScanSnapshot` here — while the objects are live — guarantees
    /// `localImagePaths` is resolved before any subsequent `context.delete()` can make
    /// the backing inaccessible. `LazyVGrid` receives only the value-type snapshot array,
    /// so it can never hold a zombie `@Model` reference.
    private func refreshQueuedScans() {
        let readContext = ModelContext(modelContext.container)
        let firstNonRunnableRaw = ScanQueueState.externalImport.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate<OfflineQueuedScan> {
                $0.scanStateRaw < firstNonRunnableRaw || $0.queueNeedsAttention
            },
            sortBy: [SortDescriptor(\OfflineQueuedScan.timestamp, order: .reverse)]
        )
        let fetched = (try? readContext.fetch(descriptor)) ?? []
        let queuedIds = fetched.map(\.id)
        let completedIds: Set<String>
        if queuedIds.isEmpty {
            completedIds = []
        } else {
            let recordDescriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate<LocalScanRecord> { queuedIds.contains($0.id) }
            )
            completedIds = Set(((try? readContext.fetch(recordDescriptor)) ?? []).map(\.id))
        }
        let visibleQueued = fetched.filter { !completedIds.contains($0.id) }
        let snapshots = visibleQueued.map {
            QueuedScanSnapshot(
                id: $0.id,
                imagePath: $0.coverImagePath,
                capturedMediaJSON: $0.capturedMediaJSON,
                queueState: $0.queueState,
                timestamp: $0.timestamp,
                queueNextRetryAt: $0.queueNextRetryAt,
                queueLastErrorMessage: $0.queueLastErrorMessage,
                queueNeedsAttention: $0.queueNeedsAttention,
                approximateQueuedBytes: QueuedScanContext.approximateQueuedBytes(
                    mediaItems: $0.serializedCapturedMediaItems,
                    inferenceImagePaths: $0.inferenceImagePaths
                )
            )
        }
        if queuedScans != snapshots {
            let stateSummary = Dictionary(grouping: fetched, by: \.scanStateRaw)
                .map { "\($0.key):\($0.value.count)" }
                .sorted()
                .joined(separator: ",")
            let visibleSummary = visibleQueued.map(\.id).joined(separator: ",")
            MerianLog.data.debug(
                "ScansSheetView.refreshQueuedScans: changed queued=\(fetched.count, privacy: .public) visible=\(visibleQueued.count, privacy: .public) completedMatches=\(completedIds.count, privacy: .public) states=\(stateSummary, privacy: .public) visibleIds=\(visibleSummary, privacy: .private)"
            )
            queuedScans = snapshots
        }
    }

    /// Forces `searchManager` to reflect the latest `LocalScanRecord` state by fetching
    /// directly from the model context, bypassing any stale `@Query rawRecords` cache.
    ///
    /// Called alongside `refreshQueuedScans()` when `unsyncedItemsCount` changes so the
    /// completed scan tile appears at the same time the pending overlay disappears.
    private func syncStateFromStore() {
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate<LocalScanRecord> { $0.isBiological == true },
            sortBy: [SortDescriptor(\LocalScanRecord.timestamp, order: .reverse)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        guard scanListSignature(records) != scanListSignature(searchManager.allScans) else { return }

        MerianLog.data.debug(
            "ScansSheetView.syncStateFromStore: changed records=\(records.count, privacy: .public)"
        )
        searchManager.allScans = records
        searchManager.performSearch(query: searchManager.searchQuery)
    }

    private func scanListSignature(_ records: [LocalScanRecord]) -> [String] {
        records.map { record in
            "\(record.id)|\(record.timestamp.timeIntervalSince1970)|\(record.hasBeenViewed)"
        }
    }

    // MARK: - Action Handlers

    private func selectedLocalRecordsFromStore() -> [LocalScanRecord] {
        let selectedIds = Array(searchManager.selectedScans)
        guard !selectedIds.isEmpty else { return [] }

        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate<LocalScanRecord> { selectedIds.contains($0.id) },
            sortBy: [SortDescriptor(\LocalScanRecord.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = min(selectedIds.count, searchManager.maxBatchSelectionLimit)
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func handleBatchDelete() {
        let itemsToDelete = selectedLocalRecordsFromStore()
        for item in itemsToDelete {
            AppDIContainer.shared.scanRepository.eradicateScan(record: item, modelContext: modelContext)
        }
        searchManager.exitSelectionMode()
    }
}

// MARK: - Private Structs

private struct QueuedScanInsightRoute: Hashable {
    let queuedScan: QueuedScanContext

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.queuedScan.id == rhs.queuedScan.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(queuedScan.id)
    }
}

private struct LibraryTabContent: View {
    @Bindable var searchManager: ScansManager
    let filterCategories: [String]
    let queuedScans: [QueuedScanSnapshot]
    let exploreMediaIncidents: [ExploreMediaIncident]
    @Binding var isSearchFocused: Bool
    let onScanSelected: (LocalScanRecord) -> Void
    let onQueuedScanSelected: (QueuedScanContext) -> Void
    @Binding var showSelectionLimitAlert: Bool
    @Binding var scanToDelete: String?
    @Binding var showDeleteConfirmation: Bool
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        LibraryView(
            searchManager: searchManager,
            filterCategories: filterCategories,
            isSearchFocused: isSearchFocused,
            queuedScans: queuedScans,
            exploreMediaIncidents: exploreMediaIncidents,
            isSelectionMode: searchManager.isSelectionMode,
            isSelected: { scan in searchManager.selectedScans.contains(scan.id) },
            onSelect: { scan in
                if searchManager.isSelectionMode {
                    let didToggle = searchManager.toggleSelection(for: scan.id)
                    if !didToggle {
                        HapticManager.shared.triggerErrorThump()
                        showSelectionLimitAlert = true
                    }
                } else {
                    inferenceEngine.load(from: scan)
                    isSearchFocused = false
                    onScanSelected(scan)
                }
            },
            onDelete: { scan in
                scanToDelete = scan.id
                showDeleteConfirmation = true
            },
            onShareToExplore: { scan in
                Task {
                    await searchManager.shareToExplore(
                        scanId: scan.id,
                        modelContext: modelContext
                    )
                }
            },
            onQueuedInsight: { queuedContext in
                MerianLog.data.debug(
                    "ScansSheetView: pushing queued insight scanId=\(queuedContext.id, privacy: .private) state=\(queuedContext.queueState.rawValue, privacy: .public)"
                )
                onQueuedScanSelected(queuedContext)
            }
        )
    }
}

private struct CollectionsTabContent: View {
    let searchManager: ScansManager
    let isSearchFocused: Bool
    let collections: [ScanCollection]
    let hiddenSmartCollectionIDs: Set<String>
    let onHideSmartCollection: (SmartCollectionSnapshot) -> Void
    @Binding var newlyCreatedCollection: ScanCollection?

    var body: some View {
        CollectionsView(
            searchQuery: searchManager.searchQuery,
            isSearchFocused: isSearchFocused,
            collections: collections,
            hiddenSmartCollectionIDs: hiddenSmartCollectionIDs,
            onHideSmartCollection: onHideSmartCollection,
            newlyCreatedCollection: $newlyCreatedCollection
        )
    }
}

private struct ScansSheetToolbar: ToolbarContent {
    @Bindable var searchManager: ScansManager
    @Binding var activeTab: ScansTab
    @Environment(AppSettings.self) private var appSettings
    let dismiss: DismissAction
    let onNewCollection: () -> Void
    let onShare: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some ToolbarContent {
        @Bindable var appSettings = appSettings

        if searchManager.isSelectionMode {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { searchManager.exitSelectionMode() }
            }
            ToolbarItem(placement: .principal) {
                Text("\(searchManager.selectedScans.count) Selected").font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select All") { searchManager.selectAll() }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button(action: onShare) { Image(systemName: "square.and.arrow.up") }
                .disabled(searchManager.selectedScans.isEmpty)
                Spacer()
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download").fontWeight(.semibold)
                }
                .disabled(searchManager.selectedScans.isEmpty)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .tint(searchManager.selectedScans.isEmpty ? .gray : .red)
                .disabled(searchManager.selectedScans.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    if !searchManager.searchQuery.isEmpty {
                        searchManager.searchQuery = ""
                    } else {
                        dismiss()
                    }
                }) {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if activeTab == .collections {
                    Button(action: onNewCollection) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(.blue)
                    .accessibilityLabel("New collection")
                } else if activeTab == .library {
                    Menu {
                        ControlGroup {
                            Toggle(isOn: Binding(get: { appSettings.gridColumns == 1 }, set: { if $0 { appSettings.gridColumns = 1 } })) {
                                Label("1x1", systemImage: "rectangle.grid.1x2")
                            }
                            Toggle(isOn: Binding(get: { appSettings.gridColumns == 2 }, set: { if $0 { appSettings.gridColumns = 2 } })) {
                                Label("2x2", systemImage: "square.grid.2x2")
                            }
                            Toggle(isOn: Binding(get: { appSettings.gridColumns == 3 }, set: { if $0 { appSettings.gridColumns = 3 } })) {
                                Label("3x3", systemImage: "square.grid.3x3")
                            }
                        }

                        Button(action: { searchManager.isSelectionMode = true }) {
                            Label("Select multiple", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .accessibilityLabel("More options")
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $activeTab) {
                    Text("Scans").tag(ScansTab.library)
                    Text("Collections").tag(ScansTab.collections)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }
}
