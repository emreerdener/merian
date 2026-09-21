import SwiftUI

struct SpeciesSearchView: View {
    @Bindable var model: SpeciesSearchViewModel
    let exploreViewModel: ExploreFeedViewModel
    let onOpenPost: (ExplorePost) -> Void
    var starterImageDependencies: SpeciesCatalogImageDependencies = .live
    @FocusState private var inputFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            if model.hasResults {
                resultsHeader
                results
            } else {
                introduction
            }
            if let notice = model.notice {
                Text(notice).font(.subheadline).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("SpeciesSearchNotice")
            }
            if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                    Button("Retry", action: model.retry).buttonStyle(.bordered)
                }
                .font(.subheadline).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.isLoading {
                ProgressView(model.hasResults ? "Updating results…" : "Searching Naturebook…")
                    .padding(12).accessibilityIdentifier("SpeciesSearchLoading")
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.newSearch(); inputFocused = false } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                    .buttonStyle(.plain)
                    .tint(.primary)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("New search")
                    .accessibilityIdentifier("SpeciesSearchReset")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .onAppear {
            if !model.hasResults { model.rotateIllustration() }
        }
        .task(id: model.request?.requestId) { await model.execute() }
        .onChange(of: model.needsClarification) { _, needsAnswer in
            if needsAnswer { inputFocused = true }
        }
        .onChange(of: model.selectedTab) { _, _ in
            inputFocused = false
            model.loadSelectedTab()
        }
        .onChange(of: model.isLoading) { _, loading in
            if !loading { model.loadSelectedTab() }
        }
        .onChange(of: model.sightings) { previous, posts in
            SpeciesSearchSightings.register(posts, previous: previous, in: exploreViewModel)
        }
        .accessibilityIdentifier("SpeciesSearchView")
    }
    private var introduction: some View {
        SpeciesSearchIntroduction(
            prompts: model.suggestedPrompts,
            illustrationName: model.illustrationName,
            catalog: model.starterCatalog,
            isSearching: model.isLoading,
            imageDependencies: starterImageDependencies,
            onSubmit: { submit($0) }
        )
    }
    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.interpretation).font(.headline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Menu {
                        Button("All groups") { model.setGroup(nil) }
                        ForEach(SpeciesSearchGroup.allCases, id: \.self) { group in
                            Button(group.title) { model.setGroup(group) }
                        }
                    } label: {
                        Label(model.context?.group?.title ?? "All groups", systemImage: "line.3.horizontal.decrease")
                    }
                    if model.selectedTab == .sightings || model.context?.media != nil {
                        Menu {
                            Button("All media") { model.setMedia(nil) }
                            ForEach(SpeciesSearchMedia.allCases, id: \.self) { media in
                                Button(media.title) { model.setMedia(media) }
                            }
                        } label: {
                            Label("Sightings: \(model.context?.media?.title ?? "All media")", systemImage: "photo.on.rectangle")
                        }
                    }
                }
                .buttonStyle(.bordered).font(.subheadline)
                .disabled(model.isLoading && model.request?.question != nil)
            }
            if model.selectedTab == .species && model.context?.media != nil {
                Text("Media filters apply to Sightings.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Search results", selection: $model.selectedTab) {
                Text("Species").tag(SpeciesSearchResultKind.species)
                Text("Sightings").tag(SpeciesSearchResultKind.sightings)
            }
            .pickerStyle(.segmented)
            .disabled(model.isLoading)
            .accessibilityIdentifier("SpeciesSearchResultTabs")
        }
        .padding(16)
    }
    @ViewBuilder private var results: some View {
        if model.selectedTab == .species {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(model.context?.mode == .description ? "Possible matches" : "Species")
                        .font(.subheadline).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                    ForEach(model.species) { match in
                        NavigationLink(value: SpeciesDictionaryRoute(scientificName: match.item.scientificName, speciesId: match.id, entryPoint: .search)) {
                            VStack(alignment: .leading, spacing: 6) {
                                SpeciesDictionaryCatalogRow(item: match.item)
                                if !match.excerpt.isEmpty {
                                    Text("From the dictionary: \(match.excerpt)")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(4)
                                        .padding(.horizontal, 10)
                                }
                            }
                        }
                        .buttonStyle(.plain).id(match.id)
                    }
                    if model.species.isEmpty && !model.isLoading {
                        emptyResults("No matching species", message: "Try a name or fewer descriptive traits. Naturebook may not have an entry yet.")
                    }
                    moreButton
                }
                .scrollTargetLayout().padding(.horizontal, 16).padding(.bottom, 16)
            }
            .scrollPosition(id: $model.speciesScrollID)
            .scrollDismissesKeyboard(.interactively)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(visibleSightings) { post in
                        SpeciesSearchSightingCard(post: post, mediaReloadGeneration: exploreViewModel.mediaReloadGeneration) {
                            inputFocused = false
                            onOpenPost(post)
                        }.id(post.id)
                    }
                    if visibleSightings.isEmpty && !model.isLoading {
                        emptyResults("No matching public sightings", message: "There may still be matching species in the dictionary. Try the Species tab or broaden your search.")
                    }
                    moreButton
                }
                .scrollTargetLayout().padding(.horizontal, 16).padding(.bottom, 16)
            }
            .scrollPosition(id: $model.sightingsScrollID)
            .scrollDismissesKeyboard(.interactively)
        }
    }
    private var visibleSightings: [ExplorePost] {
        model.sightings.compactMap { exploreViewModel.post(id: $0.id) }
            .filter { SpeciesSearchSightings.canSurface($0, in: exploreViewModel) }
    }
    private func emptyResults(_ title: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: "magnifyingglass", description: Text(message))
    }
    @ViewBuilder private var moreButton: some View {
        if model.hasMore { Button("Load more", action: model.loadMore).frame(maxWidth: .infinity).padding(12) }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if model.hasResults && model.draft.isEmpty && !model.isLoading {
                Button(model.context?.group == nil ? "Narrow by species group" : "Show all groups") {
                    if model.context?.group != nil {
                        model.setGroup(nil)
                    } else {
                        model.draft = "Only "
                        inputFocused = true
                    }
                }
                .font(.caption).buttonStyle(.bordered)
            }
            HStack(alignment: .center, spacing: 10) {
                TextField(model.hasResults ? "Refine your search…" : "Ask Naturebook…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...4).focused($inputFocused)
                    .frame(minHeight: 44)
                    .submitLabel(.search).onSubmit { submit() }
                    .accessibilityIdentifier("SpeciesSearchInput")
                Button { submit() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                        .foregroundStyle(canSubmit ? Color.primary : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(!canSubmit)
                .accessibilityLabel("Search Naturebook")
            }
            .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 5)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            if model.draft.utf16.count > 600 { Text("Use 600 characters or fewer.").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(uiColor: .systemGroupedBackground))
    }
    private var canSubmit: Bool {
        !model.isLoading && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.draft.utf16.count <= 600
    }
    private func submit(_ question: String? = nil) {
        guard question != nil || canSubmit else { return }
        inputFocused = false
        model.submit(question)
    }
}
