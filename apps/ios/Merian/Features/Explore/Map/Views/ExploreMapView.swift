import MapKit
import SwiftData
import SwiftUI

struct ExploreMapView: View {
    static let approximateCoordinateRadiusMeters: CLLocationDistance = 10_000
    static let tabBarOverlayClearance: CGFloat = 28

    enum PreviewCardDragAxis {
        case horizontal
        case vertical
    }

    @Bindable var viewModel: ExploreMapViewModel
    @Bindable var feedViewModel: ExploreFeedViewModel
    @Bindable var postStore: ExplorePostStore
    @Environment(EnvironmentContextManager.self) var environmentContextManager
    @Environment(\.modelContext) var modelContext
    @Environment(AppSettings.self) var appSettings
    @Environment(SupabaseManager.self) var mapAuth
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var mapNavigation = MapNavigationModel()
    @State var ignoreNextBackgroundTap = false
    @State var discoveries: ExploreMapDiscoveriesViewModel?
    @State var isShowingFilterSheet = false
    @State var cardDragOffset: CGSize = .zero
    @State var activeCardDragAxis: PreviewCardDragAxis?
    @State var previewCarouselStepWidth: CGFloat = 0
    @State var previewSwipeCommitGeneration = 0
    @State var isCommittingPreviewSelection = false
    @State var previewCarouselAnchorPostId: String?
    @State var continuousZoomLevel: Double?

    let onOpenDetail: (ExplorePost, Bool) -> Void
    let onOpenAuthorProfile: (ExplorePost) -> Void

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
                      viewModel.visiblePosts.isEmpty,
                      viewModel.visibleClusters.isEmpty,
                      !viewModel.isLoading {
                ExploreMapStateCard(
                    title: "Map unavailable",
                    message: errorMessage,
                    actionTitle: "Retry",
                    action: { Task { await viewModel.searchCurrentArea() } }
                )
                .padding(.horizontal, 20)
            }

            topOverlayChrome
            bottomOverlayChrome
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .task {
            await viewModel.loadInitialData(using: environmentContextManager)
            feedViewModel.refreshPreferredSpeciesNames(
                for: viewModel.visiblePosts.map(\.speciesScientificName),
                modelContext: modelContext
            )
        }
        .onChange(of: feedViewModel.visibility.generation) { _, _ in
            let hidden = feedViewModel.visibility.reportedPostIDs
            discoveries?.cancelLoading()
            for id in hidden { discoveries?.removePost(id: id) }
        }
        .onChange(of: postStore.changeVersion) { _, _ in
            viewModel.syncPosts(from: postStore.allPosts)
            discoveries?.syncVisibility(from: postStore.allPosts)
        }
        .onChange(of: viewModel.posts) { _, posts in
            feedViewModel.refreshPreferredSpeciesNames(
                for: posts.map(\.speciesScientificName),
                modelContext: modelContext
            )
        }
        .onChange(of: viewModel.selectedPostId) { _, _ in
            activeCardDragAxis = nil

            if isCommittingPreviewSelection {
                isCommittingPreviewSelection = false
                return
            }

            previewSwipeCommitGeneration += 1
            previewCarouselAnchorPostId = nil
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                cardDragOffset = .zero
            }
        }
        .onDisappear {
            previewSwipeCommitGeneration += 1
            previewCarouselAnchorPostId = nil
        }
        .modifier(MapNavigationPresentation(
            navigation: mapNavigation,
            owner: mapAuth.currentUser?.id,
            onDestination: viewModel.navigate
        ))
        .sheet(item: $discoveries) { discoveries in
            ExploreMapDiscoveriesSheet(
                discoveries: discoveries,
                feedViewModel: feedViewModel,
                onOpen: openPost,
                onOpenAuthorProfile: onOpenAuthorProfile,
                onLike: { post in Task { await toggleLike(for: post) } },
                onUnshare: { post in Task { await unshare(post) } },
                onBlock: { post in Task { await blockAuthor(of: post) } },
                onReport: { post in Task { await report(post) } }
            )
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            ExploreMapFilterSheet(
                viewModel: viewModel,
                isPresented: $isShowingFilterSheet
            )
        }
    }

    private var mapLayer: some View {
        Map(position: $viewModel.cameraPosition) {
            if let selectedPost = viewModel.selectedPost,
               selectedPost.coordinateVisibility == .obscured {
                MapCircle(
                    center: selectedPost.coordinate,
                    radius: Self.approximateCoordinateRadiusMeters
                )
                .foregroundStyle(Color.accentColor.opacity(0.14))
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            }

            ForEach(viewModel.visibleClusters) { cluster in
                Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                    Button {
                        HapticManager.shared.triggerSelectionPulse()
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

            ForEach(viewModel.orderedMapPosts.filter { $0.id != viewModel.selectedPostId }) { post in
                waypointAnnotation(for: post)
            }

            if let selectedPost = viewModel.selectedPost {
                waypointAnnotation(for: selectedPost)
            }

            // Keep the native location dot above discovery markers, including the selected post.
            if environmentContextManager.isAuthorized {
                UserAnnotation()
            }
        }
        .mapStyle(appSettings.mapAppearance == .satellite ? .imagery : .standard)
        // Render map tiles behind the transparent navigation bar, not the container background.
        .ignoresSafeArea(.container, edges: .top)
        .transparentTopToolbar()
        .onTapGesture {
            dismissSelectedPostIfNeeded()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            if viewModel.cameraPosition.positionedByUser { mapNavigation.cancelNavigation() }
            let zoom = ExploreMapCameraPolicy.zoomLevel(for: context.region)
            if abs((continuousZoomLevel ?? 0) - zoom) > 0.05 {
                continuousZoomLevel = zoom
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.markCameraChanged(
                region: context.region,
                positionedByUser: viewModel.cameraPosition.positionedByUser
            )
            continuousZoomLevel = nil
        }
        .overlay {
            if viewModel.isLoading,
               viewModel.visiblePosts.isEmpty,
               viewModel.visibleClusters.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(18)
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .allowsHitTesting(false)
            }
        }
    }

    private var topOverlayChrome: some View {
        VStack(spacing: 8) {
            ExploreMapFilterBar(
                viewModel: viewModel,
                onShowFilters: { isShowingFilterSheet = true }
            )

            if viewModel.isOffline {
                ExploreMapStatusBanner(
                    systemImage: "wifi.slash",
                    message: "Offline. Cached map tiles may still show, but new discoveries won’t load."
                )
            }

            if showsEmptyBanner {
                ExploreMapStatusBanner(
                    systemImage: "binoculars",
                    message: "No discoveries here yet. Pan somewhere new or zoom out to explore more shared posts nearby."
                )
            }

            if viewModel.needsSearchInArea {
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    AppTelemetry.trackExploreMapSearchTriggered(reason: "search_this_area")
                    Task { await viewModel.searchCurrentArea() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Search this area")
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: viewModel.needsSearchInArea)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isOffline)
    }

    private var bottomOverlayChrome: some View {
        VStack(spacing: 8) {
            MapBottomControlRow {
                infoChip
            } controls: {
                navigationToolbar
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .center)

            if activePreviewCenterPost != nil {
                previewCarousel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, Self.tabBarOverlayClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(
            .spring(response: 0.28, dampingFraction: 0.84),
            value: activePreviewCenterPost != nil
        )
    }

    private func waypointAnnotation(for post: ExploreMapPost) -> some MapContent {
        Annotation("", coordinate: post.coordinate, anchor: .bottom) {
            Button {
                HapticManager.shared.triggerSelectionPulse()
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
                    imageUrl: post.mapThumbnailUrl,
                    reloadGeneration: feedViewModel.mediaReloadGeneration,
                    isSelected: viewModel.selectedPostId == post.id,
                    isApproximate: post.coordinateVisibility == .obscured,
                    hasVideo: post.hasVideoMedia,
                    showsThumbnail: effectiveShowsThumbnail,
                    zoomLevel: effectiveZoomLevel,
                    isNew: !postStore.containsFeedPost(id: post.id)
                )
            }
            .buttonStyle(.plain)
        }
        .annotationTitles(.hidden)
    }

    private var infoChip: some View {
        let label = viewModel.mode == .clusters && !viewModel.visibleClusters.isEmpty
            ? ExploreMapPresentation.discoveriesInViewLabel(
                count: viewModel.visibleDiscoveryCount,
                usesCompactCount: true
            )
            : ExploreMapPresentation.discoveriesInViewLabel(
                count: viewModel.visiblePosts.count
            )

        return Button {
            HapticManager.shared.triggerSelectionPulse()
            discoveries = ExploreMapDiscoveriesViewModel(mapViewModel: viewModel)
        } label: {
            MapCountPillLabel(
                fullLabel: label,
                compactLabel: "\(viewModel.visibleDiscoveryCount.formatted()) in view"
            )
        }
        .buttonStyle(.plain)
    }

    private var navigationToolbar: some View {
        MapNavigationToolbar(
            appearance: appSettings.mapAppearance,
            isLocating: mapNavigation.isLocating,
            identifierPrefix: "ExploreMap",
            onToggleStyle: {
                appSettings.mapAppearance = appSettings.mapAppearance == .satellite ? .standard : .satellite
                HapticManager.shared.triggerSelectionPulse()
            },
            onSearch: {
                let owner = mapAuth.currentUser?.id
                mapNavigation.openSearch(owner: owner) { owner == mapAuth.currentUser?.id }
            },
            onLocate: {
                HapticManager.shared.triggerSelectionPulse()
                AppTelemetry.trackExploreMapSearchTriggered(reason: "recenter")
                let owner = mapAuth.currentUser?.id
                mapNavigation.locate(
                    request: environmentContextManager.requestCurrentLocation,
                    authorization: { environmentContextManager.locationAuthorizationStatus },
                    isCurrent: { owner == mapAuth.currentUser?.id },
                    onLocation: { location in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            viewModel.navigate(to: location)
                        }
                    }
                )
            }
        )
    }

    private var effectiveZoomLevel: Double {
        if let continuousZoomLevel {
            return continuousZoomLevel
        }
        guard let region = viewModel.visibleRegion ?? viewModel.lastCommittedRegion else {
            return 0
        }
        return ExploreMapCameraPolicy.zoomLevel(for: region)
    }

    private var effectiveShowsThumbnail: Bool {
        viewModel.mode == .posts
            && !viewModel.visiblePosts.isEmpty
            && effectiveZoomLevel >= ExploreMapCameraPolicy.thumbnailZoomLevel
    }

    private var showsEmptyBanner: Bool {
        !viewModel.isLoading
            && viewModel.errorMessage == nil
            && viewModel.visiblePosts.isEmpty
            && viewModel.visibleClusters.isEmpty
            && viewModel.lastCommittedRegion != nil
    }

}
