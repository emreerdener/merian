import SwiftUI

struct CategoryFilterBar<Item: Hashable>: View {
    // MARK: - State Dependencies
    let items: [Item]
    let activeItem: Item
    let title: (Item) -> String
    let leadingTitle: String?
    let isLeadingSelected: Bool

    // MARK: - Callbacks
    let onSelection: (Item) -> Void
    let onLeadingSelection: (() -> Void)?

    init(
        items: [Item],
        activeItem: Item,
        title: @escaping (Item) -> String,
        leadingTitle: String? = nil,
        isLeadingSelected: Bool = false,
        onSelection: @escaping (Item) -> Void,
        onLeadingSelection: (() -> Void)? = nil
    ) {
        self.items = items
        self.activeItem = activeItem
        self.title = title
        self.leadingTitle = leadingTitle
        self.isLeadingSelected = isLeadingSelected
        self.onSelection = onSelection
        self.onLeadingSelection = onLeadingSelection
    }

    // MARK: - Component Layout
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let leadingTitle, let onLeadingSelection {
                    filterButton(
                        title: leadingTitle,
                        isSelected: isLeadingSelected,
                        action: onLeadingSelection
                    )
                }

                ForEach(items, id: \.self) { item in
                    filterButton(
                        title: title(item),
                        isSelected: activeItem == item,
                        action: { onSelection(item) }
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func filterButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation {
                action()
            }
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.primary : Color.secondary.opacity(0.15))
                .foregroundColor(isSelected ? Color(UIColor.systemBackground) : .primary)
                .clipShape(Capsule())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FilterSheetSelectionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 38, height: 38)
                .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
