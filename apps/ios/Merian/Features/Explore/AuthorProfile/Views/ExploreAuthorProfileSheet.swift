import SwiftData
import SwiftUI

enum ExploreAuthorProfileNavigationPolicy {
    static let maxProfileDepth = 1

    static func canOpenProfile(from currentDepth: Int) -> Bool {
        currentDepth < maxProfileDepth
    }

    static func nextProfileDepth(from currentDepth: Int) -> Int {
        min(currentDepth + 1, maxProfileDepth)
    }
}

struct ExploreAuthorProfileRoute: Identifiable, Equatable, Hashable {
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let navigationDepth: Int

    var id: String { authorUserId }

    var authorFirstName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }

    init(post: ExplorePost, navigationDepth: Int = 0) {
        self.authorUserId = post.authorUserId
        self.authorName = post.authorName
        self.authorUsername = post.authorUsername
        self.authorAvatarUrl = post.authorAvatarUrl
        self.navigationDepth = navigationDepth
    }

    init(comment: ExploreComment, navigationDepth: Int = 0) {
        self.authorUserId = comment.authorUserId
        self.authorName = comment.authorName
        self.authorUsername = comment.authorUsername
        self.authorAvatarUrl = comment.authorAvatarUrl
        self.navigationDepth = navigationDepth
    }

    init(mention: ExploreCommentMention, navigationDepth: Int = 0) {
        self.authorUserId = mention.userId
        self.authorName = mention.displayName
        self.authorUsername = mention.username
        self.authorAvatarUrl = mention.avatarUrl
        self.navigationDepth = navigationDepth
    }

    init(
        authorUserId: String,
        authorName: String,
        authorUsername: String?,
        authorAvatarUrl: String?,
        navigationDepth: Int = 0
    ) {
        self.authorUserId = authorUserId
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorAvatarUrl = authorAvatarUrl
        self.navigationDepth = navigationDepth
    }

    func withNavigationDepth(_ depth: Int) -> ExploreAuthorProfileRoute {
        ExploreAuthorProfileRoute(
            authorUserId: authorUserId,
            authorName: authorName,
            authorUsername: authorUsername,
            authorAvatarUrl: authorAvatarUrl,
            navigationDepth: depth
        )
    }
}

struct ExploreAuthorProfileSheet: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let route: ExploreAuthorProfileRoute

    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ExploreAuthorProfileContent(
                viewModel: viewModel,
                route: route,
                presentation: .sheet,
                onClose: { dismiss() },
                onOpenPostRoute: { route in
                    navigationPath.append(route)
                },
                onOpenPublication: { publicationId in
                    navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                },
                onOpenTemplate: { templateId in
                    navigationPath.append(FieldTripTemplateRoute(templateId: templateId))
                }
            )
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
                    showsCloseButton: false,
                    exploreViewModel: viewModel
                )
            }
            .navigationDestination(for: FieldTripPublicationRoute.self) { route in
                FieldTripPublicationDetailView(publicationId: route.publicationId)
            }
            .navigationDestination(for: FieldTripTemplateRoute.self) { route in
                FieldTripTemplateDetailView(
                    reference: route.reference,
                    focusedChecklistItemId: route.focusedChecklistItemId,
                    onOpenCompletedScan: { _ in },
                    onOpenPublication: { publicationId in
                        navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                    },
                    onOpenAuthorProfile: { _ in }
                )
            }
        }
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
    }
}

struct ExploreAuthorProfileContent: View {
    enum Presentation: Equatable {
        case sheet
        case stack
    }

    enum Mode: Equatable {
        case profile
        case library
    }

    @Bindable var viewModel: ExploreFeedViewModel
    let route: ExploreAuthorProfileRoute
    let presentation: Presentation
    let onClose: () -> Void
    let onOpenPostRoute: (ExplorePostRoute) -> Void
    let onOpenPublication: (String) -> Void
    let onOpenTemplate: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var localScans: [LocalScanRecord]

    @State private var profile: ExploreAuthorProfile?
    @State private var isLoadingProfile = true
    @State private var profileErrorMessage: String?
    @State private var mode: Mode = .profile
    @State private var libraryPosts: [ExplorePost] = []
    @State private var libraryCursor = ExploreAuthorPostCursor.empty
    @State private var isLoadingLibrary = false
    @State private var hasReachedEndOfLibrary = false
    @State private var isUpdatingFollow = false
    @State private var isReportUserPresented = false

    private let previewLimit = 9
    private let libraryPageSize = 30

    var body: some View {
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
        .navigationBarBackButtonHidden(mode == .library)
        .navigationTitle(navigationTitle)
        .toolbar { toolbarContent }
        .task(id: route.authorUserId) {
            await loadProfile()
        }
        .sheet(isPresented: $isReportUserPresented) {
            if let profile {
                ExploreReportUserSheet(profile: profile) {
                    viewModel.toastMessage = "Report submitted for review."
                }
            }
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
                onClose()
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
            return ""
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
        if mode == .library || presentation == .sheet {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: leadingToolbarAction) {
                    Image(systemName: mode == .library ? "chevron.left" : "xmark")
                        .font(.system(size: 16, weight: .bold))
                }
                .accessibilityLabel(mode == .library ? "Back to profile" : "Close")
            }
        }

        if mode == .profile, let profile, profile.viewerCanReport == true {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isReportUserPresented = true
                    } label: {
                        Label("Report user", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Profile actions")
            }
        }
    }

    private var loadingState: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                ExploreAuthorProfileSkeletonCard()

                if !isCurrentUserRoute {
                    ExploreAuthorProfileSkeletonFollowButton()
                }

                ExploreAuthorProfileSkeletonStats()
                ExploreAuthorProfileSkeletonHeatmap()
                ExploreAuthorProfileSkeletonGrid()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityLabel("Loading profile")
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Profile unavailable",
            message: message
        ) {
            Task { await loadProfile(force: true) }
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

                if FeatureFlags.isEnabled(.fieldTrips),
                   let fieldTrips = profile.fieldTrips,
                   FieldTripProfilePresentation.hasContent(
                       fieldTrips,
                       eventsEnabled: FieldTripEventsAvailability.isEnabled
                   ) {
                    FieldTripProfilePreview(
                        summaries: fieldTrips,
                        onOpenTemplate: onOpenTemplate,
                        onOpenPublication: onOpenPublication
                    )
                }

                publishedPreview(profile)

                let awards = visibleAwards(for: profile)
                if !awards.isEmpty {
                    Achievements(
                        awards: awards,
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
        let earnedPatches = earnedFieldTripPatches(for: profile)

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                authorAvatar(url: profile.authorAvatarURL, size: 48)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(profile.profileTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityAddTraits(.isHeader)

                        if shouldShowProBadge(for: profile) {
                            ExploreProBadge()
                        }
                    }

                    if let username = profile.publicUsernameDisplayName {
                        Text(username)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)
            }

            Divider()

            profileSummaryCountsRow(profile)

            if !earnedPatches.isEmpty {
                Divider()
                EarnedFieldTripPatchCarousel(
                    patches: earnedPatches,
                    onOpenFieldTrip: onOpenTemplate
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func earnedFieldTripPatches(for profile: ExploreAuthorProfile) -> [EarnedFieldTripPatch] {
        guard FeatureFlags.isEnabled(.fieldTrips), let fieldTrips = profile.fieldTrips else { return [] }
        return EarnedFieldTripPatchPresentation.items(profileSummaries: fieldTrips.active)
    }

    private var isCurrentUserRoute: Bool {
        SupabaseManager.shared.currentUser?.id.uuidString.lowercased()
            == route.authorUserId.lowercased()
    }

    private func shouldShowProBadge(for profile: ExploreAuthorProfile) -> Bool {
        profile.authorIsPro == true || (isCurrentUserProfile(profile) && RevenueCatManager.shared.isProActive)
    }

    private func profileSummaryCountsRow(_ profile: ExploreAuthorProfile) -> some View {
        HStack(spacing: 0) {
            profileSummaryCountView(count: profile.heatmap.totalCaptures, label: "Scans")
                .frame(maxWidth: .infinity)

            profileSummaryCountView(
                count: visibleAwards(for: profile).filter(\.isCompleted).count,
                label: "Achievements"
            )
                .frame(maxWidth: .infinity)

            profileSummaryCountView(count: profile.followerCount, label: "Followers")
                .frame(maxWidth: .infinity)

            profileSummaryCountView(count: profile.followingCount, label: "Following")
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func visibleAwards(for profile: ExploreAuthorProfile) -> [AwardPayload] {
        guard !FeatureFlags.isEnabled(.fieldTrips) else { return profile.awardPayloads }
        return profile.awardPayloads.filter { $0.type != .firstFieldTrip }
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
                    profileGrid(posts: Array(profile.previewPosts.prefix(previewLimit)), applyCornerRounding: true)
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
                        Text(profile.profileTitle)
                            .font(.headline)
                            .lineLimit(1)

                        if let username = profile.publicUsernameDisplayName,
                           username != profile.profileTitle {
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
        shouldPaginate: Bool = false,
        applyCornerRounding: Bool = false
     ) -> some View {
         let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

         return LazyVGrid(columns: columns, spacing: 2) {
             ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                 let localReferenceUrl = localReferenceUrl(for: post)
                 Button {
                     openPost(post)
                 } label: {
                     if applyCornerRounding {
                         ExploreHeroImageView(
                             imageUrl: post.gridThumbnailUrl(
                                 localReferenceUrl: localReferenceUrl
                             ),
                             reloadGeneration: viewModel.mediaReloadGeneration,
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
                         .profilePublishedScanTileCorners(index: index, itemCount: posts.count)
                     } else {
                         ExploreHeroImageView(
                             imageUrl: post.gridThumbnailUrl(
                                 localReferenceUrl: localReferenceUrl
                             ),
                             reloadGeneration: viewModel.mediaReloadGeneration,
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
                 .buttonStyle(.plain)
                 .accessibilityLabel("\(viewModel.resolvedSpeciesCommonName(for: post)), published scan")
                 .onAppear {
                     guard shouldPaginate, post.id == libraryPosts.last?.id else { return }
                     Task { await loadMoreLibraryPostsIfNeeded() }
                 }
             }
         }
     }

    private func localReferenceUrl(for post: ExplorePost) -> String? {
        guard SupabaseManager.shared.currentUser?.id.uuidString.lowercased()
            == route.authorUserId.lowercased() else {
            return nil
        }

        return localScans.first { $0.id == post.scanId }?.referenceImageUrl
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
            onClose()
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

            LocalImageLoader.shared.prefetch(
                records: loadedProfile.previewPosts.map { post in
                    (
                        imagePath: nil,
                        fallbackUrl: post.gridThumbnailUrl(
                            localReferenceUrl: localReferenceUrl(for: post)
                        )
                    )
                },
                maxDimension: 360
            )
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
        hasReachedEndOfLibrary = false
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
        guard profile != nil else { return }

        isLoadingLibrary = true
        defer { isLoadingLibrary = false }

        do {
            let page = try await MerianNetworkClient.shared.getExploreAuthorPosts(
                authorUserId: route.authorUserId,
                limit: libraryPageSize,
                cursor: libraryCursor.isEmpty ? nil : libraryCursor
            )
            guard !Task.isCancelled else { return }

            mergeLibraryPosts(page.data)
            registerPosts(page.data)
            libraryCursor = page.nextCursor ?? .empty
            hasReachedEndOfLibrary = page.nextCursor == nil
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
        onOpenPostRoute(ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil,
            authorProfileDepth: route.navigationDepth
        ))
    }
}

private struct ExploreReportUserSheet: View {
    let profile: ExploreAuthorProfile
    let onReported: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ExploreUserReportReason.spam
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let detailsLimit = 1_000

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(ExploreUserReportReason.allCases) { reportReason in
                            Text(reportReason.rawValue).tag(reportReason)
                        }
                    }
                } header: {
                    Text("Why are you reporting this profile?")
                }

                Section {
                    TextField(
                        "Add optional context",
                        text: $details,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .onChange(of: details) { _, newValue in
                        if newValue.count > detailsLimit {
                            details = String(newValue.prefix(detailsLimit))
                        }
                    }

                    Text("\(details.count)/\(detailsLimit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } header: {
                    Text("Details")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Report error: \(errorMessage)")
                    }
                }

                Section {
                    Text("Reporting does not automatically block this person. Naturebook moderators will review the report.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report \(profile.publicAuthorDisplayName)")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSubmitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await MerianNetworkClient.shared.reportUser(
                reportedUserId: profile.authorUserId,
                reason: reason,
                details: details
            )
            guard !Task.isCancelled else { return }
            HapticManager.shared.triggerSuccessPulse()
            onReported()
            dismiss()
        } catch {
            guard !Task.isCancelled else { return }
            HapticManager.shared.triggerErrorThump()
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

private struct ExploreAuthorProfileSkeletonCard: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GlowPulsingSkeletonView(cornerRadius: 24)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 5) {
                    GlowPulsingSkeletonView(cornerRadius: 6)
                        .frame(width: 156, height: 22)

                    GlowPulsingSkeletonView(cornerRadius: 5)
                        .frame(width: 92, height: 15)
                }

                Spacer(minLength: 0)
            }

            Divider()

            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(spacing: 4) {
                        GlowPulsingSkeletonView(cornerRadius: 5)
                            .frame(width: 38, height: 20)
                        GlowPulsingSkeletonView(cornerRadius: 4)
                            .frame(width: 64, height: 13)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if FeatureFlags.isEnabled(.fieldTrips) {
                Divider()
                EarnedFieldTripPatchCarouselSkeleton()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityHidden(true)
    }
}

private struct ExploreAuthorProfileSkeletonFollowButton: View {
    var body: some View {
        GlowPulsingSkeletonView(cornerRadius: 24)
            .frame(height: 50)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }
}

private struct ExploreAuthorProfileSkeletonStats: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    GlowPulsingSkeletonView(cornerRadius: 10)
                        .frame(width: 54, height: 54)
                    Spacer(minLength: 0)
                    GlowPulsingSkeletonView(cornerRadius: 7)
                        .frame(width: 74, height: 34)
                    GlowPulsingSkeletonView(cornerRadius: 6)
                        .frame(width: 128, height: 18)
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ExploreAuthorProfileSkeletonHeatmap: View {
    private let columns = Array(repeating: GridItem(.fixed(11), spacing: 3), count: 18)

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                GlowPulsingSkeletonView(cornerRadius: 5)
                    .frame(width: 28, height: 28)
                GlowPulsingSkeletonView(cornerRadius: 7)
                    .frame(width: 176, height: 30)
                GlowPulsingSkeletonView(cornerRadius: 7)
                    .frame(width: 64, height: 30)
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<126, id: \.self) { _ in
                    GlowPulsingSkeletonView(cornerRadius: 2, style: .raisedGrid)
                        .frame(width: 11, height: 11)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}

private struct ExploreAuthorProfileSkeletonGrid: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                GlowPulsingSkeletonView(cornerRadius: 6)
                    .frame(width: 150, height: 24)
                Spacer()
                GlowPulsingSkeletonView(cornerRadius: 5)
                    .frame(width: 34, height: 18)
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<6, id: \.self) { _ in
                    GlowPulsingSkeletonView(cornerRadius: 3, style: .raisedGrid)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

private extension ExploreAuthorProfile {
    var completedAchievementCount: Int {
        awardPayloads.filter(\.isCompleted).count
    }

    var authorFirstName: String {
        publicAuthorDisplayName
    }

    var profileTitle: String {
        if publicAuthorDisplayName == publicUsernameDisplayName {
            return "Explorer"
        }
        return publicAuthorDisplayName
    }
}
