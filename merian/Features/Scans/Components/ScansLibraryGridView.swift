import SwiftUI

struct ScansLibraryGridView: View {
    @ObservedObject var searchManager: ScansSearchManager
    let filterCategories: [String]
    let isSearchFocused: Bool
    var isSelectionMode: Bool = false
    var isSelected: ((LocalScanRecord) -> Bool)? = nil
    let onSelect: (LocalScanRecord) -> Void
    let onDelete: (LocalScanRecord) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            if searchManager.searchQuery.isEmpty && !isSearchFocused {
                CategoryFilterBar(
                    filterCategories: filterCategories,
                    activeCategory: Binding(
                        get: { searchManager.activeCategoryFilter },
                        set: { searchManager.activeCategoryFilter = $0 }
                    ),
                    onCategorySelected: { category in
                        if !searchManager.searchQuery.isEmpty {
                            searchManager.searchQuery = "" // Triggers onChange debounced search
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
            
            ScrollView {
                if searchManager.filteredScans.isEmpty {
                    EmptyStateView(
                        iconName: "camera.macro",
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
                } else {
                    ScanGridMatrix(
                        scans: searchManager.filteredScans,
                        onSelect: onSelect,
                        onDelete: onDelete,
                        isSelectionMode: isSelectionMode,
                        isSelected: isSelected
                    )
                }
            }
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.library)
    }
}
