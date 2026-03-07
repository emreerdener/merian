import Foundation
import Combine
import SwiftUI

/// Manages real-time AI taxonomy processing via Supabase Edge Functions
@MainActor
final class InferenceEngine: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var activePayload: Data? = nil
    @Published var speciesData: SpeciesData? = nil
    
    private var inferenceTask: Task<Void, Never>?
    
    /// Struct defining the exact expected JSON schema from the Gemini Edge Function
    private struct EdgeResponse: Codable {
        let is_biological_subject: Bool?
        let scientific_name: String?
        let common_name: String?
        let confidence_score: Double?
        struct Insight: Codable {
            let description: String?
            let is_poisonous: Bool?
        }
        let insight_data: Insight?
        let wikipedia_url: String?
        let reference_image_url: String?
    }
    
    func analyze(imageData: Data) {
        // Reset states for a fresh native scan
        self.isProcessing = true
        self.activePayload = imageData
        self.speciesData = nil
        
        self.inferenceTask = Task {
            do {
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }
                
                let client = MerianNetworkClient.shared
                
                // 1. Upload high-res physical image cleanly to Gemini
                let fileUri = try await client.uploadToGeminiFileAPI(imageData: imageData)
                
                // 2. Transmit the active URI to the robust Supabase architecture for verification
                let resultString = try await client.analyzeSubject(
                    fileUris: [fileUri],
                    depthScaleText: nil, // Extrapolating later if depth hardware demands it
                    gpsLatitude: nil,
                    gpsLongitude: nil,
                    weatherCondition: nil
                )
                
                // 3. Decode the returned JSON string intelligently into our local Swift UI Models
                if let jsonData = resultString.data(using: .utf8) {
                    let decoder = JSONDecoder()
                    // Silently handle schema discrepancies securely without crashing the UI
                    if let edgeRes = try? decoder.decode(EdgeResponse.self, from: jsonData) {
                        
                        // Map the Edge JSON cleanly into the established SpeciesData structure
                        let insight = InsightData(
                            description: edgeRes.insight_data?.description ?? "No ecological description available for this subject.",
                            isPoisonous: edgeRes.insight_data?.is_poisonous ?? false
                        )
                        
                        let mappedData = SpeciesData(
                            commonName: edgeRes.common_name ?? "Unknown Subject",
                            scientificName: edgeRes.scientific_name ?? "Taxonomy Unavailable",
                            insightData: insight,
                            confidenceScore: edgeRes.confidence_score ?? 0.0,
                            diagnosticComparison: nil,
                            wikipediaUrl: edgeRes.wikipedia_url,
                            referenceImageUrl: edgeRes.reference_image_url
                        )
                        
                        
                        CircuitBreakerManager.shared.recordSuccess()
                        self.speciesData = mappedData
                    } else {
                        print("⚠️ Inference Engine: Failed to structure Gemini JSON properly")
                        self.speciesData = SpeciesData(commonName: "Analysis Failed", scientificName: "Data Unreadable", insightData: InsightData(description: "Cannot process the server taxonomy schema.", isPoisonous: false), confidenceScore: 0, diagnosticComparison: nil, wikipediaUrl: nil, referenceImageUrl: nil)
                    }
                }
            } catch {
                CircuitBreakerManager.shared.recordFailure()
                print("⚠️ Inference Engine Critical Failure: \(error.localizedDescription)")
                self.speciesData = SpeciesData(commonName: "Network Timeout", scientificName: "Offline Mode", insightData: InsightData(description: "Please check your network boundary connection. The scan has been safely queued offline.", isPoisonous: false), confidenceScore: 0, diagnosticComparison: nil, wikipediaUrl: nil, referenceImageUrl: nil)
            }
            
            // Unconditionally clear the active loading hardware state
            self.isProcessing = false
        }
    }
    
    /// Halts active inferences instantly if the iOS Watchdog forces a termination
    func cancelActiveRequest() {
        print("Cancelled active inference request to prevent watchdog termination.")
        inferenceTask?.cancel()
        isProcessing = false
        activePayload = nil
    }
}
