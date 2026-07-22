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
    var onOpenCaptureGoal: ((CaptureGoalDestination) -> Void)?

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

                if !viewModel.fieldTripScanContributions.isEmpty {
                    FieldTripProgressCard(
                        contributions: viewModel.fieldTripScanContributions,
                        onOpen: { destination in
                            onOpenCaptureGoal?(destination)
                        }
                    )
                    .cardEntrance(index: 3)
                }

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
    let onOpen: (CaptureGoalDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InsightCardHeader(systemImage: "map.fill", title: "Field trip progress")

            VStack(spacing: 0) {
                ForEach(Array(contributions.enumerated()), id: \.element.id) { index, contribution in
                    if let destination = contribution.destination {
                        Button {
                            onOpen(destination)
                        } label: {
                            FieldTripProgressContributionRow(contribution: contribution)
                        }
                        .buttonStyle(.plain)
                    } else {
                        FieldTripProgressContributionRow(contribution: contribution)
                    }

                    if index < contributions.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}

private struct FieldTripProgressContributionRow: View {
    let contribution: FieldTripScanContribution
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var goalTitle: String { "\(contribution.prompt) goal complete" }
    private var sourceSubtitle: String {
        "\(contribution.title) · Level \(contribution.levelNumber)"
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
                        progressAndDisclosure
                    }
                }
            } else {
                HStack(spacing: 12) {
                    artwork
                    labels
                    Spacer(minLength: 8)
                    progressAndDisclosure
                }
            }
        }
        .padding(.vertical, 12)
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
            Text(goalTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(sourceSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressAndDisclosure: some View {
        HStack(spacing: 8) {
            GoalProgressRing(
                completedCount: contribution.completedCount,
                targetCount: contribution.targetCount,
                tint: .green
            )
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)

            if contribution.destination != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
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
                        .padding(4)
                } else {
                    Image(systemName: "binoculars.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 46, height: 46)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.green, in: Circle())
                .overlay { Circle().stroke(.background, lineWidth: 2) }
                .offset(x: 3, y: 3)
        }
        .frame(width: 50, height: 50)
        .accessibilityHidden(true)
    }
}
