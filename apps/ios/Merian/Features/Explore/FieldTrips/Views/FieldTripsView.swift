import SwiftData
import SwiftUI

struct FieldTripsView: View {
    let userRegion: String?
    @Binding var selectedSection: FieldTripsSection
    let onOpenTemplate: (String) -> Void
    let onOpenCompletedScan: (String) -> Void
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    @Query private var localScans: [LocalScanRecord]
    @State private var viewModel = FieldTripsViewModel()
    @State private var filters = FieldTripCatalogFilters()
    @State private var isShowingFilterSheet = false

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
        .sheet(isPresented: $isShowingFilterSheet) {
            outingFilterSheet
        }
        .task {
            await viewModel.load(userRegion: userRegion)
        }
        .onChange(of: selectedSection) { _, _ in
            HapticManager.shared.triggerSelectionPulse()
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            switch event {
            case .fieldTripProgressInvalidated:
                Task {
                    await viewModel.refresh(userRegion: userRegion)
                }
            case .captureGoalContextInvalidated(let source) where source == .fieldTrip:
                Task {
                    await viewModel.refresh(userRegion: userRegion)
                }
            case .fieldTripChallengeProgressInvalidated:
                Task {
                    await viewModel.refresh(userRegion: userRegion)
                }
            default:
                break
            }
        }
        .merianSystemFeedback(
            toast: Binding(
                get: { viewModel.toastMessage },
                set: { viewModel.toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    private var fieldTripsContent: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    filterBar

                    LazyVStack(spacing: 16) {
                        if viewModel.isLoading && viewModel.templates.isEmpty {
                            ForEach(0..<4, id: \.self) { _ in
                                FieldTripTemplateSkeletonCard()
                            }
                        } else if let errorMessage = viewModel.errorMessage, viewModel.templates.isEmpty {
                            FieldTripUnavailableCard(
                                title: "Field trips unavailable",
                                message: errorMessage
                            ) {
                                Task { await viewModel.refresh(userRegion: userRegion) }
                            }
                        } else if viewModel.templates.isEmpty {
                            fieldTripEmptyState(
                                title: "No outings yet",
                                message: "New field trips will appear here as soon as they’re ready."
                            )
                            .frame(
                                minHeight: max(440, geometry.size.height - 96)
                            )
                        } else if filteredTemplates.isEmpty {
                            filteredEmptyState
                                .frame(
                                    minHeight: max(440, geometry.size.height - 96)
                                )
                        } else {
                            ForEach(filteredTemplates) { template in
                                FieldTripTemplateCard(
                                    template: template,
                                    localScansById: localScansById,
                                    onOpenTemplate: {
                                        HapticManager.shared.triggerLightImpact(
                                            intensity: 0.45,
                                            source: "fieldTrips.catalog.template.open"
                                        )
                                        onOpenTemplate(template.templateId)
                                    },
                                    onOpenCompletedScan: onOpenCompletedScan
                                )
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .refreshable {
                await viewModel.refresh(userRegion: userRegion)
            }
        }
    }

    private var filteredTemplates: [FieldTripTemplate] {
        viewModel.templates.filtering(by: filters)
    }

    private var localScansById: [String: LocalScanRecord] {
        localScans.reduce(into: [:]) { scans, scan in
            scans[scan.id] = scan
        }
    }

    private var filterBar: some View {
        CategoryFilterBar(
            items: FieldTripDifficultyFilter.allCases,
            activeItem: filters.difficulty,
            title: { $0.title },
            leadingTitle: filters.hasActiveFilters
                ? "Filters \(filters.activeFilterCount.formatted())"
                : "Filters",
            leadingSystemImage: "line.3.horizontal.decrease",
            isLeadingSelected: filters.hasActiveFilters,
            onSelection: { filter in
                selectDifficulty(filter)
            },
            onLeadingSelection: {
                HapticManager.shared.triggerSelectionPulse()
                isShowingFilterSheet = true
            }
        )
        .accessibilityLabel("Field trip filters")
    }

    private var filteredEmptyState: some View {
        EmptyStateView(
            imageName: "fieldtrip-backpack",
            imageHeight: 300,
            title: "No outings match these filters",
            message: "Try changing or resetting your filters."
        ) {
            Button {
                resetFilters()
            } label: {
                Text("Reset filters")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    private var outingFilterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    filterSectionTitle("Difficulty")

                    ForEach(FieldTripDifficultyFilter.allCases, id: \.self) { filter in
                        Button {
                            selectDifficulty(filter)
                        } label: {
                            FilterSheetSelectionRow(
                                title: filter.title,
                                subtitle: difficultyFilterSubtitle(filter),
                                systemImage: difficultyFilterSymbol(filter),
                                isSelected: filters.difficulty == filter
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filters.difficulty == filter ? .isSelected : [])
                    }

                    filterSectionTitle("Status")
                        .padding(.top, 8)

                    ForEach(FieldTripStateFilter.allCases, id: \.self) { filter in
                        Button {
                            selectState(filter)
                        } label: {
                            FilterSheetSelectionRow(
                                title: filter.title,
                                subtitle: stateFilterSubtitle(filter),
                                systemImage: stateFilterSymbol(filter),
                                isSelected: filters.state == filter
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filters.state == filter ? .isSelected : [])
                    }
                }
                .padding()
            }
            .navigationTitle("Outing filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        resetFilters()
                    }
                    .disabled(!filters.hasActiveFilters)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.triggerSelectionPulse()
                        isShowingFilterSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private func filterSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func selectDifficulty(_ filter: FieldTripDifficultyFilter) {
        guard filter != filters.difficulty else { return }
        filters.difficulty = filter
        HapticManager.shared.triggerSelectionPulse()
    }

    private func selectState(_ filter: FieldTripStateFilter) {
        guard filter != filters.state else { return }
        filters.state = filter
        HapticManager.shared.triggerSelectionPulse()
    }

    private func resetFilters() {
        guard filters.hasActiveFilters else { return }
        filters.reset()
        HapticManager.shared.triggerSelectionPulse()
    }

    private func difficultyFilterSubtitle(_ filter: FieldTripDifficultyFilter) -> String {
        switch filter {
        case .all:
            "Show every difficulty"
        case .starter:
            "Onboarding-friendly outings with familiar goals"
        case .easy:
            "Focused outings suited to one ordinary field trip"
        case .moderate:
            "Outings requiring more time or a specific habitat"
        case .hard:
            "Specialized or time-dependent outings"
        }
    }

    private func difficultyFilterSymbol(_ filter: FieldTripDifficultyFilter) -> String {
        switch filter {
        case .all:
            "circle.grid.2x2"
        case .starter:
            "sparkles"
        case .easy:
            "leaf"
        case .moderate:
            "figure.walk"
        case .hard:
            "mountain.2"
        }
    }

    private func stateFilterSubtitle(_ filter: FieldTripStateFilter) -> String {
        switch filter {
        case .all:
            "Show outings at every status"
        case .completed:
            "Outings with every goal completed"
        case .inProgress:
            "Started outings that are not complete"
        case .incomplete:
            "Outings you haven’t started"
        }
    }

    private func stateFilterSymbol(_ filter: FieldTripStateFilter) -> String {
        switch filter {
        case .all:
            "rectangle.stack"
        case .completed:
            "checkmark.circle"
        case .inProgress:
            "clock.arrow.circlepath"
        case .incomplete:
            "circle"
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

        return GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    if viewModel.isLoading && viewModel.challenges.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            FieldTripChallengeSkeletonCard()
                        }
                    } else if let challengeErrorMessage = viewModel.challengeErrorMessage, visibleChallenges.isEmpty {
                        FieldTripUnavailableCard(
                            title: "Events unavailable",
                            message: challengeErrorMessage
                        ) {
                            Task { await viewModel.refresh(userRegion: userRegion) }
                        }
                    } else if visibleChallenges.isEmpty {
                        fieldTripEmptyState(
                            title: "No events right now",
                            message: "Check back soon for upcoming seasonal field trips."
                        )
                        .frame(
                            minHeight: max(440, geometry.size.height - 40)
                        )
                    } else {
                        ForEach(visibleChallenges) { challenge in
                            NavigationLink(value: FieldTripChallengeRoute(challengeId: challenge.challengeId)) {
                                FieldTripChallengeCard(challenge: challenge)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    HapticManager.shared.triggerLightImpact(
                                        intensity: 0.45,
                                        source: "fieldTrips.catalog.challenge.open"
                                    )
                                }
                            )
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable {
                await viewModel.refresh(userRegion: userRegion)
            }
        }
    }

    private func fieldTripEmptyState(title: String, message: String) -> some View {
        EmptyStateView(
            imageName: "fieldtrip-backpack",
            imageHeight: 300,
            title: title,
            message: message
        )
    }
}
