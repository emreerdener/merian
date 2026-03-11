import Foundation
import Combine
import SwiftUI
import SwiftData
import ImageIO

/// Manages real-time AI taxonomy processing via Supabase Edge Functions
@MainActor
final class InferenceEngine: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var activePayload: Data? = nil
    @Published var activeCompressedPayload: Data? = nil
    @Published var activePayloads: [String] = []
    @Published var speciesData: SpeciesData? = nil
    private(set) var activeLatitude: Double? = nil
    private(set) var activeLongitude: Double? = nil
    private(set) var activeElevation: Double? = nil
    private(set) var activeWeatherCondition: String? = nil
    private(set) var activeTemperatureF: Double? = nil
    
    private var inferenceTask: Task<Void, Never>?
    
    /// Wrapper preventing double string decoding JSON extraction logic
    struct EdgeResponseWrapper: Codable {
        let success: Bool?
        let data: EdgeResponse
    }
    
    /// Struct defining the exact expected JSON schema from the Gemini Edge Function
    struct EdgeResponse: Codable {
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
    

    
    func analyze(imageData: Data, gpsLatitude: Double? = nil, gpsLongitude: Double? = nil, gpsElevation: Double? = nil, weatherCondition: String? = nil, weatherTemperatureF: Double? = nil, modelContext: ModelContext? = nil) {
        // Reset states for a fresh native scan
        self.isProcessing = true
        self.activePayload = imageData
        self.activeCompressedPayload = nil
        self.activePayloads = []
        self.speciesData = nil
        
        self.activeLatitude = gpsLatitude
        self.activeLongitude = gpsLongitude
        self.activeElevation = gpsElevation
        self.activeWeatherCondition = weatherCondition
        self.activeTemperatureF = weatherTemperatureF
        
        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 1. Data is already safely compressed from camera cropper directly
            let compressedData = imageData
            self.activeCompressedPayload = compressedData
            
            do {
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }
                
                let client = MerianNetworkClient.shared
                
                // 2. Request Secure Cloudflare R2 Staging URL
                let presignedUrls = try await client.generateUploadURLs(fileNames: ["live_scan.jpg"])
                guard let target = presignedUrls.first else {
                    throw URLError(.badServerResponse)
                }
                
                // 3. Upload bytes to R2 (compressed)
                try await client.uploadToR2(url: target.signedUrl, data: compressedData)
                
                // 3. Transmit the Object Key to the robust Supabase architecture for verification
                // 3. Transmit the Object Key to the robust Supabase architecture for verification
                let resultData = try await client.analyzeSubject(
                    r2ObjectKey: target.objectKey,
                    depthScaleText: nil, // Extrapolating later if depth hardware demands it
                    gpsLatitude: gpsLatitude,
                    gpsLongitude: gpsLongitude,
                    gpsElevation: gpsElevation,
                    weatherCondition: weatherCondition,
                    weatherTemperatureF: weatherTemperatureF
                )
                
                // 4. Decode the returned raw bytes intelligently into our local Swift UI Models bypassing stringification payloads entirely
                let decoder = JSONDecoder()
                if let parsedWrapper = try? decoder.decode(EdgeResponseWrapper.self, from: resultData) {
                    let edgeRes = parsedWrapper.data
                        
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
                            await Task.detached(priority: .userInitiated) {
                                try? compressedData.write(to: url, options: .atomic)
                            }.value
                            
                            let targetName = mappedData.scientificName
                            let fetchDescriptor = FetchDescriptor<LocalScanRecord>(
                                predicate: #Predicate { $0.scientificName == targetName }
                            )
                            
                            if let existingRecord = try? context.fetch(fetchDescriptor).first {
                                // Update the existing species record rather than inserting a duplicate
                                if existingRecord.additionalImagePaths == nil {
                                    existingRecord.additionalImagePaths = []
                                }
                                existingRecord.additionalImagePaths?.append(filename)
                                
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
                                    localImagePath: filename,
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
                        UsageManager.shared.recordSuccessfulScan()
                        GamificationManager.shared.recordNewSpeciesDiscovered()
                        AppTelemetry.trackScan(isPro: RevenueCatManager.shared.isProActive)
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
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.isProcessing = false
                    return
                }
                CircuitBreakerManager.shared.recordFailure()
                OfflineQueueManager.shared.enqueueCapture(
                    imageData: compressedData,
                    gpsLatitude: gpsLatitude,
                    gpsLongitude: gpsLongitude,
                    gpsElevation: gpsElevation,
                    weatherCondition: weatherCondition,
                    weatherTemperatureF: weatherTemperatureF
                )
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
        activeCompressedPayload = nil
        activePayloads.removeAll()
        activeLatitude = nil
        activeLongitude = nil
        activeElevation = nil
        activeWeatherCondition = nil
        activeTemperatureF = nil
    }
    
    /// Rehydrates the SpeciesData and UI payloads natively from an offline Life List record
    func load(from record: LocalScanRecord) {
        self.isProcessing = true
        
        self.activePayload = nil
        var paths: [String] = []
        if let localPath = record.localImagePath {
            paths.append(localPath)
        }
        if let extras = record.additionalImagePaths {
            paths.append(contentsOf: extras)
        }
        self.activePayloads = paths
        
        let commonName = record.commonName
        let scientificName = record.scientificName
        let insightDescription = record.insightDescription
        let isPoisonous = record.isPoisonous
        let confidenceScore = record.confidenceScore ?? 1.0
        let wikipediaUrl = record.wikipediaUrl
        let referenceImageUrl = record.referenceImageUrl
        
        self.speciesData = SpeciesData(
            commonName: commonName,
            scientificName: scientificName,
            insightData: InsightData(description: insightDescription, isPoisonous: isPoisonous, regionalStatusRationale: nil),
            confidenceScore: confidenceScore, 
            diagnosticComparison: nil,
            wikipediaUrl: wikipediaUrl,
            referenceImageUrl: referenceImageUrl,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown",
            taxonomy: nil
        )
        self.isProcessing = false
    }
    
    nonisolated private func downsampleLocalPayload(data: Data, maxDimension: CGFloat = 1024.0) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
        let thumbnail = UIImage(cgImage: cgImage)
        return thumbnail.jpegData(compressionQuality: 0.7)
    }
}
