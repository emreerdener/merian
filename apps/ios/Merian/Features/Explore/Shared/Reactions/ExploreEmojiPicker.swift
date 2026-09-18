import SwiftUI

struct ExploreEmojiPicker: View {
    let selectedEmojis: Set<String>
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: String?
    @State private var detent: PresentationDetent = .medium
    @FocusState private var isSearching: Bool

    private var entries: [ExploreEmojiEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExploreEmojiCatalog.entries.filter { entry in
            if !search.isEmpty {
                return entry.emoji == search || entry.name.localizedStandardContains(search)
                    || entry.keywords.localizedStandardContains(search)
                    || entry.category.localizedStandardContains(search)
            }
            return category == nil || entry.category == category
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search emoji", text: $query)
                    .focused($isSearching)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("explore.emoji.search")
                Button("Done") { dismiss() }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    categoryButton("All", value: nil)
                    ForEach(ExploreEmojiCatalog.categories, id: \.self) { categoryButton($0, value: $0) }
                }
            }
            ScrollView {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No emoji found", systemImage: "face.smiling", description: Text("Try another search."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
                        ForEach(entries) { entry in
                            Button {
                                HapticManager.shared.triggerSelectionPulse(source: "explore.reaction.picker.select")
                                onSelect(entry.emoji)
                                dismiss()
                            } label: {
                                Text(verbatim: entry.emoji).font(.system(size: 32))
                                    .frame(maxWidth: .infinity, minHeight: 56)
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: isSearching) { _, searching in if searching { detent = .large } }
        .exploreVideoPresentedOverlayLifecycle(reason: "explore-emoji-picker")
    }

    private func categoryButton(_ label: String, value: String?) -> some View {
        Button(label) {
            if category != value || !query.isEmpty {
                HapticManager.shared.triggerSelectionPulse(source: "explore.reaction.picker.category")
            }
            category = value
            query = ""
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(category == value ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
        .buttonStyle(.plain)
        .accessibilityAddTraits(category == value ? .isSelected : [])
    }
}
