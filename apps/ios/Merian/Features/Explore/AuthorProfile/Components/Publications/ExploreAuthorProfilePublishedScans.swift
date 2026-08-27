import SwiftUI

struct ExploreAuthorProfilePublishedPreview: View {
    let profile: ExploreAuthorProfile
    let posts: [ExplorePost]
    let mediaReloadGeneration: UInt64
    let localReferenceUrl: (ExplorePost) -> String?
    let resolvedCommonName: (ExplorePost) -> String
    let onOpenPost: (ExplorePost) -> Void
    let onShowLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Published scans")
                    .font(.title3.weight(.bold))

                Spacer()

                Text(profile.publishedPostCount.formatted(.number.notation(.compactName)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if posts.isEmpty {
                Text("No published scans are visible right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            } else {
                ExploreAuthorProfileGrid(
                    posts: posts,
                    mediaReloadGeneration: mediaReloadGeneration,
                    appliesCornerRounding: true,
                    localReferenceUrl: localReferenceUrl,
                    resolvedCommonName: resolvedCommonName,
                    onOpenPost: onOpenPost
                )
            }

            if profile.publishedPostCount > ExploreAuthorProfilePresentation.previewLimit {
                Button(action: onShowLibrary) {
                    HStack(spacing: 4) {
                        Text("View more scans")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ExploreAuthorProfileLibraryView: View {
    let profile: ExploreAuthorProfile
    let posts: [ExplorePost]
    let isLoading: Bool
    let mediaReloadGeneration: UInt64
    let localReferenceUrl: (ExplorePost) -> String?
    let resolvedCommonName: (ExplorePost) -> String
    let onOpenPost: (ExplorePost) -> Void
    let onLoadMore: () -> Void
    let onRefresh: @MainActor @Sendable () async -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                libraryHeader

                if posts.isEmpty && isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if posts.isEmpty {
                    EmptyStateView(
                        iconName: "square.grid.3x3",
                        title: "No published scans",
                        message: "Published scans that are visible to you will appear here."
                    )
                    .frame(minHeight: 360)
                    .padding(.horizontal, 16)
                } else {
                    ExploreAuthorProfileGrid(
                        posts: posts,
                        mediaReloadGeneration: mediaReloadGeneration,
                        localReferenceUrl: localReferenceUrl,
                        resolvedCommonName: resolvedCommonName,
                        onOpenPost: onOpenPost,
                        onLoadMore: onLoadMore
                    )
                }

                if isLoading && !posts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable {
            await onRefresh()
        }
    }

    private var libraryHeader: some View {
        HStack(spacing: 12) {
            ExploreAuthorAvatar(url: profile.authorAvatarURL, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.profileTitle)
                    .font(.headline)
                    .lineLimit(1)

                if let username = profile.publicUsernameDisplayName,
                   username != profile.profileTitle {
                    Text(username)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(
                    "\(profile.publishedPostCount.formatted(.number)) " +
                        "published scan\(profile.publishedPostCount == 1 ? "" : "s")"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .padding(.horizontal, 16)
    }
}

private struct ExploreAuthorProfileGrid: View {
    let posts: [ExplorePost]
    let mediaReloadGeneration: UInt64
    var appliesCornerRounding = false
    let localReferenceUrl: (ExplorePost) -> String?
    let resolvedCommonName: (ExplorePost) -> String
    let onOpenPost: (ExplorePost) -> Void
    var onLoadMore: (() -> Void)?

    private let columns = PublishedScanGridStyle.columns

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                Button {
                    onOpenPost(post)
                } label: {
                    ExploreHeroImageView(
                        imageUrl: post.gridThumbnailUrl(
                            localReferenceUrl: localReferenceUrl(post)
                        ),
                        reloadGeneration: mediaReloadGeneration,
                        maxDimension: 360
                    )
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if post.hasVideoMedia || post.hasAudioMedia {
                            ExploreMediaTypeIndicator(kind: post.hasVideoMedia ? .video : .audio)
                                .padding(8)
                        }
                    }
                    .modifier(ExploreAuthorProfileGridCorners(
                        index: index,
                        itemCount: posts.count,
                        isEnabled: appliesCornerRounding
                    ))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(resolvedCommonName(post)), published scan")
                .onAppear {
                    guard post.id == posts.last?.id else { return }
                    onLoadMore?()
                }
            }
        }
    }
}

private struct ExploreAuthorProfileGridCorners: ViewModifier {
    let index: Int
    let itemCount: Int
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.publishedScanTileCorners(index: index, itemCount: itemCount)
        } else {
            content
        }
    }
}
