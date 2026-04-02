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

    // MARK: - Toast State
    @State private var toastMessage: String?

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
                            onQueuedScanTapped: {
                                let message = offlineQueueManager.isOnline
                                    ? "Scan is uploading..."
                                    : "Analysis pending network connection"
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    toastMessage = message
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
