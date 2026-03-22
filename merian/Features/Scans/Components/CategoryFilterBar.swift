import SwiftUI

struct CategoryFilterBar: View {
    // MARK: - State Dependencies
    let filterCategories: [String]
    @Binding var activeCategory: String
    
    // MARK: - Callbacks
    let onCategorySelected: (String) -> Void
    
    // MARK: - Component Layout
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filterCategories, id: \.self) { category in
                    Button(action: {
                        withAnimation {
                            activeCategory = category
                            onCategorySelected(category)
                        }
                    }) {
                        Text(category)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(activeCategory == category ? Color.primary : Color.secondary.opacity(0.15))
                            .foregroundColor(activeCategory == category ? Color(UIColor.systemBackground) : .primary)
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
