import SwiftUI

struct SpeciesSearchView: View {
    @Bindable var model: SpeciesSearchViewModel
    let exploreViewModel: ExploreFeedViewModel
    let onOpenPost: (ExplorePost) -> Void
    var starterImageDependencies: SpeciesCatalogImageDependencies = .live
    var sightingImageDependencies: ExploreHeroImageDependencies = .live
    @FocusState private var inputFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            if model.hasResults {
                resultsHeader
                SpeciesSearchResults(model: model, exploreViewModel: exploreViewModel,
                                     imageDependencies: starterImageDependencies,
                                     sightingImageDependencies: sightingImageDependencies) { post in
                    inputFocused = false
                    onOpenPost(post)
                }
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
        .task(id: model.generation) { await model.execute() }
        .onChange(of: model.needsClarification) { _, needsAnswer in
            if needsAnswer { inputFocused = true }
        }
        .onChange(of: model.sightings, initial: true) { previous, posts in
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
                    Group {
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
            if model.context?.media != nil {
                Text("Media filters apply to Sightings.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
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
