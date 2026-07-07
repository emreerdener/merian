import AVKit
import SwiftUI
import UIKit

struct ExploreProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .black))
            .tracking(0.5)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary)
            }
            .accessibilityLabel("Pro")
    }
}

struct ExploreHashtagPill: View {
    let hashtag: String

    var body: some View {
        Text("#\(hashtag)")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
            )
    }
}

struct ExplorePostCard: View {
    let post: ExplorePost
    let speciesDisplayName: String
    let mediaReloadGeneration: UInt64
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
                            ExploreProBadge()
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

    private var locationText: String? {
        post.publicDisplayLocationLabel
    }

    private var authorDisplayName: String {
        post.authorDisplayName(preferUsername: true)
    }

    private var shouldShowAuthorProBadge: Bool {
        post.authorIsPro == true
            || (post.isOwnedByViewer && RevenueCatManager.shared.isProActive)
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

private struct ExploreSquareMediaView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

struct ExploreFeedMediaView: View {
    let imageUrl: String
    let mediaItems: [ExploreMediaItem]
    let reloadGeneration: UInt64
    let preloadedImage: UIImage?
    let onSingleTap: (() -> Void)?
    let onDoubleTap: (() -> Void)?

    init(
        imageUrl: String,
        mediaItems: [ExploreMediaItem]? = nil,
        reloadGeneration: UInt64,
        preloadedImage: UIImage? = nil,
        onSingleTap: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil
    ) {
        self.imageUrl = imageUrl
        self.mediaItems = mediaItems?.isEmpty == false ? mediaItems! : [.legacyImage(url: imageUrl)]
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
        self.onSingleTap = onSingleTap
        self.onDoubleTap = onDoubleTap
    }

    var body: some View {
        // The scrolling feed intentionally uses a plain image host instead of the zoom wrapper.
        // That keeps every card on a stable square layout proposal regardless of source aspect ratio.
        ExploreSquareMediaView {
            ExplorePublicMediaView(
                mediaItem: mediaItems.first ?? .legacyImage(url: imageUrl),
                fallbackImageUrl: imageUrl,
                reloadGeneration: reloadGeneration,
                preloadedImage: preloadedImage,
                autoplay: true,
                showsVideoControls: true,
                onSingleTap: onSingleTap,
                onDoubleTap: onDoubleTap
            )
        }
    }
}

struct ExploreDetailMediaView: View {
    let imageUrl: String
    let mediaItems: [ExploreMediaItem]
    let reloadGeneration: UInt64
    let preloadedImage: UIImage?
    let allowsZoom: Bool

    init(
        imageUrl: String,
        mediaItems: [ExploreMediaItem]? = nil,
        reloadGeneration: UInt64,
        preloadedImage: UIImage? = nil,
        allowsZoom: Bool = true
    ) {
        self.imageUrl = imageUrl
        self.mediaItems = mediaItems?.isEmpty == false ? mediaItems! : [.legacyImage(url: imageUrl)]
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
        self.allowsZoom = allowsZoom
    }

    var body: some View {
        // Detail is the only path that opts into transient zoom behavior.
        ExploreSquareMediaView {
            if allowsZoom && primaryMediaItem.kind == .image {
                ExploreDetailZoomView {
                    heroImage
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                heroImage
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var primaryMediaItem: ExploreMediaItem {
        mediaItems.first ?? .legacyImage(url: imageUrl)
    }

    private var heroImage: some View {
        ExplorePublicMediaView(
            mediaItem: primaryMediaItem,
            fallbackImageUrl: imageUrl,
            reloadGeneration: reloadGeneration,
            preloadedImage: preloadedImage,
            autoplay: true,
            showsVideoControls: true,
            allowsAutoplayInLowPowerMode: true
        )
    }
}

private enum ExploreVideoAutoplayCoordinator {
    static let activePlayerDidChange = Notification.Name("MerianExploreActiveVideoPlayerDidChange")

    static func activate(_ id: String) {
        NotificationCenter.default.post(
            name: activePlayerDidChange,
            object: id
        )
    }
}

struct ExplorePublicMediaView: View {
    let mediaItem: ExploreMediaItem
    let fallbackImageUrl: String
    let reloadGeneration: UInt64
    let preloadedImage: UIImage?
    let autoplay: Bool
    let showsVideoControls: Bool
    let allowsAutoplayInLowPowerMode: Bool
    let onSingleTap: (() -> Void)?
    let onDoubleTap: (() -> Void)?

    @State private var player: AVPlayer?
    @State private var playerId = UUID().uuidString
    @State private var configuredVideoURL: String?
    @State private var playbackEndObserver: NSObjectProtocol?
    @State private var isPlaying = false
    @State private var isMuted = true

    init(
        mediaItem: ExploreMediaItem,
        fallbackImageUrl: String,
        reloadGeneration: UInt64,
        preloadedImage: UIImage?,
        autoplay: Bool,
        showsVideoControls: Bool,
        allowsAutoplayInLowPowerMode: Bool = false,
        onSingleTap: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil
    ) {
        self.mediaItem = mediaItem
        self.fallbackImageUrl = fallbackImageUrl
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
        self.autoplay = autoplay
        self.showsVideoControls = showsVideoControls
        self.allowsAutoplayInLowPowerMode = allowsAutoplayInLowPowerMode
        self.onSingleTap = onSingleTap
        self.onDoubleTap = onDoubleTap
    }

    var body: some View {
        ZStack {
            posterImage

            if mediaItem.kind == .video, let player {
                ExploreCoverVideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                    .opacity(0.96)
            }

            mediaTapLayer

            if mediaItem.kind == .video {
                videoOverlay
            }
        }
        .task(id: "\(mediaItem.url)|\(reloadGeneration)") {
            configurePlayer()
            startAutoplayIfNeeded(ignoreLowPowerMode: allowsAutoplayInLowPowerMode)
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: ExploreVideoAutoplayCoordinator.activePlayerDidChange)) { notification in
            guard let activeId = notification.object as? String,
                  activeId != playerId else { return }
            player?.pause()
            isPlaying = false
        }
    }

    private var posterImage: some View {
        ExploreHeroImageView(
            imageUrl: mediaItem.thumbnailUrl ?? fallbackImageUrl,
            reloadGeneration: reloadGeneration,
            preloadedImage: preloadedImage
        )
    }

    @ViewBuilder
    private var mediaTapLayer: some View {
        if hasMediaTapActions {
            Color.clear
                .contentShape(Rectangle())
                .gesture(mediaTapGesture)
        }
    }

    private var hasMediaTapActions: Bool {
        onSingleTap != nil || onDoubleTap != nil
    }

    private var mediaTapGesture: some Gesture {
        ExclusiveGesture(
            TapGesture(count: 2).onEnded {
                onDoubleTap?()
            },
            TapGesture().onEnded {
                onSingleTap?()
            }
        )
    }

    @ViewBuilder
    private var videoOverlay: some View {
        ZStack {
            if showsVideoControls {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(.black.opacity(isPlaying ? 0.32 : 0.46), in: Circle())
                        .shadow(color: .black.opacity(0.26), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause video" : "Play video")
            } else {
                VStack {
                    HStack {
                        ExploreMediaPlayIndicator()
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }

            if showsVideoControls {
                VStack {
                    HStack {
                        Spacer()

                        Button {
                            isMuted.toggle()
                            player?.isMuted = isMuted
                            if player?.timeControlStatus != .playing {
                                startAutoplayIfNeeded(force: true)
                            }
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.42), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isMuted ? "Unmute video" : "Mute video")
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private func configurePlayer() {
        guard mediaItem.kind == .video,
              let url = URL(string: mediaItem.url) else {
            cleanupPlayer()
            return
        }
        guard configuredVideoURL != mediaItem.url || player == nil else { return }

        cleanupPlayer()
        isPlaying = false
        let player = AVPlayer(url: url)
        player.isMuted = isMuted
        player.actionAtItemEnd = .none
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            guard let player else { return }
            player.seek(to: .zero)
            if isPlaying {
                player.play()
            }
        }
        configuredVideoURL = mediaItem.url
        self.player = player
    }

    private func cleanupPlayer() {
        player?.pause()
        isPlaying = false
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        configuredVideoURL = nil
        player = nil
    }

    private func togglePlayback() {
        guard let player else {
            configurePlayer()
            startAutoplayIfNeeded(force: true)
            return
        }

        if isPlaying || player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            startAutoplayIfNeeded(force: true)
        }
    }

    private func startAutoplayIfNeeded(force: Bool = false, ignoreLowPowerMode: Bool = false) {
        guard mediaItem.kind == .video,
              let player,
              autoplay || force,
              force || ignoreLowPowerMode || !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        ExploreVideoAutoplayCoordinator.activate(playerId)
        player.play()
        isPlaying = true
    }
}

private struct ExploreCoverVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspectFill
        controller.showsPlaybackControls = false
        controller.view.backgroundColor = .black
        controller.view.clipsToBounds = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.videoGravity = .resizeAspectFill
        controller.showsPlaybackControls = false
        controller.view.clipsToBounds = true
    }
}

struct ExploreMediaPlayIndicator: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(.black.opacity(0.42), in: Circle())
            .accessibilityLabel("Video")
    }
}

struct ExploreHeroImageView: View {
    let imageUrl: String
    let reloadGeneration: UInt64
    let maxDimension: Int
    private let preloadedImage: UIImage?

    @State private var loadedImage: UIImage?
    @State private var hasFailedToLoad = false

    init(
        imageUrl: String,
        reloadGeneration: UInt64,
        maxDimension: Int = Int(MerianConfig.displayImageMaxSize),
        preloadedImage: UIImage? = nil
    ) {
        self.imageUrl = imageUrl
        self.reloadGeneration = reloadGeneration
        self.maxDimension = maxDimension
        self.preloadedImage = preloadedImage
        _loadedImage = State(initialValue: preloadedImage)
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFill()
                } else if hasFailedToLoad {
                    failurePlaceholder
                } else {
                    loadingPlaceholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(imageUrl)|\(reloadGeneration)") {
            guard preloadedImage == nil else {
                hasFailedToLoad = false
                return
            }

            loadedImage = nil
            hasFailedToLoad = false

            let image = await LocalImageLoader.shared.loadImage(
                fromPath: nil,
                fallbackUrl: imageUrl,
                maxDimension: maxDimension
            )
            guard !Task.isCancelled else { return }

            if let image {
                loadedImage = image
            } else {
                hasFailedToLoad = true
            }
        }
    }

    private var loadingPlaceholder: some View {
        GlowPulsingSkeletonView(cornerRadius: 12)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failurePlaceholder: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct ExploreDetailZoomView<Content: View>: UIViewControllerRepresentable {
    private let content: Content
    private let onSingleTap: (() -> Void)?
    private let onDoubleTap: (() -> Void)?

    init(
        onSingleTap: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.onSingleTap = onSingleTap
        self.onDoubleTap = onDoubleTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear

        let scrollView = ExploreDetailZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        viewController.view.addSubview(scrollView)
        scrollView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostingController.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        viewController.addChild(hostingController)
        hostingController.didMove(toParent: viewController)

        context.coordinator.hostingController = hostingController
        context.coordinator.scrollView = scrollView
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTap = onDoubleTap

        if onDoubleTap != nil {
            let doubleTapRecognizer = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleDoubleTap(_:))
            )
            doubleTapRecognizer.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTapRecognizer)
            context.coordinator.doubleTapRecognizer = doubleTapRecognizer
        }

        if onSingleTap != nil {
            let singleTapRecognizer = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleSingleTap(_:))
            )
            if let doubleTapRecognizer = context.coordinator.doubleTapRecognizer {
                singleTapRecognizer.require(toFail: doubleTapRecognizer)
            }
            scrollView.addGestureRecognizer(singleTapRecognizer)
            context.coordinator.singleTapRecognizer = singleTapRecognizer
        }

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.hostingController?.rootView = content
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.layoutHostedContent(in: uiViewController)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: UIViewController,
        context: Context
    ) -> CGSize? {
        let side = proposal.width ?? proposal.height
        let width = proposal.width ?? side
        let height = proposal.height ?? side

        guard let width, let height else { return nil }
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?
        weak var scrollView: UIScrollView?
        var onSingleTap: (() -> Void)?
        var onDoubleTap: (() -> Void)?
        weak var singleTapRecognizer: UITapGestureRecognizer?
        weak var doubleTapRecognizer: UITapGestureRecognizer?

        func layoutHostedContent(in viewController: UIViewController) {
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()
            scrollView?.setNeedsLayout()
            scrollView?.layoutIfNeeded()
            hostingController?.view.setNeedsLayout()
            hostingController?.view.layoutIfNeeded()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let view = hostingController?.view else { return }

            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
            view.center = CGPoint(
                x: scrollView.contentSize.width * 0.5 + offsetX,
                y: scrollView.contentSize.height * 0.5 + offsetY
            )
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            snapBackToIdentity(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 else { return }

            if decelerate {
                scrollView.setContentOffset(scrollView.contentOffset, animated: false)
            }

            snapBackToIdentity(scrollView)
        }

        @objc
        func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView,
                  scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
                return
            }

            onSingleTap?()
        }

        @objc
        func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView,
                  scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else {
                return
            }

            onDoubleTap?()
        }

        private func snapBackToIdentity(_ scrollView: UIScrollView) {
            UIView.animate(
                withDuration: 0.38,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.3,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                scrollView.setZoomScale(1.0, animated: false)
                scrollView.contentOffset = .zero
            }
        }
    }
}

private final class ExploreDetailZoomScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            return zoomScale > minimumZoomScale + 0.01
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

#if DEBUG
private enum ExploreMediaPreviewFixtures {
    static let landscape = makeImage(
        size: CGSize(width: 1200, height: 800),
        topColor: .systemTeal,
        bottomColor: .systemOrange
    )

    static let portrait = makeImage(
        size: CGSize(width: 800, height: 1200),
        topColor: .systemPink,
        bottomColor: .systemIndigo
    )

    static let square = makeImage(
        size: CGSize(width: 1000, height: 1000),
        topColor: .systemGreen,
        bottomColor: .systemBlue
    )

    private static func makeImage(
        size: CGSize,
        topColor: UIColor,
        bottomColor: UIColor
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            topColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.5))

            bottomColor.setFill()
            context.fill(CGRect(x: 0, y: bounds.height * 0.5, width: bounds.width, height: bounds.height * 0.5))
        }
    }
}

#Preview("Explore Feed Media - Landscape") {
    ExploreFeedMediaView(
        imageUrl: "preview-landscape",
        reloadGeneration: 0,
        preloadedImage: ExploreMediaPreviewFixtures.landscape
    )
    .padding()
    .background(Color(uiColor: .secondarySystemGroupedBackground))
}

#Preview("Explore Feed Media - Portrait") {
    ExploreFeedMediaView(
        imageUrl: "preview-portrait",
        reloadGeneration: 0,
        preloadedImage: ExploreMediaPreviewFixtures.portrait
    )
    .padding()
    .background(Color(uiColor: .secondarySystemGroupedBackground))
}

#Preview("Explore Detail Media - Square") {
    ExploreDetailMediaView(
        imageUrl: "preview-square",
        reloadGeneration: 0,
        preloadedImage: ExploreMediaPreviewFixtures.square
    )
    .padding()
    .background(Color(uiColor: .secondarySystemGroupedBackground))
}
#endif
