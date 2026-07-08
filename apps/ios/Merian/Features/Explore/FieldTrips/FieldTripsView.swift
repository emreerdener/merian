import SwiftUI

struct FieldTripsView: View {
    let userRegion: String?
    let onOpenPublication: (String) -> Void

    @State private var viewModel = FieldTripsViewModel()
    @State private var publishingTemplate: FieldTripTemplate?

    var body: some View {
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
                        FieldTripTemplateCard(
                            template: template,
                            onPublish: { publishingTemplate = template },
                            onOpenPublication: onOpenPublication
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await viewModel.load(userRegion: userRegion)
        }
        .refreshable {
            await viewModel.refresh(userRegion: userRegion)
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            guard case .fieldTripProgressUpdated(let updates) = event else { return }
            viewModel.applyProgressToast(updates)
            Task { await viewModel.refresh(userRegion: userRegion) }
        }
        .sheet(item: $publishingTemplate) { template in
            FieldTripPublishSheet(template: template) { publication in
                publishingTemplate = nil
                onOpenPublication(publication.publicationId)
                Task { await viewModel.refresh(userRegion: userRegion) }
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
}

private struct FieldTripTemplateCard: View {
    let template: FieldTripTemplate
    let onPublish: () -> Void
    let onOpenPublication: (String) -> Void

    private var activeLevel: FieldTripLevel? {
        let levelNumber = template.activeProgress?.currentLevelNumber ?? 1
        return template.levels.first(where: { $0.levelNumber == levelNumber }) ?? template.levels.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

                accessBadge
            }

            if let activeProgress = template.activeProgress {
                FieldTripProgressBar(progress: activeProgress)
            }

            if let activeLevel {
                VStack(spacing: 8) {
                    ForEach(activeLevel.items.prefix(8)) { item in
                        FieldTripChecklistRow(item: item)
                    }
                }
            }

            footer
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var accessBadge: some View {
        if template.viewerHasAccess {
            Text(template.difficulty.capitalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
        } else {
            Button {
                AppEventPublisher.shared.send(.triggerPaywall)
            } label: {
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
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let progress = template.activeProgress, progress.isComplete {
            Button(action: onPublish) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Publish")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary)
                )
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(template.habitatTags.prefix(3).joined(separator: " / ").capitalized)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary.opacity(0.7))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.prompt)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let completedName = item.completedCommonName {
                    Text(completedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 180, height: 18)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 14)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 220, height: 14)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 80)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .redacted(reason: .placeholder)
    }
}
