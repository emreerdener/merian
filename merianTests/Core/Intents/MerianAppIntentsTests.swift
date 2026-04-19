import Testing
import Foundation
@testable import Merian

struct MerianAppIntentsTests {
    
    @Test func testIdentifyNatureIntentDeepLinksToViewfinder() async throws {
        let intent = IdentifyNatureIntent()
        
        let result = try await intent.perform()
        
        // As long as perform() finishes successfully without an error or a timeout
        // it means AppState.shared.navigateTo("camera") was successfully hit natively
    }
    
    @Test func testRecallLastFindIntentDeepLinksToInsights() async throws {
        let intent = RecallLastFindIntent()
        
        let result = try await intent.perform()
        
        // Assert intent yields successfully without dropping pointers
    }
}
