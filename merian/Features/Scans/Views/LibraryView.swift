import SwiftData
import SwiftUI

// MARK: - Library View

struct LibraryView: View {
    // MARK: - State Dependencies
    @Bindable var searchManager: ScansManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - App State Context
    let filterCategories: [String]
    let isSearchFocused: Bool
    var queuedScans: [QueuedScanSnapshot] = []

    // MARK: - Component Callbacks
    var isSelectionMode: Bool = false
    var isSelected: ((LocalScanRecord) -> Bool)?
    let onSelect: (LocalScanRecord) -> Void
    let onDelete: (LocalScanRecord) -> Void
    var onShareToExplore: ((LocalScanRecord) -> Void)?

    // MARK: - Component State
    @State private var toastMessage: String?
    @State private var scanToManage: QueuedScanContext?
    /// Controls the queued-scan sheet independently of `scanToManage`.
    ///
    /// Using `.sheet(isPresented:)` instead of `.sheet(item:)` lets us clear
    /// `scanToManage` (handing off to `InsightSheetView`'s internal transition)
    /// without immediately dismissing the sheet when a scan completes.
    @State private var isQueuedSheetPresented = false

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
                            isSelected: isSelected,
                            onAddScans: nil,
                            onQueuedScanTapped: { snapshot in
                                // Fetch the live OfflineQueuedScan and immediately snapshot
                                // it into QueuedScanContext — resolving all attribute faults
                                // while the object is live. The insight sheet chain then holds
                                // only the value type; no @Model reference survives the tap.
                                let scanId = snapshot.id
                                var descriptor = FetchDescriptor<OfflineQueuedScan>(
                                    predicate: #Predicate { $0.id == scanId }
                                )
                                descriptor.fetchLimit = 1
                                if let scan = (try? modelContext.fetch(descriptor))?.first {
                                    scanToManage = QueuedScanContext(from: scan)
                                    isQueuedSheetPresented = true
                                }
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
                                    if let onShareToExplore {
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
                            .frame(maxWidth: .infinity, idealHeight: 400)
                    } else {
                        EmptyStateView(
                            imageName: "fireflies",
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
            .sheet(isPresented: $isQueuedSheetPresented, onDismiss: {
                scanToManage = nil
            }) {
                // Pass the current context — may become nil mid-session when the scan
                // completes and InsightSheetView transitions internally to results.
                InsightSheetView(isPresented: $isQueuedSheetPresented, queuedScan: scanToManage, inferenceEngine: inferenceEngine)
            }
            .onChange(of: queuedScans.map(\.id)) { _, newIds in
                guard let managed = scanToManage, !newIds.contains(managed.id) else { return }
                // Scan left the queue. Determine whether it completed or was deleted/failed.
                let scanId = managed.id
                var descriptor = FetchDescriptor<LocalScanRecord>(
                    predicate: #Predicate { $0.id == scanId }
                )
                descriptor.fetchLimit = 1
                if let record = (try? modelContext.fetch(descriptor))?.first {
                    // Completed successfully — load the engine proactively so the sheet
                    // transitions seamlessly to the correct biological state, preventing
                    // the intermediate \"Analyzing\" fallback that occurs if scanToManage
                    // drops before the engine is populated.
                    inferenceEngine.load(from: record)
                    scanToManage = nil
                } else {
                    // Deleted or failed — close the sheet entirely.
                    isQueuedSheetPresented = false
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
