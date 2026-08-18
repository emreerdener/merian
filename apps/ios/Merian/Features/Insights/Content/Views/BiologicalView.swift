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
    @State private var namePickerScanId: String?
    @State private var namePickerScientificName: String?
    @State private var namePickerGeneration: UInt64?

    private func refinementAction(
        scanId: String?,
        generation: UInt64
    ) -> (() -> Void)? {
        guard let scanId else { return nil }
        return {
            guard viewModel.isPresentingLocalRecord(
                      scanId: scanId,
                      generation: generation
                  ),
                  inferenceEngine.speciesData?.scanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame else {
                return
            }
            var descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            descriptor.fetchLimit = 1
            guard let record = try? modelContext.fetch(descriptor).first else { return }

            HapticManager.shared.triggerSelectionPulse()
            AppDIContainer.shared.appRouteCoordinator.request(
                .refinement(
                    scanId: record.id,
                    initialDescription: viewModel.shareableFieldNotes,
                    entryPoint: .standard
                ),
                source: .internalUserAction
            )
            dismiss()
        }
    }

    // MARK: - Visual Layout
    var body: some View {
        let fieldNotesScanId = viewModel.currentFieldNotesScanId
        let fieldNotesGeneration = viewModel.scanBoundActionGeneration
        let biologicalScanId = viewModel.presentedLocalRecordScanId
        let biologicalScientificName = inferenceEngine.speciesData?.scientificName

        VStack(spacing: 32) {

            // MARK: - Header
            InsightHeader(
                title: viewModel.resolvedHeaderTitle,
                subtitle: viewModel.headerSubtitle,
                hazardType: viewModel.hazardType,
                paragraphs: viewModel.headerParagraphs,
                confidenceScore: inferenceEngine.speciesData?.presentationConfidenceScore,
                inferenceTier: inferenceEngine.speciesData?.inferenceTier,
                userIdentificationOverride: inferenceEngine.speciesData?.userIdentificationOverride,
                userConfirmedIdentification: inferenceEngine.speciesData?.userConfirmedIdentification ?? false,
                isFlagged: inferenceEngine.speciesData?.isFlagged ?? false,
                aiScientificName: inferenceEngine.speciesData?.aiScientificName,
                onAskCommunity: viewModel.canRequestCommunityIdentification ? {
                    guard let scanId = biologicalScanId else { return }
                    viewModel.presentCommunityIdentificationRequest(
                        expectedScanId: scanId,
                        expectedGeneration: fieldNotesGeneration
                    )
                } : nil,
                onScrollOffsetChange: { maxY in
                    viewModel.evaluateScrollOffset(minY: maxY)
                },
                alternativeCommonNames: viewModel.displayAlternativeCommonNames,
                onAlternativeNamesTap: {
                    guard let scanId = biologicalScanId,
                          let scientificName = biologicalScientificName,
                          viewModel.isPresentingLocalRecord(
                              scanId: scanId,
                              generation: fieldNotesGeneration
                          ),
                          inferenceEngine.speciesData?.scientificName
                            .caseInsensitiveCompare(scientificName) == .orderedSame else {
                        return
                    }
                    namePickerScanId = scanId
                    namePickerScientificName = scientificName
                    namePickerGeneration = fieldNotesGeneration
                    viewModel.state.isNamePickerPresented = true
                }
            )
            .cardEntrance(index: 0)
            .sheet(isPresented: namePickerPresentedBinding) {
                if let scanId = namePickerScanId,
                   let scientificName = namePickerScientificName,
                   let generation = namePickerGeneration,
                   viewModel.isPresentingLocalRecord(
                       scanId: scanId,
                       generation: generation
                   ),
                   inferenceEngine.speciesData?.scientificName
                    .caseInsensitiveCompare(scientificName) == .orderedSame {
                    NamePickerSheet(
                        allNames: viewModel.allNamesForPicker,
                        activeName: viewModel.resolvedHeaderTitle,
                        onSelect: { chosen in
                            guard viewModel.isPresentingLocalRecord(
                                scanId: scanId,
                                generation: generation
                            ),
                                  namePickerScanId?
                                    .caseInsensitiveCompare(scanId) ==
                                    .orderedSame,
                                  namePickerScientificName?
                                    .caseInsensitiveCompare(scientificName) ==
                                    .orderedSame,
                                  namePickerGeneration == generation else {
                                return
                            }
                            viewModel.setPreferredCommonName(
                                chosen,
                                for: scientificName,
                                expectedScanId: scanId,
                                expectedGeneration: generation,
                                modelContext: modelContext
                            )
                            namePickerScanId = nil
                            namePickerScientificName = nil
                            namePickerGeneration = nil
                            viewModel.state.isNamePickerPresented = false
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: inferenceEngine.scanPresentationGeneration) {
                namePickerScanId = nil
                namePickerScientificName = nil
                namePickerGeneration = nil
                viewModel.state.isNamePickerPresented = false
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
                            guard let scanId = biologicalScanId else { return }
                            viewModel.presentCommunityIdentificationRequest(
                                expectedScanId: scanId,
                                expectedGeneration: fieldNotesGeneration
                            )
                        } : nil,
                        onMatchConfirmed: {
                            guard let scanId = biologicalScanId,
                                  viewModel.isPresentingLocalRecord(
                                      scanId: scanId,
                                      generation: fieldNotesGeneration
                                  ) else {
                                return
                            }
                            viewModel.state.toastMessage = .success("Match confirmed")
                        },
                        onRefineScan: refinementAction(
                            scanId: biologicalScanId,
                            generation: fieldNotesGeneration
                        )
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
                                guard let scanId = biologicalScanId,
                                      viewModel.isPresentingLocalRecord(
                                          scanId: scanId,
                                          generation: fieldNotesGeneration
                                      ) else {
                                    return
                                }
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
                                viewModel.dismissFieldNotesCard(
                                    expectedScanId: fieldNotesScanId,
                                    expectedGeneration: fieldNotesGeneration
                                )
                            }
                        },
                        action: {
                            viewModel.presentFieldNotes(
                                expectedScanId: fieldNotesScanId,
                                expectedGeneration: fieldNotesGeneration
                            )
                        }
                    )
                    .cardEntrance(index: 4)
                }

                // MARK: - Educational Reference
                OverviewCard(
                    isSafariPresented: safariPresentedBinding(
                        scanId: biologicalScanId,
                        generation: fieldNotesGeneration
                    ),
                    selectedWikiURL: selectedWikiURLBinding(
                        scanId: biologicalScanId,
                        generation: fieldNotesGeneration
                    )
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
                if let scanId = viewModel.presentedLocalRecordScanId,
                   inferenceEngine.speciesData?.scanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame {
                    UserTagsCard(scanId: scanId)
                        .id(scanId.lowercased())
                        .cardEntrance(index: 10)
                }
            }
        }
        .padding(.horizontal)
    }

    private func safariPresentedBinding(
        scanId: String?,
        generation: UInt64
    ) -> Binding<Bool> {
        guard let scanId else { return .constant(false) }
        return Binding(
            get: {
                viewModel.isPresentingLocalRecord(
                    scanId: scanId,
                    generation: generation
                ) && isSafariPresented
            },
            set: { isPresented in
                guard viewModel.isPresentingLocalRecord(
                    scanId: scanId,
                    generation: generation
                ) else {
                    return
                }
                if isPresented {
                    viewModel.state.safariPresentationScanId = scanId
                    viewModel.state.safariPresentationGeneration = generation
                } else {
                    guard viewModel.state.safariPresentationScanId?
                        .caseInsensitiveCompare(scanId) == .orderedSame,
                          viewModel.state.safariPresentationGeneration ==
                            generation else {
                        return
                    }
                    viewModel.state.safariPresentationScanId = nil
                    viewModel.state.safariPresentationGeneration = nil
                    selectedWikiURL = nil
                }
                isSafariPresented = isPresented
            }
        )
    }

    private var namePickerPresentedBinding: Binding<Bool> {
        let expectedScanId = namePickerScanId
        let expectedScientificName = namePickerScientificName
        let expectedGeneration = namePickerGeneration
        return Binding(
            get: {
                guard viewModel.state.isNamePickerPresented,
                      let expectedScanId,
                      let expectedScientificName,
                      let expectedGeneration,
                      namePickerScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      namePickerScientificName?
                        .caseInsensitiveCompare(expectedScientificName) ==
                        .orderedSame,
                      namePickerGeneration == expectedGeneration else {
                    return false
                }
                return viewModel.isPresentingLocalRecord(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                ) && inferenceEngine.speciesData?.scientificName
                    .caseInsensitiveCompare(expectedScientificName) ==
                    .orderedSame
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedScanId,
                      let expectedScientificName,
                      let expectedGeneration,
                      namePickerScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      namePickerScientificName?
                        .caseInsensitiveCompare(expectedScientificName) ==
                        .orderedSame,
                      namePickerGeneration == expectedGeneration,
                      viewModel.isPresentingLocalRecord(
                          scanId: expectedScanId,
                          generation: expectedGeneration
                      ) else {
                    return
                }
                namePickerScanId = nil
                namePickerScientificName = nil
                namePickerGeneration = nil
                viewModel.state.isNamePickerPresented = false
            }
        )
    }

    private func selectedWikiURLBinding(
        scanId: String?,
        generation: UInt64
    ) -> Binding<URL?> {
        guard let scanId else { return .constant(nil) }
        return Binding(
            get: {
                guard viewModel.isPresentingLocalRecord(
                    scanId: scanId,
                    generation: generation
                ) else {
                    return nil
                }
                return selectedWikiURL
            },
            set: { url in
                guard viewModel.isPresentingLocalRecord(
                    scanId: scanId,
                    generation: generation
                ) else {
                    return
                }
                selectedWikiURL = url
            }
        )
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
