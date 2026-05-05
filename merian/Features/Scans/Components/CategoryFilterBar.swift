import SwiftUI

struct CategoryFilterBar<Item: Hashable>: View {
    // MARK: - State Dependencies
    let items: [Item]
    let activeItem: Item
    let title: (Item) -> String

    // MARK: - Callbacks
    let onSelection: (Item) -> Void

    // MARK: - Component Layout
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button(action: {
                        withAnimation {
                            onSelection(item)
                        }
                    }) {
                        Text(title(item))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(activeItem == item ? Color.primary : Color.secondary.opacity(0.15))
                            .foregroundColor(activeItem == item ? Color(UIColor.systemBackground) : .primary)
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
