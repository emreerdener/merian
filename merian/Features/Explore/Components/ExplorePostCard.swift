import SwiftUI
import UIKit

struct ExplorePostCard: View {
    let post: ExplorePost
    let mediaReloadGeneration: UInt64
    let onLike: () -> Void
    let onComments: () -> Void
    let onShare: () -> Void
    let onOpenDetail: () -> Void
    let onOpenInsight: () -> Void
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
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .onDisappear {
            doubleTapHeartTask?.cancel()
            doubleTapHeartTask = nil
        }
    }

    private var mediaView: some View {
        ExploreFeedMediaView(
            imageUrl: post.heroImageUrl,
            reloadGeneration: mediaReloadGeneration
        )
        .overlay(alignment: .topLeading) {
            speciesOverlay
                .padding(14)
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
        .contentShape(Rectangle())
        .gesture(mediaTapGesture)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
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
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenDetail)

            Spacer(minLength: 12)

            menuButton
        }
    }

    private var mediaTapGesture: some Gesture {
        ExclusiveGesture(
            TapGesture(count: 2).onEnded {
                handleDoubleTapLike()
            },
            TapGesture().onEnded {
                onOpenDetail()
            }
        )
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
        let common = post.resolvedSpeciesCommonName.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var menuButton: some View {
        Menu {
            if post.isOwnedByViewer {
                Button(action: onOpenInsight) {
                    Label("Open insight", systemImage: "sparkles")
                }

                Button(role: .destructive, action: onUnshare) {
                    Label("Remove post", systemImage: "trash")
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
    let reloadGeneration: UInt64
    let preloadedImage: UIImage?

    init(
        imageUrl: String,
        reloadGeneration: UInt64,
        preloadedImage: UIImage? = nil
    ) {
        self.imageUrl = imageUrl
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
    }

    var body: some View {
        // The scrolling feed intentionally uses a plain image host instead of the zoom wrapper.
        // That keeps every card on a stable square layout proposal regardless of source aspect ratio.
        ExploreSquareMediaView {
            ExploreHeroImageView(
                imageUrl: imageUrl,
                reloadGeneration: reloadGeneration,
                preloadedImage: preloadedImage
            )
        }
    }
}

struct ExploreDetailMediaView: View {
    let imageUrl: String
    let reloadGeneration: UInt64
    let preloadedImage: UIImage?

    init(
        imageUrl: String,
        reloadGeneration: UInt64,
        preloadedImage: UIImage? = nil
    ) {
        self.imageUrl = imageUrl
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
    }

    var body: some View {
        // Detail is the only path that opts into transient zoom behavior.
        ExploreSquareMediaView {
            ExploreDetailZoomView {
                ExploreHeroImageView(
                    imageUrl: imageUrl,
                    reloadGeneration: reloadGeneration,
                    preloadedImage: preloadedImage
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            ProgressView()
                .progressViewStyle(.circular)
        }
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
        var onSingleTap: (() -> Void)?
        var onDoubleTap: (() -> Void)?
        weak var singleTapRecognizer: UITapGestureRecognizer?
        weak var doubleTapRecognizer: UITapGestureRecognizer?

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
