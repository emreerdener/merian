import SwiftData
import SwiftUI

struct BiologicalView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(EntitlementManager.self) private var entitlementManager
    @Bindable var viewModel: InsightSheetViewModel
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?
    @Environment(\.modelContext) private var modelContext

    // MARK: - Context State
    var timestamp: Date?
    var onOpenFieldTripOverview: ((InsightFieldTripOverviewDestination) -> Void)?
    var prepareCommunityConsent: CommunityConsentPreparation?
    var prepareSavedReanalysis: SavedReanalysisPreparation?
    var confidenceReviewControls = ConfidenceReviewControls()

    @Environment(\.dismiss) private var dismiss
    @State private var namePickerScanId: String?
    @State private var namePickerScientificName: String?
    @State private var namePickerGeneration: UInt64?

    private func refinementAction(
        scanId: String?,
        generation: UInt64
    ) -> (() -> Void)? {
        guard let scanId, prepareSavedReanalysis != nil ||
                ObservationHistoryEnrollmentService.permitsLegacyMutation(scanID: scanId, container: modelContext.container) else { return nil }
        return {
            guard viewModel.isPresentingLocalRecord(
                      scanId: scanId,
                      generation: generation
                  ),
                  inferenceEngine.speciesData?.scanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame else {
                return
            }
            if let prepareSavedReanalysis {
                prepareSavedReanalysis(scanId, inferenceEngine.scanPresentationGeneration).resume()
                return
            }
            if viewModel.requestRefinement(
                expectedScanId: scanId,
                expectedGeneration: generation,
                modelContext: modelContext
            ) {
                viewModel.endPresentationSession()
                dismiss()
            }
        }
    }

    // MARK: - Visual Layout
    private func communityAction(scanID: String?, generation: UInt64) -> (() -> Void)? {
        guard let scanID else { return nil }
        if let prepareCommunityConsent {
            let engineGeneration = inferenceEngine.scanPresentationGeneration
            return { prepareCommunityConsent(scanID, engineGeneration)?.resume() }
        }
        guard viewModel.canRequestCommunityIdentification,
              ObservationHistoryEnrollmentService.permitsLegacyMutation(scanID: scanID, container: modelContext.container) else { return nil }
        return { viewModel.presentCommunityIdentificationRequest(expectedScanId: scanID, expectedGeneration: generation) }
    }

    var body: some View {
        let fieldNotesScanId = viewModel.currentFieldNotesScanId
        let fieldNotesGeneration = viewModel.scanBoundActionGeneration
        let biologicalScanId = viewModel.presentedLocalRecordScanId
        let biologicalScientificName = inferenceEngine.speciesData?.scientificName
        let cardEntranceAnimationEnabled =
            viewModel.isContentCardEntranceAnimationEnabled

        VStack(spacing: 32) {

            if let identity = inferenceEngine.speciesData?.verifiedConfirmedSpeciesIdentity {
                VStack(spacing: 8) {
                    Text("Your selected species").font(.subheadline).foregroundStyle(.secondary)
                    Text(identity.scientificName).font(.title3).italic()
                    NavigationLink(value: SpeciesDictionaryRoute(
                        scientificName: identity.scientificName,
                        speciesId: identity.speciesID,
                        entryPoint: .insightConfirmedSpecies
                    )) {
                        Label("View species details", systemImage: "book")
                    }
                    Text("The AI result and confidence below describe the original identification.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            }

            // MARK: - Header
            InsightHeader(
                title: viewModel.resolvedHeaderTitle,
                subtitle: viewModel.headerSubtitle,
                hazardType: viewModel.hazardType,
                paragraphs: viewModel.headerParagraphs,
                confidenceScore: inferenceEngine.speciesData?.presentationConfidenceScore,
                inferenceTier: inferenceEngine.speciesData?.inferenceTier,
                provenance: inferenceEngine.speciesData?.identificationProvenance,
                primaryRankDescription: inferenceEngine.speciesData?.primaryRankDescription,
                userIdentificationOverride: inferenceEngine.speciesData?.primaryIdentification == nil ? inferenceEngine.speciesData?.userIdentificationOverride : nil,
                userConfirmedIdentification: inferenceEngine.speciesData?.primaryIdentification == nil ? (inferenceEngine.speciesData?.userConfirmedIdentification ?? false) : false,
                isFlagged: inferenceEngine.speciesData?.isFlagged ?? false,
                aiScientificName: inferenceEngine.speciesData?.aiScientificName,
                onAskCommunity: communityAction(scanID: biologicalScanId, generation: fieldNotesGeneration),
                prepareCommunityConsent: prepareCommunityConsent,
                prepareSavedReanalysis: prepareSavedReanalysis,
                    confidenceReviewControls: confidenceReviewControls,
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
                },
                onRevealFeedback: viewModel.performContentHeaderRevealFeedback,
                modelTierBadgePresentation: modelTierBadgePresentation,
                onModelTierUpgrade: {
                    guard fieldNotesGeneration ==
                            viewModel.scanBoundActionGeneration else {
                        return
                    }
                    viewModel.state.showPaywall = true
                }
            )
            .insightCardEntrance(index: 0, isAnimationEnabled: cardEntranceAnimationEnabled)
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
            ToxicityBanner(hazardType: viewModel.hazardType)
                .insightCardEntrance(index: 1, isAnimationEnabled: cardEntranceAnimationEnabled)

            // MARK: - Layout Guards
            let isBiological = inferenceEngine.speciesData?.isBiological ?? false

            if isBiological {
                let isUnknownSubject = inferenceEngine.speciesData?.scientificName == "Taxonomy Unavailable"

                if CandidateReviewVisibilityPolicy.showsIncorrectGuidance(
                    for: inferenceEngine.speciesData,
                    canReanalyze: viewModel.canReanalyze,
                    canAskCommunity: communityAction(scanID: biologicalScanId, generation: fieldNotesGeneration) != nil
                ) {
                    IncorrectIdentificationGuidanceCard(
                        onReanalyze: viewModel.canReanalyze ? refinementAction(
                            scanId: biologicalScanId,
                            generation: fieldNotesGeneration
                        ) : nil,
                        onAskCommunity: communityAction(scanID: biologicalScanId, generation: fieldNotesGeneration)
                    )
                }

                // MARK: - Identification Candidates
                let candidates = CandidateReviewVisibilityPolicy.visibleCandidates(for: inferenceEngine.speciesData)

                let primaryAIName = inferenceEngine.speciesData?.aiScientificName
                if (primaryAIName != nil && !candidates.isEmpty) || !confidenceReviewControls.candidateChoices.isEmpty {
                    CandidatesCard(
                        candidates: candidates,
                        aiScientificName: primaryAIName ?? "",
                        inferenceTier: inferenceEngine.speciesData?.inferenceTier,
                        confirmButtonTitle: "Confirm \(viewModel.resolvedHeaderTitle)",
                        onAskCommunity: communityAction(scanID: biologicalScanId, generation: fieldNotesGeneration),
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
                        ),
                        prepareCommunityConsent: prepareCommunityConsent,
                        prepareSavedReanalysis: prepareSavedReanalysis,
                        confidenceReviewControls: confidenceReviewControls
                    )
                    .insightCardEntrance(index: 2, isAnimationEnabled: cardEntranceAnimationEnabled)
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
                                viewModel.performFieldTripOpenFeedback()
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
                .insightCardEntrance(index: 3, isAnimationEnabled: cardEntranceAnimationEnabled)

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
                .insightCardEntrance(index: 4, isAnimationEnabled: cardEntranceAnimationEnabled)

                // MARK: - Habitat & Distribution
                if !isUnknownSubject {
                    HabitatAndDistributionCard()
                        .insightCardEntrance(index: 5, isAnimationEnabled: cardEntranceAnimationEnabled)
                }

                // MARK: - Observation Patterns
                if !isUnknownSubject,
                   let scientificName = inferenceEngine.speciesData?.scientificName,
                   !scientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SpeciesObservationChartsCard(
                        speciesId: viewModel.activeConfirmedSpeciesId,
                        scientificName: scientificName
                    )
                    .insightCardEntrance(index: 6, isAnimationEnabled: cardEntranceAnimationEnabled)
                }

                // MARK: - Biological Classification
                if !isUnknownSubject {
                    TaxonomyCard(
                        taxonomyData: inferenceEngine.speciesData?.taxonomy,
                        scientificName: inferenceEngine.speciesData?.scientificName
                    )
                    .insightCardEntrance(index: 7, isAnimationEnabled: cardEntranceAnimationEnabled)
                }

                // MARK: - Similar Species Gallery
                if !isUnknownSubject {
                    Group {
                        if let similarData = inferenceEngine.speciesData?.similarSpecies {
                            SimilarSpeciesGallery(
                                similarData: similarData,
                                currentScientificName: inferenceEngine.speciesData?.scientificName,
                                currentCommonName: inferenceEngine.speciesData?.commonName,
                                currentSpeciesId: viewModel.activeConfirmedSpeciesId,
                                routeForSpecies: insightSimilarSpeciesRoute
                            )
                            .transition(.opacity)
                        } else if inferenceEngine.isLookalikesLoading {
                            SimilarSpeciesGallery.Skeleton()
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut, value: inferenceEngine.isLookalikesLoading)
                    .insightCardEntrance(index: 8, isAnimationEnabled: cardEntranceAnimationEnabled)
                }

                // MARK: - Spatiotemporal Context
                ScanInformationCard(
                    speciesData: inferenceEngine.speciesData,
                    timestamp: timestamp,
                    imageCount: viewModel.activeImageCount
                )
                .insightCardEntrance(index: 9, isAnimationEnabled: cardEntranceAnimationEnabled)

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
                    .insightCardEntrance(index: 10, isAnimationEnabled: cardEntranceAnimationEnabled)
                }

                // MARK: - Custom Tags
                if let scanId = viewModel.presentedLocalRecordScanId,
                   inferenceEngine.speciesData?.scanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame {
                    UserTagsCard(scanId: scanId)
                        .id(scanId.lowercased())
                        .insightCardEntrance(index: 11, isAnimationEnabled: cardEntranceAnimationEnabled)
                }
            }
        }
        .padding(.horizontal)
    }

    private var modelTierBadgePresentation: ModelTierBadgePresentation? {
        ModelTierBadgePresentation.resolve(
            confidenceScore: inferenceEngine.speciesData?
                .presentationConfidenceScore,
            inferenceTier: inferenceEngine.speciesData?.inferenceTier,
                provenance: inferenceEngine.speciesData?.identificationProvenance,
            isSubscribed: revenueCatManager.isSubscribed,
            isProActive: revenueCatManager.isProActive,
            hasComplimentaryAccess: entitlementManager
                .hasVerifiedComplimentaryAccess,
            complimentaryScansRemaining: entitlementManager.scansRemaining,
            isComplimentaryExhausted: entitlementManager
                .isComplimentaryExhausted
        )
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
