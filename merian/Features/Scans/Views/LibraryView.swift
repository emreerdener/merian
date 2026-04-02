import SwiftUI

struct LibraryView: View {
    // MARK: - State Dependencies
    @Bindable var searchManager: ScansManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

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
                                }
                            }
                        )
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
                        )
                    }
                }

                if let message = toastMessage {
                    Toast(message: message)
                }
            }
            .sheet(item: $scanToManage) { queuedScan in
                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .padding(.bottom, 4)
                        
                        Text("Pending analysis")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text(offlineQueueManager.isOnline ? "Scan is uploading..." : "Analysis pending network connection")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: 12) {
                        Button(role: .destructive) {
                            Task {
                                await offlineQueueManager.deleteQueuedScan(scanId: queuedScan.id)
                            }
                            scanToManage = nil
                        } label: {
                            Text("Cancel analysis & delete")
                                .font(.headline)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        
                        Button(role: .cancel) {
                            scanToManage = nil
                        } label: {
                            Text("Close")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(24)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
            }
            .task(id: toastMessage) {
                guard toastMessage != nil else { return }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeInOut(duration: 0.2)) {
                    toastMessage = nil
                }
            }
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.library)
    }
}
