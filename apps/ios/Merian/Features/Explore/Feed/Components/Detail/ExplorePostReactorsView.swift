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
                    HStack(spacing: 8) {
                        Image(systemName: "person.2")
                        Text(summary).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
                .accessibilityHint("Show who reacted and which reactions they used")
                .accessibilityIdentifier("explore.reactions.summary")
            } else if model.isLoading {
                ProgressView("Loading reactions…").font(.caption).frame(minHeight: 44)
            } else if model.errorMessage != nil {
                Button("Couldn’t load reactions. Retry") { Task { await model.refresh() } }
                    .font(.caption).frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct ExplorePostReactorsSheet: View {
    @Bindable var model: ExplorePostReactorsViewModel
    @Environment(\.dismiss) private var dismiss
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
                            Text(reactor.displayName).font(.body.weight(.semibold))
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { await model.refresh() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .exploreVideoPresentedOverlayLifecycle(reason: "explore-post-reactors")
    }
}
