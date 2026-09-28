import SwiftUI

struct ExploreEmojiPicker: View {
    let selectedEmojis: Set<String>
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedCategory: String?
    @State private var detent: PresentationDetent = .medium
    @FocusState private var isSearching: Bool

    private var entries: [ExploreEmojiEntry] {
        ExploreEmojiCatalog.pickerEntries(matching: query, category: selectedCategory)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search emoji", text: $query)
                    .focused($isSearching)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("explore.emoji.search")
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            CategoryFilterBar(
                items: ExploreEmojiCatalog.pickerCategories,
                activeItem: selectedCategory,
                title: { $0 },
                leadingTitle: "All",
                isLeadingSelected: selectedCategory == nil,
                onSelection: { selectCategory($0) },
                onLeadingSelection: { selectCategory(nil) }
            )
            .buttonStyle(.plain)
            // The shared filter bar supplies its own horizontal inset.
            .padding(.horizontal, -16)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if entries.isEmpty {
                            ContentUnavailableView(
                                "No emoji found", systemImage: "face.smiling",
                                description: Text("Try another search or choose a different category."))
                        } else {
                            emojiGrid
                        }
                    }
                    .id("emoji-grid-top")
                }
                .transparentTopToolbar()
                .onChange(of: selectedCategory) { _, _ in
                    proxy.scrollTo("emoji-grid-top", anchor: .top)
                }
                .onChange(of: query) { _, _ in
                    proxy.scrollTo("emoji-grid-top", anchor: .top)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: isSearching) { _, searching in if searching { detent = .large } }
        .exploreVideoPresentedOverlayLifecycle(reason: "explore-emoji-picker")
    }

    private func selectCategory(_ category: String?) {
        guard selectedCategory != category else { return }
        HapticManager.shared.triggerSelectionPulse(source: "explore.reaction.picker.category")
        selectedCategory = category
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
            ForEach(entries) { entry in
                Button {
                    HapticManager.shared.triggerSelectionPulse(source: "explore.reaction.picker.select")
                    onSelect(entry.emoji)
                    dismiss()
                } label: {
                    Text(verbatim: entry.emoji).font(.system(size: 32))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            selectedEmojis.contains(entry.emoji) ? Color.accentColor.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.name)
                .accessibilityAddTraits(selectedEmojis.contains(entry.emoji) ? .isSelected : [])
                .help(entry.name)
            }
        }
    }
}
