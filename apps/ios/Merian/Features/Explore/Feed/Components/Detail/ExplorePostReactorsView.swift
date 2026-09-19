import SwiftUI

struct ExplorePostReactionSummary: View {
    @Bindable var model: ExplorePostReactorsViewModel
    let onOpen: () -> Void

    var body: some View {
        Group {
            if let summary = model.summary {
                Button {
                    HapticManager.shared.triggerSheetSpring(source: "explore.reaction.people.open")
                    onOpen()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2").font(.caption)
                        Text(summary).font(.caption).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
                .accessibilityHint("Show who reacted and which reactions they used")
                .accessibilityIdentifier("explore.reactions.summary")
            }
        }
        .padding(.horizontal, 12)
    }
}

struct ExplorePostReactorsSheet: View {
    @Bindable var model: ExplorePostReactorsViewModel
    @ScaledMetric(relativeTo: .title3) private var emojiRowHeight: CGFloat = 48

    var body: some View {
        NavigationStack {
            List {
                if model.isLoading {
                    ProgressView("Loading reactions…")
                } else if model.hasLoaded && model.reactors.isEmpty {
                    ContentUnavailableView("No reactions yet", systemImage: "face.smiling")
                }
                ForEach(model.reactors) { reactor in
                    HStack(alignment: .top, spacing: 12) {
                        ExploreAuthorAvatar(url: reactor.avatarUrl.flatMap(URL.init(string:)), size: 44)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ExplorePost.publicAuthorDisplayName(
                                from: reactor.displayName, username: reactor.username, preferUsername: true
                            ))
                            .font(.body.weight(.semibold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 6) {
                                    ForEach(reactor.emojis, id: \.self) { emoji in
                                        Text(emoji).font(.title3)
                                            .padding(6)
                                            .background(.quaternary, in: Circle())
                                            .accessibilityLabel(ExploreEmojiCatalog.name(for: emoji))
                                    }
                                }
                            }
                            .frame(height: emojiRowHeight)
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
                }
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("Try again") {
                        Task {
                            if model.hasLoaded { await model.loadMore() } else { await model.refresh() }
                        }
                    }
                } else if model.isLoadingMore {
                    ProgressView()
                } else if model.nextCursor != nil {
                    Button("Load more") {
                        HapticManager.shared.triggerSelectionPulse(source: "explore.reaction.people.more")
                        Task { await model.loadMore() }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refresh() }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await model.refresh() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .exploreVideoPresentedOverlayLifecycle(reason: "explore-post-reactors")
    }
}
