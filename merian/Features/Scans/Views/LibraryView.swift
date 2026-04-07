import SwiftUI

// MARK: - Library View

struct LibraryView: View {
    // MARK: - State Dependencies
    @Bindable var searchManager: ScansManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - App State Context
    let filterCategories: [String]
    let isSearchFocused: Bool
    var queuedScans: [OfflineQueuedScan] = []

    // MARK: - Component Callbacks
    var isSelectionMode: Bool = false
    var isSelected: ((LocalScanRecord) -> Bool)?
    let onSelect: (LocalScanRecord) -> Void
    let onDelete: (LocalScanRecord) -> Void

    // MARK: - Component State
    @State private var toastMessage: String?
    @State private var scanToManage: OfflineQueuedScan?

    // MARK: - Visual Layout
    var body: some View {
        VStack(spacing: 8) {
            // 1. Dynamic Header Constraints
            if searchManager.searchQuery.isEmpty && !isSearchFocused {
                CategoryFilterBar(
                    filterCategories: filterCategories,
                    activeCategory: Binding(
                        get: { searchManager.activeCategoryFilter },
                        set: { searchManager.activeCategoryFilter = $0 }
                    ),
                    onCategorySelected: { category in
                        if !searchManager.searchQuery.isEmpty {
                            searchManager.searchQuery = ""
                        } else {
                            searchManager.performSearch(query: "", category: category)
                        }
                    }
                )
            } else {
                HStack {
                    Text(searchManager.searchQuery.isEmpty ? "Search library" : "Search results")
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
            let hasContent = !searchManager.filteredScans.isEmpty || !queuedScans.isEmpty
            ZStack(alignment: .bottom) {
                ScrollView {
                    if hasContent {
                        ScansGrid(
                            scans: searchManager.filteredScans,
                            queuedScans: queuedScans,
                            onSelect: onSelect,
                            onDelete: onDelete,
                            isSelectionMode: isSelectionMode,
                            isSelected: isSelected,
                            onQueuedScanTapped: { queuedScan in
                                scanToManage = queuedScan
                            },
                            onQueuedScanDelete: { queuedScan in
                                Task {
                                    await offlineQueueManager.deleteQueuedScan(scanId: queuedScan.id)
                                    await MainActor.run {
                                        withAnimation { toastMessage = "Scan cancelled & deleted" }
                                    }
                                }
                            }
                        )
                    } else if searchManager.isFiltering {
                        Color.clear
                            .frame(maxWidth: .infinity, idealHeight: 400)
                    } else {
                        EmptyStateView(
                            iconName: "viewfinder",
                            title: "No scans found",
                            message: {
                                if !searchManager.searchQuery.isEmpty {
                                    return "No results for \"\(searchManager.searchQuery)\" in \(searchManager.activeCategoryFilter)"
                                } else if searchManager.activeCategoryFilter != "All" {
                                    return "You haven't documented any \(searchManager.activeCategoryFilter.lowercased()) yet"
                                } else {
                                    return "Start exploring and capture your first scan!"
                                }
                            }()
                        ) {
                            if searchManager.searchQuery.isEmpty {
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
                    }
                }

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .sheet(item: $scanToManage) { queuedScan in
                QueuedScanManagementSheet(
                    queuedScan: queuedScan,
                    isOnline: offlineQueueManager.isOnline,
                    onDelete: {
                        Task {
                            await offlineQueueManager.deleteQueuedScan(scanId: queuedScan.id)
                            await MainActor.run {
                                withAnimation { toastMessage = "Scan cancelled & deleted" }
                            }
                        }
                        scanToManage = nil
                    },
                    onClose: { scanToManage = nil }
                )
            }
            .onChange(of: queuedScans.map(\.id)) { _, newIds in
                // Auto-dismiss the management sheet when its scan completes (leaves the queue).
                // Holding a live OfflineQueuedScan reference after flushOfflineQueuedScan
                // deletes the object causes SwiftUI to render against a zombie @Model — nil
                // out scanToManage as soon as the scan ID disappears from the queue.
                // Comparing [String] ids is cheaper than PersistentModel equality on the full array.
                guard let managed = scanToManage else { return }
                if !newIds.contains(managed.id) {
                    scanToManage = nil
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
                if isOnline && !queuedScans.isEmpty {
                    withAnimation { toastMessage = "Back online, uploading scans..." }
                }
            }
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.library)
    }
}
