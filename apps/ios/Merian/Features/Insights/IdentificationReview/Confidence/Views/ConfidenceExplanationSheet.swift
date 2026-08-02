import CoreLocation
import SwiftData
import SwiftUI

struct ConfidenceExplanationSheet: View {
    let scanId: String
    let presentationGeneration: UInt64
    let confidenceScore: Double?
    let inferenceTier: String?
    var userIdentificationOverride: String?
    var userConfirmedIdentification: Bool = false
    var isFlagged: Bool = false
    var aiScientificName: String?
    var onAskCommunity: (() -> Void)?

    @Environment(EnvironmentContextManager.self) private var environmentContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isSwipeModalPresented = false
    @State private var showPaywall = false
    @State private var localRefinementRecord: LocalScanRecord?

    private var showLocationPrompt: Bool {
        let status = environmentContext.locationAuthorizationStatus
        return status == .notDetermined || status == .restricted || status == .denied
    }

    private var refinementAction: (() -> Void)? {
        guard let record = localRefinementRecord else { return nil }

        return {
            guard isSubjectPresentationCurrent,
                  record.id.caseInsensitiveCompare(scanId) == .orderedSame else {
                return
            }
            if revenueCatManager.isProActive {
                HapticManager.shared.triggerSelectionPulse()
                AppEventPublisher.shared.send(.triggerRefinement(
                    scanId: record.id,
                    initialDescription: record.fieldNotes
                ))
                dismiss()
            } else {
                showPaywall = true
            }
        }
    }

    private var headerTitle: String {
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

    private var storedCandidates: [IdentificationCandidate] {
        inferenceEngine.speciesData?.candidates ?? []
    }

    private var visibleReviewCandidates: [IdentificationCandidate] {
        CandidateReviewVisibilityPolicy.visibleCandidates(for: inferenceEngine.speciesData)
    }

    private var swipeModalCandidates: [IdentificationCandidate] {
        if inferenceEngine.speciesData?.alternativesExhausted == true {
            return storedCandidates
        }
        return visibleReviewCandidates
    }

    private var isSubjectPresentationCurrent: Bool {
        inferenceEngine.scanPresentationGeneration == presentationGeneration &&
            inferenceEngine.speciesData?.scanId?
                .caseInsensitiveCompare(scanId) == .orderedSame
    }

    private var communityRequestAction: (() -> Void)? {
        onAskCommunity.map { action in
            {
                openCommunityRequestAfterDismiss(
                    action,
                    expectedScanId: scanId,
                    expectedGeneration: presentationGeneration
                )
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                ConfidenceHeader(title: headerTitle)

                let candidates = visibleReviewCandidates
                let storedCandidateCount = storedCandidates.count
                let isExhausted = inferenceEngine.speciesData?.alternativesExhausted == true

                if isExhausted {
                    AllCandidatesReviewedView(
                        candidatesCount: storedCandidateCount,
                        onReviewAgain: {
                            guard isSubjectPresentationCurrent else { return }
                            isSwipeModalPresented = true
                        },
                        onReset: {
                            guard isSubjectPresentationCurrent else { return }
                            HapticManager.shared.triggerLightImpact()
                            Task { @MainActor in
                                guard isSubjectPresentationCurrent else { return }
                                await inferenceEngine.resetIdentificationReview(
                                    expectedScanId: scanId,
                                    modelContext: modelContext
                                )
                            }
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
                            guard isSubjectPresentationCurrent else { return }
                            HapticManager.shared.triggerLightImpact()
                            Task { @MainActor in
                                guard isSubjectPresentationCurrent else { return }
                                await inferenceEngine.resetIdentificationReview(
                                    expectedScanId: scanId,
                                    modelContext: modelContext
                                )
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if userConfirmedIdentification {
                    ConfirmedView(
                        onReset: {
                            guard isSubjectPresentationCurrent else { return }
                            HapticManager.shared.triggerLightImpact()
                            Task { @MainActor in
                                guard isSubjectPresentationCurrent else { return }
                                await inferenceEngine.resetIdentificationReview(
                                    expectedScanId: scanId,
                                    modelContext: modelContext
                                )
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if !candidates.isEmpty {

                    CandidatesCard(
                        candidates: candidates,
                        aiScientificName: aiScientificName ?? "Unknown subject",
                        inferenceTier: inferenceTier,
                        confirmButtonTitle: confirmButtonTitle,
                        onAskCommunity: communityRequestAction,
                        onMatchConfirmed: nil,
                        onRefineScan: refinementAction,
                        showDismissButton: false
                    )
                    .padding(.horizontal, 16)
                }

                let onReanalyze = refinementAction
                let onAskCommunity = communityRequestAction
                if onReanalyze != nil || onAskCommunity != nil {
                    ConfidenceSheetActionButtons(
                        isReanalyzeLocked: !revenueCatManager.isProActive,
                        onReanalyze: onReanalyze,
                        onAskCommunity: onAskCommunity
                    )
                    .padding(.horizontal, 16)
                }

                if !userConfirmedIdentification && userIdentificationOverride == nil {
                    ConfidenceSpectrum(inferenceTier: inferenceTier)
                }

                if !revenueCatManager.isProActive {
                    PlanCard(showPaywall: $showPaywall)
                        .padding(.horizontal, 16)
                }

                ProTips(showLocationPrompt: showLocationPrompt)
            }
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .sheet(isPresented: swipeModalPresentedBinding) {
            CandidateSwipeModal(
                isPresented: swipeModalPresentedBinding,
                scanId: scanId,
                presentationGeneration: presentationGeneration,
                candidates: swipeModalCandidates,
                aiScientificName: aiScientificName ?? "Unknown",
                confirmButtonTitle: confirmButtonTitle,
                onConfirmOriginal: {
                    guard isSubjectPresentationCurrent else { return }
                    Task { @MainActor in
                        guard isSubjectPresentationCurrent else { return }
                        await inferenceEngine.confirmAIIdentification(
                            expectedScanId: scanId,
                            modelContext: modelContext
                        )
                    }
                },
                onAskCommunity: communityRequestAction,
                onRefineScan: refinementAction
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onChange(of: inferenceEngine.scanPresentationGeneration) {
            guard !isSubjectPresentationCurrent else { return }
            isSwipeModalPresented = false
            showPaywall = false
            localRefinementRecord = nil
        }
        .task(id: presentationGeneration) {
            guard isSubjectPresentationCurrent else {
                localRefinementRecord = nil
                return
            }
            let descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            if let record = try? modelContext.fetch(descriptor).first,
               isSubjectPresentationCurrent,
               record.id.caseInsensitiveCompare(scanId) == .orderedSame {
                localRefinementRecord = record
            } else {
                localRefinementRecord = nil
            }
        }
    }

    private func openCommunityRequestAfterDismiss(
        _ action: @escaping () -> Void,
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard expectedGeneration == presentationGeneration,
              expectedScanId.caseInsensitiveCompare(scanId) == .orderedSame,
              isSubjectPresentationCurrent else {
            return
        }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard expectedGeneration == presentationGeneration,
                  expectedScanId.caseInsensitiveCompare(scanId) == .orderedSame,
                  isSubjectPresentationCurrent else {
                return
            }
            action()
        }
    }

    private var swipeModalPresentedBinding: Binding<Bool> {
        Binding(
            get: { isSwipeModalPresented && isSubjectPresentationCurrent },
            set: { isPresented in
                guard !isPresented || isSubjectPresentationCurrent else { return }
                isSwipeModalPresented = isPresented
            }
        )
    }
}

private struct ConfidenceSheetActionButtons: View {
    let isReanalyzeLocked: Bool
    var onReanalyze: (() -> Void)?
    var onAskCommunity: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            if let onReanalyze {
                Button(action: onReanalyze) {
                    Label(
                        "Reanalyze species",
                        systemImage: isReanalyzeLocked ? "lock.fill" : "arrow.2.circlepath"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange.opacity(0.14))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfidenceSheetReanalyzeButton")
            }

            if let onAskCommunity {
                Button {
                    HapticManager.shared.triggerMediumPulse()
                    onAskCommunity()
                } label: {
                    Label("Ask the community", systemImage: "person.2")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue.opacity(0.14))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfidenceSheetAskCommunityButton")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
