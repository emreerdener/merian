import SwiftUI
import UIKit

struct ExplorePostCard: View {
    let post: ExplorePost
    let mediaReloadGeneration: UInt64
    let onLike: () -> Void
    let onComments: () -> Void
    let onShare: () -> Void
    let onOpenDetail: () -> Void
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
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                ExploreTransientZoomView(
                    onSingleTap: onOpenDetail,
                    onDoubleTap: handleDoubleTapLike
                ) {
                    ExploreHeroImageView(
                        imageUrl: post.heroImageUrl,
                        reloadGeneration: mediaReloadGeneration
                    )
                }
            )
            .clipped()
            .overlay(alignment: .bottomLeading) {
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

struct ExploreHeroImageView: View {
    let imageUrl: String
    let reloadGeneration: UInt64

    @State private var loadedImage: UIImage?
    @State private var hasFailedToLoad = false

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasFailedToLoad {
                failurePlaceholder
            } else {
                loadingPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: "\(imageUrl)|\(reloadGeneration)") {
            loadedImage = nil
            hasFailedToLoad = false

            let image = await LocalImageLoader.shared.loadImage(
                fromPath: nil,
                fallbackUrl: imageUrl,
                maxDimension: Int(MerianConfig.displayImageMaxSize)
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
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
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
                )
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    speciesOverlay
                        .padding(14)
                }
        }

        private var speciesOverlay: some View {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(glowColor.opacity(isGlowing ? 0.8 : 0.55))
                    .frame(width: 170, height: 16)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(glowColor.opacity(isGlowing ? 0.62 : 0.4))
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

struct ExploreTransientZoomView<Content: View>: UIViewControllerRepresentable {
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

        let scrollView = ExploreTransientZoomScrollView()
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

private final class ExploreTransientZoomScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            return zoomScale > minimumZoomScale + 0.01
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
