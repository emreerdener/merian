import SwiftUI

struct ExploreDictionarySearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search species", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(isFocused ? 0.56 : 0.32), lineWidth: 0.5)
        )
        .frame(maxWidth: 560)
        .padding(.horizontal, 18)
        .accessibilityIdentifier("ExploreDictionarySearchBar")
    }
}

struct ExploreBottomMenu: View {
    let activeTab: ExploreTab
    let onSelect: (ExploreTab) -> Void
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ExploreBottomMenuItem.allCases) { item in
                ExploreBottomMenuButton(
                    item: item,
                    isSelected: activeTab == item.tab,
                    selectionNamespace: selectionNamespace,
                    action: { select(item.tab) }
                )
            }
        }
        .padding(6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.16), radius: 15, x: 0, y: 8)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .frame(maxWidth: 560)
        .padding(.horizontal, 18)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: activeTab)
        .accessibilityIdentifier("ExploreBottomMenu")
    }

    private func select(_ tab: ExploreTab) {
        guard tab != activeTab else { return }
        onSelect(tab)
    }
}

private struct ExploreBottomMenuButton: View {
    let item: ExploreBottomMenuItem
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: item.iconName)
                    .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                    .frame(width: 28, height: 24)

                Text(item.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                        .overlay(
                            Capsule(style: .continuous)
                                .fill(.regularMaterial)
                                .opacity(0.45)
                        )
                        .matchedGeometryEffect(id: "ExploreBottomMenuSelection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(item.accessibilityIdentifier)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ExploreBottomMenuItem: Identifiable, CaseIterable {
    let tab: ExploreTab
    let title: String
    let iconName: String
    let accessibilityIdentifier: String

    var id: ExploreTab { tab }

    static let allCases: [ExploreBottomMenuItem] = [
        ExploreBottomMenuItem(
            tab: .feed,
            title: "Feed",
            iconName: "safari",
            accessibilityIdentifier: "ExploreBottomMenu_Feed"
        ),
        ExploreBottomMenuItem(
            tab: .map,
            title: "Map",
            iconName: "map",
            accessibilityIdentifier: "ExploreBottomMenu_Map"
        ),
        ExploreBottomMenuItem(
            tab: .dictionary,
            title: "Dictionary",
            iconName: "book.closed",
            accessibilityIdentifier: "ExploreBottomMenu_Dictionary"
        ),
        ExploreBottomMenuItem(
            tab: .tree,
            title: "Tree",
            iconName: "point.3.connected.trianglepath.dotted",
            accessibilityIdentifier: "ExploreBottomMenu_Tree"
        )
    ]
}

#Preview {
    VStack {
        Spacer()
        ExploreBottomMenu(activeTab: .feed) { _ in }
    }
    .padding(.bottom)
    .background(Color(uiColor: .systemGroupedBackground))
}
