import AVFoundation
import Combine
import SwiftUI
import UIKit

enum ExploreVideoMutePreference {
    static let key = "MerianExplorePublicVideoMuted"
    static let didResetNotification = Notification.Name("ExploreVideoMutePreferenceDidReset")

    static func resetToMuted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
        NotificationCenter.default.post(name: didResetNotification, object: nil)
    }
}

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
        .onReceive(
            NotificationCenter.default.publisher(
                for: ExploreAudioBoostPreferenceStore.didChangeNotification
            )
        ) { notification in
            guard notification.userInfo?[ExploreAudioBoostPreferenceStore.postIdUserInfoKey] as? String == post.id,
                  let enabled = notification.userInfo?[ExploreAudioBoostPreferenceStore.enabledUserInfoKey] as? Bool,
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
    @Binding var audioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?
    let onSingleTap: (() -> Void)?
    let onDoubleTap: (() -> Void)?

    init(
        imageUrl: String,
        mediaItems: [ExploreMediaItem]? = nil,
        reloadGeneration: UInt64,
        preloadedImage: UIImage? = nil,
        audioBoostEnabled: Binding<Bool> = .constant(false),
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil,
        onSingleTap: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil
    ) {
        self.imageUrl = imageUrl
        self.mediaItems = mediaItems?.isEmpty == false ? mediaItems! : [.legacyImage(url: imageUrl)]
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
        self._audioBoostEnabled = audioBoostEnabled
        self.audioBoostActionToken = audioBoostActionToken
        self.onAudioBoostActionFinished = onAudioBoostActionFinished
        self.onAudioBoostToggleRequested = onAudioBoostToggleRequested
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
                surface: .feed,
                autoplay: true,
                showsVideoControls: true,
                audioBoostEnabled: audioBoostEnabled,
                audioBoostActionToken: audioBoostActionToken,
                onAudioBoostActionFinished: onAudioBoostActionFinished,
                onAudioBoostToggleRequested: onAudioBoostToggleRequested,
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
    @Binding var audioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?

    init(
        imageUrl: String,
        mediaItems: [ExploreMediaItem]? = nil,
        reloadGeneration: UInt64,
        preloadedImage: UIImage? = nil,
        allowsZoom: Bool = true,
        audioBoostEnabled: Binding<Bool> = .constant(false),
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil
    ) {
        self.imageUrl = imageUrl
        self.mediaItems = mediaItems?.isEmpty == false ? mediaItems! : [.legacyImage(url: imageUrl)]
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
        self.allowsZoom = allowsZoom
        self._audioBoostEnabled = audioBoostEnabled
        self.audioBoostActionToken = audioBoostActionToken
        self.onAudioBoostActionFinished = onAudioBoostActionFinished
        self.onAudioBoostToggleRequested = onAudioBoostToggleRequested
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
            surface: .detail,
            autoplay: true,
            showsVideoControls: true,
            allowsAutoplayInLowPowerMode: true,
            audioBoostEnabled: audioBoostEnabled,
            audioBoostActionToken: audioBoostActionToken,
            onAudioBoostActionFinished: onAudioBoostActionFinished,
            onAudioBoostToggleRequested: onAudioBoostToggleRequested
        )
    }
}

struct ExploreVideoPlaybackOverlayState: Equatable {
    enum Event: Equatable {
        case autoplayStarted
        case playerBecamePlaying
        case playbackStarted
        case playbackPaused
        case playbackTemporarilyPaused
        case playbackWaiting
        case playbackUnavailable
        case playbackInterrupted
        case recoveryRebuildCompleted
        case revealControls
        case controlFadeCompleted
    }

    private(set) var isPlaying: Bool
    private(set) var showsPlaybackControl: Bool
    private(set) var needsPlayerRebuildForRecovery: Bool
    private(set) var isAutoplayControlSuppressed: Bool

    init(
        isPlaying: Bool = false,
        showsPlaybackControl: Bool = true,
        needsPlayerRebuildForRecovery: Bool = false,
        isAutoplayControlSuppressed: Bool = false
    ) {
        self.isPlaying = isPlaying
        self.showsPlaybackControl = showsPlaybackControl
        self.needsPlayerRebuildForRecovery = needsPlayerRebuildForRecovery
        self.isAutoplayControlSuppressed = isAutoplayControlSuppressed
    }

    mutating func reduce(_ event: Event) {
        switch event {
        case .autoplayStarted:
            isPlaying = true
            showsPlaybackControl = false
            needsPlayerRebuildForRecovery = false
            isAutoplayControlSuppressed = true
        case .playerBecamePlaying:
            isPlaying = true
            needsPlayerRebuildForRecovery = false
            if isAutoplayControlSuppressed {
                showsPlaybackControl = false
            }
        case .playbackStarted:
            isPlaying = true
            showsPlaybackControl = true
            needsPlayerRebuildForRecovery = false
            isAutoplayControlSuppressed = false
        case .playbackPaused:
            isPlaying = false
            showsPlaybackControl = true
            isAutoplayControlSuppressed = false
        case .playbackTemporarilyPaused:
            break
        case .playbackWaiting:
            if !isPlaying {
                showsPlaybackControl = true
                isAutoplayControlSuppressed = false
            }
        case .playbackUnavailable:
            isPlaying = false
            showsPlaybackControl = true
            needsPlayerRebuildForRecovery = false
            isAutoplayControlSuppressed = false
        case .playbackInterrupted:
            isPlaying = false
            showsPlaybackControl = true
            needsPlayerRebuildForRecovery = true
            isAutoplayControlSuppressed = false
        case .recoveryRebuildCompleted:
            needsPlayerRebuildForRecovery = false
            showsPlaybackControl = true
            isAutoplayControlSuppressed = false
        case .revealControls:
            showsPlaybackControl = true
            isAutoplayControlSuppressed = false
        case .controlFadeCompleted:
            showsPlaybackControl = !isPlaying || needsPlayerRebuildForRecovery
        }
    }
}

enum ExploreFeedMediaInteractionPolicy {
    static let centerPlaybackHitSize: CGFloat = 96

    static func usesCenterPlaybackZone(
        surface: ExploreVideoPlaybackSurface,
        mediaKind: ExploreMediaKind,
        hasNavigationAction: Bool
    ) -> Bool {
        guard hasNavigationAction else { return false }
        guard mediaKind == .video || mediaKind == .audio else { return false }
        if case .feed = surface { return true }
        return false
    }
}

enum ExploreFeedAudioBoostPillState: Equatable {
    case boost
    case boosting
    case reverting
    case boosted

    static func resolve(
        surface: ExploreVideoPlaybackSurface,
        mediaKind: ExploreMediaKind,
        isBoostEnabled: Bool,
        isPreparingBoost: Bool = false,
        isRevertingBoost: Bool = false,
        isBoostedAudioReady: Bool,
        hasToggleAction: Bool
    ) -> Self? {
        guard surface == .feed || surface == .detail,
              mediaKind == .audio,
              hasToggleAction else { return nil }
        if isBoostEnabled && isPreparingBoost { return .boosting }
        if !isBoostEnabled && isRevertingBoost { return .reverting }
        return isBoostEnabled && isBoostedAudioReady ? .boosted : .boost
    }

    var title: String {
        switch self {
        case .boost: "Boost audio"
        case .boosting: "Boosting…"
        case .reverting: "Reverting…"
        case .boosted: "Boosted audio"
        }
    }

    var systemImage: String? {
        self == .boost ? "chevron.right" : nil
    }

    var accessibilityLabel: String {
        switch self {
        case .boost: "Boost audio"
        case .boosting: "Boosting audio"
        case .reverting: "Reverting audio boost"
        case .boosted: "Turn off audio boost"
        }
    }
}

struct ExploreVideoPlaybackResumeIntentState: Equatable {
    private(set) var shouldResumeAfterSystemInterruption = false

    mutating func markSystemInterruption(shouldResume: Bool) {
        shouldResumeAfterSystemInterruption = shouldResumeAfterSystemInterruption || shouldResume
    }

    mutating func consumeSystemResumeIntent() -> Bool {
        let shouldResume = shouldResumeAfterSystemInterruption
        shouldResumeAfterSystemInterruption = false
        return shouldResume
    }

    mutating func clear() {
        shouldResumeAfterSystemInterruption = false
    }
}

struct ExplorePublicMediaView: View {
    let mediaItem: ExploreMediaItem
    let fallbackImageUrl: String
    let reloadGeneration: UInt64
    let preloadedImage: UIImage?
    let surface: ExploreVideoPlaybackSurface
    let autoplay: Bool
    let showsVideoControls: Bool
    let allowsAutoplayInLowPowerMode: Bool
    let onSingleTap: (() -> Void)?
    let onDoubleTap: (() -> Void)?
    let audioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?

    @Environment(ExploreVideoPlaybackCoordinator.self) private var playbackCoordinator: ExploreVideoPlaybackCoordinator?
    @State private var player: AVPlayer?
    @State private var playerId = UUID().uuidString
    @State private var configuredVideoURL: String?
    @State private var videoSurfaceGeneration = 0
    @State private var pendingRecoverySeekTime: CMTime?
    @State private var playbackObservers: [NSObjectProtocol] = []
    @State private var playbackTimeObserver: Any?
    @State private var audioPlaybackProgress = 0.0
    @State private var audioElapsedSeconds = 0.0
    @State private var audioDurationSeconds = 0.0
    @State private var playbackStatusObserver: AnyCancellable?
    @State private var playerItemStatusObserver: AnyCancellable?
    @State private var isPlayerItemReady = false
    @State private var playbackOverlayState = ExploreVideoPlaybackOverlayState()
    @State private var playbackControlFadeTask: Task<Void, Never>?
    @State private var playbackRecoveryWatchdogTask: Task<Void, Never>?
    @State private var unexpectedPauseRecoveryTask: Task<Void, Never>?
    @State private var playbackResumeIntentState = ExploreVideoPlaybackResumeIntentState()
    @State private var hasTrackedAudioPlaybackStart = false
    @State private var hasActivatedAudioPlaybackSession = false
    @State private var boostedAudioURL: URL?
    @State private var isPreparingAudioBoost = false
    @State private var isRevertingAudioBoost = false
    @State private var audioBoostPreparationFailed = false
    @State private var showsAudioBoostPreparationStatus = false
    @State private var isAudioSeeking = false
    @State private var audioSeekWasPlaying = false
    @AppStorage(ExploreVideoMutePreference.key) private var isMuted = true

    init(
        mediaItem: ExploreMediaItem,
        fallbackImageUrl: String,
        reloadGeneration: UInt64,
        preloadedImage: UIImage?,
        surface: ExploreVideoPlaybackSurface,
        autoplay: Bool,
        showsVideoControls: Bool,
        allowsAutoplayInLowPowerMode: Bool = false,
        audioBoostEnabled: Bool = false,
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil,
        onSingleTap: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil
    ) {
        self.mediaItem = mediaItem
        self.fallbackImageUrl = fallbackImageUrl
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
        self.surface = surface
        self.autoplay = autoplay
        self.showsVideoControls = showsVideoControls
        self.allowsAutoplayInLowPowerMode = allowsAutoplayInLowPowerMode
        self.audioBoostEnabled = audioBoostEnabled
        self.audioBoostActionToken = audioBoostActionToken
        self.onAudioBoostActionFinished = onAudioBoostActionFinished
        self.onAudioBoostToggleRequested = onAudioBoostToggleRequested
        self.onSingleTap = onSingleTap
        self.onDoubleTap = onDoubleTap
    }

    var body: some View {
        ZStack {
            posterImage

            if mediaItem.kind == .video, let player {
                ExploreCoverVideoPlayer(player: player, playerId: playerId, surface: surface)
                    .id("\(configuredVideoURL ?? mediaItem.url)|\(videoSurfaceGeneration)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                    .opacity(isPlayerItemReady ? 0.96 : 0)
            }

            if mediaItem.kind == .audio,
               audioPlaybackProgress > 0 || playbackOverlayState.isPlaying {
                TimelineView(.animation(paused: !playbackOverlayState.isPlaying)) { _ in
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(.white.opacity(0.92))
                            .frame(width: 2)
                            .shadow(color: .black.opacity(0.45), radius: 2)
                            .offset(
                                x: max(
                                    0,
                                    min(
                                        proxy.size.width - 2,
                                        proxy.size.width * displayedAudioPlaybackProgress
                                    )
                                )
                            )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(1)
            }

            if mediaItem.kind == .audio, audioDurationSeconds > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(formattedAudioTime(audioElapsedSeconds)) / \(formattedAudioTime(audioDurationSeconds))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.58), in: Capsule())
                    }
                }
                .padding(12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(3)
            }

            audioBoostOverlay

            if mediaItem.kind == .audio &&
                isPreparingAudioBoost &&
                showsAudioBoostPreparationStatus &&
                onAudioBoostToggleRequested == nil {
                Text("Boosting audio…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.62), in: Capsule())
                    .allowsHitTesting(false)
                    .zIndex(4)
            }

            if mediaItem.kind == .audio && audioBoostPreparationFailed {
                Text("Audio boost unavailable. Playing original.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.68), in: Capsule())
                    .allowsHitTesting(false)
                    .zIndex(4)
            }

            if audioSeekingMode == .fullSpectrogram {
                audioSeekLayer
                    .zIndex(2)
            } else {
                mediaTapLayer
                    .zIndex(2)
            }

            if isVideoPlaybackHost {
                videoOverlay
                    .zIndex(4)
            }
        }
        .task(id: "\(mediaItem.url)|\(reloadGeneration)") {
            configurePlayerIfNeeded()
            resumeAutoplayIfUncovered()
        }
        .task(id: audioBoostEnabled) {
            guard mediaItem.kind == .audio else { return }
            await updateAudioBoostMode()
        }
        .onAppear {
            logPlayback("appear")
            resumeAutoplayIfUncovered()
        }
        .onChange(of: shouldDisplayPlaybackControl) { _, isVisible in
            logPlayback(
                "control-visibility",
                extra: "visible=\(isVisible) playerNil=\(player == nil) rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
            )
        }
        .onChange(of: isMuted) { _, newValue in
            guard mediaItem.kind == .video else { return }
            guard !newValue else {
                player?.isMuted = true
                logPlayback("mute-changed", extra: "muted=true")
                return
            }
            Task { @MainActor in
                let activated = await MediaPlaybackAudioSession.activate(
                    source: "media.explore.\(surface.rawValue).unmute"
                )
                guard activated, !isMuted else { return }
                player?.isMuted = false
                logPlayback("mute-changed", extra: "muted=false")
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ExploreVideoMutePreference.didResetNotification
            )
        ) { _ in
            guard mediaItem.kind == .video else { return }
            isMuted = true
            player?.isMuted = true
        }
        .onDisappear {
            logPlayback("disappear")
            cleanupPlayer()
        }
        .onChange(of: playbackCoordinator?.activePlayerID) { _, activeId in
            guard let activeId,
                  activeId != playerId,
                  player != nil else { return }
            pauseForExternalActivePlayer()
        }
        .onChange(of: playbackCoordinator?.pauseGeneration) { _, _ in
            guard playbackCoordinator?.hasActiveOverlay == true else { return }
            pauseForOverlayPresentation(shouldResume: playbackOverlayState.isPlaying || player?.timeControlStatus == .playing)
        }
        .onChange(of: playbackCoordinator?.resumeGeneration) { _, _ in
            guard playbackCoordinator?.hasActiveOverlay != true else { return }
            finishOverlayDismissalPaused()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            pauseForSystemInterruption(shouldResume: playbackOverlayState.isPlaying || player?.timeControlStatus == .playing)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            resumeAfterInterruptionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            handleAudioSessionInterruption(notification)
        }
    }

    @ViewBuilder
    private var audioBoostOverlay: some View {
        if let pillState = ExploreFeedAudioBoostPillState.resolve(
            surface: surface,
            mediaKind: mediaItem.kind,
            isBoostEnabled: audioBoostEnabled,
            isPreparingBoost: isPreparingAudioBoost,
            isRevertingBoost: isRevertingAudioBoost,
            isBoostedAudioReady: boostedAudioURL != nil && !audioBoostPreparationFailed,
            hasToggleAction: onAudioBoostToggleRequested != nil
        ) {
            VStack {
                Spacer()
                HStack {
                    Button {
                        onAudioBoostToggleRequested?()
                    } label: {
                        HStack(spacing: 4) {
                            Text(pillState.title)
                            if let systemImage = pillState.systemImage {
                                Image(systemName: systemImage)
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.58), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(pillState == .boosting || pillState == .reverting)
                    .accessibilityLabel(pillState.accessibilityLabel)
                    Spacer()
                }
            }
            .padding(12)
            .zIndex(5)
        } else if mediaItem.kind == .audio,
                  audioBoostEnabled,
                  boostedAudioURL != nil,
                  !audioBoostPreparationFailed {
            VStack {
                Spacer()
                HStack {
                    Text("Boosted audio")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.58), in: Capsule())
                    Spacer()
                }
            }
            .padding(12)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio boost is on")
            .zIndex(3)
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if mediaItem.kind == .audio {
            if let spectrogramUrl = mediaItem.audioSpectrogramPosterUrl {
                ExploreHeroImageView(
                    imageUrl: spectrogramUrl,
                    reloadGeneration: reloadGeneration,
                    preloadedImage: nil
                )
            } else {
                ExploreAudioSpectrogramPoster(audioUrl: mediaItem.url)
            }
        } else if let posterImageUrl = mediaItem.posterImageUrl(fallback: fallbackImageUrl) {
            ExploreHeroImageView(
                imageUrl: posterImageUrl,
                reloadGeneration: reloadGeneration,
                preloadedImage: preloadedImage
            )
        } else {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                Image(systemName: "photo")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct ExploreAudioSpectrogramPoster: View {
        let audioUrl: String

        @State private var spectrogram: UIImage?

        var body: some View {
            ZStack {
                Color(uiColor: .secondarySystemBackground)

                if let spectrogram {
                    Image(uiImage: spectrogram)
                        .resizable()
                        .scaledToFill()
                } else {
                    GlowPulsingSkeletonView(cornerRadius: 0)
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .task(id: audioUrl) {
                spectrogram = await AudioSpectrogramThumbnailLoader.shared.loadImage(
                    fromPath: audioUrl,
                    maxDimension: Int(MerianConfig.displayImageMaxSize)
                )
            }
            .accessibilityLabel("Audio spectrogram")
        }
    }

    @ViewBuilder
    private var mediaTapLayer: some View {
        if hasMediaTapActions {
            Color.clear
                .contentShape(Rectangle())
                .gesture(mediaTapGesture)
        } else if shouldRepairHiddenPlaybackControlOnTap || shouldRevealPlaybackControlOnTap {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if shouldRepairHiddenPlaybackControlOnTap {
                        repairHiddenPlaybackControlFromTap()
                    } else {
                        revealPlaybackControlFromTap()
                    }
                }
        }
    }

    private var hasMediaTapActions: Bool {
        onSingleTap != nil || onDoubleTap != nil
    }

    private var audioSeekingMode: AudioSpectrogramSeekingMode {
        mediaItem.kind == .audio && surface == .detail ? .fullSpectrogram : .disabled
    }

    private var audioSeekLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        seekAudioWithoutChangingPlayback(
                            progress: AudioSpectrogramSeekingPolicy.normalizedProgress(
                                locationX: value.location.x,
                                width: proxy.size.width
                            )
                        )
                    }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            updateAudioSeek(
                                progress: AudioSpectrogramSeekingPolicy.normalizedProgress(
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                            )
                        }
                        .onEnded { value in
                            guard isAudioSeeking else { return }
                            finishAudioSeek(
                                progress: AudioSpectrogramSeekingPolicy.normalizedProgress(
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                            )
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Audio position")
                .accessibilityValue(
                    "\(formattedAudioTime(audioElapsedSeconds)) of \(formattedAudioTime(audioDurationSeconds))"
                )
                .accessibilityAdjustableAction { direction in
                    let adjustment: AudioSeekAdjustment = direction == .increment ? .forward : .backward
                    seekAudioForAccessibility(adjustment)
                }
        }
    }

    private var hasLocalVideoPlaybackState: Bool {
        mediaItem.kind == .video || mediaItem.kind == .audio ||
            player != nil ||
            configuredVideoURL != nil ||
            playbackOverlayState.needsPlayerRebuildForRecovery
    }

    private var isVideoPlaybackHost: Bool {
        hasLocalVideoPlaybackState
    }

    private var shouldDisplayPlaybackControl: Bool {
        isVideoPlaybackHost &&
            showsVideoControls &&
            (playbackOverlayState.showsPlaybackControl ||
                playbackOverlayState.needsPlayerRebuildForRecovery ||
                player == nil)
    }

    private var playbackControlShowsPlayingIcon: Bool {
        playbackOverlayState.isPlaying &&
            !playbackOverlayState.needsPlayerRebuildForRecovery
    }

    private var shouldRevealPlaybackControlOnTap: Bool {
        isVideoPlaybackHost &&
            showsVideoControls &&
            !playbackOverlayState.showsPlaybackControl &&
            !shouldRepairHiddenPlaybackControlOnTap &&
            (onSingleTap == nil || playbackOverlayState.needsPlayerRebuildForRecovery)
    }

    private var shouldRepairHiddenPlaybackControlOnTap: Bool {
        isVideoPlaybackHost &&
            showsVideoControls &&
            !playbackOverlayState.showsPlaybackControl &&
            (playbackOverlayState.needsPlayerRebuildForRecovery ||
                player?.timeControlStatus != .playing)
    }

    private var mediaTapGesture: some Gesture {
        ExclusiveGesture(
            TapGesture(count: 2).onEnded {
                onDoubleTap?()
            },
            TapGesture().onEnded {
                if shouldRepairHiddenPlaybackControlOnTap {
                    repairHiddenPlaybackControlFromTap()
                    return
                }
                if shouldRevealPlaybackControlOnTap {
                    revealPlaybackControlFromTap()
                    return
                }
                onSingleTap?()
            }
        )
    }

    private var usesFeedCenterPlaybackZone: Bool {
        ExploreFeedMediaInteractionPolicy.usesCenterPlaybackZone(
            surface: surface,
            mediaKind: mediaItem.kind,
            hasNavigationAction: onSingleTap != nil
        )
    }

    private var centerPlaybackGesture: some Gesture {
        ExclusiveGesture(
            TapGesture(count: 2).onEnded {
                onDoubleTap?()
            },
            TapGesture().onEnded {
                togglePlayback()
            }
        )
    }

    @ViewBuilder
    private var videoOverlay: some View {
        ZStack {
            if showsVideoControls {
                if usesFeedCenterPlaybackZone {
                    feedCenterPlaybackControl
                } else if audioSeekingMode == .fullSpectrogram {
                    detailAudioCenterPlaybackControl
                } else if shouldDisplayPlaybackControl {
                    Button(action: togglePlayback) {
                        Image(systemName: playbackControlShowsPlayingIcon ? "pause.fill" : "play.fill")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.black.opacity(playbackControlShowsPlayingIcon ? 0.32 : 0.46), in: Circle())
                            .shadow(color: .black.opacity(0.26), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                        .accessibilityLabel(playbackControlAccessibilityLabel)
                    .onAppear {
                        logPlayback(
                            "control-appeared",
                            extra: "playerNil=\(player == nil) rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeInOut(duration: 0.22), value: shouldDisplayPlaybackControl)
                }
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

            if showsVideoControls && mediaItem.kind == .video {
                VStack {
                    HStack {
                        Spacer()

                        Button {
                            isMuted.toggle()
                            HapticManager.shared.triggerSelectionPulse(
                                source: "media.explore.\(surface.rawValue).mute.\(isMuted ? "on" : "off")"
                            )
                            player?.isMuted = isMuted
                            if playbackOverlayState.needsPlayerRebuildForRecovery || player?.timeControlStatus != .playing {
                                resumeAutoplayIfEligible(force: true, revealsPlaybackControl: true)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playbackControlAccessibilityLabel: String {
        let medium = mediaItem.kind == .audio ? "audio" : "video"
        return playbackControlShowsPlayingIcon ? "Pause \(medium)" : "Play \(medium)"
    }

    private var detailAudioCenterPlaybackControl: some View {
        ZStack {
            if shouldDisplayPlaybackControl {
                Image(systemName: playbackControlShowsPlayingIcon ? "pause.fill" : "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(playbackControlShowsPlayingIcon ? 0.32 : 0.46), in: Circle())
                    .shadow(color: .black.opacity(0.26), radius: 12, x: 0, y: 6)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(
            width: ExploreFeedMediaInteractionPolicy.centerPlaybackHitSize,
            height: ExploreFeedMediaInteractionPolicy.centerPlaybackHitSize
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: togglePlayback)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(playbackControlAccessibilityLabel)
        .accessibilityAction {
            togglePlayback()
        }
        .animation(.easeInOut(duration: 0.22), value: shouldDisplayPlaybackControl)
    }

    private func updateAudioSeek(progress: Double) {
        guard resolvedAudioDuration > 0, let player else { return }
        if !isAudioSeeking {
            isAudioSeeking = true
            audioSeekWasPlaying = player.timeControlStatus == .playing || playbackOverlayState.isPlaying
            HapticManager.shared.triggerLightImpact(
                intensity: 0.35,
                source: "media.explore.detail.seek.begin"
            )
            player.pause()
            reducePlaybackOverlay(.playbackTemporarilyPaused)
        }
        applyAudioSeek(progress: progress, player: player)
    }

    private func finishAudioSeek(progress: Double) {
        guard isAudioSeeking, let player else { return }
        applyAudioSeek(progress: progress, player: player)
        let shouldResume = audioSeekWasPlaying
        isAudioSeeking = false
        audioSeekWasPlaying = false
        HapticManager.shared.triggerSelectionPulse(source: "media.explore.detail.seek.commit")
        if shouldResume {
            playbackCoordinator?.activate(playerID: playerId, surface: surface)
            player.play()
        } else {
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        }
    }

    private func applyAudioSeek(progress: Double, player: AVPlayer) {
        let seconds = AudioSpectrogramSeekingPolicy.seconds(
            progress: progress,
            duration: resolvedAudioDuration
        )
        audioPlaybackProgress = progress
        audioElapsedSeconds = seconds
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func seekAudioForAccessibility(_ adjustment: AudioSeekAdjustment) {
        guard resolvedAudioDuration > 0, let player else { return }
        let progress = AudioSpectrogramSeekingPolicy.progress(
            after: adjustment,
            currentProgress: audioPlaybackProgress,
            duration: resolvedAudioDuration
        )
        applyAudioSeek(progress: progress, player: player)
        HapticManager.shared.triggerSelectionPulse(source: "media.explore.detail.seek.accessibility")
        UIAccessibility.post(
            notification: .announcement,
            argument: formattedAudioTime(audioElapsedSeconds)
        )
    }

    private var resolvedAudioDuration: TimeInterval {
        if audioDurationSeconds.isFinite, audioDurationSeconds > 0 {
            return audioDurationSeconds
        }
        guard let duration = player?.currentItem?.duration,
              duration.isNumeric,
              duration.seconds.isFinite,
              duration.seconds > 0 else {
            return 0
        }
        return duration.seconds
    }

    private var displayedAudioPlaybackProgress: Double {
        AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: audioPlaybackProgress,
            currentTime: player?.currentTime().seconds ?? 0,
            duration: resolvedAudioDuration,
            isPlaying: playbackOverlayState.isPlaying,
            playerIsPlaying: player?.timeControlStatus == .playing,
            isSeeking: isAudioSeeking
        )
    }

    private func synchronizeAudioPlaybackProgress() {
        guard mediaItem.kind == .audio,
              let player,
              resolvedAudioDuration > 0 else { return }
        let currentTime = player.currentTime().seconds
        audioPlaybackProgress = AudioSpectrogramSeekingPolicy.normalizedProgress(
            currentTime: currentTime,
            duration: resolvedAudioDuration,
            fallback: audioPlaybackProgress
        )
        if currentTime.isFinite {
            audioElapsedSeconds = min(resolvedAudioDuration, max(0, currentTime))
        }
    }

    private func seekAudioWithoutChangingPlayback(progress: Double) {
        guard resolvedAudioDuration > 0, let player else { return }
        applyAudioSeek(progress: progress, player: player)
        HapticManager.shared.triggerSelectionPulse(source: "media.explore.detail.seek.tap")
    }

    @discardableResult
    private func configurePlayerIfNeeded(forceRebuildForRecovery: Bool = false) -> AVPlayer? {
        guard let videoURLString = videoURLStringForPlayerConfiguration(forceRebuildForRecovery: forceRebuildForRecovery),
              let url = URL(string: videoURLString) else {
            cleanupPlayer()
            return nil
        }
        let shouldRebuildPlayer = forceRebuildForRecovery || playbackOverlayState.needsPlayerRebuildForRecovery
        guard configuredVideoURL != videoURLString || player == nil || shouldRebuildPlayer else { return player }

        let recoverySeekTime = shouldRebuildPlayer ? (pendingRecoverySeekTime ?? currentRecoverySeekTime()) : nil
        resetCurrentPlayer()
        if shouldRebuildPlayer {
            videoSurfaceGeneration += 1
        }
        logPlayback(
            shouldRebuildPlayer ? "configure-rebuild" : "configure",
            extra: "generation=\(videoSurfaceGeneration)"
        )
        let player = AVPlayer(url: url)
        player.isMuted = mediaItem.kind == .video ? isMuted : false
        player.actionAtItemEnd = .none
        playbackObservers = [
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                guard let player else { return }
                logPlayback("item-ended")
                if mediaItem.kind == .audio {
                    audioPlaybackProgress = 0
                    audioElapsedSeconds = 0
                    AppTelemetry.trackExploreAudioPlaybackCompleted(surface: surface.rawValue)
                }
                player.seek(to: .zero)
                if playbackOverlayState.isPlaying {
                    player.play()
                } else {
                    reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
                }
            },
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: player.currentItem,
                queue: .main
            ) { _ in
                logPlayback("item-stalled")
                pauseForRecoverableInterruption()
            },
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                logPlayback("item-failed-to-end")
                if mediaItem.kind == .audio {
                    AppTelemetry.trackExploreAudioPlaybackFailed(surface: surface.rawValue)
                }
                pauseForRecoverableInterruption()
            }
        ]
        playbackStatusObserver = player.publisher(for: \.timeControlStatus, options: [.new])
            .receive(on: DispatchQueue.main)
            .sink { status in
                handlePlaybackStatusChange(status)
            }
        playerItemStatusObserver = player.currentItem?.publisher(for: \.status, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { status in
                isPlayerItemReady = status == .readyToPlay
                if mediaItem.kind == .audio,
                   status == .readyToPlay,
                   let duration = player.currentItem?.duration,
                   duration.isNumeric,
                   duration.seconds.isFinite,
                   duration.seconds > 0 {
                    audioDurationSeconds = duration.seconds
                }
                if status == .failed {
                    reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
                    if mediaItem.kind == .audio {
                        AppTelemetry.trackExploreAudioPlaybackFailed(surface: surface.rawValue)
                    }
                }
            }
        playbackTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard mediaItem.kind == .audio,
                  let duration = player.currentItem?.duration,
                  duration.isNumeric,
                  duration.seconds.isFinite,
                  duration.seconds > 0 else { return }
            audioPlaybackProgress = max(0, min(1, time.seconds / duration.seconds))
            audioElapsedSeconds = max(0, time.seconds)
            audioDurationSeconds = duration.seconds
        }
        configuredVideoURL = videoURLString
        self.player = player
        if let recoverySeekTime {
            logPlayback("seek-recovery", extra: "seconds=\(recoverySeekTime.seconds)")
            player.seek(to: recoverySeekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        pendingRecoverySeekTime = nil
        if shouldRebuildPlayer {
            reducePlaybackOverlay(.recoveryRebuildCompleted, animation: .easeInOut(duration: 0.18))
        }
        reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        return player
    }

    private func videoURLStringForPlayerConfiguration(forceRebuildForRecovery: Bool) -> String? {
        if mediaItem.kind == .video || mediaItem.kind == .audio {
            if mediaItem.kind == .audio, audioBoostEnabled, let boostedAudioURL {
                return boostedAudioURL.absoluteString
            }
            return mediaItem.url
        }

        let shouldRecoverExistingVideo = forceRebuildForRecovery ||
            playbackOverlayState.needsPlayerRebuildForRecovery ||
            player != nil

        return shouldRecoverExistingVideo ? configuredVideoURL : nil
    }

    @MainActor
    private func updateAudioBoostMode() async {
        let wasPlaying = player?.timeControlStatus == .playing
        let resumeTime = player?.currentTime()
        let shouldShowReverting = !audioBoostEnabled && boostedAudioURL != nil
        isRevertingAudioBoost = shouldShowReverting
        defer {
            if shouldShowReverting { isRevertingAudioBoost = false }
        }

        if audioBoostEnabled {
            let actionToken = audioBoostActionToken
            isPreparingAudioBoost = true
            showsAudioBoostPreparationStatus = ExploreAudioBoostFeedbackPolicy.shouldPresent(
                actionToken: actionToken
            )
            audioBoostPreparationFailed = false
            defer {
                isPreparingAudioBoost = false
                showsAudioBoostPreparationStatus = false
                if let actionToken {
                    onAudioBoostActionFinished?(actionToken)
                }
            }
            do {
                let result = try await AudioBoostProcessor.shared.prepare(urlString: mediaItem.url)
                guard !Task.isCancelled else { return }
                boostedAudioURL = result.url
                AppTelemetry.trackExploreAudioBoost(
                    event: "enabled",
                    surface: surface.rawValue,
                    gainBand: result.gainBand
                )
            } catch {
                guard !Task.isCancelled else { return }
                boostedAudioURL = nil
                let shouldPresentFailure = ExploreAudioBoostFeedbackPolicy.shouldPresent(
                    actionToken: actionToken
                )
                audioBoostPreparationFailed = shouldPresentFailure
                if shouldPresentFailure {
                    HapticManager.shared.triggerErrorThump(
                        source: "media.explore.\(surface.rawValue).audioBoost.failed"
                    )
                }
                AppTelemetry.trackExploreAudioBoost(event: "preparation_failed", surface: surface.rawValue)
            }
        } else {
            showsAudioBoostPreparationStatus = false
            audioBoostPreparationFailed = false
            guard boostedAudioURL != nil else { return }
            AppTelemetry.trackExploreAudioBoost(event: "disabled", surface: surface.rawValue)
        }

        resetCurrentPlayer()
        guard let rebuilt = configurePlayerIfNeeded() else { return }
        if let resumeTime, resumeTime.isNumeric {
            await rebuilt.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if wasPlaying {
            resumeAutoplayIfEligible(force: true, revealsPlaybackControl: true)
        }
    }

    private var feedCenterPlaybackControl: some View {
        ZStack {
            if shouldDisplayPlaybackControl {
                Image(systemName: playbackControlShowsPlayingIcon ? "pause.fill" : "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(playbackControlShowsPlayingIcon ? 0.32 : 0.46), in: Circle())
                    .shadow(color: .black.opacity(0.26), radius: 12, x: 0, y: 6)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(
            width: ExploreFeedMediaInteractionPolicy.centerPlaybackHitSize,
            height: ExploreFeedMediaInteractionPolicy.centerPlaybackHitSize
        )
        .contentShape(Rectangle())
        .gesture(centerPlaybackGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(playbackControlAccessibilityLabel)
        .accessibilityAction {
            togglePlayback()
        }
        .animation(.easeInOut(duration: 0.22), value: shouldDisplayPlaybackControl)
    }

    private func cleanupPlayer() {
        let cleanupState = [
            "kind=\(mediaItem.kind.rawValue)",
            "overlay=\(playbackCoordinator?.hasActiveOverlay == true)",
            "rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
        ].joined(separator: " ")
        logPlayback("cleanup", extra: cleanupState)
        if isVideoPlaybackHost,
           playbackCoordinator?.hasActiveOverlay == true ||
           playbackOverlayState.needsPlayerRebuildForRecovery {
            cleanupPlayerForOverlayRecovery()
            return
        }

        resetCurrentPlayer()
        playbackResumeIntentState.clear()
        pendingRecoverySeekTime = nil
        reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
    }

    private func cleanupPlayerForOverlayRecovery() {
        if pendingRecoverySeekTime == nil {
            pendingRecoverySeekTime = currentRecoverySeekTime()
        }

        logPlayback(
            "overlay-cleanup-preserved",
            extra: "seek=\(pendingRecoverySeekTime?.seconds ?? -1)"
        )
        player?.pause()
        playbackCoordinator?.clearActivePlayer(playerId)
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        unexpectedPauseRecoveryTask?.cancel()
        unexpectedPauseRecoveryTask = nil
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = nil
        videoSurfaceGeneration += 1
        reducePlaybackOverlay(.playbackInterrupted, animation: .easeInOut(duration: 0.18))
    }

    private func resetCurrentPlayer() {
        if player != nil {
            logPlayback("reset-player")
            playbackCoordinator?.clearActivePlayer(playerId)
        }
        player?.pause()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        unexpectedPauseRecoveryTask?.cancel()
        unexpectedPauseRecoveryTask = nil
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = nil
        playbackStatusObserver?.cancel()
        playbackStatusObserver = nil
        playerItemStatusObserver?.cancel()
        playerItemStatusObserver = nil
        isPlayerItemReady = false
        if let playbackTimeObserver {
            player?.removeTimeObserver(playbackTimeObserver)
            self.playbackTimeObserver = nil
        }
        audioPlaybackProgress = 0
        audioElapsedSeconds = 0
        audioDurationSeconds = 0
        for observer in playbackObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        playbackObservers = []
        configuredVideoURL = nil
        player = nil
        deactivateAudioPlaybackSessionIfNeeded()
    }

    private func currentRecoverySeekTime() -> CMTime? {
        guard let player else { return nil }
        let currentTime = player.currentTime()
        guard currentTime.isNumeric,
              currentTime.seconds.isFinite,
              currentTime.seconds > 0 else {
            return nil
        }

        if let duration = player.currentItem?.duration,
           duration.isNumeric,
           duration.seconds.isFinite,
           duration.seconds - currentTime.seconds <= 0.5 {
            return .zero
        }

        return currentTime
    }

    private func formattedAudioTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func pauseForUserInteraction() {
        logPlayback("pause-user")
        synchronizeAudioPlaybackProgress()
        player?.pause()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        unexpectedPauseRecoveryTask?.cancel()
        unexpectedPauseRecoveryTask = nil
        playbackResumeIntentState.clear()
        pendingRecoverySeekTime = nil
        reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = nil
    }

    private func pauseForExternalActivePlayer() {
        logPlayback("pause-external-active-player")
        synchronizeAudioPlaybackProgress()
        player?.pause()
        reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
    }

    private func pauseForOverlayPresentation(shouldResume: Bool) {
        logPlayback("pause-overlay", extra: "shouldResume=\(shouldResume)")
        pauseForRecoverableInterruption()
    }

    private func pauseForSystemInterruption(shouldResume: Bool) {
        logPlayback("pause-system", extra: "shouldResume=\(shouldResume)")
        playbackResumeIntentState.markSystemInterruption(shouldResume: shouldResume)
        pauseForRecoverableInterruption()
    }

    private func pauseForRecoverableInterruption() {
        guard isVideoPlaybackHost else { return }
        if let recoverySeekTime = currentRecoverySeekTime() {
            pendingRecoverySeekTime = recoverySeekTime
        }
        logPlayback(
            "pause-recoverable",
            extra: "seek=\(pendingRecoverySeekTime?.seconds ?? -1)"
        )
        synchronizeAudioPlaybackProgress()
        player?.pause()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        unexpectedPauseRecoveryTask?.cancel()
        unexpectedPauseRecoveryTask = nil
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = nil
        reducePlaybackOverlay(.playbackInterrupted, animation: .easeInOut(duration: 0.18))
    }

    private func finishOverlayDismissalPaused() {
        logPlayback(
            "overlay-dismiss-paused",
            extra: "status=\(playbackStatusDescription(player?.timeControlStatus))"
        )
        playbackResumeIntentState.clear()
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = nil
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        unexpectedPauseRecoveryTask?.cancel()
        unexpectedPauseRecoveryTask = nil
        player?.pause()

        if player == nil || playbackOverlayState.needsPlayerRebuildForRecovery {
            rebuildPausedPlayerForRecovery(reason: "overlay-dismiss")
        } else {
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        }
    }

    private func resumeAfterInterruptionIfNeeded() {
        guard playbackResumeIntentState.consumeSystemResumeIntent() else {
            reconcilePlaybackStateWithPlayer()
            return
        }

        resumeAutoplayIfEligible(ignoreLowPowerMode: allowsAutoplayInLowPowerMode)
    }

    private func resumeAutoplayIfUncovered() {
        guard playbackCoordinator?.hasActiveOverlay != true else {
            logPlayback("skip-autoplay-covered")
            pauseForOverlayPresentation(shouldResume: false)
            return
        }

        resumeAutoplayIfEligible(ignoreLowPowerMode: allowsAutoplayInLowPowerMode)
    }

    private func revealPlaybackControlFromTap() {
        logPlayback("tap-reveal-control")
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = nil
        reducePlaybackOverlay(.revealControls, animation: .easeInOut(duration: 0.18))
    }

    private func repairHiddenPlaybackControlFromTap() {
        logPlayback(
            "tap-repair-hidden-control",
            extra: "status=\(playbackStatusDescription(player?.timeControlStatus)) rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
        )
        resumeAutoplayIfEligible(
            force: true,
            revealsPlaybackControl: true,
            forcePlayerRebuild: playbackOverlayState.needsPlayerRebuildForRecovery || player?.timeControlStatus != .playing,
            verifiesRecovery: true
        )
    }

    private func rebuildPausedPlayerForRecovery(reason: String) {
        guard isVideoPlaybackHost else { return }

        logPlayback(
            "rebuild-paused-recovery",
            extra: "reason=\(reason) status=\(playbackStatusDescription(player?.timeControlStatus))"
        )
        playbackControlFadeTask?.cancel()
        playbackControlFadeTask = nil
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        unexpectedPauseRecoveryTask?.cancel()
        unexpectedPauseRecoveryTask = nil

        guard configurePlayerIfNeeded(forceRebuildForRecovery: true) != nil else {
            reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
            return
        }

        player?.pause()
        reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
    }

    private func reducePlaybackOverlay(
        _ event: ExploreVideoPlaybackOverlayState.Event,
        animation: Animation? = nil
    ) {
        if let animation {
            withAnimation(animation) {
                playbackOverlayState.reduce(event)
            }
        } else {
            playbackOverlayState.reduce(event)
        }
    }

    private func togglePlayback() {
        if playbackOverlayState.needsPlayerRebuildForRecovery || player == nil {
            HapticManager.shared.triggerMediumPulse(
                source: "media.explore.\(surface.rawValue).play"
            )
            resumeAutoplayIfEligible(
                force: true,
                revealsPlaybackControl: true,
                forcePlayerRebuild: playbackOverlayState.needsPlayerRebuildForRecovery || player == nil,
                verifiesRecovery: true
            )
            return
        }

        let player = configurePlayerIfNeeded()
        guard let player else {
            reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
            return
        }

        if player.timeControlStatus == .playing {
            HapticManager.shared.triggerLightImpact(
                intensity: 0.55,
                source: "media.explore.\(surface.rawValue).pause"
            )
            pauseForUserInteraction()
        } else {
            HapticManager.shared.triggerMediumPulse(
                source: "media.explore.\(surface.rawValue).play"
            )
            resumeAutoplayIfEligible(force: true, revealsPlaybackControl: true)
        }
    }

    private func resumeAutoplayIfEligible(
        force: Bool = false,
        ignoreLowPowerMode: Bool = false,
        revealsPlaybackControl: Bool = false,
        forcePlayerRebuild: Bool = false,
        verifiesRecovery: Bool = false
    ) {
        guard isVideoPlaybackHost else { return }
        guard mediaItem.kind != .audio || force else { return }
        guard force || playbackCoordinator?.hasActiveOverlay != true else {
            logPlayback("skip-resume-covered")
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
            return
        }
        guard autoplay || force,
              force || ignoreLowPowerMode || !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            logPlayback("skip-resume-low-power")
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
            return
        }
        let isRecoveringPlayback = forcePlayerRebuild || playbackOverlayState.needsPlayerRebuildForRecovery
        let shouldRevealPlaybackControl = revealsPlaybackControl
        let shouldVerifyRecovery = verifiesRecovery || isRecoveringPlayback
        guard let player = configurePlayerIfNeeded(
            forceRebuildForRecovery: isRecoveringPlayback
        ) else {
            logPlayback("resume-unavailable")
            reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
            return
        }
        playbackCoordinator?.activate(playerID: playerId, surface: surface)
        logPlayback(
            "resume",
            extra: "force=\(force) rebuild=\(isRecoveringPlayback) reveal=\(shouldRevealPlaybackControl) verify=\(shouldVerifyRecovery)"
        )
        if shouldRevealPlaybackControl {
            reducePlaybackOverlay(.playbackStarted, animation: .easeInOut(duration: 0.18))
            showPlaybackControlTemporarily()
        } else {
            reducePlaybackOverlay(.autoplayStarted, animation: .easeInOut(duration: 0.18))
        }
        if mediaItem.kind == .audio {
            guard activateAudioPlaybackSession() else {
                reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
                AppTelemetry.trackExploreAudioPlaybackFailed(surface: surface.rawValue)
                return
            }
            player.isMuted = false
            if !hasTrackedAudioPlaybackStart {
                hasTrackedAudioPlaybackStart = true
                AppTelemetry.trackExploreAudioPlaybackStarted(surface: surface.rawValue)
                if audioBoostEnabled, boostedAudioURL != nil {
                    AppTelemetry.trackExploreAudioBoost(
                        event: "boosted_playback_started",
                        surface: surface.rawValue
                    )
                }
            }
        }
        if mediaItem.kind == .video, !isMuted {
            Task { @MainActor in
                let activated = await MediaPlaybackAudioSession.activate(
                    source: "media.explore.\(surface.rawValue).video.play"
                )
                guard activated, self.player === player, !isMuted else { return }
                player.isMuted = false
                player.play()
                if shouldVerifyRecovery {
                    startPlaybackRecoveryWatchdog(for: player)
                }
                playbackResumeIntentState.clear()
            }
            return
        }
        player.play()
        if shouldVerifyRecovery {
            startPlaybackRecoveryWatchdog(for: player)
        }
        playbackResumeIntentState.clear()
    }

    private func activateAudioPlaybackSession() -> Bool {
        guard mediaItem.kind == .audio else { return true }
        guard !hasActivatedAudioPlaybackSession else { return true }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .duckOthers)
            try session.setActive(true)
            hasActivatedAudioPlaybackSession = true
            return true
        } catch {
            logPlayback("audio-session-activation-failed", extra: "error=\(error.localizedDescription)")
            return false
        }
    }

    private func deactivateAudioPlaybackSessionIfNeeded() {
        guard hasActivatedAudioPlaybackSession else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        hasActivatedAudioPlaybackSession = false
    }

    private func startPlaybackRecoveryWatchdog(for watchedPlayer: AVPlayer) {
        playbackRecoveryWatchdogTask?.cancel()
        logPlayback("start-recovery-watchdog")
        playbackRecoveryWatchdogTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let player, player === watchedPlayer else { return }
                playbackRecoveryWatchdogTask = nil

                guard watchedPlayer.timeControlStatus == .playing else {
                    logPlayback(
                        "recovery-watchdog-failed",
                        extra: "status=\(playbackStatusDescription(watchedPlayer.timeControlStatus))"
                    )
                    pauseForRecoverableInterruption()
                    return
                }

                logPlayback("recovery-watchdog-passed")
            }
        }
    }

    private func scheduleUnexpectedPauseRecoveryIfNeeded(for watchedPlayer: AVPlayer?) {
        guard let watchedPlayer else { return }
        unexpectedPauseRecoveryTask?.cancel()
        unexpectedPauseRecoveryTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let player,
                      player === watchedPlayer,
                      playbackOverlayState.isPlaying else {
                    unexpectedPauseRecoveryTask = nil
                    return
                }

                unexpectedPauseRecoveryTask = nil
                guard watchedPlayer.timeControlStatus == .playing else {
                    logPlayback(
                        "unexpected-pause-confirmed",
                        extra: "status=\(playbackStatusDescription(watchedPlayer.timeControlStatus))"
                    )
                    pauseForRecoverableInterruption()
                    return
                }
            }
        }
    }

    private func showPlaybackControlTemporarily() {
        playbackControlFadeTask?.cancel()
        logPlayback("show-control-temporarily")
        reducePlaybackOverlay(.revealControls, animation: .easeInOut(duration: 0.18))
        guard playbackOverlayState.isPlaying,
              !playbackOverlayState.needsPlayerRebuildForRecovery else {
            playbackControlFadeTask = nil
            return
        }

        playbackControlFadeTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard playbackOverlayState.isPlaying,
                      !playbackOverlayState.needsPlayerRebuildForRecovery else {
                    return
                }
                logPlayback("control-fade-completed")
                reducePlaybackOverlay(.controlFadeCompleted, animation: .easeInOut(duration: 0.26))
            }
        }
    }

    private func handlePlaybackStatusChange(_ status: AVPlayer.TimeControlStatus) {
        logPlayback("status-change", extra: "status=\(playbackStatusDescription(status))")
        guard !playbackOverlayState.needsPlayerRebuildForRecovery else {
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
            return
        }

        switch status {
        case .playing:
            unexpectedPauseRecoveryTask?.cancel()
            unexpectedPauseRecoveryTask = nil
            let shouldFadeVisibleControl = playbackOverlayState.showsPlaybackControl &&
                !playbackOverlayState.isAutoplayControlSuppressed
            reducePlaybackOverlay(.playerBecamePlaying)
            if shouldFadeVisibleControl {
                showPlaybackControlTemporarily()
            }
        case .paused:
            if isAudioSeeking {
                reducePlaybackOverlay(.playbackTemporarilyPaused)
                return
            }
            if playbackOverlayState.isPlaying {
                reducePlaybackOverlay(.playbackTemporarilyPaused)
                scheduleUnexpectedPauseRecoveryIfNeeded(for: player)
                return
            }
            playbackControlFadeTask?.cancel()
            playbackControlFadeTask = nil
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        case .waitingToPlayAtSpecifiedRate:
            if playbackOverlayState.isPlaying {
                reducePlaybackOverlay(.playbackWaiting)
                return
            }
            playbackControlFadeTask?.cancel()
            playbackControlFadeTask = nil
            reducePlaybackOverlay(.playbackWaiting, animation: .easeInOut(duration: 0.18))
        @unknown default:
            playbackControlFadeTask?.cancel()
            playbackControlFadeTask = nil
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        }
    }

    private func reconcilePlaybackStateWithPlayer() {
        guard let player else {
            logPlayback(
                "reconcile-player-nil",
                extra: "rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
            )
            rebuildPausedPlayerForRecovery(reason: "reconcile-player-nil")
            return
        }
        logPlayback(
            "reconcile",
            extra: "status=\(playbackStatusDescription(player.timeControlStatus)) rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
        )
        guard !playbackOverlayState.needsPlayerRebuildForRecovery else {
            playbackControlFadeTask?.cancel()
            playbackControlFadeTask = nil
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
            return
        }

        if player.timeControlStatus == .playing {
            let shouldFadeVisibleControl = playbackOverlayState.showsPlaybackControl &&
                !playbackOverlayState.isAutoplayControlSuppressed
            reducePlaybackOverlay(.playerBecamePlaying)
            if shouldFadeVisibleControl {
                showPlaybackControlTemporarily()
            }
        } else {
            playbackControlFadeTask?.cancel()
            playbackControlFadeTask = nil
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            pauseForSystemInterruption(shouldResume: playbackOverlayState.isPlaying || player?.timeControlStatus == .playing)
        case .ended:
            resumeAfterInterruptionIfNeeded()
        @unknown default:
            reconcilePlaybackStateWithPlayer()
        }
    }

    private func playbackStatusDescription(_ status: AVPlayer.TimeControlStatus?) -> String {
        switch status {
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .waitingToPlayAtSpecifiedRate:
            return "waiting"
        case nil:
            return "nil"
        @unknown default:
            return "unknown"
        }
    }

    private func logPlayback(_ event: String, extra: String = "") {
        MerianLog.exploreVideo.debug(
            "player=\(self.playerId, privacy: .public) surface=\(self.surface.rawValue, privacy: .public) event=\(event, privacy: .public) \(extra, privacy: .public)"
        )
    }
}

private struct ExploreCoverVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    let playerId: String
    let surface: ExploreVideoPlaybackSurface

    func makeUIView(context: Context) -> ExplorePlayerLayerView {
        let view = ExplorePlayerLayerView()
        view.playerLayer.player = player
        MerianLog.exploreVideo.debug(
            "layer attach player=\(self.playerId, privacy: .public) surface=\(self.surface.rawValue, privacy: .public)"
        )
        return view
    }

    func updateUIView(_ view: ExplorePlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
            MerianLog.exploreVideo.debug(
                "layer update player=\(self.playerId, privacy: .public) surface=\(self.surface.rawValue, privacy: .public)"
            )
        }
        view.playerLayer.videoGravity = .resizeAspectFill
    }

    static func dismantleUIView(_ view: ExplorePlayerLayerView, coordinator: ()) {
        MerianLog.exploreVideo.debug("layer dismantle")
        view.playerLayer.player = nil
    }
}

private final class ExplorePlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        clipsToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

struct ExploreMediaTypeIndicator: View {
    let kind: ExploreMediaKind

    var body: some View {
        Image(systemName: kind == .video ? "play.fill" : "waveform")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(.black.opacity(0.62), in: Circle())
            .accessibilityLabel(kind == .video ? "Video" : "Audio recording")
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
