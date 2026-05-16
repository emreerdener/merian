import SwiftData
import SwiftUI
import UIKit

struct ProfilePublicScansPreview: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let onOpenPost: (ExplorePost) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SupabaseManager.self) private var supabase
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var localScans: [LocalScanRecord]

    @State private var remotePosts: [ExplorePost] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var didFail = false
    @State private var shareStateRevision: UInt64 = 0

    private let previewLimit = 9
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

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
    }

    @ViewBuilder
    private var content: some View {
        let items = previewItems

        if currentUserId != nil, isLoading || !items.isEmpty || hasLoaded || didFail {
            VStack(alignment: .leading, spacing: 14) {
                Text("Explore scans")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLoading && items.isEmpty {
                    loadingGrid
                } else if didFail && items.isEmpty {
                    unavailableState
                } else if items.isEmpty {
                    emptyState
                } else {
                    scanGrid(items: items)
                }
            }
        }
    }

    private var currentUserId: String? {
        supabase.currentUser?.id.uuidString
    }

    private var previewItems: [ProfilePublicScanPreviewItem] {
        _ = shareStateRevision

        var items: [ProfilePublicScanPreviewItem] = []
        var seenPostIds = Set<String>()
        var seenScanIds = Set<String>()

        for post in remotePosts {
            guard items.count < previewLimit else { break }
            seenPostIds.insert(post.id)
            seenScanIds.insert(post.scanId)
            items.append(
                ProfilePublicScanPreviewItem(
                    id: post.id,
                    scanId: post.scanId,
                    postId: post.id,
                    imagePath: nil,
                    fallbackUrl: post.heroImageUrl,
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
                    post: nil
                )
            )
        }

        return items
    }

    private func scanGrid(items: [ProfilePublicScanPreviewItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(items) { item in
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
                    .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Explore scan")
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
        Text("No public Explore scans yet.")
            .profileExploreStateStyle()
    }

    private var unavailableState: some View {
        Text("Explore scans unavailable right now.")
            .profileExploreStateStyle()
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
            Task { await loadPreviewPosts(for: currentUserId) }
        case .explorePostNeedsRefresh(let postId):
            guard remotePosts.contains(where: { $0.id == postId }) else { return }
            Task {
                if let post = try? await MerianNetworkClient.shared.getExplorePost(postId: postId) {
                    registerPosts([post])
                    upsertRemotePost(post)
                }
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

private struct ProfilePublicScanPreviewItem: Identifiable, Equatable {
    let id: String
    let scanId: String
    let postId: String?
    let imagePath: String?
    let fallbackUrl: String?
    let post: ExplorePost?
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

private extension String {
    var trimmedProfilePreviewValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension View {
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
