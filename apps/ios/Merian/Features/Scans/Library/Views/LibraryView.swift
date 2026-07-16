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
    let isSearchFocused: Bool
    var queuedScans: [QueuedScanSnapshot] = []

    // MARK: - Component Callbacks
    var isSelectionMode: Bool = false
    var isSelected: ((LocalScanRecord) -> Bool)?
    let onSelect: (LocalScanRecord) -> Void
    let onDelete: (LocalScanRecord) -> Void
    var onShareToExplore: ((LocalScanRecord) -> Void)?
    var onQueuedInsight: ((QueuedScanContext) -> Void)?

    // MARK: - Component State
    @State private var toastMessage: String?

    // MARK: - Visual Layout
    var body: some View {
        VStack(spacing: 8) {
            // 1. Dynamic Header Constraints
            if shouldShowHeader {
                HStack {
                    Text(headerTitle)
                        .font(.title3)
                        .fontWeight(.bold)

                    Spacer()

                    Text("\(searchManager.filteredScans.count) found")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            // 2. Main Discovery Scroll Container
            let completedScanIds = Set(searchManager.allScans.map(\.id))
            let visibleQueuedScans = queuedScans.filter { !completedScanIds.contains($0.id) }
            let hasContent = !searchManager.filteredScans.isEmpty || !visibleQueuedScans.isEmpty
            let emptyStateCopy = ScanLibraryEmptyStateCopy.make(
                startupStoreState: startupStoreState,
                hasLibraryContent: !searchManager.allScans.isEmpty || !visibleQueuedScans.isEmpty,
                searchQuery: searchManager.searchQuery,
                hasActiveFilters: searchManager.hasActiveFilters
            )
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        if hasContent {
                            ScansGrid(
                                scans: searchManager.filteredScans,
                                queuedScans: visibleQueuedScans,
                                onSelect: onSelect,
                                onDelete: onDelete,
                                isSelected: isSelected,
                                onAddScans: nil,
                                onQueuedScanTapped: { snapshot in
                                    openQueuedScan(snapshot)
                                },
                                onQueuedScanDelete: { snapshot in
                                    Task {
                                        await offlineQueueManager.deleteQueuedScan(scanId: snapshot.id)
                                        await MainActor.run {
                                            withAnimation { toastMessage = "Scan cancelled & deleted" }
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
                    }
                    .scrollClipDisabled()

                    if let message = toastMessage {
                        ToastBanner(onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                toastMessage = nil
                            }
                        }) {
                            Text(message)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        .padding(.bottom, 60)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(100)
                    }
                }
            }
            .task(id: toastMessage) {
                guard toastMessage != nil else { return }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeInOut(duration: 0.2)) {
                    toastMessage = nil
                }
            }
            .onChange(of: offlineQueueManager.isOnline) { _, isOnline in
                if isOnline && !visibleQueuedScans.isEmpty {
                    withAnimation { toastMessage = "Back online, uploading scans..." }
                }
            }
        }
        .padding(.top, shouldShowHeader ? 0 : 16)
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.library)
    }

    private var shouldShowHeader: Bool {
        isSearchFocused || !searchManager.searchQuery.isEmpty || searchManager.hasActiveFilters
    }

    private var headerTitle: String {
        if !searchManager.searchQuery.isEmpty {
            return "Search results"
        }

        if searchManager.activeCategoryFilter != "All" {
            return searchManager.activeCategoryFilter
        }

        if searchManager.hasActiveFilters {
            return "Filtered scans"
        }

        return "Search library"
    }

    private func openQueuedScan(_ snapshot: QueuedScanSnapshot) {
        if let completedRecord = localScanRecord(id: snapshot.id) {
            MerianLog.data.debug(
                "LibraryView.openQueuedScan: opening completed record scanId=\(snapshot.id, privacy: .public)"
            )
            onSelect(completedRecord)
            return
        }

        if let queuedScanContext = queuedScanContext(id: snapshot.id) {
            MerianLog.data.debug(
                "LibraryView.openQueuedScan: opening fresh queued insight scanId=\(snapshot.id, privacy: .public) state=\(queuedScanContext.queueState.rawValue, privacy: .public)"
            )
            onQueuedInsight?(queuedScanContext)
            UITestSeedCoordinator.triggerQueuedAudioHandoffIfNeeded(
                scanId: queuedScanContext.id,
                container: modelContext.container
            )
            return
        }

        MerianLog.data.debug(
            "LibraryView.openQueuedScan: opening snapshot queued insight scanId=\(snapshot.id, privacy: .public) state=\(snapshot.queueState.rawValue, privacy: .public)"
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
