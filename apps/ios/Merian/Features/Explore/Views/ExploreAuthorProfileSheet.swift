import SwiftData
import SwiftUI

struct ExploreAuthorProfileRoute: Identifiable, Equatable {
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?

    var id: String { authorUserId }

    var authorFirstName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }

    init(post: ExplorePost) {
        self.authorUserId = post.authorUserId
        self.authorName = post.authorName
        self.authorUsername = post.authorUsername
        self.authorAvatarUrl = post.authorAvatarUrl
    }
}

struct ExploreAuthorProfileSheet: View {
    enum Mode: Equatable {
        case profile
        case library
    }

    @Bindable var viewModel: ExploreFeedViewModel
    let route: ExploreAuthorProfileRoute

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var profile: ExploreAuthorProfile?
    @State private var isLoadingProfile = true
    @State private var profileErrorMessage: String?
    @State private var mode: Mode = .profile
    @State private var libraryPosts: [ExplorePost] = []
    @State private var libraryCursor = ExploreAuthorPostCursor.empty
    @State private var isLoadingLibrary = false
    @State private var hasReachedEndOfLibrary = false
    @State private var navigationPath = NavigationPath()
    @State private var isUpdatingFollow = false

    private let previewLimit = 9
    private let libraryPageSize = 30

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                switch profileState {
                case .loading:
                    loadingState
                        .transition(.opacity)
                case .error(let message):
                    errorState(message: message)
                        .transition(.opacity)
                case .loaded(let loadedProfile):
                    ZStack {
                        if mode == .profile {
                            profileContent(loadedProfile)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        } else {
                            libraryContent(loadedProfile)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: mode)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(navigationTitle)
            .toolbar { toolbarContent }
            .navigationDestination(for: ExplorePostRoute.self) { route in
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: route.postId,
                    shouldFocusCommentComposer: route.shouldFocusCommentComposer,
                    shouldOpenInsight: route.shouldOpenInsight,
                    targetCommentId: route.targetCommentId,
                    targetReplyParentCommentId: route.targetReplyParentCommentId,
                    allowsInsightPresentation: false,
                    allowsAuthorProfilePresentation: false
                )
            }
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false
                )
            }
        }
        .task(id: route.authorUserId) {
            await loadProfile()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            guard case .publicAuthorIdentityChanged(let previousUserId, let currentUserId) = event,
                  authorIdentityChangeAffects(
                    route.authorUserId,
                    previousUserId: previousUserId,
                    currentUserId: currentUserId
                  ) else { return }

            if previousUserId == route.authorUserId.lowercased(),
               currentUserId != route.authorUserId.lowercased() {
                dismiss()
            } else {
                Task { await loadProfile(force: true) }
            }
        }
    }

    private enum ProfileState {
        case loading
        case error(String)
        case loaded(ExploreAuthorProfile)
    }

    private var profileState: ProfileState {
        if isLoadingProfile && profile == nil {
            return .loading
        }

        if let profile {
            return .loaded(profile)
        }

        return .error(profileErrorMessage ?? "This profile is not available right now.")
    }

    private var navigationTitle: String {
        switch mode {
        case .profile:
            guard let profile else { return "Profile" }
            return profile.publicUsernameDisplayName ?? profile.publicAuthorDisplayName
        case .library:
            if route.authorUserId.lowercased() == SupabaseManager.shared.currentUser?.id.uuidString.lowercased() {
                return "Your published scans"
            }
            let name = route.authorFirstName
            let possessiveName = name.hasSuffix("s") ? "\(name)’" : "\(name)’s"
            return "\(possessiveName) scans"
        }
    }

    private func authorIdentityChangeAffects(
        _ authorUserId: String,
        previousUserId: String?,
        currentUserId: String
    ) -> Bool {
        let normalizedAuthorId = authorUserId.lowercased()
        return previousUserId == normalizedAuthorId || currentUserId == normalizedAuthorId
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: leadingToolbarAction) {
                Image(systemName: mode == .library ? "chevron.left" : "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
            .accessibilityLabel(mode == .library ? "Back to profile" : "Close")
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading profile...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        EmptyStateView(
            iconName: "person.crop.circle.badge.exclamationmark",
            title: "Profile unavailable",
            message: message
        ) {
            Button {
                Task { await loadProfile(force: true) }
            } label: {
                Text("Try again")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func profileContent(_ profile: ExploreAuthorProfile) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                authorHeader(profile)

                if !isCurrentUserProfile(profile) {
                    followButton(profile)
                }

                UserStats(
                    speciesCount: profile.speciesCount,
                    streak: profile.currentStreak
                )

                ScansHeatmap(heatmapData: profile.profileHeatmapData)

                publishedPreview(profile)

                if !profile.awardPayloads.isEmpty {
                    Achievements(
                        awards: profile.awardPayloads,
                        allowsDetailPresentation: false
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func authorHeader(_ profile: ExploreAuthorProfile) -> some View {
        VStack(spacing: 12) {
            authorAvatar(url: profile.authorAvatarURL, size: 112)

            VStack(spacing: 6) {
                Text(profile.authorFirstName)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                Text(UserPersona(speciesCount: profile.speciesCount).title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            profileSummaryCountsRow(profile)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func profileSummaryCountsRow(_ profile: ExploreAuthorProfile) -> some View {
        HStack(spacing: 0) {
            profileSummaryCountView(count: profile.heatmap.totalCaptures, label: "Scans")
                .frame(maxWidth: .infinity)

            profileSummaryCountView(count: profile.completedAchievementCount, label: "Achievements")
                .frame(maxWidth: .infinity)

            profileSummaryCountView(count: profile.followerCount, label: "Followers")
                .frame(maxWidth: .infinity)

            profileSummaryCountView(count: profile.followingCount, label: "Following")
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func profileSummaryCountView(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(count.formatted(.number.notation(.compactName)))
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
    }

    private func followButton(_ profile: ExploreAuthorProfile) -> some View {
        Button {
            Task { await toggleFollow(for: profile) }
        } label: {
            HStack(spacing: 8) {
                if isUpdatingFollow {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: profile.viewerIsFollowing ? "checkmark" : "person.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                }

                Text(profile.viewerIsFollowing ? "Following" : "Follow")
                    .font(.headline)
            }
            .foregroundStyle(profile.viewerIsFollowing ? .primary : Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(profile.viewerIsFollowing ? Color(uiColor: .secondarySystemGroupedBackground) : Color.primary)
            )
            .overlay(
                Capsule()
                    .stroke(profile.viewerIsFollowing ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingFollow)
        .accessibilityLabel(profile.viewerIsFollowing ? "Following" : "Follow")
        .padding(.top, 2)
    }

    private func publishedPreview(_ profile: ExploreAuthorProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Published scans")
                    .font(.title3.weight(.bold))

                Spacer()

                Text(profile.publishedPostCount.formatted(.number.notation(.compactName)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if profile.previewPosts.isEmpty {
                Text("No published scans are visible right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                } else {
                    profileGrid(posts: Array(profile.previewPosts.prefix(previewLimit)))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

            if profile.publishedPostCount > previewLimit {
                Button(action: showLibrary) {
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
        }
    }

    private func libraryContent(_ profile: ExploreAuthorProfile) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    authorAvatar(url: profile.authorAvatarURL, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.authorFirstName)
                            .font(.headline)
                            .lineLimit(1)

                        if let username = profile.publicUsernameDisplayName,
                           username != profile.publicAuthorDisplayName {
                            Text(username)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text("\(profile.publishedPostCount.formatted(.number)) published scan\(profile.publishedPostCount == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
                .padding(.horizontal, 16)

                if libraryPosts.isEmpty && isLoadingLibrary {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if libraryPosts.isEmpty {
                    EmptyStateView(
                        iconName: "square.grid.3x3",
                        title: "No published scans",
                        message: "Published scans that are visible to you will appear here."
                    )
                    .frame(minHeight: 360)
                    .padding(.horizontal, 16)
                } else {
                    profileGrid(posts: libraryPosts, shouldPaginate: true)
                }

                if isLoadingLibrary && !libraryPosts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable {
            await reloadLibrary(from: profile)
        }
    }

    private func profileGrid(
        posts: [ExplorePost],
        shouldPaginate: Bool = false
    ) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(posts) { post in
                Button {
                    openPost(post)
                } label: {
                    ExploreHeroImageView(
                        imageUrl: post.heroImageUrl,
                        reloadGeneration: viewModel.mediaReloadGeneration,
                        maxDimension: 360
                    )
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(viewModel.resolvedSpeciesCommonName(for: post)), published scan")
                .onAppear {
                    guard shouldPaginate, post.id == libraryPosts.last?.id else { return }
                    Task { await loadMoreLibraryPostsIfNeeded() }
                }
            }
        }
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

    private func leadingToolbarAction() {
        switch mode {
        case .profile:
            dismiss()
        case .library:
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                mode = .profile
            }
        }
    }

    private func isCurrentUserProfile(_ profile: ExploreAuthorProfile) -> Bool {
        SupabaseManager.shared.currentUser?.id.uuidString.lowercased() == profile.authorUserId.lowercased()
    }

    @MainActor
    private func toggleFollow(for currentProfile: ExploreAuthorProfile) async {
        guard !isUpdatingFollow, !isCurrentUserProfile(currentProfile) else { return }

        let nextFollowingState = !currentProfile.viewerIsFollowing
        var optimisticProfile = currentProfile
        optimisticProfile.viewerIsFollowing = nextFollowingState
        optimisticProfile.followerCount = max(
            0,
            currentProfile.followerCount + (nextFollowingState ? 1 : -1)
        )

        isUpdatingFollow = true
        profile = optimisticProfile
        defer { isUpdatingFollow = false }

        do {
            let followState = try await MerianNetworkClient.shared.setUserFollow(
                authorUserId: currentProfile.authorUserId,
                isFollowing: nextFollowingState
            )
            guard !Task.isCancelled else { return }

            applyFollowState(followState)
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            guard !Task.isCancelled else { return }
            profile = currentProfile
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    @MainActor
    private func applyFollowState(_ followState: ExploreFollowState) {
        guard var currentProfile = profile,
              currentProfile.authorUserId.lowercased() == followState.authorUserId.lowercased() else {
            return
        }

        currentProfile.followerCount = followState.followerCount
        currentProfile.followingCount = followState.followingCount
        currentProfile.viewerIsFollowing = followState.viewerIsFollowing
        profile = currentProfile
    }

    private func showLibrary() {
        guard let profile else { return }
        if libraryPosts.isEmpty {
            seedLibrary(from: profile)
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            mode = .library
        }

        Task {
            await loadMoreLibraryPostsIfNeeded()
        }
    }

    @MainActor
    private func loadProfile(force: Bool = false) async {
        guard force || profile == nil else { return }
        isLoadingProfile = true
        profileErrorMessage = nil

        do {
            let loadedProfile = try await MerianNetworkClient.shared.getExploreAuthorProfile(
                authorUserId: route.authorUserId,
                previewLimit: previewLimit
            )
            guard !Task.isCancelled else { return }

            profile = loadedProfile
            profileErrorMessage = nil
            seedLibrary(from: loadedProfile)
            registerPosts(loadedProfile.previewPosts)
        } catch {
            guard !Task.isCancelled else { return }

            profile = nil
            profileErrorMessage = ExploreErrorFormatter.message(for: error)
        }

        isLoadingProfile = false
    }

    @MainActor
    private func seedLibrary(from profile: ExploreAuthorProfile) {
        libraryPosts = deduplicated(profile.previewPosts)
        if let lastPost = libraryPosts.last {
            libraryCursor = ExploreAuthorPostCursor(
                beforeSharedAt: lastPost.sharedAt,
                beforePostId: lastPost.id
            )
        } else {
            libraryCursor = .empty
        }
        hasReachedEndOfLibrary = libraryPosts.count >= profile.publishedPostCount
    }

    @MainActor
    private func reloadLibrary(from profile: ExploreAuthorProfile) async {
        libraryPosts = []
        libraryCursor = .empty
        hasReachedEndOfLibrary = false
        await loadMoreLibraryPostsIfNeeded()

        if libraryPosts.isEmpty {
            seedLibrary(from: profile)
        }
    }

    @MainActor
    private func loadMoreLibraryPostsIfNeeded() async {
        guard !isLoadingLibrary, !hasReachedEndOfLibrary else { return }
        guard let profile else { return }

        isLoadingLibrary = true
        defer { isLoadingLibrary = false }

        do {
            let page = try await MerianNetworkClient.shared.getExploreAuthorPosts(
                authorUserId: route.authorUserId,
                limit: libraryPageSize,
                cursor: libraryCursor.isEmpty ? nil : libraryCursor
            )
            guard !Task.isCancelled else { return }

            mergeLibraryPosts(page)
            registerPosts(page)

            if let lastPost = libraryPosts.last {
                libraryCursor = ExploreAuthorPostCursor(
                    beforeSharedAt: lastPost.sharedAt,
                    beforePostId: lastPost.id
                )
            }

            hasReachedEndOfLibrary = page.count < libraryPageSize || libraryPosts.count >= profile.publishedPostCount
        } catch {
            guard !Task.isCancelled else { return }
            HapticManager.shared.triggerErrorThump()
            viewModel.toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    @MainActor
    private func mergeLibraryPosts(_ posts: [ExplorePost]) {
        libraryPosts = deduplicated(libraryPosts + posts)
    }

    private func deduplicated(_ posts: [ExplorePost]) -> [ExplorePost] {
        var seenIds = Set<String>()
        return posts.filter { post in
            seenIds.insert(post.id).inserted
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
    private func openPost(_ post: ExplorePost) {
        viewModel.upsertPost(post)
        viewModel.refreshPreferredSpeciesNames(for: [post.speciesScientificName], modelContext: modelContext)
        navigationPath.append(ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil
        ))
    }
}

private extension ExploreAuthorProfile {
    var completedAchievementCount: Int {
        awardPayloads.filter(\.isCompleted).count
    }

    var authorFirstName: String {
        publicAuthorDisplayName
    }
}
