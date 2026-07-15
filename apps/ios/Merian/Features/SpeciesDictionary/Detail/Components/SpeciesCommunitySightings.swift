import SwiftData
import SwiftUI

struct SpeciesCommunitySightingsSection: View {
    let speciesId: String
    let exploreViewModel: ExploreFeedViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SpeciesCommunitySightingsViewModel()
    @State private var selectedPostRoute: ExplorePostRoute?

    private let previewLimit = 6
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 2
    )

    var body: some View {
        // Keep an identity-bearing container mounted even before the first page
        // starts loading. A conditional-only Group can collapse to EmptyView,
        // preventing the task that triggers the request from ever attaching.
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isLoadingInitial && viewModel.posts.isEmpty {
                loadingSection
            } else if !viewModel.posts.isEmpty {
                sightingsSection
            }
        }
        .task(id: speciesId) {
            await viewModel.loadInitial(speciesId: speciesId, limit: previewLimit)
        }
        .onChange(of: viewModel.posts, initial: true) { _, posts in
            registerPosts(posts)
        }
        .navigationDestination(isPresented: selectedPostBinding) {
            if let selectedPostRoute {
                postDetail(for: selectedPostRoute)
            }
        }
    }

    private var sightingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            InsightCardHeader(systemImage: "person.3", title: "Community sightings") {
                Spacer()

                if viewModel.hasMore {
                    NavigationLink {
                        SpeciesCommunitySightingsGrid(
                            speciesId: speciesId,
                            viewModel: viewModel,
                            exploreViewModel: exploreViewModel
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Text("View all")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(viewModel.posts.prefix(previewLimit).enumerated()), id: \.element.id) { index, post in
                    Button {
                        openPost(post)
                    } label: {
                        SpeciesCommunitySightingTile(
                            post: post,
                            reloadGeneration: exploreViewModel.mediaReloadGeneration
                        )
                        .profilePublishedScanTileCorners(
                            index: index,
                            itemCount: min(viewModel.posts.count, previewLimit),
                            columnCount: 2
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(exploreViewModel.resolvedSpeciesCommonName(for: post)) community sighting")
                }
            }
        }
    }

    private var loadingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            InsightCardHeader(systemImage: "person.3", title: "Community sightings")
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<previewLimit, id: \.self) { index in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            GlowPulsingSkeletonView(cornerRadius: 0)
                        }
                        .profilePublishedScanTileCorners(
                            index: index,
                            itemCount: previewLimit,
                            columnCount: 2
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading community sightings")
    }

    private var selectedPostBinding: Binding<Bool> {
        Binding(
            get: { selectedPostRoute != nil },
            set: { if !$0 { selectedPostRoute = nil } }
        )
    }

    private func openPost(_ post: ExplorePost) {
        exploreViewModel.upsertPost(post)
        exploreViewModel.refreshPreferredSpeciesNames(
            for: [post.speciesScientificName],
            modelContext: modelContext
        )
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil,
            authorProfileDepth: 0
        )
    }

    private func registerPosts(_ posts: [ExplorePost]) {
        for post in posts {
            exploreViewModel.upsertPost(post)
        }
        exploreViewModel.refreshPreferredSpeciesNames(
            for: posts.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }

    private func postDetail(for route: ExplorePostRoute) -> some View {
        ExplorePostDetailView(
            viewModel: exploreViewModel,
            postId: route.postId,
            shouldFocusCommentComposer: route.shouldFocusCommentComposer,
            shouldOpenInsight: route.shouldOpenInsight,
            targetCommentId: route.targetCommentId,
            targetReplyParentCommentId: route.targetReplyParentCommentId,
            allowsInsightPresentation: false,
            authorProfileDepth: route.authorProfileDepth
        )
    }
}

private struct SpeciesCommunitySightingsGrid: View {
    let speciesId: String
    @Bindable var viewModel: SpeciesCommunitySightingsViewModel
    let exploreViewModel: ExploreFeedViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var selectedPostRoute: ExplorePostRoute?

    private let pageSize = 30
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 2
    )

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.posts) { post in
                    Button {
                        openPost(post)
                    } label: {
                        SpeciesCommunitySightingTile(
                            post: post,
                            reloadGeneration: exploreViewModel.mediaReloadGeneration
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(exploreViewModel.resolvedSpeciesCommonName(for: post)) community sighting")
                    .onAppear {
                        guard post.id == viewModel.posts.last?.id else { return }
                        Task { await viewModel.loadMore(limit: pageSize) }
                    }
                }
            }
            .padding(.top, 16)

            if viewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                Color.clear.frame(height: 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Community sightings")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: speciesId) {
            if viewModel.posts.isEmpty {
                await viewModel.loadInitial(speciesId: speciesId, limit: pageSize)
            }
        }
        .refreshable {
            await viewModel.refresh(limit: pageSize)
        }
        .onChange(of: viewModel.posts, initial: true) { _, posts in
            registerPosts(posts)
        }
        .navigationDestination(isPresented: selectedPostBinding) {
            if let selectedPostRoute {
                ExplorePostDetailView(
                    viewModel: exploreViewModel,
                    postId: selectedPostRoute.postId,
                    shouldFocusCommentComposer: selectedPostRoute.shouldFocusCommentComposer,
                    shouldOpenInsight: selectedPostRoute.shouldOpenInsight,
                    targetCommentId: selectedPostRoute.targetCommentId,
                    targetReplyParentCommentId: selectedPostRoute.targetReplyParentCommentId,
                    allowsInsightPresentation: false,
                    authorProfileDepth: selectedPostRoute.authorProfileDepth
                )
            }
        }
    }

    private var selectedPostBinding: Binding<Bool> {
        Binding(
            get: { selectedPostRoute != nil },
            set: { if !$0 { selectedPostRoute = nil } }
        )
    }

    private func openPost(_ post: ExplorePost) {
        exploreViewModel.upsertPost(post)
        exploreViewModel.refreshPreferredSpeciesNames(
            for: [post.speciesScientificName],
            modelContext: modelContext
        )
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil,
            authorProfileDepth: 0
        )
    }

    private func registerPosts(_ posts: [ExplorePost]) {
        for post in posts {
            exploreViewModel.upsertPost(post)
        }
        exploreViewModel.refreshPreferredSpeciesNames(
            for: posts.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }
}

private struct SpeciesCommunitySightingTile: View {
    let post: ExplorePost
    let reloadGeneration: UInt64

    var body: some View {
        ExploreHeroImageView(
            imageUrl: post.gridThumbnailUrl,
            reloadGeneration: reloadGeneration,
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
    }
}
