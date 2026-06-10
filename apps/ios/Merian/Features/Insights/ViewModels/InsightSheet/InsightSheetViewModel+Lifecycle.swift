import SwiftData
import SwiftUI

extension InsightSheetViewModel {
    // MARK: - Lifecycle Handlers

    func evaluateVoiceOverAndCelebration(inferenceEngine: InferenceEngine) {
        let hazardType = inferenceEngine.speciesData?.insightData.hazardType ?? "none"
        let commonName = inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..."

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

        if let data = inferenceEngine.speciesData, data.isNewDiscovery {
            let lowerName = data.commonName.lowercased()
            if data.isBiological && lowerName != "not applicable" && lowerName != "unknown subject" && lowerName != "inanimate object" {
                state.showCelebration = true
            }
        }
    }

    func evaluateProcessingCompletion(isStillProcessing: Bool, inferenceEngine: InferenceEngine, modelContext: ModelContext) {
        guard !isStillProcessing else { return }

        markRecordViewedIfAppropriate(modelContext: modelContext)

        // The sheet was opened before inference completed, so onAppear saw nil speciesData.
        // Re-evaluate celebration and VoiceOver now that data has arrived.
        evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
        if let data = inferenceEngine.speciesData {
            let lowerName = data.commonName.lowercased()
            let isValidCelebration = data.isNewDiscovery && data.isBiological
                && lowerName != "not applicable"
                && lowerName != "unknown subject"
                && lowerName != "inanimate object"
            if !isValidCelebration {
                HapticManager.shared.triggerSheetSpring()
            }
            
            if data.isBiological && !appSettings.hasSeenExploreOnboarding {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    if self.canShareToExplore && !self.appSettings.hasSeenExploreOnboarding {
                        self.appSettings.hasSeenExploreOnboarding = true
                        withAnimation {
                            self.state.showExploreOnboarding = true
                        }
                    }
                }
            } else if !data.isBiological {
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
}
