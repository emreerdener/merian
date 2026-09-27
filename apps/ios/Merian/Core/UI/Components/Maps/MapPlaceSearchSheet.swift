import SwiftUI

struct MapPlaceSearchSheet: View {
    @Bindable var model: MapPlaceSearchModel
    let onClose: () -> Void
    @FocusState private var isFocused: Bool
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("Search for a location", text: $model.query)
                        .focused($isFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("MapPlaceSearchField")
                        .onSubmit { model.submit() }
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .modifier(MapGlassCapsule())
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 48, height: 48) }
                    .modifier(MapGlassCapsule())
                    .accessibilityLabel("Close location search")
                    .accessibilityIdentifier("MapPlaceSearchClose")
            }
            .padding(16)
            .foregroundStyle(.primary)
            .buttonStyle(.plain)

            if showsSearchHint {
                Text("Search cities, states, addresses, and places.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                Spacer(minLength: 0)
            } else {
                resultsList
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.hidden)
        .onChange(of: isFocused) { _, focused in if focused { detent = .large } }
        .onChange(of: model.query) { _, _ in model.queryChanged() }
    }

    private var showsSearchHint: Bool {
        !model.isLoading && model.errorMessage == nil && !model.hasSearched
            && model.results.isEmpty && model.suggestions.isEmpty && model.recents.isEmpty
            && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resultsList: some View {
        List {
            if model.isLoading {
                HStack { ProgressView(); Text("Searching places…") }
            } else if let message = model.errorMessage {
                Text(message)
                Button("Try again") { model.retry() }
            } else if !model.results.isEmpty {
                Section("Locations") {
                    ForEach(model.results) { result in
                        Button { model.select(result) } label: { placeLabel(result.label) }
                    }
                }
            } else if !model.suggestions.isEmpty {
                Section("Locations") {
                    ForEach(model.suggestions) { suggestion in
                        Button { model.resolve(suggestion) } label: { placeLabel(suggestion.label) }
                    }
                }
            } else if model.hasSearched {
                Text("No places found. Try a city, state, address, or place name.")
                    .foregroundStyle(.secondary)
            } else if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    ForEach(model.recents) { recent in
                        Button { model.resolve(recent) } label: { placeLabel(recent, symbol: "clock") }
                            .swipeActions {
                                Button("Remove", role: .destructive) { model.remove(recent) }
                            }
                    }
                    Button("Clear recents", role: .destructive) { model.clearRecents() }
                } header: { Text("Recent places") }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("MapPlaceSearchResults")
    }

    private func placeLabel(_ place: RecentPlace, symbol: String? = nil) -> some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(place.title).fontWeight(.medium)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle).font(.subheadline).foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
