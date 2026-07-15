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

        if shouldPresentNewToMerianMilestone(for: inferenceEngine.speciesData) {
            state.hasPresentedNewToMerianMilestone = true
            MilestoneToastPresenter.shared.enqueueNewToMerianMilestone()
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
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    if self.canShareToExplore,
                       self.shareRecommendation == .publishToExplore,
                       !self.appSettings.hasSeenExploreOnboarding {
                        self.appSettings.hasSeenExploreOnboarding = true
                        withAnimation {
                            self.state.showExploreOnboarding = true
                        }
                    }
                }
            } else if data.isClassifiedNonBiological {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    self.state.toastMessage = "Scan succeeded. Added to non-biological collection."
                    self.toastActionTitle = "View"
                    self.toastAction = {
                        AppEventPublisher.shared.send(.requestOpenNonBiologicalScansIntent)
                    }
                }
            }
        }
    }

    private func shouldPresentNewToMerianMilestone(for data: SpeciesData?) -> Bool {
        guard !state.hasPresentedNewToMerianMilestone, let data else { return false }
        return isValidNewToMerianMilestone(data)
    }

    private func isValidNewToMerianMilestone(_ data: SpeciesData) -> Bool {
        let lowerName = data.commonName.lowercased()
        return data.isNewToMerianDictionary
            && data.isBiological
            && lowerName != "not applicable"
            && lowerName != "unknown subject"
            && lowerName != "inanimate object"
    }
}
