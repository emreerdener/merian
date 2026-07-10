import SwiftUI

struct FieldTripsView: View {
    let userRegion: String?
    @Binding var selectedSection: FieldTripsSection
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    @State private var viewModel = FieldTripsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            switch selectedSection {
            case .fieldTrips:
                fieldTripsContent
            case .seasonal:
                seasonalTripsContent
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await viewModel.load(userRegion: userRegion)
        }
        .onChange(of: selectedSection) { _, _ in
            HapticManager.shared.triggerSelectionPulse()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .fieldTripProgressUpdated(let updates):
                viewModel.applyProgressToast(updates)
                Task { await viewModel.refresh(userRegion: userRegion) }
            case .fieldTripChallengeProgressUpdated(let updates):
                viewModel.applyChallengeProgressToast(updates)
                Task { await viewModel.refresh(userRegion: userRegion) }
            default:
                break
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

    private var fieldTripsContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading && viewModel.templates.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        FieldTripTemplateSkeletonCard()
                    }
                } else if let errorMessage = viewModel.errorMessage, viewModel.templates.isEmpty {
                    FieldTripUnavailableCard(message: errorMessage) {
                        Task { await viewModel.refresh(userRegion: userRegion) }
                    }
                } else if viewModel.templates.isEmpty {
                    FieldTripUnavailableCard(message: "Field Trips are not available right now.") {
                        Task { await viewModel.refresh(userRegion: userRegion) }
                    }
                } else {
                    ForEach(viewModel.templates) { template in
                        NavigationLink(value: FieldTripTemplateRoute(templateId: template.templateId)) {
                            FieldTripTemplateCard(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.refresh(userRegion: userRegion)
        }
    }

    private var seasonalTripsContent: some View {
        let visibleChallenges = viewModel.challenges
            .filter { $0.isLive || $0.isUpcoming }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.isLive
                }
                return lhs.startsAt < rhs.startsAt
            }

        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading && viewModel.challenges.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        FieldTripRecentSkeletonCard()
                    }
                } else if let challengeErrorMessage = viewModel.challengeErrorMessage, visibleChallenges.isEmpty {
                    FieldTripUnavailableCard(message: challengeErrorMessage) {
                        Task { await viewModel.refresh(userRegion: userRegion) }
                    }
                } else if visibleChallenges.isEmpty {
                    FieldTripUnavailableCard(message: "Seasonal Field Trips are not available right now.") {
                        Task { await viewModel.refresh(userRegion: userRegion) }
                    }
                } else {
                    ForEach(visibleChallenges) { challenge in
                        NavigationLink(value: FieldTripChallengeRoute(challengeId: challenge.challengeId)) {
                            FieldTripChallengeCard(challenge: challenge)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.refresh(userRegion: userRegion)
        }
    }
}

struct FieldTripTemplateDetailView: View {
    let templateId: String
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    @State private var template: FieldTripTemplate?
    @State private var communityPreview: [FieldTripRecentPublication] = []
    @State private var isLoading = false
    @State private var isStarting = false
    @State private var isLoadingCommunityPreview = false
    @State private var errorMessage: String?
    @State private var publishingTemplate: FieldTripTemplate?
    @State private var toastMessage: String?
    @State private var selectedDetailSection: FieldTripDetailSection = .objectives

    var body: some View {
        ScrollView(showsIndicators: false) {
            if isLoading && template == nil {
                FieldTripTemplateDetailSkeleton()
                    .padding(16)
            } else if let errorMessage, template == nil {
                FieldTripUnavailableCard(message: errorMessage) {
                    Task { await load(force: true) }
                }
                .padding(16)
            } else if let template {
                detailContent(template)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(template?.title ?? "Field Trip")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load(force: false)
        }
        .refreshable {
            await load(force: true)
        }
        .sheet(item: $publishingTemplate) { template in
            FieldTripPublishSheet(template: template) { publication in
                publishingTemplate = nil
                onOpenPublication(publication.publicationId)
                Task { await load(force: true) }
            }
        }
        .merianSystemFeedback(
            toastMessage: Binding(
                get: { toastMessage },
                set: { toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    @ViewBuilder
    private func detailContent(_ template: FieldTripTemplate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldTripCoverImage(urlString: template.coverImageUrl)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(template.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = template.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FieldTripMetadataRow(template: template)

            if let progress = template.activeProgress {
                FieldTripProgressBar(progress: progress)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            }

            actionButton(template)

            Picker("Field Trip details", selection: $selectedDetailSection) {
                ForEach(FieldTripDetailSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

            switch selectedDetailSection {
            case .objectives:
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(template.levels) { level in
                        FieldTripLevelSection(
                            level: level,
                            currentLevelNumber: template.activeProgress?.currentLevelNumber ?? 1
                        )
                    }
                }
            case .tips:
                VStack(alignment: .leading, spacing: 16) {
                    if let description = template.description {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FieldTripGuideSections(template: template)
                }
            }

            FieldTripCommunityPreviewSection(
                publications: communityPreview,
                isLoading: isLoadingCommunityPreview,
                onOpenPublication: onOpenPublication,
                onOpenAuthorProfile: onOpenAuthorProfile
            )
        }
    }

    @ViewBuilder
    private func actionButton(_ template: FieldTripTemplate) -> some View {
        if !template.viewerHasAccess {
            Button {
                AppEventPublisher.shared.send(.triggerPaywall)
            } label: {
                Label("Unlock with Pro", systemImage: "lock.fill")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule(style: .continuous).fill(Color.primary))
            }
            .buttonStyle(.plain)
        } else if template.activeProgress == nil {
            Button {
                Task { await start(template) }
            } label: {
                HStack(spacing: 8) {
                    if isStarting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(uiColor: .systemBackground))
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text("Start Field Trip")
                }
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule(style: .continuous).fill(Color.primary))
            }
            .buttonStyle(.plain)
            .disabled(isStarting)
        } else if let progress = template.activeProgress, progress.isComplete {
            Button {
                publishingTemplate = template
            } label: {
                Label("Publish Field Trip", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule(style: .continuous).fill(Color.primary))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                toastMessage = "Keep scanning matching species to make progress."
            } label: {
                Label("Continue Scanning", systemImage: "sparkle.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func load(force: Bool) async {
        guard force || template == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedTemplate = try await MerianNetworkClient.shared.getFieldTripTemplate(templateId: templateId)
            template = loadedTemplate
            await loadCommunityPreview(templateId: loadedTemplate.templateId)
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func start(_ template: FieldTripTemplate) async {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            self.template = try await MerianNetworkClient.shared.startFieldTrip(templateId: template.templateId)
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Field Trip started."
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func loadCommunityPreview(templateId: String) async {
        isLoadingCommunityPreview = true
        defer { isLoadingCommunityPreview = false }

        communityPreview = (try? await MerianNetworkClient.shared.getFieldTripCommunityPublications(
            mode: .smart,
            templateId: templateId,
            userRegion: nil,
            limit: 3
        )) ?? []
    }
}

struct FieldTripChallengeDetailView: View {
    let challengeId: String
    let onOpenEntry: (String) -> Void
    let onOpenAuthorProfile: (FieldTripChallengeEntry) -> Void

    @State private var viewModel: FieldTripChallengeDetailViewModel
    @State private var publishingChallenge: FieldTripChallenge?
    @State private var selectedDetailSection: FieldTripDetailSection = .objectives

    init(
        challengeId: String,
        onOpenEntry: @escaping (String) -> Void,
        onOpenAuthorProfile: @escaping (FieldTripChallengeEntry) -> Void
    ) {
        self.challengeId = challengeId
        self.onOpenEntry = onOpenEntry
        self.onOpenAuthorProfile = onOpenAuthorProfile
        _viewModel = State(initialValue: FieldTripChallengeDetailViewModel(challengeId: challengeId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if viewModel.isLoading && viewModel.challenge == nil {
                FieldTripTemplateDetailSkeleton()
                    .padding(16)
            } else if let errorMessage = viewModel.errorMessage, viewModel.challenge == nil {
                FieldTripUnavailableCard(message: errorMessage) {
                    Task { await viewModel.refresh() }
                }
                .padding(16)
            } else if let challenge = viewModel.challenge {
                detailContent(challenge)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(viewModel.challenge?.title ?? "Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            guard case .fieldTripChallengeProgressUpdated = event else { return }
            Task { await viewModel.refresh() }
        }
        .sheet(item: $publishingChallenge) { challenge in
            FieldTripChallengePublishSheet(challenge: challenge) { entry in
                publishingChallenge = nil
                onOpenEntry(entry.entryId)
                Task { await viewModel.refresh() }
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

    private func detailContent(_ challenge: FieldTripChallenge) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldTripCoverImage(urlString: challenge.coverImageUrl)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text(challenge.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    FieldTripChallengeStatusBadge(status: challenge.status)
                }

                if let subtitle = challenge.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FieldTripChallengeStatsRow(challenge: challenge)

            if let participation = challenge.viewerParticipation {
                FieldTripChallengeProgressBar(participation: participation)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            }

            actionButton(challenge)

            if let template = challenge.template {
                Picker("Challenge details", selection: $selectedDetailSection) {
                    ForEach(FieldTripDetailSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedDetailSection {
                case .objectives:
                    FieldTripChallengeLevelsSection(
                        template: template,
                        currentLevelNumber: challenge.viewerParticipation?.currentLevelNumber ?? 1
                    )
                case .tips:
                    VStack(alignment: .leading, spacing: 16) {
                        if let description = challenge.description {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        FieldTripGuideSections(template: template)
                    }
                }
            }

            FieldTripChallengeEntriesSection(
                entries: viewModel.entries,
                hasMoreEntries: viewModel.hasMoreEntries,
                isLoadingMore: viewModel.isLoadingMoreEntries,
                onOpenEntry: onOpenEntry,
                onOpenAuthorProfile: onOpenAuthorProfile,
                onLoadMore: {
                    Task { await viewModel.loadMoreEntries() }
                }
            )
        }
    }

    @ViewBuilder
    private func actionButton(_ challenge: FieldTripChallenge) -> some View {
        if !challenge.viewerHasAccess {
            Button {
                AppEventPublisher.shared.send(.triggerPaywall)
            } label: {
                Label("Unlock with Pro", systemImage: "lock.fill")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule(style: .continuous).fill(Color.primary))
            }
            .buttonStyle(.plain)
        } else if challenge.isUpcoming {
            Label("Starts \(FieldTripDisplayDate.shortDate(challenge.startsAt))", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
        } else if challenge.viewerParticipation == nil {
            Button {
                Task { await viewModel.join() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isJoining {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(uiColor: .systemBackground))
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text(challenge.isEnded ? "Challenge Ended" : "Join Challenge")
                }
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule(style: .continuous).fill(challenge.isEnded ? Color.secondary : Color.primary))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isJoining || challenge.isEnded)
        } else if let participation = challenge.viewerParticipation, participation.isComplete {
            Button {
                publishingChallenge = challenge
            } label: {
                Label("Publish Challenge Entry", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule(style: .continuous).fill(Color.primary))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                viewModel.toastMessage = "Keep scanning during the challenge window."
            } label: {
                Label("Continue Scanning", systemImage: "sparkle.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

private enum FieldTripDetailSection: String, CaseIterable, Identifiable {
    case objectives
    case tips

    var id: String { rawValue }

    var title: String {
        switch self {
        case .objectives:
            "Objectives"
        case .tips:
            "Tips"
        }
    }
}

enum FieldTripsSection: String, CaseIterable, Identifiable {
    case fieldTrips
    case seasonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fieldTrips:
            "Field Trips"
        case .seasonal:
            "Seasonal"
        }
    }
}

private struct FieldTripTemplateCard: View {
    let template: FieldTripTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldTripCoverImage(urlString: template.coverImageUrl)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let subtitle = template.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                FieldTripAccessBadge(template: template)
            }

            if let activeProgress = template.activeProgress {
                FieldTripProgressBar(progress: activeProgress)
            }

            FieldTripTagRow(tags: Array((template.regionTags + template.habitatTags).prefix(5)))

            HStack(spacing: 8) {
                Image(systemName: template.activeProgress == nil ? "play.circle" : "checklist")
                    .foregroundStyle(.secondary)
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusText: String {
        if let progress = template.activeProgress, progress.isComplete {
            return "Ready to publish"
        }
        if template.activeProgress != nil {
            return "In progress"
        }
        if template.viewerHasAccess {
            return "Open guide"
        }
        return "Pro trip"
    }
}

private struct FieldTripChallengeCard: View {
    let challenge: FieldTripChallenge

    var body: some View {
        HStack(spacing: 12) {
            FieldTripCoverImage(urlString: challenge.coverImageUrl)
                .frame(width: 94, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(challenge.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(challenge.templateTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    FieldTripChallengeStatusBadge(status: challenge.status)
                }

                if let subtitle = challenge.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                FieldTripTagRow(tags: Array((challenge.regionTags + challenge.seasonTags + challenge.habitatTags).prefix(4)))

                HStack(spacing: 10) {
                    Label(challenge.participantCount.formatted(), systemImage: "person.2")
                    Label(challenge.completionCount.formatted(), systemImage: "rosette")
                    Label(FieldTripDisplayDate.shortRange(start: challenge.startsAt, end: challenge.endsAt), systemImage: "calendar")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FieldTripChallengeStatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status == "live" ? Color(uiColor: .systemBackground) : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(status == "live" ? Color.primary : Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }

    private var label: String {
        switch status {
        case "live":
            "Live"
        case "upcoming":
            "Upcoming"
        case "ended":
            "Ended"
        default:
            status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct FieldTripChallengeStatsRow: View {
    let challenge: FieldTripChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FieldTripMetadataPill(
                    title: FieldTripDisplayDate.shortRange(start: challenge.startsAt, end: challenge.endsAt),
                    systemImage: "calendar"
                )
                FieldTripMetadataPill(
                    title: "\(challenge.participantCount.formatted()) joined",
                    systemImage: "person.2"
                )
            }

            HStack(spacing: 8) {
                FieldTripMetadataPill(
                    title: "\(challenge.completionCount.formatted()) completed",
                    systemImage: "rosette"
                )
                FieldTripMetadataPill(
                    title: "\(challenge.publishedEntryCount.formatted()) entries",
                    systemImage: "sparkles"
                )
            }
        }
    }
}

private struct FieldTripChallengeLevelsSection: View {
    let template: FieldTripTemplate
    let currentLevelNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(template.levels) { level in
                FieldTripChallengeLevelSection(
                    level: level,
                    currentLevelNumber: currentLevelNumber
                )
            }
        }
    }
}

private struct FieldTripChallengeLevelSection: View {
    let level: FieldTripLevel
    let currentLevelNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    if let description = level.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if level.levelNumber > currentLevelNumber {
                    Image(systemName: "lock")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(level.items) { item in
                    FieldTripChallengeChecklistRow(
                        item: item,
                        isCurrentLevel: level.levelNumber == currentLevelNumber,
                        isLocked: level.levelNumber > currentLevelNumber
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(level.levelNumber == currentLevelNumber ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FieldTripChallengeChecklistRow: View {
    let item: FieldTripChecklistItem
    let isCurrentLevel: Bool
    let isLocked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isLocked ? "lock.circle" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isCurrentLevel ? Color.accentColor : Color.secondary.opacity(0.7))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.prompt)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let guideTip = item.guideTip {
                    Text(guideTip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct FieldTripChallengeEntriesSection: View {
    let entries: [FieldTripChallengeEntry]
    let hasMoreEntries: Bool
    let isLoadingMore: Bool
    let onOpenEntry: (String) -> Void
    let onOpenAuthorProfile: (FieldTripChallengeEntry) -> Void
    let onLoadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Challenge Entries")
                .font(.headline.weight(.bold))

            if entries.isEmpty {
                Text("No published entries yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            } else {
                ForEach(entries) { entry in
                    FieldTripChallengeEntryCard(
                        entry: entry,
                        onOpenEntry: onOpenEntry,
                        onOpenAuthorProfile: onOpenAuthorProfile
                    )
                }

                if hasMoreEntries {
                    Button(action: onLoadMore) {
                        HStack(spacing: 8) {
                            if isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text("Load more")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingMore)
                }
            }
        }
    }
}

private struct FieldTripChallengeEntryCard: View {
    let entry: FieldTripChallengeEntry
    let onOpenEntry: (String) -> Void
    let onOpenAuthorProfile: (FieldTripChallengeEntry) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onOpenEntry(entry.entryId)
            } label: {
                FieldTripCoverImage(urlString: entry.coverImageUrl)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Label("Field Trip", systemImage: "map")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                Button {
                    onOpenEntry(entry.entryId)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(entry.challengeTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    onOpenAuthorProfile(entry)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                        Text(entry.publicAuthorDisplayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                FieldTripTagRow(tags: Array((entry.regionTags + entry.habitatTags).prefix(3)))

                HStack(spacing: 10) {
                    Label("\(entry.itemCount)", systemImage: "leaf")
                    Label(entry.likeCount.formatted(), systemImage: "heart")
                    Label(entry.commentCount.formatted(), systemImage: "bubble.left")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                onOpenEntry(entry.entryId)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct FieldTripCommunityPublicationCard: View {
    let publication: FieldTripRecentPublication
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onOpenPublication(publication.publicationId)
            } label: {
                FieldTripCoverImage(urlString: publication.coverImageUrl)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Button {
                    onOpenPublication(publication.publicationId)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(publication.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(publication.templateTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    onOpenAuthorProfile(publication)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                        Text(publication.publicAuthorDisplayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                FieldTripTagRow(tags: Array((publication.regionTags + publication.habitatTags).prefix(3)))

                HStack(spacing: 10) {
                    Label("\(publication.itemCount)", systemImage: "leaf")
                    Label(publication.likeCount.formatted(), systemImage: "heart")
                    Label(publication.commentCount.formatted(), systemImage: "bubble.left")
                    if let reason = publication.communityReasonLabel {
                        Label(reason, systemImage: reason == "Following" ? "person.fill.checkmark" : "sparkle")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                onOpenPublication(publication.publicationId)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FieldTripCommunityPreviewSection: View {
    let publications: [FieldTripRecentPublication]
    let isLoading: Bool
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    var body: some View {
        if isLoading || !publications.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Community")
                    .font(.headline.weight(.bold))

                if isLoading && publications.isEmpty {
                    ForEach(0..<2, id: \.self) { _ in
                        FieldTripRecentSkeletonCard()
                    }
                } else {
                    ForEach(publications) { publication in
                        FieldTripCommunityPublicationCard(
                            publication: publication,
                            onOpenPublication: onOpenPublication,
                            onOpenAuthorProfile: onOpenAuthorProfile
                        )
                    }
                }
            }
        }
    }
}

private struct FieldTripGuideSections: View {
    let template: FieldTripTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let whereToLook = template.guideWhereToLook {
                FieldTripGuideRow(title: "Where to look", systemImage: "binoculars", bodyText: whereToLook)
            }

            if let whyItMatters = template.guideWhyItMatters {
                FieldTripGuideRow(title: "Why it matters", systemImage: "leaf", bodyText: whyItMatters)
            }

            if let safety = template.guideSafetyEthics {
                FieldTripGuideRow(title: "Safety", systemImage: "hand.raised", bodyText: safety)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FieldTripGuideRow: View {
    let title: String
    let systemImage: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(bodyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FieldTripLevelSection: View {
    let level: FieldTripLevel
    let currentLevelNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    if let description = level.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if level.levelNumber > currentLevelNumber {
                    Image(systemName: "lock")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(level.items) { item in
                    FieldTripChecklistRow(item: item, showsGuide: true)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(level.levelNumber == currentLevelNumber ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FieldTripMetadataRow: View {
    let template: FieldTripTemplate

    var body: some View {
        HStack(spacing: 8) {
            if let estimatedDurationMinutes = template.estimatedDurationMinutes {
                FieldTripMetadataPill(
                    title: durationLabel(minutes: estimatedDurationMinutes),
                    systemImage: "clock"
                )
            }

            FieldTripMetadataPill(
                title: template.difficulty.capitalized,
                systemImage: "speedometer"
            )

            FieldTripMetadataPill(
                title: "\(template.levels.reduce(0) { $0 + $1.items.count }) items",
                systemImage: "checklist"
            )
        }
    }

    private func durationLabel(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(remainder) min"
    }
}

private struct FieldTripMetadataPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

private struct FieldTripAccessBadge: View {
    let template: FieldTripTemplate

    var body: some View {
        if template.viewerHasAccess {
            Text(template.difficulty.capitalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                Text("Pro")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary))
        }
    }
}

private struct FieldTripTagRow: View {
    let tags: [String]

    private var displayTags: [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    var body: some View {
        if !displayTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(displayTags, id: \.self) { tag in
                        Text(tag.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

private struct FieldTripCoverImage: View {
    let urlString: String?

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder.redacted(reason: .placeholder)
                @unknown default:
                    placeholder
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            Image(systemName: "map")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FieldTripProgressBar: View {
    let progress: FieldTripProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Level \(progress.currentLevelNumber)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(progress.completedCount)/\(max(progress.targetCount, 0))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(6, proxy.size.width * progress.fractionComplete))
                }
            }
            .frame(height: 7)
        }
    }
}

private struct FieldTripChallengeProgressBar: View {
    let participation: FieldTripChallengeParticipation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Level \(participation.currentLevelNumber)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                if participation.isComplete {
                    Label("Badge earned", systemImage: "rosette")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(participation.completedCount)/\(max(participation.targetCount, 0))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(6, proxy.size.width * participation.fractionComplete))
                }
            }
            .frame(height: 7)
        }
    }
}

private struct FieldTripChecklistRow: View {
    let item: FieldTripChecklistItem
    var showsGuide = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary.opacity(0.7))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.prompt)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let completedName = item.completedCommonName {
                    Text(completedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if showsGuide, let guideTip = item.guideTip {
                    Text(guideTip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct FieldTripPublishSheet: View {
    let template: FieldTripTemplate
    let onPublished: (FieldTripPublicationDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?

    init(template: FieldTripTemplate, onPublished: @escaping (FieldTripPublicationDetail) -> Void) {
        self.template = template
        self.onPublished = onPublished
        _title = State(initialValue: template.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Publish Field Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text("Publish")
                        }
                    }
                    .disabled(isPublishing || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func publish() async {
        guard let progress = template.activeProgress else { return }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        do {
            let publication = try await MerianNetworkClient.shared.publishFieldTrip(
                userFieldTripId: progress.userFieldTripId,
                title: title,
                description: description
            )
            HapticManager.shared.triggerSuccessPulse()
            onPublished(publication)
        } catch {
            HapticManager.shared.triggerErrorThump()
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

private struct FieldTripChallengePublishSheet: View {
    let challenge: FieldTripChallenge
    let onPublished: (FieldTripChallengeEntryDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?

    init(challenge: FieldTripChallenge, onPublished: @escaping (FieldTripChallengeEntryDetail) -> Void) {
        self.challenge = challenge
        self.onPublished = onPublished
        _title = State(initialValue: challenge.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Publish Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text("Publish")
                        }
                    }
                    .disabled(isPublishing || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func publish() async {
        guard let participation = challenge.viewerParticipation else { return }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        do {
            let entry = try await MerianNetworkClient.shared.publishFieldTripChallengeEntry(
                participationId: participation.participationId,
                title: title,
                description: description
            )
            HapticManager.shared.triggerSuccessPulse()
            onPublished(entry)
        } catch {
            HapticManager.shared.triggerErrorThump()
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

private struct FieldTripUnavailableCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FieldTripTemplateSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(16 / 9, contentMode: .fit)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 180, height: 18)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 14)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 220, height: 14)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .redacted(reason: .placeholder)
    }
}

private struct FieldTripRecentSkeletonCard: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 180, height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 160, height: 12)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .redacted(reason: .placeholder)
    }
}

private struct FieldTripTemplateDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(16 / 9, contentMode: .fit)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 220, height: 24)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 16)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 140)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 220)
        }
        .redacted(reason: .placeholder)
    }
}

private enum FieldTripDisplayDate {
    static func shortDate(_ rawValue: String) -> String {
        guard let date = date(from: rawValue) else { return rawValue }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func shortRange(start: String, end: String) -> String {
        guard let startDate = date(from: start),
              let endDate = date(from: end) else {
            return "\(start) - \(end)"
        }

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.year, .month], from: startDate)
        let endComponents = calendar.dateComponents([.year, .month], from: endDate)
        let formatter = DateFormatter()
        formatter.timeStyle = .none

        if startComponents.year == endComponents.year,
           startComponents.month == endComponents.month {
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: startDate))-\(calendar.component(.day, from: endDate))"
        }

        formatter.dateFormat = "MMM d"
        let startLabel = formatter.string(from: startDate)
        let endLabel = formatter.string(from: endDate)
        return "\(startLabel)-\(endLabel)"
    }

    private static func date(from rawValue: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: rawValue) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
