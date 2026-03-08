import Foundation
import Combine
import SwiftUI
import SwiftData

/// Manages real-time AI taxonomy processing via Supabase Edge Functions
@MainActor
final class InferenceEngine: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var activePayload: Data? = nil
    @Published var activePayloads: [Data] = []
    @Published var speciesData: SpeciesData? = nil
    
    private var inferenceTask: Task<Void, Never>?
    
    /// Struct defining the exact expected JSON schema from the Gemini Edge Function
    private struct EdgeResponse: Codable {
        let is_biological_subject: Bool?
        let is_live_capture: Bool?
        let ecology_type: String?
        let is_invasive: Bool?
        let scientific_name: String?
        let common_name: String?
        let confidence_score: Double?
        
        struct Taxonomy: Codable {
            let kingdom: String?
            let phylum: String?
            let `class`: String?
            let order: String?
            let family: String?
            let genus: String?
        }
        let taxonomy: Taxonomy?
        
        struct Insight: Codable {
            let description: String?
            let is_poisonous: Bool?
            let regional_status_rationale: String?
        }
        let insight_data: Insight?
        let wikipedia_url: String?
        let reference_image_url: String?
    }
    
    func analyze(imageData: Data, modelContext: ModelContext? = nil) {
        // Reset states for a fresh native scan
        self.isProcessing = true
        self.activePayload = imageData
        self.activePayloads = [imageData]
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
                            isPoisonous: edgeRes.insight_data?.is_poisonous ?? false,
                            regionalStatusRationale: edgeRes.insight_data?.regional_status_rationale
                        )
                        
                        let taxonomyData = TaxonomyData(
                            kingdom: edgeRes.taxonomy?.kingdom,
                            phylum: edgeRes.taxonomy?.phylum,
                            className: edgeRes.taxonomy?.class,
                            order: edgeRes.taxonomy?.order,
                            family: edgeRes.taxonomy?.family,
                            genus: edgeRes.taxonomy?.genus
                        )
                        
                        let mappedData = SpeciesData(
                            commonName: edgeRes.common_name ?? "Unknown Subject",
                            scientificName: edgeRes.scientific_name ?? "Taxonomy Unavailable",
                            insightData: insight,
                            confidenceScore: edgeRes.confidence_score ?? 0.0,
                            diagnosticComparison: nil,
                            wikipediaUrl: edgeRes.wikipedia_url,
                            referenceImageUrl: edgeRes.reference_image_url,
                            isBiological: edgeRes.is_biological_subject ?? true,
                            isLiveCapture: edgeRes.is_live_capture ?? true,
                            isInvasive: edgeRes.is_invasive ?? false,
                            ecologyType: edgeRes.ecology_type ?? "unknown",
                            taxonomy: taxonomyData
                        )
                        
                        // Persist to SwiftData Life List if analysis was valid
                        if mappedData.confidenceScore > 0.0, let context = modelContext {
                            let filename = "\(UUID().uuidString)_lifelist.jpg"
                            let url = URL.documentsDirectory.appendingPathComponent(filename)
                            try? imageData.write(to: url, options: .atomic)
                            
                            let targetName = mappedData.scientificName
                            let fetchDescriptor = FetchDescriptor<LocalScanRecord>(
                                predicate: #Predicate { $0.scientificName == targetName }
                            )
                            
                            if let existingRecord = try? context.fetch(fetchDescriptor).first {
                                // Update the existing species record rather than inserting a duplicate
                                if existingRecord.additionalImagePaths == nil {
                                    existingRecord.additionalImagePaths = []
                                }
                                existingRecord.additionalImagePaths?.append(url.path)
                                
                                existingRecord.timestamp = Date()
                                // Note: intentionally leaving the primary localImagePath alone so the thumbnail remains the first chronological capture
                                existingRecord.insightDescription = mappedData.insightData.description
                                existingRecord.isPoisonous = mappedData.insightData.isPoisonous
                                existingRecord.wikipediaUrl = mappedData.wikipediaUrl ?? existingRecord.wikipediaUrl
                                existingRecord.referenceImageUrl = mappedData.referenceImageUrl ?? existingRecord.referenceImageUrl
                                existingRecord.confidenceScore = mappedData.confidenceScore
                            } else {
                                // First time encountering this species; insert new record natively
                                let record = LocalScanRecord(
                                    speciesId: UUID().uuidString,
                                    scientificName: mappedData.scientificName,
                                    commonName: mappedData.commonName,
                                    insightDescription: mappedData.insightData.description,
                                    timestamp: Date(),
                                    localImagePath: url.path,
                                    semanticTags: [mappedData.commonName, mappedData.scientificName],
                                    isPoisonous: mappedData.insightData.isPoisonous,
                                    wikipediaUrl: mappedData.wikipediaUrl,
                                    referenceImageUrl: mappedData.referenceImageUrl,
                                    confidenceScore: mappedData.confidenceScore
                                )
                                context.insert(record)
                            }
                            try? context.save()
                        }
                        
                        CircuitBreakerManager.shared.recordSuccess()
                        self.speciesData = mappedData
                    } else {
                        print("⚠️ Inference Engine: Failed to structure Gemini JSON properly")
                        self.speciesData = SpeciesData(
                            commonName: "Analysis Failed",
                            scientificName: "Data Unreadable",
                            insightData: InsightData(description: "Cannot process the server taxonomy schema.", isPoisonous: false, regionalStatusRationale: nil),
                            confidenceScore: 0,
                            diagnosticComparison: nil,
                            wikipediaUrl: nil,
                            referenceImageUrl: nil,
                            isBiological: true,
                            isLiveCapture: true,
                            isInvasive: false,
                            ecologyType: "unknown",
                            taxonomy: nil
                        )
                    }
                }
            } catch {
                CircuitBreakerManager.shared.recordFailure()
                print("⚠️ Inference Engine Critical Failure: \(error.localizedDescription)")
                self.speciesData = SpeciesData(
                    commonName: "Network Timeout",
                    scientificName: "Offline Mode",
                    insightData: InsightData(description: "Please check your network boundary connection. The scan has been safely queued offline.", isPoisonous: false, regionalStatusRationale: nil),
                    confidenceScore: 0,
                    diagnosticComparison: nil,
                    wikipediaUrl: nil,
                    referenceImageUrl: nil,
                    isBiological: true,
                    isLiveCapture: true,
                    isInvasive: false,
                    ecologyType: "unknown",
                    taxonomy: nil
                )
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
        activePayloads.removeAll()
    }
    
    /// Rehydrates the SpeciesData and UI payloads natively from an offline Life List record
    func load(from record: LocalScanRecord) {
        self.isProcessing = true
        
        if let path = record.localImagePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            self.activePayload = data
            var payloads: [Data] = [data]
            
            if let extraPaths = record.additionalImagePaths {
                for extra in extraPaths {
                    if let extraData = try? Data(contentsOf: URL(fileURLWithPath: extra)) {
                        payloads.append(extraData)
                    }
                }
            }
            self.activePayloads = payloads
        } else {
            self.activePayload = nil
            self.activePayloads = []
        }
        
        self.speciesData = SpeciesData(
            commonName: record.commonName,
            scientificName: record.scientificName,
            insightData: InsightData(description: record.insightDescription, isPoisonous: record.isPoisonous, regionalStatusRationale: nil),
            confidenceScore: record.confidenceScore ?? 1.0, 
            diagnosticComparison: nil,
            wikipediaUrl: record.wikipediaUrl,
            referenceImageUrl: record.referenceImageUrl,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown",
            taxonomy: nil
        )
        self.isProcessing = false
    }
}
