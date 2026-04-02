import Testing
import Foundation
@testable import Merian

struct MerianConfigTests {
    
    @Test func testInferenceImageMaxSizeResolvesTargetDimensions() {
        // Act & Assert
        let proSize = MerianConfig.inferenceImageMaxSize(isProActive: true)
        let freeSize = MerianConfig.inferenceImageMaxSize(isProActive: false)
        
        #expect(proSize == 1024.0, "Pro subscriptions must target 1024px maximum long-edge dimension")
        #expect(freeSize == 768.0, "Free subscriptions must cap at 768px maximum long-edge dimension to save tokens")
    }
    
    @Test func testConfidenceBandsResolveByTier() {
        // Act
        let proBands = MerianConfig.confidenceBands(forInferenceTier: "pro")
        let flashBands = MerianConfig.confidenceBands(forInferenceTier: "flash")
        
        // Assert Pro uses a more relaxed boundary because it's highly calibrated
        #expect(proBands.strong == 0.85)
        #expect(proBands.possible == 0.65)
        #expect(proBands.diagnosticTrigger == 0.85)
        
        // Assert Flash uses a strict boundary because it's fast and slightly overconfident
        #expect(flashBands.strong == 0.96)
        #expect(flashBands.possible == 0.75)
        #expect(flashBands.diagnosticTrigger == 0.96)
    }
    
    @Test func testMissingTierFallsBackToFlashBandsGracefully() {
        // Act
        let standardBands = MerianConfig.confidenceBands(forInferenceTier: nil)
        
        // Assert
        #expect(standardBands.strong == 0.96) // Maps to Flash defaults safely
    }
}
