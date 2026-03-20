import SwiftUI

struct CategoryFilterBar: View {
    @ObservedObject var searchManager: ScansSearchManager
    let filterCategories: [String]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filterCategories, id: \.self) { category in
                    Button(action: {
                        withAnimation {
                            if !searchManager.searchQuery.isEmpty {
                                searchManager.activeCategoryFilter = category
                                searchManager.searchQuery = "" // Triggers onChange debounced search
                            } else {
                                searchManager.performSearch(query: "", category: category)
                            }
                        }
                    }) {
                        Text(category)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(searchManager.activeCategoryFilter == category ? Color.primary : Color.secondary.opacity(0.15))
                            .foregroundColor(searchManager.activeCategoryFilter == category ? Color(UIColor.systemBackground) : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(UIColor.systemBackground))
    }
}
