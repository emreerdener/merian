import SwiftData
import SwiftUI

struct BiologicalView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Bindable var viewModel: InsightSheetViewModel
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?
    @Environment(\.modelContext) private var modelContext

    // MARK: - Context State
    var timestamp: Date?
    var onOpenFieldTripOverview: ((InsightFieldTripOverviewDestination) -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var refinementAction: (() -> Void)? {
        guard let scanIdStr = inferenceEngine.speciesData?.scanId else { return nil }
        return {
            var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanIdStr })
            descriptor.fetchLimit = 1
            guard let record = try? modelContext.fetch(descriptor).first else { return }

            HapticManager.shared.triggerSelectionPulse()
            AppEventPublisher.shared.send(.triggerRefinement(
                scanId: record.id,
                initialDescription: viewModel.shareableFieldNotes
            ))
            dismiss()
        }
    }

    // MARK: - Visual Layout
    var body: some View {
        VStack(spacing: 32) {

            // MARK: - Header
            InsightHeader(
                title: viewModel.resolvedHeaderTitle,
                subtitle: viewModel.headerSubtitle,
                hazardType: viewModel.hazardType,
                paragraphs: viewModel.headerParagraphs,
                confidenceScore: inferenceEngine.speciesData?.confidenceScore,
                inferenceTier: inferenceEngine.speciesData?.inferenceTier,
                userIdentificationOverride: inferenceEngine.speciesData?.userIdentificationOverride,
                userConfirmedIdentification: inferenceEngine.speciesData?.userConfirmedIdentification ?? false,
                isFlagged: inferenceEngine.speciesData?.isFlagged ?? false,
                aiScientificName: inferenceEngine.speciesData?.aiScientificName,
                onAskCommunity: viewModel.canRequestCommunityIdentification ? {
                    viewModel.state.isCommunityRequestSheetPresented = true
                } : nil,
                onScrollOffsetChange: { maxY in
                    viewModel.evaluateScrollOffset(minY: maxY)
                },
                alternativeCommonNames: viewModel.displayAlternativeCommonNames,
                onAlternativeNamesTap: {
                    viewModel.state.isNamePickerPresented = true
                }
            )
            .cardEntrance(index: 0)
            .sheet(isPresented: $viewModel.state.isNamePickerPresented) {
                NamePickerSheet(
                    allNames: viewModel.allNamesForPicker,
                    activeName: viewModel.resolvedHeaderTitle,
                    onSelect: { chosen in
                        if let scientificName = inferenceEngine.speciesData?.scientificName {
                            viewModel.setPreferredCommonName(chosen, for: scientificName, modelContext: modelContext)
                        }
                        viewModel.state.isNamePickerPresented = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }

            // MARK: - Toxicity Banner
            ToxicityBanner()
                .cardEntrance(index: 1)

            // MARK: - Layout Guards
            let isBiological = inferenceEngine.speciesData?.isBiological ?? false

            if isBiological {
                let isUnknownSubject = inferenceEngine.speciesData?.scientificName == "Taxonomy Unavailable"

                // MARK: - Identification Candidates
                let candidates = CandidateReviewVisibilityPolicy.visibleCandidates(for: inferenceEngine.speciesData)

                if let primaryAIName = inferenceEngine.speciesData?.aiScientificName,
                   !candidates.isEmpty {
                    CandidatesCard(
                        candidates: candidates,
                        aiScientificName: primaryAIName,
                        inferenceTier: inferenceEngine.speciesData?.inferenceTier,
                        confirmButtonTitle: "Confirm \(viewModel.resolvedHeaderTitle)",
                        onAskCommunity: viewModel.canRequestCommunityIdentification ? {
                            viewModel.state.isCommunityRequestSheetPresented = true
                        } : nil,
                        onMatchConfirmed: { viewModel.state.toastMessage = "Match confirmed" },
                        onRefineScan: refinementAction
                    )
                    .cardEntrance(index: 2)
                }

                Group {
                    if viewModel.isLoadingFieldTripScanContributions {
                        FieldTripProgressCardSkeleton()
                            .transition(.opacity)
                    } else if !viewModel.fieldTripScanContributions.isEmpty {
                        FieldTripProgressCard(
                            contributions: viewModel.fieldTripScanContributions,
                            onOpen: { destination in
                                onOpenFieldTripOverview?(destination)
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(
                    .easeInOut(duration: 0.2),
                    value: viewModel.isLoadingFieldTripScanContributions
                )
                .cardEntrance(index: 3)

                if viewModel.shouldShowFieldNotesCard {
                    FieldNotesCard(
                        previewText: viewModel.fieldNotesText,
                        promptContext: viewModel.fieldNotesPromptContext,
                        visibility: viewModel.state.sharedExplorePostId == nil
                            ? nil
                            : (viewModel.state.exploreFieldNotesArePublic ? .published : .privateNotes),
                        onDismiss: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                viewModel.dismissFieldNotesCard()
                            }
                        },
                        action: {
                            viewModel.state.isFieldNotesSheetPresented = true
                        }
                    )
                    .cardEntrance(index: 4)
                }

                // MARK: - Educational Reference
                OverviewCard(
                    isSafariPresented: $isSafariPresented,
                    selectedWikiURL: $selectedWikiURL
                )
                .cardEntrance(index: 5)

                // MARK: - Habitat & Distribution
                if !isUnknownSubject {
                    HabitatAndDistributionCard()
                        .cardEntrance(index: 5)
                }

                // MARK: - Observation Patterns
                if !isUnknownSubject,
                   let scientificName = inferenceEngine.speciesData?.scientificName,
                   !scientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SpeciesObservationChartsCard(
                        speciesId: viewModel.activeConfirmedSpeciesId,
                        scientificName: scientificName
                    )
                    .cardEntrance(index: 6)
                }
    
                // MARK: - Biological Classification
                if !isUnknownSubject {
                    TaxonomyCard(
                        taxonomyData: inferenceEngine.speciesData?.taxonomy,
                        scientificName: inferenceEngine.speciesData?.scientificName
                    )
                    .cardEntrance(index: 7)
                }
    
                // MARK: - Similar Species Gallery
                if !isUnknownSubject {
                    Group {
                        if let similarData = inferenceEngine.speciesData?.similarSpecies {
                            SimilarSpeciesGallery(
                                similarData: similarData,
                                currentScientificName: inferenceEngine.speciesData?.scientificName,
                                currentCommonName: inferenceEngine.speciesData?.commonName,
                                routeForSpecies: insightSimilarSpeciesRoute
                            )
                            .transition(.opacity)
                        } else if inferenceEngine.isLookalikesLoading {
                            SimilarSpeciesGallery.Skeleton()
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut, value: inferenceEngine.isLookalikesLoading)
                    .cardEntrance(index: 8)
                }
    
                // MARK: - Spatiotemporal Context
                ScanInformationCard(
                    speciesData: inferenceEngine.speciesData,
                    timestamp: timestamp,
                    imageCount: viewModel.activeImageCount
                )
                .cardEntrance(index: 9)

                // MARK: - Custom Tags
                if let scanId = inferenceEngine.speciesData?.scanId {
                    UserTagsCard(scanId: scanId)
                        .cardEntrance(index: 10)
                }
            }
        }
        .padding(.horizontal)
    }

    private func insightSimilarSpeciesRoute(for entry: SimilarSpeciesEntry) -> SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: entry.scientificName,
            speciesId: entry.speciesId,
            entryPoint: .insightSimilarSpecies
        )
    }
}

struct FieldTripProgressCard: View {
    let contributions: [FieldTripScanContribution]
    let onOpen: (InsightFieldTripOverviewDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InsightCardHeader(systemImage: "map", title: "Field trips")

            VStack(spacing: 22) {
                ForEach(contributions) { contribution in
                    if let destination = InsightFieldTripOverviewDestination(
                        contribution: contribution
                    ) {
                        Button {
                            HapticManager.shared.triggerSelectionPulse(
                                source: "insight.fieldTripProgress.open"
                            )
                            onOpen(destination)
                        } label: {
                            FieldTripProgressContributionRow(contribution: contribution)
                        }
                        .buttonStyle(.plain)
                    } else {
                        FieldTripProgressContributionRow(contribution: contribution)
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}

private struct FieldTripProgressCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InsightCardHeader(systemImage: "map", title: "Field trips")
            FieldTripProgressContributionRowSkeleton()
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Field trip progress")
    }
}

private struct FieldTripProgressContributionRowSkeleton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        artwork
                        labels
                    }
                    HStack {
                        Spacer()
                        progressRing
                    }
                }
            } else {
                HStack(spacing: 12) {
                    artwork
                    labels
                    Spacer(minLength: 8)
                    progressRing
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var artwork: some View {
        GlowPulsingSkeletonView(cornerRadius: 14)
            .frame(width: 68, height: 68)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 7) {
            GlowPulsingSkeletonView(cornerRadius: 4)
                .frame(width: 92, height: 10)

            GlowPulsingSkeletonView(cornerRadius: 5)
                .frame(maxWidth: 148)
                .frame(height: 18)

            GlowPulsingSkeletonView(cornerRadius: 4)
                .frame(maxWidth: 116)
                .frame(height: 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var progressRing: some View {
        ZStack {
            GlowPulsingSkeletonView(cornerRadius: 32)
                .mask {
                    Circle().stroke(lineWidth: 5)
                }

            GlowPulsingSkeletonView(cornerRadius: 4)
                .frame(width: 28, height: 16)
        }
        .frame(width: 64, height: 64)
    }
}

private struct FieldTripProgressContributionRow: View {
    let contribution: FieldTripScanContribution
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sourceSubtitle: String {
        contribution.title
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        artwork
                        labels
                    }
                    HStack {
                        Spacer()
                        progressRing
                    }
                }
            } else {
                HStack(spacing: 12) {
                    artwork
                    labels
                    Spacer(minLength: 8)
                    progressRing
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(contribution.prompt) goal complete in \(contribution.title), "
                + "\(contribution.completedCount) of \(contribution.targetCount)"
        )
        .accessibilityHint(contribution.destination == nil ? "" : "Opens Field trip details")
        .accessibilityAddTraits(contribution.destination == nil ? [] : .isButton)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GOAL COMPLETE")
                .font(.caption2.weight(.medium))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Text(contribution.prompt)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(sourceSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var progressRing: some View {
        GoalProgressRing(
            completedCount: contribution.completedCount,
            targetCount: contribution.targetCount,
            lineWidth: 5,
            labelFontSize: 18,
            tint: .accentColor
        )
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let imageName = FieldTripObjectiveArtwork.exactImageName(
                    for: contribution.artworkPrompt,
                    templateSlug: contribution.artworkTemplateSlug
                ) {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                } else {
                    Image(systemName: "binoculars.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(.green, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                }
                .offset(x: 3, y: 3)
        }
        .frame(width: 68, height: 68)
        .accessibilityHidden(true)
    }
}
