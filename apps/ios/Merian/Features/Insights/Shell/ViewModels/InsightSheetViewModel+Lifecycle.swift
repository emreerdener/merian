import SwiftData
import SwiftUI

extension InsightSheetViewModel {
    // MARK: - Lifecycle Handlers

    func evaluateVoiceOverAndCelebration(inferenceEngine: InferenceEngine) {
        let hazardType = inferenceEngine.speciesData?.insightData.hazardType ?? "none"
        let commonName: String
        if let speciesData = inferenceEngine.speciesData,
           speciesData.isInferenceErrorPlaceholder {
            let trimmedName = speciesData.commonName.trimmingCharacters(in: .whitespacesAndNewlines)
            commonName = trimmedName.isEmpty ? "Analysis unavailable" : trimmedName
        } else {
            commonName = inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..."
        }

        if UIAccessibility.isVoiceOverRunning {
            let hazardWarning: String
            switch hazardType {
            case "venomous":   hazardWarning = "Warning: This species is venomous."
            case "allergenic": hazardWarning = "Warning: This species may trigger allergic reactions."
            case "irritant":   hazardWarning = "Warning: This species may cause skin or eye irritation."
            case "poisonous":  hazardWarning = "Warning: This species is toxic."
            default:           hazardWarning = ""
            }
            let announcement = hazardWarning.isEmpty ? commonName : "\(commonName). \(hazardWarning)"
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }

    }

    func evaluateProcessingCompletion(isStillProcessing: Bool, inferenceEngine: InferenceEngine, modelContext: ModelContext) {
        guard !isStillProcessing else { return }

        if let data = inferenceEngine.speciesData,
           !data.isInferenceErrorPlaceholder {
            HapticManager.shared.triggerHeavyImpact(source: "insight.analysis.completed")
        }

        markRecordViewedIfAppropriate(modelContext: modelContext)

        // The sheet was opened before inference completed, so onAppear saw nil speciesData.
        // Re-evaluate celebration and VoiceOver now that data has arrived.
        evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
        if let data = inferenceEngine.speciesData {
            if data.isBiological && !appSettings.hasSeenExploreOnboarding {
                guard let scanId = presentedLocalRecordScanId else {
                    cancelDelayedExploreOnboardingPresentation()
                    return
                }
                let generation = scanBoundActionGeneration
                scheduleDelayedExploreOnboardingPresentation(
                    scanId: scanId,
                    generation: generation
                )
            } else {
                cancelDelayedExploreOnboardingPresentation()
                if data.isClassifiedNonBiological {
                    let scanId = presentedLocalRecordScanId
                    let generation = scanBoundActionGeneration
                    self.state.toastMessage = .success(
                        "Scan succeeded. Added to non-biological collection.",
                        action: .viewNonBiologicalScans
                    )
                    self.toastAction = { [weak self] in
                        guard let self,
                              let scanId,
                              self.isPresentingLocalRecord(
                                  scanId: scanId,
                                  generation: generation
                              ) else {
                            return
                        }
                        AppDIContainer.shared.appRouteCoordinator.request(
                            .nonBiologicalScans,
                            source: .internalUserAction
                        )
                    }
                }
            }
        }
    }

    private func scheduleDelayedExploreOnboardingPresentation(
        scanId: String,
        generation: UInt64
    ) {
        if exploreOnboardingPresentationTask != nil,
           exploreOnboardingPresentationScanID?.caseInsensitiveCompare(scanId) == .orderedSame,
           exploreOnboardingPresentationGeneration == generation {
            return
        }

        cancelDelayedExploreOnboardingPresentation()
        let taskID = UUID()
        exploreOnboardingPresentationTaskID = taskID
        exploreOnboardingPresentationScanID = scanId
        exploreOnboardingPresentationGeneration = generation
        exploreOnboardingPresentationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard let self else { return }
            defer {
                if self.exploreOnboardingPresentationTaskID == taskID {
                    self.exploreOnboardingPresentationTask = nil
                    self.exploreOnboardingPresentationTaskID = nil
                    self.exploreOnboardingPresentationScanID = nil
                    self.exploreOnboardingPresentationGeneration = nil
                }
            }
            guard self.exploreOnboardingPresentationTaskID == taskID,
                  !Task.isCancelled,
                  self.isPresentingLocalRecord(
                              scanId: scanId,
                              generation: generation
                  ),
                  self.canShareToExplore,
                  self.shareRecommendation == .publishToExplore,
                  !self.appSettings.hasSeenExploreOnboarding else { return }

            self.appSettings.hasSeenExploreOnboarding = true
            self.state.exploreOnboardingPresentationScanId = scanId
            self.state.exploreOnboardingPresentationGeneration = generation
            self.state.showExploreOnboarding = true
        }
    }

    func cancelDelayedExploreOnboardingPresentation() {
        exploreOnboardingPresentationTask?.cancel()
        exploreOnboardingPresentationTask = nil
        exploreOnboardingPresentationTaskID = nil
        exploreOnboardingPresentationScanID = nil
        exploreOnboardingPresentationGeneration = nil
    }
}
