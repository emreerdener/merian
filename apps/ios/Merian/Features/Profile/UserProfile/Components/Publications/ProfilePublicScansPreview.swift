import SwiftData
import SwiftUI

@MainActor
struct ProfilePublicScansPreview: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let onOpenPost: (ExplorePost) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse)
    private var localScans: [LocalScanRecord]

    @State private var publications: ProfilePublicScansPreviewViewModel
    @State private var isLibraryPresented = false

    private let previewLimit = 9
    private let columns = PublishedScanGridStyle.columns

    init(
        viewModel: ExploreFeedViewModel,
        onOpenPost: @escaping (ExplorePost) -> Void,
        dependencies: ProfilePublicationsDependencies? = nil
    ) {
        self.viewModel = viewModel
        self.onOpenPost = onOpenPost
        _publications = State(
            initialValue: ProfilePublicScansPreviewViewModel(
                previewLimit: 9,
                dependencies: dependencies ?? .live
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .task(id: currentUserID) {
            registerPosts(await publications.load(authorUserID: currentUserID))
        }
        .onChange(of: viewModel.store.changeVersion) {
            publications.retainPosts { viewModel.post(id: $0.id) != nil }
        }
        .onReceive(publications.appEvents) { event in
            Task {
                let update = await publications.handle(
                    event: event,
                    currentUserID: currentUserID
                )
                registerPosts(update.postsToRegister)
                if update.refreshesSocialStats {
                    await profileViewModel.fetchSocialStats()
                }
            }
        }
        .onChange(of: profileViewModel.socialStats) { _, stats in
            clearRecoveryDismissalIfResolved(stats: stats)
        }
        .navigationDestination(isPresented: $isLibraryPresented) {
            if let currentUserID {
                ProfilePublishedScansLibraryView(
                    viewModel: viewModel,
                    authorUserID: currentUserID
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let posts = previewPosts

        if currentUserID != nil,
           publications.isLoading || !posts.isEmpty || publications.didFail ||
           recoverySummary != nil {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader

                if publications.isLoading && posts.isEmpty {
                    loadingGrid
                } else if publications.didFail && posts.isEmpty {
                    Text("Published scans unavailable right now.")
                        .profileExploreStateStyle()
                } else if posts.isEmpty {
                    Text(
                        recoverySummary?.userFacingEmptyMessage ??
                            "No published scans yet."
                    )
                    .profileExploreStateStyle()
                } else {
                    scanGrid(posts: posts)
                }

                if let recoverySummary, let currentUserID {
                    ProfilePublicationRecoverySummaryView(
                        summary: recoverySummary,
                        ownerUserID: currentUserID,
                        onReview: reviewRecovery,
                        onDismissFeedback: publications.selectionFeedback
                    )
                }

                if shouldShowViewMoreButton {
                    viewMoreButton
                }
            }
        } else {
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
        }
    }

    private var currentUserID: String? {
        profileViewModel.currentUserId
    }

    private var previewPosts: [ExplorePost] {
        Array(publications.posts.prefix(previewLimit))
    }

    private var recoverySummary: ProfilePublicationRecoverySummary? {
        profileViewModel.socialStats.flatMap(
            ProfilePublicationRecoverySummary.publishedOnly
        )
    }

    private var shouldShowViewMoreButton: Bool {
        if let visibleCount = profileViewModel.socialStats?
            .visiblePublishedPostCount {
            return visibleCount > previewLimit
        }
        return publications.hasLoaded && publications.posts.count == previewLimit
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Published scans")
                .font(.title3.weight(.bold))

            Spacer()

            if let visibleCount = profileViewModel.socialStats?
                .visiblePublishedPostCount {
                let noun = visibleCount == 1 ? "scan" : "scans"
                Text(
                    "\(visibleCount.formatted(.number.notation(.compactName))) \(noun)"
                )
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

    private func scanGrid(posts: [ExplorePost]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                let localReferenceURL = localScans.first {
                    $0.id == post.scanId
                }?.referenceImageUrl
                Button {
                    onOpenPost(post)
                } label: {
                    ProfilePublicScanImageView(
                        imagePath: nil,
                        fallbackURL: post.gridThumbnailUrl(
                            localReferenceUrl: localReferenceURL
                        ),
                        reloadGeneration: viewModel.mediaReloadGeneration
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .bottomTrailing) {
                        if post.hasVideoMedia || post.hasAudioMedia {
                            ExploreMediaTypeIndicator(
                                kind: post.hasVideoMedia ? .video : .audio
                            )
                            .padding(8)
                        }
                    }
                    .clipped()
                    .publishedScanTileCorners(
                        index: index,
                        itemCount: posts.count
                    )
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

    private var viewMoreButton: some View {
        Button {
            isLibraryPresented = true
        } label: {
            HStack(spacing: 4) {
                Text("View all scans")
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

    private func reviewRecovery() {
        guard let currentUserID, recoverySummary != nil else { return }
        publications.reviewRecovery(ownerUserID: currentUserID)
    }

    private func clearRecoveryDismissalIfResolved(
        stats: ProfileSocialStats?
    ) {
        guard let currentUserID,
              let stats,
              ProfilePublicationRecoverySummary.publishedOnly(from: stats) == nil
        else { return }
        ProfileRecoveryNoticePreferences.clear(ownerUserID: currentUserID)
    }

    private func registerPosts(_ posts: [ExplorePost]) {
        guard !posts.isEmpty else { return }
        posts.forEach { viewModel.upsertPost($0) }
        viewModel.refreshPreferredSpeciesNames(
            for: posts.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }
}
