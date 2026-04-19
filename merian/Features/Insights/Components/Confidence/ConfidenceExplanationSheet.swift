import CoreLocation
import SwiftData
import SwiftUI

struct ConfidenceExplanationSheet: View {
    let confidenceScore: Double?
    let inferenceTier: String?
    var userIdentificationOverride: String?
    var userConfirmedIdentification: Bool = false
    var isFlagged: Bool = false
    var aiScientificName: String?

    @Environment(EnvironmentContextManager.self) private var environmentContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isFlagPresented = false
    @State private var isSwipeModalPresented = false
    @State private var showPaywall = false
    @State private var localRefinementRecord: LocalScanRecord?

    private var showLocationPrompt: Bool {
        let status = environmentContext.locationAuthorizationStatus
        return status == .notDetermined || status == .restricted || status == .denied
    }

    private var refinementAction: (() -> Void)? {
        guard let record = localRefinementRecord,
              (record.additionalImagePaths ?? []).isEmpty else { return nil }
        return {
            HapticManager.shared.triggerSelectionPulse()
            AppEventPublisher.shared.send(.triggerRefinement(record: record))
            dismiss()
        }
    }

    private var headerTitle: String {
        if isFlagged { return "Under review" }
        if userIdentificationOverride != nil || userConfirmedIdentification { return "Confirmed" }
        guard let score = confidenceScore else { return "Analysis" }
        let pct = Int(round(score * 100))
        return "\(pct)% confident"
    }

    private var confirmButtonTitle: String {
        let cName = inferenceEngine.speciesData?.commonName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isCommonNameValid = !cName.isEmpty && cName.lowercased() != "unknown subject"
        let aiSciName = aiScientificName ?? "Unknown"
        let isScientificNameValid = !aiSciName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && aiSciName.lowercased() != "unknown subject"
        
        if isCommonNameValid {
            return "Confirm \(cName.capitalized)"
        } else if isScientificNameValid {
            return "Confirm \(aiSciName)"
        } else {
            return "Confirm initial match"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                ConfidenceHeader(title: headerTitle)

                let candidates = inferenceEngine.speciesData?.candidates ?? []
                let isExhausted = inferenceEngine.speciesData?.alternativesExhausted == true

                if isExhausted {
                    AllCandidatesReviewedView(
                        candidatesCount: candidates.count,
                        onReviewAgain: {
                            isSwipeModalPresented = true
                        },
                        onReset: {
                            HapticManager.shared.triggerLightImpact()
                            Task { await inferenceEngine.resetIdentificationReview(modelContext: modelContext) }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if isFlagged {
                    UnderReviewView(
                        onUndo: {
                            HapticManager.shared.triggerLightImpact()
                            Task { await inferenceEngine.unflagAIIdentification(modelContext: modelContext) }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if let override = userIdentificationOverride {
                    let newCommon = inferenceEngine.speciesData?.commonName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let displayOverride = (newCommon.isEmpty || newCommon.lowercased() == "unknown subject") ? override : "\(newCommon.capitalized) (\(override))"

                    OverriddenView(
                        overrideName: displayOverride,
                        aiScientificName: aiScientificName ?? "Unknown",
                        onUndo: {
                            HapticManager.shared.triggerLightImpact()
                            Task {
                                await inferenceEngine.resetIdentificationReview(modelContext: modelContext)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if userConfirmedIdentification {
                    ConfirmedView(
                        onReset: {
                            HapticManager.shared.triggerLightImpact()
                            Task {
                                await inferenceEngine.resetIdentificationReview(modelContext: modelContext)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                } else {

                    CandidatesCard(
                        candidates: candidates,
                        aiScientificName: aiScientificName ?? "Unknown subject",
                        inferenceTier: inferenceTier,
                        confirmButtonTitle: confirmButtonTitle,
                        onFlagIssue: {
                            isFlagPresented = true
                        },
                        onMatchConfirmed: nil,
                        onRefineScan: refinementAction,
                        showDismissButton: false
                    )
                    .padding(.horizontal, 16)
                }

                if !userConfirmedIdentification && userIdentificationOverride == nil && !isFlagged {
                    ConfidenceSpectrum(inferenceTier: inferenceTier)
                }

                PlanCard(showPaywall: $showPaywall)
                    .padding(.horizontal, 16)

                ProTips(showLocationPrompt: showLocationPrompt)
            }
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .sheet(isPresented: $isFlagPresented) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                FlagIdentificationModal(scanId: scanId)
            }
        }
        .sheet(isPresented: $isSwipeModalPresented) {
            
            CandidateSwipeModal(
                isPresented: $isSwipeModalPresented,
                candidates: inferenceEngine.speciesData?.candidates ?? [],
                aiScientificName: aiScientificName ?? "Unknown",
                confirmButtonTitle: confirmButtonTitle,
                onConfirmOriginal: {
                    Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
                },
                onFlagIssue: {
                    isFlagPresented = true
                },
                onRefineScan: refinementAction
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .task(id: inferenceEngine.speciesData?.scanId) {
            guard let scanIdStr = inferenceEngine.speciesData?.scanId else {
                localRefinementRecord = nil
                return
            }
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanIdStr })
            if let record = try? modelContext.fetch(descriptor).first, !(record.localImagePath?.starts(with: "http") == true) {
                localRefinementRecord = record
            } else {
                localRefinementRecord = nil
            }
        }
    }
}
