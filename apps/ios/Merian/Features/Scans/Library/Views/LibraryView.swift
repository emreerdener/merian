import SwiftData
import SwiftUI

// MARK: - Library View

struct LibraryView: View {
    // MARK: - State Dependencies
    @Bindable var searchManager: ScansManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.startupStoreState) private var startupStoreState

    // MARK: - App State Context
    let filterCategories: [String]
    let isSearchFocused: Bool
    var queuedScans: [QueuedScanSnapshot] = []
    var unavailableMediaScanCount = 0
    var isUnavailableMediaOverviewVisible = true
    var isExploreMediaIncidentRefreshRunning = false
    var onRefreshExploreMediaIncidents: (() -> Void)?
    var onDismissUnavailableMediaOverview: (() -> Void)?

    // MARK: - Component Callbacks
    var isSelectionMode: Bool = false
    var isSelected: ((LocalScanRecord) -> Bool)?
    let onSelect: (LocalScanRecord) -> Void
    let onDelete: (LocalScanRecord) -> Void
    var onShareToExplore: ((LocalScanRecord) -> Void)?
    var onQueuedInsight: ((QueuedScanContext) -> Void)?

    // MARK: - Component State
    @State private var toastMessage: ToastPayload?
    @State private var isShowingFilterSheet = false

    // MARK: - Visual Layout
    var body: some View {
        let completedScanIds = Set(searchManager.allScans.map(\.id))
        let visibleQueuedScans = isUnavailableMediaFilterEnabled
            ? []
            : queuedScans.filter { !completedScanIds.contains($0.id) }
        let hasContent = !displayedScans.isEmpty || !visibleQueuedScans.isEmpty
        let emptyStateCopy = ScanLibraryEmptyStateCopy.make(
            startupStoreState: startupStoreState,
            hasLibraryContent: !searchManager.allScans.isEmpty || !visibleQueuedScans.isEmpty,
            searchQuery: searchManager.searchQuery,
            hasActiveFilters: searchManager.hasActiveFilters
        )

        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                        if unavailableMediaScanCount > 0,
                           isUnavailableMediaOverviewVisible {
                            unavailableMediaHeader
                        }

                        Section {
                            if hasContent {
                                ScansGrid(
                                    scans: displayedScans,
                                    queuedScans: visibleQueuedScans,
                                    onSelect: onSelect,
                                    onDelete: onDelete,
                                    isSelected: isSelected,
                                    onAddScans: nil,
                                    onQueuedScanTapped: { snapshot in
                                        openQueuedScan(snapshot)
                                    },
                                    onQueuedScanDelete: { snapshot in
                                        guard !searchManager.isDownloading else { return }
                                        Task {
                                            await offlineQueueManager.deleteQueuedScan(scanId: snapshot.id)
                                            await MainActor.run {
                                                toastMessage = .success("Scan cancelled & deleted")
                                            }
                                        }
                                    },
                                    customMenuItems: { scan in
                                        Group {
                                            if let onShareToExplore, scan.isExploreShareEligible {
                                                Button {
                                                    onShareToExplore(scan)
                                                } label: {
                                                    Label("Share to Explore", systemImage: "safari")
                                                }
                                            }
                                        }
                                    },
                                    isSelectionMode: isSelectionMode
                                )
                            } else if isUnavailableMediaFilterEnabled {
                                EmptyStateView(
                                    imageName: "fireflies",
                                    title: "No matching scans on this device",
                                    message: "The published scans with unavailable media aren’t stored "
                                        + "on this device or don’t match your Library filters."
                                ) {
                                    EmptyView()
                                }
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                            } else if searchManager.isFiltering {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                            } else {
                                EmptyStateView(
                                    imageName: "fireflies",
                                    title: emptyStateCopy.title,
                                    message: emptyStateCopy.message
                                ) {
                                    switch emptyStateCopy.action {
                                    case .clearFilters:
                                        Button {
                                            HapticManager.shared.triggerMediumPulse()
                                            searchManager.clearFilters()
                                        } label: {
                                            Text(emptyStateCopy.actionTitle ?? "Clear filters")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.regular)
                                    case .dismiss:
                                        Button {
                                            dismiss()
                                        } label: {
                                            Text(emptyStateCopy.actionTitle ?? "Start scanning")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.regular)
                                    case .none:
                                        EmptyView()
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                            }
                        } header: {
                            libraryFilterHeader
                        }
                    }
                }
                .scrollClipDisabled()

            }
        }
        .merianSystemFeedback(
            toast: $toastMessage,
            showsAchievementToasts: false
        )
        .onChange(of: offlineQueueManager.isOnline) { _, isOnline in
            if isOnline && !visibleQueuedScans.isEmpty {
                toastMessage = .information("Back online, uploading scans...")
            }
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.library)
    }

    private var unavailableMediaHeader: some View {
        HStack {
            Text("\(unavailableMediaScanCount.formatted()) media unavailable")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Spacer()

            if isExploreMediaIncidentRefreshRunning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading…")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else {
                Button("Refresh") {
                    HapticManager.shared.triggerSelectionPulse()
                    onRefreshExploreMediaIncidents?()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
            }

            if let onDismissUnavailableMediaOverview {
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onDismissUnavailableMediaOverview()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss unavailable media notice")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var libraryFilterHeader: some View {
        if searchManager.searchQuery.isEmpty && !isSearchFocused {
            CategoryFilterBar(
                items: filterCategories,
                activeItem: searchManager.activeCategoryFilter == "All"
                    && searchManager.filters.hasAdvancedFilters
                    ? nil
                    : searchManager.activeCategoryFilter,
                title: { $0 },
                leadingTitle: searchManager.hasActiveFilters
                    ? "Filters \(searchManager.activeFilterCount.formatted())"
                    : "Filters",
                leadingSystemImage: "line.3.horizontal.decrease",
                isLeadingSelected: searchManager.hasActiveFilters,
                presentation: .overContent,
                onSelection: { category in
                    searchManager.performSearch(query: "", category: category)
                },
                onLeadingSelection: {
                    HapticManager.shared.triggerSelectionPulse()
                    isShowingFilterSheet = true
                }
            )
            .sheet(isPresented: $isShowingFilterSheet) {
                ScansFilterSheet(
                    searchManager: searchManager,
                    filterCategories: filterCategories
                )
            }
        } else {
            HStack {
                Text(headerTitle)
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                Text("\(displayedScans.count) found")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    private var isUnavailableMediaFilterEnabled: Bool {
        searchManager.filters.explorePostFilters.contains(.unavailableMedia)
    }

    private var displayedScans: [LocalScanRecord] {
        searchManager.filteredScans
    }

    private var headerTitle: String {
        searchManager.searchQuery.isEmpty ? "Search library" : "Search results"
    }

    private func openQueuedScan(_ snapshot: QueuedScanSnapshot) {
        if let completedRecord = localScanRecord(id: snapshot.id) {
            MerianLog.data.debug(
                "LibraryView.openQueuedScan: opening completed record scanId=\(snapshot.id, privacy: .private)"
            )
            onSelect(completedRecord)
            return
        }

        if let queuedScanContext = queuedScanContext(id: snapshot.id) {
            MerianLog.data.debug(
                "LibraryView.openQueuedScan: opening fresh queued insight scanId=\(snapshot.id, privacy: .private) state=\(queuedScanContext.queueState.rawValue, privacy: .public)"
            )
            onQueuedInsight?(queuedScanContext)
            return
        }

        MerianLog.data.debug(
            "LibraryView.openQueuedScan: opening snapshot queued insight scanId=\(snapshot.id, privacy: .private) state=\(snapshot.queueState.rawValue, privacy: .public)"
        )
        onQueuedInsight?(
            QueuedScanContext(
                id: snapshot.id,
                capturedMediaItems: snapshot.capturedMediaItems,
                queueState: snapshot.queueState,
                timestamp: snapshot.timestamp,
                queueNextRetryAt: snapshot.queueNextRetryAt,
                queueLastErrorMessage: snapshot.queueLastErrorMessage,
                queueNeedsAttention: snapshot.queueNeedsAttention,
                approximateQueuedBytes: snapshot.approximateQueuedBytes
            )
        )
    }

    private func localScanRecord(id scanId: String) -> LocalScanRecord? {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func queuedScanContext(id scanId: String) -> QueuedScanContext? {
        let readContext = ModelContext(modelContext.container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let scan = (try? readContext.fetch(descriptor))?.first else { return nil }
        return QueuedScanContext(from: scan)
    }
}

enum ScanLibraryEmptyStateAction: Equatable {
    case clearFilters
    case dismiss
    case none
}

struct ScanLibraryEmptyStateCopy: Equatable {
    let title: String
    let message: String
    let actionTitle: String?
    let action: ScanLibraryEmptyStateAction

    static func make(
        startupStoreState: StartupStoreState,
        hasLibraryContent: Bool,
        searchQuery: String,
        hasActiveFilters: Bool
    ) -> ScanLibraryEmptyStateCopy {
        if startupStoreState == .safeMode && !hasLibraryContent {
            return ScanLibraryEmptyStateCopy(
                title: "Local library unavailable",
                message: "Naturebook is running in safe mode because the local database did not open. Your saved scans have not loaded in this session, and new local changes are temporary. Restart Naturebook to try reopening the library.",
                actionTitle: "Back to camera",
                action: .dismiss
            )
        }

        if !searchQuery.isEmpty {
            return ScanLibraryEmptyStateCopy(
                title: "No scans found",
                message: "No results for \"\(searchQuery)\"",
                actionTitle: nil,
                action: .none
            )
        }

        if hasActiveFilters {
            return ScanLibraryEmptyStateCopy(
                title: "No scans found",
                message: "No scans match the current filters",
                actionTitle: "Clear filters",
                action: .clearFilters
            )
        }

        return ScanLibraryEmptyStateCopy(
            title: "No scans found",
            message: "Start exploring and capture your first scan!",
            actionTitle: "Start scanning",
            action: .dismiss
        )
    }
}
