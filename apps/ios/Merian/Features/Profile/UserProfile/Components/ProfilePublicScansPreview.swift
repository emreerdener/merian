import SwiftData
import SwiftUI
import UIKit

struct ProfilePublicScansPreview: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let onOpenPost: (ExplorePost) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SupabaseManager.self) private var supabase
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var localScans: [LocalScanRecord]

    @State private var remotePosts: [ExplorePost] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var didFail = false
    @State private var shareStateRevision: UInt64 = 0
    @State private var isLibraryPresented = false

    private let previewLimit = 9
    private let columns = ProfilePublishedScanGridStyle.columns

    var body: some View {
        content
            .task(id: currentUserId) {
                await loadPreviewPosts(for: currentUserId)
            }
            .onChange(of: viewModel.store.changeVersion) {
                remotePosts.removeAll { viewModel.post(id: $0.id) == nil }
            }
            .onReceive(AppEventPublisher.shared.publisher) { event in
                handleAppEvent(event)
            }
            .navigationDestination(isPresented: $isLibraryPresented) {
                if let currentUserId {
                    ProfilePublishedScansLibraryView(
                        viewModel: viewModel,
                        authorUserId: currentUserId
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        let items = previewItems

        if currentUserId != nil, isLoading || !items.isEmpty || hasLoaded || didFail {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader

                if isLoading && items.isEmpty {
                    loadingGrid
                } else if didFail && items.isEmpty {
                    unavailableState
                } else if items.isEmpty {
                    emptyState
                } else {
                    scanGrid(items: items)
                }

                if shouldShowViewMoreButton {
                    viewMoreButton
                }
            }
        }
    }

    private var currentUserId: String? {
        supabase.currentUser?.id.uuidString
    }

    private var publishedPostCount: Int? {
        profileViewModel.socialStats?.publishedPostCount
    }

    private var shouldShowViewMoreButton: Bool {
        if let publishedPostCount {
            return publishedPostCount > previewLimit
        }

        return hasLoaded && remotePosts.count == previewLimit
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Published scans")
                .font(.title3.weight(.bold))

            Spacer()

            if let publishedPostCount {
                Text(publishedPostCount.formatted(.number.notation(.compactName)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if profileViewModel.isLoadingSocialStats {
                Text("000")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .redacted(reason: .placeholder)
                    .accessibilityLabel("Loading published scans count")
            }
        }
    }

    private var previewItems: [ProfilePublicScanPreviewItem] {
        _ = shareStateRevision

        var items: [ProfilePublicScanPreviewItem] = []
        var seenPostIds = Set<String>()
        var seenScanIds = Set<String>()

        for post in remotePosts {
            guard items.count < previewLimit else { break }
            let localScan = localScans.first { $0.id == post.scanId }
            seenPostIds.insert(post.id)
            seenScanIds.insert(post.scanId)
            items.append(
                ProfilePublicScanPreviewItem(
                    id: post.id,
                    scanId: post.scanId,
                    postId: post.id,
                    imagePath: nil,
                    fallbackUrl: post.gridThumbnailUrl(
                        localReferenceUrl: localScan?.referenceImageUrl
                    ),
                    localHasAudioMedia: false,
                    post: post
                )
            )
        }

        for scan in localScans {
            guard items.count < previewLimit else { break }
            guard let postId = ExploreShareStateStore.sharedPostId(for: scan.id) else { continue }
            guard !seenPostIds.contains(postId), !seenScanIds.contains(scan.id) else { continue }

            seenPostIds.insert(postId)
            seenScanIds.insert(scan.id)
            items.append(
                ProfilePublicScanPreviewItem(
                    id: postId,
                    scanId: scan.id,
                    postId: postId,
                    imagePath: localImagePath(for: scan),
                    fallbackUrl: scan.referenceImageUrl?.trimmedProfilePreviewValue,
                    localHasAudioMedia: scan.capturedMediaSnapshot.summary.hasAudio,
                    post: nil
                )
            )
        }

        return items
    }

    private func scanGrid(items: [ProfilePublicScanPreviewItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    Task { await openPreviewItem(item) }
                } label: {
                    ProfilePublicScanImageView(
                        imagePath: item.imagePath,
                        fallbackUrl: item.fallbackUrl,
                        reloadGeneration: viewModel.mediaReloadGeneration
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if item.hasVideoMedia || item.hasAudioMedia {
                            ExploreMediaTypeIndicator(kind: item.hasVideoMedia ? .video : .audio)
                                .padding(6)
                        }
                    }
                    .clipped()
                    .profilePublishedScanTileCorners(index: index, itemCount: items.count)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Published scan")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<previewLimit, id: \.self) { _ in
                GlowPulsingSkeletonView(cornerRadius: 3, style: .raisedGrid)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private var emptyState: some View {
        Text("No published scans yet.")
            .profileExploreStateStyle()
    }

    private var unavailableState: some View {
        Text("Published scans unavailable right now.")
            .profileExploreStateStyle()
    }

    private var viewMoreButton: some View {
        Button {
            isLibraryPresented = true
        } label: {
            HStack(spacing: 4) {
                Text("View more scans")
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadPreviewPosts(for authorUserId: String?) async {
        guard let authorUserId else {
            remotePosts = []
            hasLoaded = false
            didFail = false
            isLoading = false
            return
        }

        isLoading = true
        hasLoaded = false
        didFail = false
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let loadedPosts = try await MerianNetworkClient.shared.getExploreAuthorPosts(
                authorUserId: authorUserId,
                limit: previewLimit
            )
            guard !Task.isCancelled else { return }

            registerPosts(loadedPosts)
            remotePosts = loadedPosts
        } catch {
            guard !Task.isCancelled else { return }
            remotePosts = []
            didFail = true
        }
    }

    @MainActor
    private func openPreviewItem(_ item: ProfilePublicScanPreviewItem) async {
        if let post = item.post {
            onOpenPost(post)
            return
        }

        guard let postId = item.postId else { return }

        do {
            let post = try await MerianNetworkClient.shared.getExplorePost(postId: postId)
            registerPosts([post])
            upsertRemotePost(post)
            onOpenPost(post)
        } catch {
            didFail = true
        }
    }

    @MainActor
    private func registerPosts(_ posts: [ExplorePost]) {
        for post in posts {
            viewModel.upsertPost(post)
        }
        viewModel.refreshPreferredSpeciesNames(
            for: posts.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }

    @MainActor
    private func upsertRemotePost(_ post: ExplorePost) {
        if let index = remotePosts.firstIndex(where: { $0.id == post.id }) {
            remotePosts[index] = post
        } else {
            remotePosts.insert(post, at: 0)
            remotePosts = Array(remotePosts.prefix(previewLimit))
        }
    }

    private func handleAppEvent(_ event: AppEvent) {
        switch event {
        case .exploreShareStateChanged(let scanId, let postId):
            shareStateRevision &+= 1
            if postId == nil {
                remotePosts.removeAll { $0.scanId == scanId }
            }
            Task {
                await loadPreviewPosts(for: currentUserId)
                await profileViewModel.fetchSocialStats()
            }
        case .explorePostNeedsRefresh(let postId):
            guard remotePosts.contains(where: { $0.id == postId }) else { return }
            Task {
                if let post = try? await MerianNetworkClient.shared.getExplorePost(postId: postId) {
                    registerPosts([post])
                    upsertRemotePost(post)
                }
            }
        case .publicAuthorIdentityChanged(_, let currentUserId):
            Task {
                await loadPreviewPosts(for: currentUserId)
                await profileViewModel.fetchSocialStats()
            }
        default:
            break
        }
    }

    private func localImagePath(for scan: LocalScanRecord) -> String? {
        scan.coverImagePath?.trimmedProfilePreviewValue
            ?? scan.capturedMediaSnapshot.primaryImagePath?.trimmedProfilePreviewValue
    }
}

private struct ProfilePublishedScansLibraryView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let authorUserId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var localScans: [LocalScanRecord]

    @State private var posts: [ExplorePost] = []
    @State private var cursor = ExploreAuthorPostCursor.empty
    @State private var isLoading = false
    @State private var didFail = false
    @State private var hasReachedEnd = false
    @State private var selectedPostRoute: ExplorePostRoute?
    @State private var selectedInsightRoute: ScanInsightRoute?

    private let pageSize = 30
    private let columns = ProfilePublishedScanGridStyle.columns

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                    .padding(.horizontal, 16)

                if posts.isEmpty && isLoading {
                    loadingGrid(count: 12)
                } else if didFail && posts.isEmpty {
                    Text("Published scans unavailable right now.")
                        .profileExploreStateStyle()
                        .padding(.horizontal, 16)
                } else if posts.isEmpty {
                    Text("No published scans yet.")
                        .profileExploreStateStyle()
                        .padding(.horizontal, 16)
                } else {
                    libraryGrid
                }

                if isLoading && !posts.isEmpty {
                    loadingGrid(count: 6)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: authorUserId) {
            await reloadPosts()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            guard case .publicAuthorIdentityChanged(let previousUserId, let currentUserId) = event,
                  authorIdentityChangeAffects(
                    authorUserId,
                    previousUserId: previousUserId,
                    currentUserId: currentUserId
                  ) else { return }

            Task {
                await reloadPosts()
                await profileViewModel.fetchSocialStats()
            }
        }
        .refreshable {
            await reloadPosts()
        }
        .navigationDestination(
            isPresented: Binding(
                get: { selectedPostRoute != nil },
                set: { if !$0 { selectedPostRoute = nil } }
            )
        ) {
            if let selectedPostRoute {
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: selectedPostRoute.postId,
                    shouldFocusCommentComposer: selectedPostRoute.shouldFocusCommentComposer,
                    shouldOpenInsight: selectedPostRoute.shouldOpenInsight,
                    targetCommentId: selectedPostRoute.targetCommentId,
                    targetReplyParentCommentId: selectedPostRoute.targetReplyParentCommentId,
                    allowsInsightPresentation: false,
                    onOpenOwnedPostInsight: openInsight
                )
            }
        }
        .sheet(item: $selectedInsightRoute) { route in
            InsightSheetView(
                isPresented: Binding(
                    get: { selectedInsightRoute != nil },
                    set: { if !$0 { selectedInsightRoute = nil } }
                ),
                initialScanId: route.scanId,
                inferenceEngine: inferenceEngine,
                allowsExplorePresentation: false
            )
        }
    }

    private var navigationTitle: String {
        "Your published scans"
    }

    private var publishedPostCount: Int? {
        profileViewModel.socialStats?.publishedPostCount
    }

    private func authorIdentityChangeAffects(
        _ authorUserId: String,
        previousUserId: String?,
        currentUserId: String
    ) -> Bool {
        let normalizedAuthorId = authorUserId.lowercased()
        return previousUserId == normalizedAuthorId || currentUserId == normalizedAuthorId
    }

    private var publishedCountSummary: String? {
        guard let publishedPostCount else { return nil }
        let noun = publishedPostCount == 1 ? "scan" : "scans"
        return "\(publishedPostCount.formatted(.number)) published \(noun)"
    }

    private var header: some View {
        HStack(spacing: 12) {
            authorAvatar(url: profileViewModel.userAvatarURL, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(profileViewModel.userName ?? profileViewModel.publicAuthorName ?? "Explorer")
                    .font(.headline)
                    .lineLimit(1)

                if let username = profileViewModel.publicUsernameDisplayName {
                    Text(username)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let publishedCountSummary {
                    Text(publishedCountSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func authorAvatar(url: URL?, size: CGFloat) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackAvatar(size: size)
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackAvatar(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallbackAvatar(size: size)
        }
    }

    private func fallbackAvatar(size: CGFloat) -> some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }

    private var libraryGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { _, post in
                let localReferenceUrl = localScans.first { $0.id == post.scanId }?.referenceImageUrl
                Button {
                    openPost(post)
                } label: {
                    ProfilePublicScanImageView(
                        imagePath: nil,
                        fallbackUrl: post.gridThumbnailUrl(
                            localReferenceUrl: localReferenceUrl
                        ),
                        reloadGeneration: viewModel.mediaReloadGeneration
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if post.hasVideoMedia || post.hasAudioMedia {
                            ExploreMediaTypeIndicator(kind: post.hasVideoMedia ? .video : .audio)
                                .padding(6)
                        }
                    }
                    .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(viewModel.resolvedSpeciesCommonName(for: post)), published scan")
                .onAppear {
                    guard post.id == posts.last?.id else { return }
                    Task { await loadMorePostsIfNeeded() }
                }
            }
        }
    }

    private func loadingGrid(count: Int) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in
                GlowPulsingSkeletonView(cornerRadius: 3, style: .raisedGrid)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }

    @MainActor
    private func reloadPosts() async {
        posts = []
        cursor = .empty
        hasReachedEnd = false
        didFail = false
        await loadMorePostsIfNeeded()
    }

    @MainActor
    private func loadMorePostsIfNeeded() async {
        guard !isLoading, !hasReachedEnd else { return }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let page = try await MerianNetworkClient.shared.getExploreAuthorPosts(
                authorUserId: authorUserId,
                limit: pageSize,
                cursor: cursor.isEmpty ? nil : cursor
            )
            guard !Task.isCancelled else { return }

            mergePosts(page)
            registerPosts(page)
            updateCursor()
            hasReachedEnd = page.count < pageSize || hasLoadedPublishedPostCount
            didFail = false
        } catch {
            guard !Task.isCancelled else { return }
            didFail = true
        }
    }

    private var hasLoadedPublishedPostCount: Bool {
        if let publishedPostCount {
            return posts.count >= publishedPostCount
        }

        return false
    }

    @MainActor
    private func mergePosts(_ nextPage: [ExplorePost]) {
        var seenIds = Set(posts.map(\.id))
        posts.append(contentsOf: nextPage.filter { seenIds.insert($0.id).inserted })
    }

    @MainActor
    private func updateCursor() {
        guard let lastPost = posts.last else {
            cursor = .empty
            return
        }

        cursor = ExploreAuthorPostCursor(
            beforeSharedAt: lastPost.sharedAt,
            beforePostId: lastPost.id
        )
    }

    @MainActor
    private func registerPosts(_ posts: [ExplorePost]) {
        for post in posts {
            viewModel.upsertPost(post)
        }
        viewModel.refreshPreferredSpeciesNames(
            for: posts.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }

    @MainActor
    private func openPost(_ post: ExplorePost) {
        viewModel.upsertPost(post)
        viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil
        )
    }

    private func openInsight(scanId: String) -> Bool {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let record = try? modelContext.fetch(descriptor).first else {
            return false
        }

        inferenceEngine.load(from: record)
        selectedInsightRoute = ScanInsightRoute(scanId: record.id)
        return true
    }
}

private struct ProfilePublicScanPreviewItem: Identifiable, Equatable {
    let id: String
    let scanId: String
    let postId: String?
    let imagePath: String?
    let fallbackUrl: String?
    let localHasAudioMedia: Bool
    let post: ExplorePost?

    var hasVideoMedia: Bool {
        post?.hasVideoMedia == true
    }

    var hasAudioMedia: Bool {
        localHasAudioMedia || post?.hasAudioMedia == true
    }
}

private struct ProfilePublicScanImageView: View {
    let imagePath: String?
    let fallbackUrl: String?
    let reloadGeneration: UInt64

    @State private var loadedImage: UIImage?
    @State private var hasFailedToLoad = false

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
        .task(id: "\(imagePath ?? "")|\(fallbackUrl ?? "")|\(reloadGeneration)") {
            loadedImage = nil
            hasFailedToLoad = false

            let image = await LocalImageLoader.shared.loadImage(
                fromPath: imagePath,
                fallbackUrl: fallbackUrl,
                maxDimension: 360
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
        GlowPulsingSkeletonView(cornerRadius: 3, style: .raisedGrid)
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

enum ProfilePublishedScanGridStyle {
    static let columnCount = 3
    static let spacing: CGFloat = 2
    static let cornerRadius: CGFloat = 16

    static var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    static func cornerRadii(index: Int, itemCount: Int) -> RectangleCornerRadii {
        guard itemCount > 0 else { return RectangleCornerRadii() }

        let r = index / columnCount
        let c = index % columnCount
        let totalRows = (itemCount + columnCount - 1) / columnCount

        func itemsInRow(_ row: Int) -> Int {
            min(columnCount, itemCount - row * columnCount)
        }

        let isTopLeft = r == 0 && c == 0
        let isTopRight = r == 0 && c == itemsInRow(0) - 1

        let isBottomLeft = c == 0 && r == totalRows - 1

        let hasNoCellBelow = (r + 1 == totalRows) || (c >= itemsInRow(r + 1))
        let isBottomRight = c == itemsInRow(r) - 1 && hasNoCellBelow

        return RectangleCornerRadii(
            topLeading: isTopLeft ? cornerRadius : 0,
            bottomLeading: isBottomLeft ? cornerRadius : 0,
            bottomTrailing: isBottomRight ? cornerRadius : 0,
            topTrailing: isTopRight ? cornerRadius : 0
        )
    }
}

private extension String {
    var trimmedProfilePreviewValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension View {
    func profilePublishedScanTileCorners(index: Int, itemCount: Int) -> some View {
        clipShape(
            UnevenRoundedRectangle(
                cornerRadii: ProfilePublishedScanGridStyle.cornerRadii(index: index, itemCount: itemCount),
                style: .continuous
            )
        )
    }

    func profileExploreStateStyle() -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}
