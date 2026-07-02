import SwiftData
import SwiftUI

// MARK: - Library View

struct LibraryView: View {
    // MARK: - State Dependencies
    @Bindable var searchManager: ScansManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
                                title: "No scans found",
                                message: {
                                    if !searchManager.searchQuery.isEmpty {
                                        return "No results for \"\(searchManager.searchQuery)\""
                                    } else if searchManager.hasActiveFilters {
                                        return "No scans match the current filters"
                                    } else {
                                        return "Start exploring and capture your first scan!"
                                    }
                                }()
                            ) {
                                if searchManager.hasActiveFilters {
                                    Button {
                                        HapticManager.shared.triggerMediumPulse()
                                        searchManager.clearFilters()
                                    } label: {
                                        Text("Clear filters")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.regular)
                                } else if searchManager.searchQuery.isEmpty {
                                    Button {
                                        dismiss()
                                    } label: {
                                        Text("Start scanning")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.regular)
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
                timestamp: snapshot.timestamp
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
