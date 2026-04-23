import SwiftData
import SwiftUI

struct BiologicalView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Bindable var viewModel: InsightSheetViewModel
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?

    // MARK: - Context State
    var timestamp: Date?

    @Environment(\.dismiss) private var dismiss

    private var refinementAction: (() -> Void)? {
        guard let scanIdStr = inferenceEngine.speciesData?.scanId else { return nil }
        return {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanIdStr })
            guard let record = try? viewModel.activeLocalRecord?.modelContext?.fetch(descriptor).first ?? viewModel.activeLocalRecord else { return }
            
            var hasCloudImage = false
            var imageCount = 0
            if let jsonStr = record.capturedMediaJSON,
               let jsonData = jsonStr.data(using: .utf8),
               let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
                for item in items {
                    if case .image(let path) = item {
                        imageCount += 1
                        if path.starts(with: "http") { hasCloudImage = true }
                    }
                }
            }
            guard !hasCloudImage, imageCount <= 1 else { return }
            
            HapticManager.shared.triggerSelectionPulse()
            AppEventPublisher.shared.send(.triggerRefinement(record: record))
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
                            viewModel.setPreferredCommonName(chosen, for: scientificName)
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
                // MARK: - Identification Candidates
                let hasReviewState = inferenceEngine.speciesData?.userIdentificationOverride != nil ||
                                     inferenceEngine.speciesData?.userConfirmedIdentification == true ||
                                     inferenceEngine.speciesData?.isFlagged == true ||
                                     inferenceEngine.speciesData?.alternativesExhausted == true
                let candidates = inferenceEngine.speciesData?.candidates ?? []

                let isUnknownSubject = inferenceEngine.speciesData?.scientificName == "Taxonomy Unavailable"
                let isHumanSubject = inferenceEngine.speciesData?.isHumanSubject ?? false

                if let primaryAIName = inferenceEngine.speciesData?.aiScientificName,
                   !isUnknownSubject && !isHumanSubject && !hasReviewState {
                    CandidatesCard(
                        candidates: candidates,
                        aiScientificName: primaryAIName,
                        inferenceTier: inferenceEngine.speciesData?.inferenceTier,
                        confirmButtonTitle: "Confirm \(viewModel.resolvedHeaderTitle)",
                        onFlagIssue: { viewModel.state.isIdentificationFlagPresented = true },
                        onMatchConfirmed: { viewModel.state.toastMessage = "Match confirmed" },
                        onRefineScan: refinementAction
                    )
                    .cardEntrance(index: 3)
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
                                similarData: similarData
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
                let imageCount: Int = {
                    if inferenceEngine.activeMedia.liveImageData != nil { return 1 }
                    var c = 0
                    if let jsonStr = viewModel.activeLocalRecord?.capturedMediaJSON,
                       let jsonData = jsonStr.data(using: .utf8),
                       let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
                        c = items.filter { if case .image = $0 { return true } else { return false } }.count
                    }
                    return max(1, c)
                }()
                ScanInformationCard(
                    speciesData: inferenceEngine.speciesData,
                    timestamp: timestamp,
                    imageCount: imageCount
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
}
