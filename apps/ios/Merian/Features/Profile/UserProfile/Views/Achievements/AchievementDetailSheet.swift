import SwiftData
import SwiftUI
import UIKit

struct AchievementDetailSheet: View {
    let award: AwardPayload
    let modelContainer: ModelContainer

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine

    @State private var navigationPath = NavigationPath()
    @State private var detailState: AchievementDetailViewModel
    @State private var activePresentation: AchievementDetailPresentation?
    @State private var fieldTripsExploreViewModel = ExploreFeedViewModel()

    init(
        award: AwardPayload,
        modelContainer: ModelContainer,
        dependencies: AchievementDetailDependencies? = nil
    ) {
        self.award = award
        self.modelContainer = modelContainer
        _detailState = State(
            initialValue: AchievementDetailViewModel(
                dependencies: dependencies ?? .live
            )
        )
    }

    private var resolvedAward: AwardPayload {
        detailState.resolvedAward(fallback: award)
    }

    private var contributions: [AchievementContribution] {
        detailState.contributions
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AchievementDetailHeader(award: resolvedAward)

                    if detailState.isLoading {
                        loadingState
                    } else if contributions.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(resolvedAward.qualifyingScansTitle)
                                .font(.headline)
                                .foregroundColor(.primary)

                            LazyVStack(spacing: 12) {
                                ForEach(contributions) { contribution in
                                    AchievementContributionRow(contribution: contribution) {
                                        openInsight(for: contribution)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(resolvedAward.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .accessibilityIdentifier("AchievementDetailSheet_Close")
                }
            }
            .navigationDestination(for: AchievementFieldTripsRoute.self) { _ in
                AchievementFieldTripsPage(
                    navigationPath: $navigationPath,
                    onOpenCompletedScan: openFieldTripCompletedScan,
                    onOpenAuthorProfile: openFieldTripAuthorProfile
                )
            }
            .navigationDestination(for: FieldTripTemplateRoute.self) { route in
                FieldTripTemplateDetailView(
                    reference: route.reference,
                    focusedChecklistItemId: route.focusedChecklistItemId,
                    onOpenCompletedScan: openFieldTripCompletedScan,
                    onOpenPublication: { publicationId in
                        navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                    },
                    onOpenAuthorProfile: openFieldTripAuthorProfile
                )
            }
            .navigationDestination(for: FieldTripChallengeRoute.self) { route in
                FieldTripChallengeDetailView(
                    challengeId: route.challengeId,
                    onOpenEntry: { entryId in
                        navigationPath.append(FieldTripChallengeEntryRoute(entryId: entryId))
                    },
                    onOpenAuthorProfile: openFieldTripChallengeAuthorProfile
                )
            }
            .navigationDestination(for: FieldTripPublicationRoute.self) { route in
                FieldTripPublicationDetailView(publicationId: route.publicationId)
            }
            .navigationDestination(for: FieldTripChallengeEntryRoute.self) { route in
                FieldTripChallengeEntryDetailView(entryId: route.entryId)
            }
        }
        .accessibilityIdentifier("AchievementDetailSheet_\(award.type.rawValue)")
        .sheet(item: $activePresentation) { presentation in
            achievementSheetContent(presentation)
        }
        .task(id: award.id) {
            await loadDetail()
        }
        .onChange(of: activePresentation) { oldValue, newValue in
            if oldValue?.isInsight == true && newValue == nil {
                Task {
                    await loadDetail(backgroundReload: true)
                }
            }
        }
    }

    @ViewBuilder
    private func achievementSheetContent(
        _ presentation: AchievementDetailPresentation
    ) -> some View {
        switch presentation {
        case .insight(let route):
            LocalScanInsightLoader(scanId: route.scanId) {
                InsightSheetView(
                    isPresented: presentationBinding(for: presentation),
                    initialScanId: route.scanId,
                    inferenceEngine: inferenceEngine
                )
            }

        case .fieldTripAuthor(let route):
            ExploreAuthorProfileSheet(
                viewModel: fieldTripsExploreViewModel,
                route: route
            )
        }
    }

    private func presentationBinding(
        for presentation: AchievementDetailPresentation
    ) -> Binding<Bool> {
        Binding(
            get: { activePresentation?.id == presentation.id },
            set: { isPresented in
                guard !isPresented,
                      activePresentation?.id == presentation.id else { return }
                activePresentation = nil
            }
        )
    }

    @discardableResult
    private func beginPresentation(
        _ presentation: AchievementDetailPresentation
    ) -> Bool {
        guard activePresentation == nil else { return false }
        activePresentation = presentation
        return true
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(
                award.type == .firstFieldTrip
                    ? "Loading achievement progress..."
                    : "Loading qualifying scans..."
            )
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                award.type == .firstFieldTrip
                    ? "Complete a Field trip to unlock this achievement."
                    : "No qualifying scans count toward this achievement yet."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)

            if AchievementDetailNavigationPolicy.showsFieldTripsLink(
                for: resolvedAward,
                fieldTripsEnabled: FeatureFlags.isEnabled(.fieldTrips)
            ) {
                Button {
                    detailState.selectionFeedback()
                    navigationPath.append(AchievementFieldTripsRoute())
                } label: {
                    HStack(spacing: 8) {
                        Label("View Field trips", systemImage: "map")

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("AchievementDetailSheet_ViewFieldTrips")
                .accessibilityHint("Opens Field trips in this achievement sheet.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @MainActor
    private func loadDetail(backgroundReload: Bool = false) async {
        guard let announcedAward = await detailState.load(
            award: award,
            modelContainer: modelContainer,
            backgroundReload: backgroundReload
        ) else { return }

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: announcedAward.accessibilityProgressSummary
            )
        }
    }

    @MainActor
    private func openInsight(for contribution: AchievementContribution) {
        guard let route = detailState.insightRoute(
            scanID: contribution.scanID,
            modelContext: modelContext,
            tracksContributionFor: resolvedAward
        ) else { return }
        beginPresentation(.insight(route))
    }

    @MainActor
    private func openFieldTripCompletedScan(_ scanID: String) {
        guard let route = detailState.insightRoute(
            scanID: scanID,
            modelContext: modelContext
        ) else {
            detailState.errorFeedback()
            return
        }

        guard beginPresentation(.insight(route)) else {
            return
        }
        detailState.selectionFeedback()
    }

    @MainActor
    private func openFieldTripAuthorProfile(_ publication: FieldTripRecentPublication) {
        let presentation = AchievementDetailPresentation.fieldTripAuthor(
            ExploreAuthorProfileRoute(
                authorUserId: publication.authorUserId,
                authorName: publication.authorName,
                authorUsername: publication.authorUsername,
                authorAvatarUrl: publication.authorAvatarUrl
            )
        )
        guard beginPresentation(presentation) else { return }
        detailState.selectionFeedback()
    }

    @MainActor
    private func openFieldTripChallengeAuthorProfile(_ entry: FieldTripChallengeEntry) {
        let presentation = AchievementDetailPresentation.fieldTripAuthor(
            ExploreAuthorProfileRoute(
                authorUserId: entry.authorUserId,
                authorName: entry.authorName,
                authorUsername: entry.authorUsername,
                authorAvatarUrl: entry.authorAvatarUrl
            )
        )
        guard beginPresentation(presentation) else { return }
        detailState.selectionFeedback()
    }
}

private struct AchievementFieldTripsPage: View {
    @Binding var navigationPath: NavigationPath

    let onOpenCompletedScan: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    @State private var selectedSection: FieldTripsSection = .fieldTrips

    private var userRegion: String? {
        EnvironmentContextManager.normalizedRegionIdentifier(Locale.current.region?.identifier)
    }

    var body: some View {
        FieldTripsView(
            userRegion: userRegion,
            selectedSection: $selectedSection,
            onOpenTemplate: { templateId in
                navigationPath.append(FieldTripTemplateRoute(templateId: templateId))
            },
            onOpenCompletedScan: onOpenCompletedScan,
            onOpenPublication: { publicationId in
                navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
            },
            onOpenAuthorProfile: onOpenAuthorProfile
        )
        .navigationTitle("Field trips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Field trips view", selection: $selectedSection) {
                    ForEach(FieldTripsSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
    }
}
