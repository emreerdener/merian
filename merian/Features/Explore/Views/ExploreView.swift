import SwiftUI

struct ExploreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreFeedViewModel()
    @State private var selectedPostRoute: ExplorePostRoute?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingInitialFeed && viewModel.posts.isEmpty {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage, viewModel.posts.isEmpty {
                    errorState(message: errorMessage)
                } else if viewModel.posts.isEmpty {
                    emptyState
                } else {
                    feedScrollView
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
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
                        shouldFocusCommentComposer: selectedPostRoute.shouldFocusCommentComposer
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.showNotificationsPlaceholder() }) {
                        Image(systemName: "bell")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .accessibilityLabel("Notifications")
                }
            }
        }
        .task {
            await viewModel.loadInitialFeed()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isCommentsSheetPresented },
                set: { if !$0 { viewModel.dismissCommentsSheet() } }
            )
        ) {
            if let post = viewModel.activeCommentsPost {
                ExploreCommentsSheet(viewModel: viewModel, post: post)
            }
        }
        .merianSystemFeedback(
            toastMessage: Binding(
                get: { viewModel.toastMessage },
                set: { viewModel.toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(viewModel.posts) { post in
                    ExplorePostCard(
                        post: post,
                        onLike: { Task { await viewModel.toggleLike(for: post) } },
                        onComments: { Task { await viewModel.openCommentsSheet(for: post) } },
                        onShare: { viewModel.share(post) },
                        onOpenDetail: { openPostDetail(for: post) },
                        onUnshare: { Task { await viewModel.unshare(post) } },
                        onBlock: { Task { await viewModel.blockAuthor(of: post) } },
                        onReport: { Task { await viewModel.report(post) } }
                    )
                    .onAppear {
                        Task { await viewModel.loadMoreIfNeeded(currentPost: post) }
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.loadInitialFeed(force: true)
        }
    }

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(0..<3, id: \.self) { _ in
                    ExplorePostCard.Skeleton()
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            imageName: "explore-base",
            imageHeight: 300,
            title: "Nothing shared yet",
            message: "Shared discoveries will show up here once people publish scans to Explore."
        )
    }

    private func errorState(message: String) -> some View {
        EmptyStateView(
            iconName: "exclamationmark.triangle",
            title: "Couldn’t load posts",
            message: message
        ) {
            Button {
                Task { await viewModel.loadInitialFeed(force: true) }
            } label: {
                Text("Try again")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func openPostDetail(for post: ExplorePost, focusCommentComposer: Bool = false) {
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: focusCommentComposer
        )
    }
}

private struct ExplorePostRoute: Equatable {
    let postId: String
    let shouldFocusCommentComposer: Bool
}

private struct ExplorePostDetailView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let postId: String
    let shouldFocusCommentComposer: Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var detail: ExplorePostDetail?
    @State private var isLoadingDetail = false
    @State private var detailErrorMessage: String?

    private let commentsSectionId = "explore-comments-section"
    private let commentsComposerId = "explore-comments-composer"

    private var currentPost: ExplorePost? {
        viewModel.posts.first(where: { $0.id == postId })
    }

    var body: some View {
        Group {
            if let post = currentPost {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            headerRow(for: post)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 12)

                            heroImage(for: post)

                            actionRow(for: post, scrollProxy: scrollProxy)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 12)

                            speciesSection(for: post)
                                .padding(.horizontal, 16)

                            insightCardsSection(for: post)
                                .padding(.top, 20)
                                .padding(.horizontal, 16)

                            ExploreObservationContextCard(post: post)
                                .padding(.top, 20)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)

                            Divider()
                                .padding(.horizontal, 16)

                            commentsSection
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 24)
                                .id(commentsSectionId)
                        }
                    }
                    .background(Color(uiColor: .systemBackground))
                    .navigationTitle(post.speciesCommonName.capitalized)
                    .navigationBarTitleDisplayMode(.inline)
                    .task(id: post.id) {
                        async let detailTask: Void = loadPostDetail()
                        async let commentsTask: Void = viewModel.openComments(for: post)
                        _ = await (detailTask, commentsTask)

                        if shouldFocusCommentComposer {
                            focusComments(using: scrollProxy, animated: false)
                        }
                    }
                    .onChange(of: currentPost?.id) { _, newValue in
                        if newValue == nil {
                            dismiss()
                        }
                    }
                }
            } else {
                Color.clear
                    .task {
                        dismiss()
                    }
            }
        }
        .onChange(of: viewModel.commentDraft) { _, newValue in
            if newValue.count > 500 {
                viewModel.commentDraft = String(newValue.prefix(500))
            }
        }
    }

    private func headerRow(for post: ExplorePost) -> some View {
        HStack(alignment: .center, spacing: 12) {
            authorAvatarView(for: post)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let locationText = locationText(for: post) {
                    Text(locationText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            detailMenuButton(for: post)
        }
    }

    @ViewBuilder
    private func authorAvatarView(for post: ExplorePost) -> some View {
        if let avatarUrl = resolvedAuthorAvatarUrl(for: post) {
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
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            fallbackAuthorAvatar
        }
    }

    private var fallbackAuthorAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 40, weight: .regular))
            .foregroundStyle(.primary)
    }

    private func heroImage(for post: ExplorePost) -> some View {
        AsyncImage(url: URL(string: post.heroImageUrl)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                ZStack {
                    LinearGradient(
                        colors: [Color(uiColor: .tertiarySystemFill), Color(uiColor: .secondarySystemFill)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            case .empty:
                ZStack {
                    Color(uiColor: .tertiarySystemFill)
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            @unknown default:
                Color(uiColor: .tertiarySystemFill)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    private func actionRow(for post: ExplorePost, scrollProxy: ScrollViewProxy) -> some View {
        HStack(spacing: 20) {
            ExploreDetailActionButton(
                systemImage: post.viewerHasLiked ? "heart.fill" : "heart",
                value: compactCount(post.likeCount),
                isHighlighted: post.viewerHasLiked,
                action: {
                    Task { await viewModel.toggleLike(for: post) }
                }
            )

            ExploreDetailActionButton(
                systemImage: "bubble.right",
                value: compactCount(post.commentCount),
                isHighlighted: false,
                action: {
                    focusComments(using: scrollProxy)
                }
            )

            Spacer(minLength: 12)

            Button(action: { viewModel.share(post) }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share post")
        }
    }

    private func speciesSection(for post: ExplorePost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.speciesCommonName.capitalized)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text(post.speciesScientificName)
                .font(.subheadline)
                .italic()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func insightCardsSection(for post: ExplorePost) -> some View {
        let shouldShowSection = isLoadingDetail
            || detail != nil
            || detailErrorMessage != nil

        if shouldShowSection {
            VStack(alignment: .leading, spacing: 16) {
                if isLoadingDetail && detail == nil {
                    ExploreLoadingInsightCard()
                } else {
                    if let detail, detail.hasOverviewContent {
                        ExploreOverviewCard(
                            iucnRedListStatus: detail.iucnRedListStatus,
                            wikipediaOverview: detail.wikipediaOverview
                        )
                    }

                    if let taxonomyData = detail?.taxonomyData {
                        TaxonomyCard(
                            taxonomyData: taxonomyData,
                            scientificName: post.speciesScientificName
                        )
                    }

                    if let detail, detail.hasHabitatDistributionContent {
                        ExploreHabitatDistributionCard(
                            scientificName: post.speciesScientificName,
                            habitatDescription: detail.habitatDescription,
                            gbifTaxonKey: detail.gbifTaxonKey
                        )
                    }
                }

                if let detailErrorMessage, detail == nil {
                    Text(detailErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Comments")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if let currentPost {
                    Text(compactCount(currentPost.commentCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isCommentsLoading && viewModel.comments.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading comments...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else if viewModel.comments.isEmpty {
                EmptyStateView(
                    iconName: "bubble.left.and.bubble.right",
                    title: "No comments yet",
                    message: "Be the first to leave a note on this discovery."
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.comments) { comment in
                        commentRow(comment)
                    }
                }
            }

            composer
                .padding(.top, 8)
                .id(commentsComposerId)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let commentErrorMessage = viewModel.commentErrorMessage {
                Text(commentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .bottom, spacing: 12) {
                if SupabaseManager.shared.isAuthenticated, let avatarUrl = SupabaseManager.shared.currentUserAvatarUrl {
                    AsyncImage(url: avatarUrl) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color(uiColor: .tertiarySystemFill)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .padding(.bottom, 6)
                }

                TextField("Add a comment", text: $viewModel.commentDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                Button(action: {
                    Task { await viewModel.submitComment() }
                }) {
                    ZStack {
                        Circle()
                            .fill(canSubmitComment ? Color.primary : Color.secondary.opacity(0.25))
                            .frame(width: 42, height: 42)

                        if viewModel.isSubmittingComment {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color(uiColor: .systemBackground))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(uiColor: .systemBackground))
                        }
                    }
                }
                .disabled(!canSubmitComment || viewModel.isSubmittingComment)
                .buttonStyle(.plain)
            }

            Text("\(viewModel.commentDraft.count)/500")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var canSubmitComment: Bool {
        !viewModel.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commentRow(_ comment: ExploreComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(comment.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let createdAtText = createdAtText(for: comment) {
                        Text(createdAtText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if comment.viewerCanDelete {
                    Menu {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteComment(comment) }
                        } label: {
                            Label("Delete comment", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                }
            }

            Text(comment.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func detailMenuButton(for post: ExplorePost) -> some View {
        Menu {
            if post.isOwnedByViewer {
                Button(role: .destructive) {
                    Task { await viewModel.unshare(post) }
                } label: {
                    Label("Remove post", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    Task { await viewModel.blockAuthor(of: post) }
                } label: {
                    Label("Block user", systemImage: "person.crop.circle.badge.xmark")
                }

                Button(role: .destructive) {
                    Task { await viewModel.report(post) }
                } label: {
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

    private func focusComments(using scrollProxy: ScrollViewProxy, animated: Bool = true) {
        let scrollBlock = {
            scrollProxy.scrollTo(commentsComposerId, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.22), scrollBlock)
        } else {
            scrollBlock()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            isComposerFocused = true
        }
    }

    private func loadPostDetail() async {
        guard !isLoadingDetail else { return }

        isLoadingDetail = true
        detailErrorMessage = nil
        detail = nil

        defer { isLoadingDetail = false }

        do {
            detail = try await MerianNetworkClient.shared.getExplorePostDetail(postId: postId)
        } catch {
            detailErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func resolvedAuthorAvatarUrl(for post: ExplorePost) -> URL? {
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

    private func locationText(for post: ExplorePost) -> String? {
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

    private func createdAtText(for comment: ExploreComment) -> String? {
        guard let createdAtDate = comment.createdAtDate else { return nil }
        return createdAtDate.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ExploreDetailActionButton: View {
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

private struct ExploreLoadingInsightCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)

            Text("Loading species details...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct ExploreOverviewCard: View {
    let iucnRedListStatus: String?
    let wikipediaOverview: String?

    private var normalizedIucnStatus: (text: String, isGood: Bool?)? {
        guard let rawStatus = iucnRedListStatus?.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawStatus.isEmpty,
              rawStatus != "not applicable",
              rawStatus != "data deficient" else {
            return nil
        }

        let normalizedStatus = rawStatus.replacingOccurrences(of: "_", with: " ")

        switch normalizedStatus {
        case _ where normalizedStatus.contains("not evaluated"):
            return ("Not evaluated", nil)
        case _ where normalizedStatus.contains("least concern"):
            return ("Not at risk", true)
        case _ where normalizedStatus.contains("near threatened"):
            return ("Near threatened", false)
        case _ where normalizedStatus.contains("vulnerable"):
            return ("Vulnerable", false)
        case _ where normalizedStatus.contains("endangered") && !normalizedStatus.contains("critically"):
            return ("Endangered", false)
        case _ where normalizedStatus.contains("critically endangered"):
            return ("Critically endangered", false)
        case _ where normalizedStatus.contains("extinct in the wild"):
            return ("Extinct in the wild", false)
        case _ where normalizedStatus.contains("extinct"):
            return ("Extinct", false)
        default:
            return (capitalizeFirstLetter(normalizedStatus), true)
        }
    }

    private var trimmedWikipediaOverview: String? {
        guard let wikipediaOverview else { return nil }
        let trimmed = wikipediaOverview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 60 ? trimmed : nil
    }

    var body: some View {
        if normalizedIucnStatus != nil || trimmedWikipediaOverview != nil {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "book")
                        .foregroundColor(.secondary)
                    Text("Overview")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                if let status = normalizedIucnStatus {
                    let iconName: String? = {
                        switch status.isGood {
                        case true?: return "checkmark.circle.fill"
                        case false?: return "exclamationmark.shield.fill"
                        case nil: return nil
                        }
                    }()

                    let iconColor: Color? = {
                        switch status.isGood {
                        case true?: return .green
                        case false?: return .red
                        case nil: return nil
                        }
                    }()

                    let textColor: Color? = {
                        switch status.isGood {
                        case false?: return .red
                        default: return nil
                        }
                    }()

                    KeyValueRow(
                        title: "CONSERVATION",
                        value: status.text,
                        valueIcon: iconName,
                        valueIconColor: iconColor,
                        valueTextColor: textColor
                    )
                }

                if let trimmedWikipediaOverview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WIKIPEDIA")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        Text(trimmedWikipediaOverview)
                            .font(.system(.body))
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func capitalizeFirstLetter(_ string: String) -> String {
        guard let first = string.first else { return "" }
        return String(first).uppercased() + string.dropFirst()
    }
}

private struct ExploreObservationContextCard: View {
    let post: ExplorePost

    private var rows: [ExploreObservationContextRow] {
        var rows: [ExploreObservationContextRow] = []

        if let location = post.publicLocationLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            rows.append(
                ExploreObservationContextRow(
                    title: "LOCATION",
                    value: location,
                    valueIcon: nil
                )
            )
        }

        if let observationContext = post.observationContextLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "OBSERVED",
                    value: observationContext,
                    valueIcon: nil
                )
            )
        }

        if let weatherLabel = post.publicWeatherLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "WEATHER",
                    value: weatherLabel,
                    valueIcon: weatherIcon(for: post.weatherCondition)
                )
            )
        }

        if let sharedDateLabel = post.sharedDateLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "SHARED",
                    value: sharedDateLabel,
                    valueIcon: nil
                )
            )
        }

        return rows
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .foregroundColor(.secondary)
                    Text("Observation")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                VStack(spacing: 12) {
                    ForEach(rows) { row in
                        KeyValueRow(
                            title: row.title,
                            value: row.value,
                            valueIcon: row.valueIcon
                        )
                    }
                }
            }
            .card()
        }
    }

    private func weatherIcon(for condition: String?) -> String? {
        guard let condition else { return nil }

        let lower = condition.lowercased()
        if lower.contains("sun") || lower.contains("clear") { return "sun.max.fill" }
        if lower.contains("fog") || lower.contains("haze") { return "cloud.fog.fill" }
        if lower.contains("rain") || lower.contains("drizzle") || lower.contains("shower") { return "cloud.rain.fill" }
        if lower.contains("snow") || lower.contains("ice") { return "snowflake" }
        if lower.contains("thunder") || lower.contains("storm") { return "cloud.bolt.rain.fill" }
        if lower.contains("wind") || lower.contains("breeze") { return "wind" }
        if lower.contains("cloud") || lower.contains("overcast") { return "cloud.fill" }
        return "cloud.sun.fill"
    }
}

private struct ExploreObservationContextRow: Identifiable {
    let title: String
    let value: String
    let valueIcon: String?

    var id: String {
        "\(title)-\(value)-\(valueIcon ?? "none")"
    }
}

private struct ExploreHabitatDistributionCard: View {
    let scientificName: String
    let habitatDescription: String?
    let gbifTaxonKey: Int?

    private var trimmedHabitatDescription: String? {
        guard let habitatDescription else { return nil }
        let trimmed = habitatDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        if gbifTaxonKey != nil || trimmedHabitatDescription != nil {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text("Habitat & distribution")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                if let gbifTaxonKey {
                    GBIFHeatmapMapView(taxonKey: gbifTaxonKey)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }

                if let trimmedHabitatDescription {
                    Text(styledHabitat(text: trimmedHabitatDescription))
                        .font(.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    private func styledHabitat(text: String) -> AttributedString {
        var result = AttributedString(text)
        var searchRange = result.startIndex..<result.endIndex

        while let range = result[searchRange].range(of: scientificName, options: .caseInsensitive) {
            result[range].font = .system(.body, design: .monospaced)
            result[range].backgroundColor = Color.secondary.opacity(0.15)
            searchRange = range.upperBound..<result.endIndex
        }

        return result
    }
}

private extension ExplorePost {
    static let exploreTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var publicDayPartLabel: String? {
        guard let timeOfDay,
              let time = Self.exploreTimeFormatter.date(from: timeOfDay) else {
            return nil
        }

        let hour = Calendar.current.component(.hour, from: time)
        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<21:
            return "Evening"
        default:
            return "Night"
        }
    }

    var publicMonthLabel: String? {
        guard let currentMonth, (1...12).contains(currentMonth) else { return nil }
        return Calendar.current.monthSymbols[currentMonth - 1]
    }

    var observationContextLabel: String? {
        let rawValues: [String?] = [publicDayPartLabel, publicMonthLabel]
        let values = rawValues.reduce(into: [String]()) { partialResult, value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return
            }
            partialResult.append(value)
        }

        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }

    var publicWeatherLabel: String? {
        let normalizedCondition = weatherCondition?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized

        let normalizedTemperature = weatherTemperatureF.map { "\($0.formatted(.number.precision(.fractionLength(0))))°F" }

        let rawValues: [String?] = [normalizedCondition, normalizedTemperature]
        let values = rawValues.reduce(into: [String]()) { partialResult, value in
            guard let value, !value.isEmpty else { return }
            partialResult.append(value)
        }

        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }

    var sharedDateLabel: String? {
        guard let sharedAtDate else { return nil }
        return sharedAtDate.formatted(date: .abbreviated, time: .omitted)
    }
}
