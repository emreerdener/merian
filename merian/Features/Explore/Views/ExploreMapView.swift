import MapKit
import SwiftUI

struct ExploreMapView: View {
    @Bindable var viewModel: ExploreMapViewModel
    @Bindable var feedViewModel: ExploreFeedViewModel
    @Bindable var postStore: ExplorePostStore
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @State private var ignoreNextBackgroundTap = false
    @State private var isShowingDiscoveriesSheet = false

    let onOpenDetail: (ExplorePost, Bool) -> Void

    var body: some View {
        ZStack {
            mapLayer

            if viewModel.hasServiceUnavailableError {
                Text("Habitat data not available")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
            } else if let errorMessage = viewModel.errorMessage,
               viewModel.posts.isEmpty,
               viewModel.clusters.isEmpty,
               !viewModel.isLoading {
                stateCard(
                    title: "Couldn’t load the map",
                    message: errorMessage,
                    actionTitle: "Try again",
                    action: { Task { await viewModel.searchCurrentArea() } }
                )
                .padding(.horizontal, 20)
            }

            overlayChrome
        }
        .background(Color(uiColor: .systemBackground))
        .containerRelativeFrame(.horizontal)
        .task {
            await viewModel.loadInitialData(using: environmentContextManager)
        }
        .onChange(of: postStore.changeVersion) { _, _ in
            viewModel.syncPosts(from: postStore.allPosts)
        }
        .sheet(isPresented: $isShowingDiscoveriesSheet) {
            discoveriesSheet
        }
    }

    private var mapLayer: some View {
        Map(position: $viewModel.cameraPosition) {
            if let selectedPost = viewModel.selectedPost,
               selectedPost.coordinateVisibility == .obscured {
                MapCircle(center: selectedPost.coordinate, radius: 2000)
                    .foregroundStyle(Color.accentColor.opacity(0.14))
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            }

            ForEach(viewModel.clusters) { cluster in
                Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                    Button {
                        AppTelemetry.trackExploreMapClusterTapped()
                        registerAnnotationTap()
                        viewModel.zoomIntoCluster(cluster)
                    } label: {
                        ExploreMapClusterBubble(postCount: cluster.postCount)
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }

            ForEach(viewModel.posts) { post in
                Annotation("", coordinate: post.coordinate, anchor: .bottom) {
                    Button {
                        if viewModel.selectedPostId != post.id {
                            AppTelemetry.trackExploreMapPreviewOpened(
                                coordinateVisibility: post.coordinateVisibility.rawValue
                            )
                        }
                        registerAnnotationTap()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            viewModel.selectPost(post.id)
                        }
                    } label: {
                        ExploreMapWaypoint(
                            isSelected: viewModel.selectedPostId == post.id,
                            isApproximate: post.coordinateVisibility == .obscured
                        )
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard)
        .onTapGesture {
            dismissSelectedPostIfNeeded()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.markCameraChanged(region: context.region)
        }
        .overlay {
            if viewModel.isLoading && viewModel.posts.isEmpty && viewModel.clusters.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(18)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }
        }
    }

    private var overlayChrome: some View {
        VStack(spacing: 14) {
            if viewModel.isOffline {
                offlineBanner
            }

            if showsEmptyBanner {
                emptyBanner
            }

            if viewModel.needsSearchInArea {
                Button {
                    AppTelemetry.trackExploreMapSearchTriggered(reason: "search_this_area")
                    Task { await viewModel.searchCurrentArea() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Search This Area")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .foregroundStyle(Color.white)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                infoChip
                Spacer()
                recenterButton
            }
            .padding(.horizontal, 16)

            if let selectedPost = resolvedSelectedPost {
                ExploreMapPreviewCard(
                    post: selectedPost,
                    mediaReloadGeneration: feedViewModel.mediaReloadGeneration,
                    onOpen: { openSelectedPost(focusCommentComposer: false) },
                    onComments: { openSelectedPost(focusCommentComposer: true) },
                    onLike: { Task { await toggleLike(for: selectedPost) } },
                    onShare: { feedViewModel.share(selectedPost) },
                    onUnshare: { Task { await unshare(selectedPost) } },
                    onBlock: { Task { await blockAuthor(of: selectedPost) } },
                    onReport: { Task { await report(selectedPost) } }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 14)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: viewModel.selectedPostId)
        .animation(.easeInOut(duration: 0.18), value: viewModel.needsSearchInArea)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isOffline)
    }

    private var showsEmptyBanner: Bool {
        !viewModel.isLoading
            && viewModel.errorMessage == nil
            && viewModel.posts.isEmpty
            && viewModel.clusters.isEmpty
            && viewModel.lastCommittedRegion != nil
    }

    private var resolvedSelectedPost: ExplorePost? {
        guard let mapPost = viewModel.selectedPost else { return nil }
        return postStore.post(id: mapPost.id) ?? mapPost.asExplorePost
    }

    private var infoChip: some View {
        let label = viewModel.mode == .clusters
            ? "\(viewModel.visibleCount.formatted(.number.notation(.compactName))) discoveries in view"
            : "\(viewModel.posts.count.formatted()) discoveries in view"

        return Button {
            isShowingDiscoveriesSheet = true
        } label: {
            Text(label)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recenterButton: some View {
        Button {
            AppTelemetry.trackExploreMapSearchTriggered(reason: "recenter")
            Task { await viewModel.recenter(using: environmentContextManager) }
        } label: {
            Image(systemName: "location")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background(.regularMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter map")
    }

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .semibold))
            Text("Offline. Cached map tiles may still show, but new discoveries won’t load.")
                .font(.footnote)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var emptyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "binoculars")
                .font(.system(size: 14, weight: .semibold))
            Text("No discoveries here yet. Pan somewhere new or zoom out to explore more shared posts nearby.")
                .font(.footnote)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func stateCard(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: action) {
                Text(actionTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
        .card()
    }

    private var discoveriesSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.posts) { mapPost in
                        let post = postStore.post(id: mapPost.id) ?? mapPost.asExplorePost
                        ExploreMapPreviewCard(
                            post: post,
                            mediaReloadGeneration: feedViewModel.mediaReloadGeneration,
                            onOpen: {
                                isShowingDiscoveriesSheet = false
                                openPost(post, focusCommentComposer: false)
                            },
                            onComments: {
                                isShowingDiscoveriesSheet = false
                                openPost(post, focusCommentComposer: true)
                            },
                            onLike: { Task { await toggleLike(for: post) } },
                            onShare: { feedViewModel.share(post) },
                            onUnshare: { Task { await unshare(post) } },
                            onBlock: { Task { await blockAuthor(of: post) } },
                            onReport: { Task { await report(post) } }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Discoveries in view")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingDiscoveriesSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private func openPost(_ post: ExplorePost, focusCommentComposer: Bool) {
        AppTelemetry.trackExploreMapDetailOpened(entryPoint: focusCommentComposer ? "comments" : "preview")
        feedViewModel.upsertPost(post)
        onOpenDetail(post, focusCommentComposer)
    }

    private func openSelectedPost(focusCommentComposer: Bool) {
        guard let selectedPost = resolvedSelectedPost else { return }
        openPost(selectedPost, focusCommentComposer: focusCommentComposer)
    }

    private func toggleLike(for post: ExplorePost) async {
        feedViewModel.upsertPost(post)
        await feedViewModel.toggleLike(for: post)
        viewModel.syncPosts(from: postStore.allPosts)
    }

    private func unshare(_ post: ExplorePost) async {
        guard await feedViewModel.unshare(post) else { return }
        viewModel.removePost(id: post.id)
    }

    private func blockAuthor(of post: ExplorePost) async {
        guard await feedViewModel.blockAuthor(of: post) else { return }
        viewModel.removePosts(byAuthorUserId: post.authorUserId)
    }

    private func report(_ post: ExplorePost) async {
        guard await feedViewModel.report(post) else { return }
        viewModel.removePost(id: post.id)
    }

    private func dismissSelectedPostIfNeeded() {
        guard !ignoreNextBackgroundTap, viewModel.selectedPostId != nil else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            viewModel.selectPost(nil)
        }
    }

    private func registerAnnotationTap() {
        ignoreNextBackgroundTap = true

        Task { @MainActor in
            await Task.yield()
            ignoreNextBackgroundTap = false
        }
    }
}

private struct ExploreMapWaypoint: View {
    let isSelected: Bool
    let isApproximate: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.white)
                .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.accentColor, lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)

            if isApproximate {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.accentColor.opacity(0.65))
                    .frame(width: isSelected ? 32 : 28, height: isSelected ? 32 : 28)
            }
        }
        .scaleEffect(isSelected ? 1.08 : 1)
    }
}

private struct ExploreMapClusterBubble: View {
    let postCount: Int

    var body: some View {
        Text(postCount.formatted(.number.notation(.compactName)))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.96))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
    }
}

private struct ExploreMapPreviewCard: View {
    let post: ExplorePost
    let mediaReloadGeneration: UInt64
    let onOpen: () -> Void
    let onComments: () -> Void
    let onLike: () -> Void
    let onShare: () -> Void
    let onUnshare: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ExploreHeroImageView(
                    imageUrl: post.heroImageUrl,
                    reloadGeneration: mediaReloadGeneration
                )
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(post.resolvedSpeciesCommonName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    Text(post.speciesScientificName)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Menu {
                    if post.isOwnedByViewer {
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
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                }
                .tint(.primary)
            }

            HStack(spacing: 10) {
                previewPill(
                    title: post.likeCount.formatted(.number.notation(.compactName)),
                    systemImage: post.viewerHasLiked ? "heart.fill" : "heart",
                    isHighlighted: post.viewerHasLiked,
                    action: onLike
                )

                previewPill(
                    title: post.commentCount.formatted(.number.notation(.compactName)),
                    systemImage: "bubble.right",
                    isHighlighted: false,
                    action: onComments
                )

                previewPill(
                    title: "Share",
                    systemImage: "square.and.arrow.up",
                    isHighlighted: false,
                    action: onShare
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpen) {
                HStack {
                    Text("Open discovery")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private var subtitle: String? {
        let rawValues: [String?] = [
            post.publicLocationLabel,
            post.observationContextLabel,
            post.publicWeatherLabel
        ]

        let values = rawValues.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }

        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }

    private func previewPill(
        title: String,
        systemImage: String,
        isHighlighted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isHighlighted ? Color.red : Color.primary)

                Text(title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
