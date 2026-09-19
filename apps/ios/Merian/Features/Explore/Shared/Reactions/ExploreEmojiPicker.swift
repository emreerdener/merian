import SwiftUI

struct ExploreEmojiPicker: View {
    let selectedEmojis: Set<String>
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var detent: PresentationDetent = .medium
    @FocusState private var isSearching: Bool

    private var entries: [ExploreEmojiEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExploreEmojiCatalog.pickerEntries.filter { entry in
            if !search.isEmpty {
                return entry.emoji == search || entry.name.localizedStandardContains(search)
                    || entry.keywords.localizedStandardContains(search)
                    || entry.category.localizedStandardContains(search)
            }
            return true
        }
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
            ScrollView {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No emoji found", systemImage: "face.smiling", description: Text("Try another search."))
                } else {
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
            .transparentTopToolbar()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: isSearching) { _, searching in if searching { detent = .large } }
        .exploreVideoPresentedOverlayLifecycle(reason: "explore-emoji-picker")
    }
}
