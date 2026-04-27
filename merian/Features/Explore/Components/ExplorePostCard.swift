import SwiftUI

struct ExplorePostCard: View {
    let post: ExplorePost
    let onLike: () -> Void
    let onComments: () -> Void
    let onShare: () -> Void
    let onUnshare: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void

    @State private var isShowingDoubleTapHeart = false
    @State private var doubleTapHeartScale: CGFloat = 0.7
    @State private var doubleTapHeartOpacity = 0.0
    @State private var doubleTapHeartTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 12)

            mediaView

            actionRow
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear {
            doubleTapHeartTask?.cancel()
            doubleTapHeartTask = nil
        }
    }

    private var mediaView: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: post.heroImageUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    ZStack {
                        LinearGradient(
                            colors: [Color(uiColor: .tertiarySystemFill), Color(uiColor: .secondarySystemFill)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                case .empty:
                    ZStack {
                        Color(uiColor: .tertiarySystemFill)
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                @unknown default:
                    Color(uiColor: .tertiarySystemFill)
                }
            }

            if isShowingDoubleTapHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 92, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                    .scaleEffect(doubleTapHeartScale)
                    .opacity(doubleTapHeartOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            speciesOverlay
                .padding(14)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: handleDoubleTapLike)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            authorAvatarView

            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let locationText = locationText {
                    Text(locationText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            menuButton
        }
    }

    @ViewBuilder
    private var authorAvatarView: some View {
        if let avatarUrl = resolvedAuthorAvatarUrl {
            AsyncImage(url: avatarUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackAuthorAvatar
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackAuthorAvatar
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            fallbackAuthorAvatar
        }
    }

    private var fallbackAuthorAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 38, weight: .regular))
            .foregroundStyle(.primary)
    }

    private var resolvedAuthorAvatarUrl: URL? {
        if let avatarUrlString = post.authorAvatarUrl,
           let avatarUrl = URL(string: avatarUrlString) {
            return avatarUrl
        }

        let currentUserId = SupabaseManager.shared.currentUser?.id.uuidString
        let isCurrentUsersPost = post.isOwnedByViewer || currentUserId == post.authorUserId
        if isCurrentUsersPost {
            return SupabaseManager.shared.currentUserAvatarUrl
        }

        return nil
    }

    private var speciesOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(post.speciesCommonName.capitalized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(post.speciesScientificName)
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.0), .white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
    }

    private var actionRow: some View {
        HStack(spacing: 20) {
            ExploreFeedActionButton(
                systemImage: post.viewerHasLiked ? "heart.fill" : "heart",
                value: compactCount(post.likeCount),
                isHighlighted: post.viewerHasLiked,
                action: onLike
            )

            ExploreFeedActionButton(
                systemImage: "bubble.right",
                value: compactCount(post.commentCount),
                isHighlighted: false,
                action: onComments
            )

            Spacer(minLength: 12)

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share post")
        }
    }

    private var menuButton: some View {
        Menu {
            if post.isOwnedByViewer {
                Button(role: .destructive, action: onUnshare) {
                    Label("Remove post", systemImage: "trash")
                }
            } else {
                Button(role: .destructive, action: onBlock) {
                    Label("Block user", systemImage: "person.crop.circle.badge.xmark")
                }

                Button(role: .destructive, action: onReport) {
                    Label("Report post", systemImage: "flag")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32, alignment: .center)
        }
        .buttonStyle(.plain)
    }

    private var locationText: String? {
        guard let publicLocationLabel = post.publicLocationLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !publicLocationLabel.isEmpty else {
            return nil
        }

        return publicLocationLabel
    }

    private func compactCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    private func handleDoubleTapLike() {
        if !post.viewerHasLiked {
            onLike()
        }

        doubleTapHeartTask?.cancel()
        isShowingDoubleTapHeart = true
        doubleTapHeartScale = 0.7
        doubleTapHeartOpacity = 0.0

        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            doubleTapHeartScale = 1.0
            doubleTapHeartOpacity = 1.0
        }

        doubleTapHeartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.35)) {
                doubleTapHeartScale = 1.12
                doubleTapHeartOpacity = 0.0
            }

            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            isShowingDoubleTapHeart = false
            doubleTapHeartTask = nil
        }
    }
}

private struct ExploreFeedActionButton: View {
    let systemImage: String
    let value: String
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(isHighlighted ? Color.red : Color.primary)

                Text(value)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

extension ExplorePostCard {
    struct Skeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                mediaView

                actionRow
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .shimmering()
            .accessibilityHidden(true)
        }

        private var headerRow: some View {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                        .frame(width: 112, height: 16)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 88, height: 12)
                }

                Spacer(minLength: 12)

                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 28, height: 28)
            }
        }

        private var mediaView: some View {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(uiColor: .tertiarySystemFill),
                                Color(uiColor: .secondarySystemFill)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                speciesOverlay
                    .padding(14)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
        }

        private var speciesOverlay: some View {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 170, height: 16)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 130, height: 12)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.0), .white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
        }

        private var actionRow: some View {
            HStack(spacing: 20) {
                actionGroup
                actionGroup

                Spacer(minLength: 12)

                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 24, height: 24)
            }
        }

        private var actionGroup: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 24, height: 24)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(width: 18, height: 14)
            }
        }
    }
}
