import MapKit
import SwiftData
import SwiftUI

struct ExploreMapView: View {
    private static let approximateCoordinateRadiusMeters: CLLocationDistance = 10_000
    private static let tabBarOverlayClearance: CGFloat = 28

    private enum PreviewCardDragAxis {
        case horizontal
        case vertical
    }

    @Bindable var viewModel: ExploreMapViewModel
    @Bindable var feedViewModel: ExploreFeedViewModel
    @Bindable var postStore: ExplorePostStore
    @Environment(EnvironmentContextManager.self) private var environmentContextManager
    @Environment(\.modelContext) private var modelContext
    @State private var ignoreNextBackgroundTap = false
    @State private var isShowingDiscoveriesSheet = false
    @State private var isShowingFilterSheet = false
    @State private var cardDragOffset: CGSize = .zero
    @State private var activeCardDragAxis: PreviewCardDragAxis?
    @State private var previewCarouselStepWidth: CGFloat = 0
    @State private var previewSwipeCommitGeneration = 0
    @State private var isCommittingPreviewSelection = false
    @State private var previewCarouselAnchorPostId: String?
    @State private var continuousZoomLevel: Double?

    private var effectiveZoomLevel: Double {
        if let continuousZoomLevel {
            return continuousZoomLevel
        }
        guard let region = viewModel.visibleRegion ?? viewModel.lastCommittedRegion else { return 0 }
        let longitudeDelta = max(region.span.longitudeDelta, 0.000_01)
        return max(0, min(log2(360 / longitudeDelta), 20))
    }

    private var effectiveShowsThumbnail: Bool {
        viewModel.mode == .posts && !viewModel.visiblePosts.isEmpty && effectiveZoomLevel >= 11.5
    }

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
               viewModel.visiblePosts.isEmpty,
               viewModel.visibleClusters.isEmpty,
               !viewModel.isLoading {
                stateCard(
                    title: "Map unavailable",
                    message: errorMessage,
                    actionTitle: "Retry",
                    action: { Task { await viewModel.searchCurrentArea() } }
                )
                .padding(.horizontal, 20)
            }

            overlayChrome
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
        .onChange(of: postStore.changeVersion) { _, _ in
            viewModel.syncPosts(from: postStore.allPosts)
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
        .sheet(isPresented: $isShowingDiscoveriesSheet) {
            discoveriesSheet
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            filterSheet
        }
    }

    private var mapLayer: some View {
        Map(position: $viewModel.cameraPosition) {
            if let selectedPost = viewModel.selectedPost,
               selectedPost.coordinateVisibility == .obscured {
                MapCircle(center: selectedPost.coordinate, radius: Self.approximateCoordinateRadiusMeters)
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
        }
        .mapStyle(.standard)
        .onTapGesture {
            dismissSelectedPostIfNeeded()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            let longitudeDelta = max(context.region.span.longitudeDelta, 0.000_01)
            let zoom = max(0, min(log2(360 / longitudeDelta), 20))
            if abs((continuousZoomLevel ?? 0) - zoom) > 0.05 {
                continuousZoomLevel = zoom
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.markCameraChanged(region: context.region)
            continuousZoomLevel = nil
        }
        .overlay {
            if viewModel.isLoading && viewModel.visiblePosts.isEmpty && viewModel.visibleClusters.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(18)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }
        }
    }

    private var overlayChrome: some View {
        VStack(spacing: 8) {
            mapFilterBar

            if viewModel.isOffline {
                offlineBanner
            }

            if showsEmptyBanner {
                emptyBanner
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

            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                infoChip
                Spacer()
                recenterButton
            }
            .padding(.horizontal, 16)

            if activePreviewCenterPost != nil {
                previewCarousel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 0)
        .padding(.bottom, Self.tabBarOverlayClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: activePreviewCenterPost != nil)
        .animation(.easeInOut(duration: 0.18), value: viewModel.needsSearchInArea)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isOffline)
    }

    private var mapFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                mapFilterPill(
                    title: viewModel.hasActiveSpeciesFilters
                        ? "Filters \(viewModel.selectedSpeciesCategories.count.formatted())"
                        : "Filters",
                    isSelected: viewModel.hasActiveSpeciesFilters
                ) {
                    isShowingFilterSheet = true
                }
                .accessibilityLabel("Map filters")

                mapFilterPill(
                    title: "All",
                    isSelected: !viewModel.hasActiveSpeciesFilters
                ) {
                    Task { await viewModel.clearSpeciesFilters() }
                }

                ForEach(viewModel.visibleCategoryCounts) { categoryCount in
                    mapFilterPill(
                        title: categoryCount.category.title,
                        isSelected: viewModel.selectedSpeciesCategories.contains(categoryCount.category)
                    ) {
                        Task { await viewModel.toggleSpeciesFilter(categoryCount.category) }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func mapFilterPill(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.shared.triggerSelectionPulse()
            action()
        }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
                .background {
                    if isSelected {
                        Capsule().fill(Color.primary)
                    } else {
                        Capsule().fill(.regularMaterial)
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    imageUrl: post.heroImageUrl,
                    reloadGeneration: feedViewModel.mediaReloadGeneration,
                    isSelected: viewModel.selectedPostId == post.id,
                    isApproximate: post.coordinateVisibility == .obscured,
                    showsThumbnail: effectiveShowsThumbnail,
                    zoomLevel: effectiveZoomLevel,
                    isNew: !postStore.containsFeedPost(id: post.id)
                )
            }
            .buttonStyle(.plain)
        }
        .annotationTitles(.hidden)
    }

    private var showsEmptyBanner: Bool {
        !viewModel.isLoading
            && viewModel.errorMessage == nil
            && viewModel.visiblePosts.isEmpty
            && viewModel.visibleClusters.isEmpty
            && viewModel.lastCommittedRegion != nil
    }

    private var resolvedSelectedPost: ExplorePost? {
        guard let mapPost = viewModel.selectedPost else { return nil }
        return postStore.post(id: mapPost.id) ?? mapPost.asExplorePost
    }

    private var activePreviewCenterMapPost: ExploreMapPost? {
        if let previewCarouselAnchorPostId,
           let anchoredPost = viewModel.visiblePosts.first(where: { $0.id == previewCarouselAnchorPostId }) {
            return anchoredPost
        }

        return viewModel.selectedPost
    }

    private var activePreviewCenterPost: ExplorePost? {
        resolvedPost(for: activePreviewCenterMapPost)
    }

    private var previousPreviewPost: ExplorePost? {
        guard let anchorPostId = activePreviewCenterMapPost?.id else { return nil }
        return resolvedPost(for: viewModel.post(relativeTo: anchorPostId, by: -1))
    }

    private var nextPreviewPost: ExplorePost? {
        guard let anchorPostId = activePreviewCenterMapPost?.id else { return nil }
        return resolvedPost(for: viewModel.post(relativeTo: anchorPostId, by: 1))
    }

    private var infoChip: some View {
        let label = viewModel.mode == .clusters && !viewModel.visibleClusters.isEmpty
            ? discoveriesInViewLabel(count: viewModel.visibleDiscoveryCount, usesCompactCount: true)
            : discoveriesInViewLabel(count: viewModel.visiblePosts.count)

        return Button {
            HapticManager.shared.triggerSelectionPulse()
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
            HapticManager.shared.triggerSelectionPulse()
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
                    ForEach(viewModel.visiblePosts) { mapPost in
                        let post = postStore.post(id: mapPost.id) ?? mapPost.asExplorePost
                        ExploreMapPreviewCard(
                            post: post,
                            speciesDisplayName: feedViewModel.resolvedSpeciesCommonName(for: post),
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
            .navigationTitle(discoveriesInViewLabel(count: viewModel.visiblePosts.count))
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    Button {
                        HapticManager.shared.triggerSelectionPulse()
                        Task { await viewModel.clearSpeciesFilters() }
                    } label: {
                        ExploreMapFilterSheetRow(
                            title: "All species",
                            subtitle: discoveriesInViewLabel(count: totalAvailableDiscoveryCount),
                            systemImage: "map",
                            isSelected: !viewModel.hasActiveSpeciesFilters
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(viewModel.visibleCategoryCounts) { categoryCount in
                        Button {
                            HapticManager.shared.triggerSelectionPulse()
                            Task { await viewModel.toggleSpeciesFilter(categoryCount.category) }
                        } label: {
                            ExploreMapFilterSheetRow(
                                title: categoryCount.category.title,
                                subtitle: categoryCount.count >= 1
                                    ? discoveriesInViewLabel(count: categoryCount.count)
                                    : "Filter map",
                                systemImage: categoryCount.category.symbolName,
                                isSelected: viewModel.selectedSpeciesCategories.contains(categoryCount.category)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Map filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        HapticManager.shared.triggerSelectionPulse()
                        Task { await viewModel.clearSpeciesFilters() }
                    }
                    .disabled(!viewModel.hasActiveSpeciesFilters)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.triggerSelectionPulse()
                        isShowingFilterSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private var totalAvailableDiscoveryCount: Int {
        let countedTotal = viewModel.categoryCounts.reduce(0) { $0 + $1.count }
        return max(countedTotal, viewModel.visibleCount)
    }

    private func openPost(_ post: ExplorePost, focusCommentComposer: Bool) {
        AppTelemetry.trackExploreMapDetailOpened(entryPoint: focusCommentComposer ? "comments" : "preview")
        feedViewModel.upsertPost(post)
        onOpenDetail(post, focusCommentComposer)
    }

    private func discoveriesInViewLabel(count: Int, usesCompactCount: Bool = false) -> String {
        let formattedCount = usesCompactCount
            ? count.formatted(.number.notation(.compactName))
            : count.formatted()
        let noun = count == 1 ? "discovery" : "discoveries"
        return "\(formattedCount) \(noun) in view"
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

    @ViewBuilder
    private var previewCarousel: some View {
        if let centerPreviewPost = activePreviewCenterPost {
            let previousPreviewPost = previousPreviewPost
            let nextPreviewPost = nextPreviewPost
            let mainCardHorizontalInset: CGFloat = 16
            let cardSpacing: CGFloat = 8

            previewCard(for: centerPreviewPost, isInteractive: false)
                .padding(.horizontal, mainCardHorizontalInset)
                .frame(maxWidth: .infinity)
                .hidden()
                .overlay {
                    GeometryReader { geometry in
                        let availableWidth = geometry.size.width
                        let cardWidth = max(
                            availableWidth - (mainCardHorizontalInset * 2) - (cardSpacing * 2),
                            0
                        )
                        let stepWidth = cardWidth + cardSpacing

                        HStack(spacing: cardSpacing) {
                            if let previousPreviewPost {
                                previewCard(for: previousPreviewPost, isInteractive: false)
                                    .frame(width: cardWidth)
                            }

                            previewCard(for: centerPreviewPost, isInteractive: true)
                                .frame(width: cardWidth)

                            if let nextPreviewPost {
                                previewCard(for: nextPreviewPost, isInteractive: false)
                                    .frame(width: cardWidth)
                            }
                        }
                        .offset(x: cardDragOffset.width)
                        .frame(width: availableWidth, height: geometry.size.height, alignment: .center)
                        .clipped()
                        .onAppear {
                            updatePreviewCarouselStepWidth(stepWidth)
                        }
                        .onChange(of: stepWidth) { _, newValue in
                            updatePreviewCarouselStepWidth(newValue)
                        }
                    }
                }
            .padding(.bottom, 10)
            .offset(y: max(0, cardDragOffset.height))
            .contentShape(Rectangle())
            .gesture(previewCardDragGesture)
            .accessibilityElement(children: .contain)
        }
    }

    private var previewCardDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged(handlePreviewCardDragChanged)
            .onEnded(handlePreviewCardDragEnded)
    }

    private func handlePreviewCardDragChanged(_ value: DragGesture.Value) {
        let horizontalMagnitude = abs(value.translation.width)
        let verticalMagnitude = abs(value.translation.height)

        if activeCardDragAxis == nil,
           horizontalMagnitude > 6 || verticalMagnitude > 6 {
            activeCardDragAxis = horizontalMagnitude > verticalMagnitude ? .horizontal : .vertical
        }

        switch activeCardDragAxis {
        case .horizontal:
            let maxHorizontalTravel = max(previewCarouselStepWidth, 180) * 0.92
            let clampedWidth = min(max(value.translation.width, -maxHorizontalTravel), maxHorizontalTravel)
            cardDragOffset = CGSize(width: clampedWidth, height: 0)
        case .vertical:
            cardDragOffset = CGSize(
                width: 0,
                height: max(0, value.translation.height)
            )
        case nil:
            break
        }
    }

    private func handlePreviewCardDragEnded(_ value: DragGesture.Value) {
        defer { activeCardDragAxis = nil }

        switch activeCardDragAxis {
        case .horizontal:
            handlePreviewCardHorizontalSwipeEnded(value)
        case .vertical:
            handlePreviewCardVerticalDragEnded(value)
        case nil:
            resetPreviewCardPosition()
        }
    }

    private func handlePreviewCardHorizontalSwipeEnded(_ value: DragGesture.Value) {
        let swipeThreshold = min(max(previewCarouselStepWidth * 0.24, 56), 96)
        let didRequestNextPost = value.translation.width < -swipeThreshold || value.velocity.width < -360
        let didRequestPreviousPost = value.translation.width > swipeThreshold || value.velocity.width > 360

        if didRequestNextPost,
           viewModel.post(relativeToSelectedBy: 1) != nil {
            animatePreviewSelection(by: 1)
            return
        }

        if didRequestPreviousPost,
           viewModel.post(relativeToSelectedBy: -1) != nil {
            animatePreviewSelection(by: -1)
            return
        }

        resetPreviewCardPosition()
    }

    private func handlePreviewCardVerticalDragEnded(_ value: DragGesture.Value) {
        if value.translation.height > 60 || value.velocity.height > 300 {
            dismissSelectedPostIfNeeded()
        } else {
            resetPreviewCardPosition()
        }
    }

    private func resetPreviewCardPosition() {
        previewSwipeCommitGeneration += 1
        previewCarouselAnchorPostId = nil

        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            cardDragOffset = .zero
        }
    }

    private func animatePreviewSelection(by offset: Int) {
        previewCarouselAnchorPostId = viewModel.selectedPostId
        previewSwipeCommitGeneration += 1
        let commitGeneration = previewSwipeCommitGeneration

        let stepWidth = max(previewCarouselStepWidth, 1)
        let targetOffset = CGFloat(offset) * -stepWidth

        withAnimation(
            .spring(response: 0.24, dampingFraction: 0.9),
            completionCriteria: .logicallyComplete
        ) {
            cardDragOffset = CGSize(width: targetOffset, height: 0)
        } completion: {
            guard previewSwipeCommitGeneration == commitGeneration else { return }

            var transaction = Transaction()
            transaction.animation = nil

            isCommittingPreviewSelection = true
            withTransaction(transaction) {
                _ = viewModel.selectAdjacentPost(by: offset)
                cardDragOffset = .zero
                previewCarouselAnchorPostId = nil
            }

            HapticManager.shared.triggerLightImpact(intensity: 0.45)
        }
    }

    private func updatePreviewCarouselStepWidth(_ newValue: CGFloat) {
        guard newValue.isFinite, newValue > 0 else { return }
        guard abs(previewCarouselStepWidth - newValue) > 0.5 else { return }
        previewCarouselStepWidth = newValue
    }

    private func previewCard(for post: ExplorePost, isInteractive: Bool) -> some View {
        ExploreMapPreviewCard(
            post: post,
            speciesDisplayName: feedViewModel.resolvedSpeciesCommonName(for: post),
            mediaReloadGeneration: feedViewModel.mediaReloadGeneration,
            onOpen: { openPost(post, focusCommentComposer: false) },
            onComments: { openPost(post, focusCommentComposer: true) },
            onLike: { Task { await toggleLike(for: post) } },
            onShare: { feedViewModel.share(post) },
            onUnshare: { Task { await unshare(post) } },
            onBlock: { Task { await blockAuthor(of: post) } },
            onReport: { Task { await report(post) } }
        )
        .allowsHitTesting(isInteractive)
        .accessibilityHidden(!isInteractive)
    }

    private func resolvedPost(for mapPost: ExploreMapPost?) -> ExplorePost? {
        guard let mapPost else { return nil }
        return postStore.post(id: mapPost.id) ?? mapPost.asExplorePost
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
    let imageUrl: String
    let reloadGeneration: UInt64
    let isSelected: Bool
    let isApproximate: Bool
    let showsThumbnail: Bool
    let zoomLevel: Double
    let isNew: Bool

    var body: some View {
        Group {
            if showsThumbnail {
                thumbnailWaypoint
            } else {
                dotWaypoint
            }
        }
        .scaleEffect(isSelected ? 1.08 : 1)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .zIndex(isSelected ? 1 : 0)
    }

    private var dotWaypoint: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.white)
                .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.accentColor, lineWidth: 3)
                )

            if isApproximate {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.accentColor.opacity(0.65))
                    .frame(width: isSelected ? 32 : 28, height: isSelected ? 32 : 28)
            }
        }
    }

    private var thumbnailWaypoint: some View {
        let baseZoom: Double = 11.5
        let maxZoom: Double = 20.0
        let zoomProgress = max(0, min((zoomLevel - baseZoom) / (maxZoom - baseZoom), 1.0))
        let sizeMultiplier = 1.0 + (zoomProgress * 0.75)
        
        let baseImageSize: CGFloat = isSelected ? 50 : 44
        let imageSize: CGFloat = baseImageSize * CGFloat(sizeMultiplier)
        
        let haloSize = imageSize + (isApproximate ? 12 : 8)

        return ZStack {
            Circle()
                .fill(.regularMaterial)
                .frame(width: haloSize, height: haloSize)

            ExploreHeroImageView(
                imageUrl: imageUrl,
                reloadGeneration: reloadGeneration,
                maxDimension: 160
            )
            .frame(width: imageSize, height: imageSize)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.white, lineWidth: isSelected ? 3 : 2.5)
            }

            Circle()
                .stroke(
                    isApproximate
                        ? Color.accentColor.opacity(isSelected ? 0.95 : 0.7)
                        : Color.black.opacity(0.08),
                    style: StrokeStyle(
                        lineWidth: isApproximate ? 1.5 : 1,
                        dash: isApproximate ? [3, 2] : []
                    )
                )
                .frame(width: haloSize, height: haloSize)

            if isNew {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: haloSize / 2 * 0.707, y: -haloSize / 2 * 0.707)
            }
        }
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

private struct ExploreMapFilterSheetRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 38, height: 38)
                .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ExploreMapPreviewCard: View {
    let post: ExplorePost
    let speciesDisplayName: String
    let mediaReloadGeneration: UInt64
    let onOpen: () -> Void
    let onComments: () -> Void
    let onLike: () -> Void
    let onShare: () -> Void
    let onUnshare: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void

    @State private var showUnpublishConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: {
                        HapticManager.shared.triggerSelectionPulse()
                        onOpen()
                    }) {
                        ExploreHeroImageView(
                            imageUrl: post.heroImageUrl,
                            reloadGeneration: mediaReloadGeneration
                        )
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(speciesDisplayName)
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
                }

                Spacer(minLength: 8)

                Menu {
                    if post.isOwnedByViewer {
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
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                }
                .tint(.primary)
            }

            // MARK: - Action Buttons
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

                Spacer(minLength: 0)

                previewPill(
                    title: "Share",
                    systemImage: "square.and.arrow.up",
                    isHighlighted: false,
                    action: onShare
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            // MARK: - View Discovery Button
            Button(action: {
                HapticManager.shared.triggerSelectionPulse()
                onOpen()
            }) {
                Text("View discovery")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
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
        .alert("Unpublish Post?", isPresented: $showUnpublishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unpublish", role: .destructive, action: onUnshare)
        } message: {
            Text("This will remove the post from Explore. Your original scan will remain safely in your library.")
        }
    }

    private var subtitle: String? {
        post.publicDisplayLocationLabel
    }

    private func previewPill(
        title: String,
        systemImage: String,
        isHighlighted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.shared.triggerSelectionPulse()
            action()
        }) {
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
            .background(Color(uiColor: .secondarySystemFill))
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
