import SwiftUI
import UIKit

struct ExplorePostCard: View {
    let post: ExplorePost
    let speciesDisplayName: String
    let mediaReloadGeneration: UInt64
    let authorPresentation: ExplorePostCardAuthorPresentation
    let onLike: () -> Void
    let onComments: () -> Void
    let onShare: () -> Void
    let onOpenDetail: () -> Void
    let onOpenAuthorProfile: () -> Void
    let onOpenHashtag: ((String) -> Void)?
    let onOpenInsight: (() -> Void)?
    let onEditPost: () -> Void
    let onUnshare: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void

    @State private var isShowingDoubleTapHeart = false
    @State private var doubleTapHeartScale: CGFloat = 0.7
    @State private var doubleTapHeartOpacity = 0.0
    @State private var doubleTapHeartTask: Task<Void, Never>?
    @State private var showUnpublishConfirmation = false
    @State private var isAudioBoostEnabled = false
    @State private var audioBoostActionToken: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 12)

            mediaView

            hashtagRow
                .padding(.top, 10)

            actionRow
                .padding(.horizontal, 16)
                .padding(.top, post.hashtags?.isEmpty == false ? 8 : 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .onAppear {
            guard hasStandalonePrimaryAudio else { return }
            let restored = ExploreAudioBoostPreferenceStore().isEnabled(for: post.id)
            isAudioBoostEnabled = restored
            if restored {
                AppTelemetry.trackExploreAudioBoost(event: "restored", surface: "feed")
            }
        }
        .onChange(of: isAudioBoostEnabled) { _, enabled in
            guard hasStandalonePrimaryAudio else { return }
            ExploreAudioBoostPreferenceStore().setEnabled(enabled, for: post.id)
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            guard case let .exploreAudioBoostPreferenceChanged(postId, enabled) = event,
                  postId == post.id,
                  enabled != isAudioBoostEnabled else { return }
            isAudioBoostEnabled = enabled
        }
        .onDisappear {
            doubleTapHeartTask?.cancel()
            doubleTapHeartTask = nil
        }
        .alert("Unpublish Post?", isPresented: $showUnpublishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unpublish", role: .destructive, action: onUnshare)
        } message: {
            Text("This will remove the post from Explore. Your original scan will remain safely in your library.")
        }
    }

    private var mediaView: some View {
        ExploreFeedMediaView(
            imageUrl: post.heroImageUrl,
            mediaItems: post.resolvedMediaItems,
            reloadGeneration: mediaReloadGeneration,
            audioBoostEnabled: $isAudioBoostEnabled,
            audioBoostActionToken: audioBoostActionToken,
            onAudioBoostActionFinished: finishAudioBoostAction,
            onAudioBoostToggleRequested: toggleAudioBoost,
            onSingleTap: onOpenDetail,
            onDoubleTap: handleDoubleTapLike
        )
        .overlay(alignment: .topLeading) {
            speciesOverlay
                .padding(14)
                .allowsHitTesting(false)
        }
        .overlay {
            if isShowingDoubleTapHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 92, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                    .scaleEffect(doubleTapHeartScale)
                    .opacity(doubleTapHeartOpacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                authorAvatarView

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(authorDisplayName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if shouldShowAuthorProBadge {
                            MerianProBadge()
                        }
                    }
                    .accessibilityElement(children: .combine)

                    if let locationText = locationText {
                        Text(locationText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenAuthorProfile)

            Spacer(minLength: 12)

            menuButton
        }
    }

    @ViewBuilder
    private var authorAvatarView: some View {
        if let avatarUrl = authorPresentation.avatarURL {
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

    private var displaySpeciesName: String {
        let common = speciesDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !common.isEmpty {
            return common
        }
        return post.speciesScientificName
    }

    // MARK: Species Overlay
    private var speciesOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displaySpeciesName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 99, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 99, style: .continuous)
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

    @ViewBuilder
    private var hashtagRow: some View {
        if let hashtags = post.hashtags, !hashtags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hashtags, id: \.self) { hashtag in
                        Button(action: { onOpenHashtag?(hashtag) }) {
                            ExploreHashtagPill(hashtag: hashtag)
                        }
                        .buttonStyle(.plain)
                        .disabled(onOpenHashtag == nil)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    private var menuButton: some View {
        Menu {
            if hasStandalonePrimaryAudio {
                Button(action: toggleAudioBoost) {
                    Label(
                        isAudioBoostEnabled ? "Turn off audio boost" : "Boost audio",
                        systemImage: isAudioBoostEnabled ? "speaker.wave.2" : "speaker.wave.3"
                    )
                }
            }

            if post.isOwnedByViewer {
                if let onOpenInsight {
                    Button(action: onOpenInsight) {
                        Label("View insight", systemImage: "sparkles")
                    }
                }

                Button(action: onEditPost) {
                    Label("Edit post", systemImage: "square.and.pencil")
                }

                Button(role: .destructive, action: { showUnpublishConfirmation = true }) {
                    Label("Unpublish post", systemImage: "minus.circle")
                }
                .tint(.red)
            } else {
                Button(role: .destructive, action: onBlock) {
                    Label("Block user", systemImage: "person.crop.circle.badge.xmark")
                }
                .tint(.red)

                Button(role: .destructive, action: onReport) {
                    Label("Report post", systemImage: "flag")
                }
                .tint(.red)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32, alignment: .center)
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }

    private func toggleAudioBoost() {
        if !isAudioBoostEnabled {
            audioBoostActionToken = UUID()
        }
        isAudioBoostEnabled.toggle()
        if isAudioBoostEnabled {
            HapticManager.shared.triggerMediumPulse(source: "media.explore.feed.audioBoost.enabled")
        } else {
            HapticManager.shared.triggerLightImpact(
                intensity: 0.5,
                source: "media.explore.feed.audioBoost.disabled"
            )
        }
    }

    private var hasStandalonePrimaryAudio: Bool {
        post.resolvedMediaItems.first?.kind == .audio
    }

    private func finishAudioBoostAction(_ token: UUID) {
        guard audioBoostActionToken == token else { return }
        audioBoostActionToken = nil
    }

    private var locationText: String? {
        post.publicDisplayLocationLabel
    }

    private var authorDisplayName: String {
        post.authorDisplayName(preferUsername: true)
    }

    private var shouldShowAuthorProBadge: Bool {
        authorPresentation.showsProBadge
    }

    private func compactCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    private func handleDoubleTapLike() {
        HapticManager.shared.triggerHeavyImpact(intensity: 1.0)

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
        @Environment(\.colorScheme) private var colorScheme
        @State private var isGlowing = false

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
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(glowOverlay)
            .shadow(color: glowShadowColor, radius: isGlowing ? 22 : 10, x: 0, y: 0)
            .opacity(isGlowing ? 1.0 : 0.92)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isGlowing = true
                }
            }
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
                        .fill(placeholderFill(secondary: true))
                        .frame(width: 88, height: 12)
                }

                Spacer(minLength: 12)

                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 28, height: 28)
            }
        }

        private var mediaView: some View {
            ExploreSquareMediaView {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                placeholderFill(secondary: true),
                                placeholderFill()
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(glowColor.opacity(isGlowing ? 0.14 : 0.04))
                            .blur(radius: isGlowing ? 18 : 8)
                    )
            }
            .overlay(alignment: .topLeading) {
                speciesOverlay
                    .padding(14)
            }
        }

        // MARK: Species Overlay
        private var speciesOverlay: some View {
            VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(glowColor.opacity(isGlowing ? 0.8 : 0.55))
                    .frame(width: 170, height: 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 99, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 99, style: .continuous)
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
                    .fill(placeholderFill(secondary: true))
                    .frame(width: 24, height: 24)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(placeholderFill())
                    .frame(width: 18, height: 14)
            }
        }

        private var glowOverlay: some View {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(glowColor.opacity(isGlowing ? 0.42 : 0.14), lineWidth: 1)
                .blur(radius: isGlowing ? 12 : 6)
                .padding(.horizontal, 4)
        }

        private var glowColor: Color {
            colorScheme == .dark ? .white : Color(red: 0.92, green: 0.95, blue: 1.0)
        }

        private var glowShadowColor: Color {
            colorScheme == .dark
                ? glowColor.opacity(isGlowing ? 0.18 : 0.06)
                : glowColor.opacity(isGlowing ? 0.65 : 0.24)
        }

        private func placeholderFill(secondary: Bool = false) -> Color {
            if colorScheme == .dark {
                return secondary
                    ? Color(uiColor: .secondarySystemFill)
                    : Color(uiColor: .tertiarySystemFill)
            }

            let base = secondary
                ? Color(uiColor: .secondarySystemFill)
                : Color(uiColor: .tertiarySystemFill)
            return base.opacity(isGlowing ? 0.86 : 0.66)
        }
    }
}
