import SwiftUI

struct FieldTripsView: View {
    let userRegion: String?
    let onOpenPublication: (String) -> Void

    @State private var viewModel = FieldTripsViewModel()
    @State private var selectedSection: FieldTripsSection = .available

    var body: some View {
        VStack(spacing: 0) {
            Picker("Field Trips", selection: $selectedSection) {
                ForEach(FieldTripsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            switch selectedSection {
            case .available:
                availableTripsContent
            case .recent:
                recentTripsContent
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await viewModel.load(userRegion: userRegion)
        }
        .task(id: selectedSection) {
            guard selectedSection == .recent else { return }
            await viewModel.loadRecent(userRegion: userRegion)
        }
        .onChange(of: selectedSection) { _, _ in
            HapticManager.shared.triggerSelectionPulse()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            guard case .fieldTripProgressUpdated(let updates) = event else { return }
            viewModel.applyProgressToast(updates)
            Task { await viewModel.refresh(userRegion: userRegion) }
        }
        .merianSystemFeedback(
            toastMessage: Binding(
                get: { viewModel.toastMessage },
                set: { viewModel.toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    private var availableTripsContent: some View {
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

    private var recentTripsContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                if viewModel.isLoadingRecent && viewModel.recentPublications.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        FieldTripRecentSkeletonCard()
                    }
                } else if let errorMessage = viewModel.recentErrorMessage, viewModel.recentPublications.isEmpty {
                    FieldTripUnavailableCard(message: errorMessage) {
                        Task { await viewModel.refreshRecent(userRegion: userRegion) }
                    }
                } else if viewModel.recentPublications.isEmpty {
                    FieldTripUnavailableCard(message: "No recent Field Trips are visible right now.") {
                        Task { await viewModel.refreshRecent(userRegion: userRegion) }
                    }
                } else {
                    ForEach(viewModel.recentPublications) { publication in
                        Button {
                            onOpenPublication(publication.publicationId)
                        } label: {
                            FieldTripRecentPublicationCard(publication: publication)
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.hasMoreRecentPublications {
                        Button {
                            Task { await viewModel.loadMoreRecent(userRegion: userRegion) }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isLoadingMoreRecent {
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
                        .disabled(viewModel.isLoadingMoreRecent)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.refreshRecent(userRegion: userRegion)
        }
    }
}

struct FieldTripTemplateDetailView: View {
    let templateId: String
    let onOpenPublication: (String) -> Void

    @State private var template: FieldTripTemplate?
    @State private var isLoading = false
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var publishingTemplate: FieldTripTemplate?
    @State private var toastMessage: String?

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

            if let description = template.description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FieldTripGuideSections(template: template)

            VStack(alignment: .leading, spacing: 12) {
                Text("Levels")
                    .font(.headline.weight(.bold))

                ForEach(template.levels) { level in
                    FieldTripLevelSection(
                        level: level,
                        currentLevelNumber: template.activeProgress?.currentLevelNumber ?? 1
                    )
                }
            }
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
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary))
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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary))
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
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary))
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
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            template = try await MerianNetworkClient.shared.getFieldTripTemplate(templateId: templateId)
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
}

private enum FieldTripsSection: String, CaseIterable, Identifiable {
    case available
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available:
            "Available"
        case .recent:
            "Recent Trips"
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

private struct FieldTripRecentPublicationCard: View {
    let publication: FieldTripRecentPublication

    var body: some View {
        HStack(spacing: 12) {
            FieldTripCoverImage(urlString: publication.coverImageUrl)
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(publication.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(publication.publicAuthorDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                FieldTripTagRow(tags: Array((publication.regionTags + publication.habitatTags).prefix(3)))

                HStack(spacing: 10) {
                    Label("\(publication.itemCount)", systemImage: "leaf")
                    Label(publication.likeCount.formatted(), systemImage: "heart")
                    Label(publication.commentCount.formatted(), systemImage: "bubble.left")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

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
        }
        .padding(12)
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

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
