import Foundation
import CoreImage
import Combine
import SwiftUI
import SwiftData
import ImageIO

enum APIError: Error {
    case proRequiredForOfflineTracking
    case decodingFailed
}

/// Manages real-time AI taxonomy processing via Supabase Edge Functions
@MainActor
final class InferenceEngine: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var activeImageData: Data? = nil
    @Published var activeCompressedImageData: Data? = nil
    @Published var activeImageDatas: [String] = []
    @Published var validHistoricImagePaths: [String] = []
    @Published var speciesData: SpeciesData? = nil
    private(set) var activeLatitude: Double? = nil
    private(set) var activeLongitude: Double? = nil
    private(set) var activeElevation: Double? = nil
    private(set) var activeLocationName: String? = nil
    private(set) var activeWeatherCondition: String? = nil
    private(set) var activeTemperatureF: Double? = nil
    private(set) var activePitchDegrees: Double? = nil
    private(set) var activeCompassHeading: Double? = nil
    private(set) var activeRelativeHumidity: Double? = nil
    private(set) var activeUvIndex: Int? = nil
    private(set) var activeFlashFired: Bool? = nil
    private(set) var activeDistanceInMeters: Float? = nil
    
    private var inferenceTask: Task<Void, Error>?
    public var isBackgroundRescued = false
    
    /// Wrapper preventing double string decoding JSON extraction logic
    struct EdgeResponseWrapper: Codable {
        let success: Bool?
        let data: EdgeResponse
    }
    
    /// Struct defining the exact expected JSON schema from the Gemini Edge Function
    struct EdgeResponse: Codable {
        let scan_id: String?
        let is_biological_subject: Bool?
        let is_live_capture: Bool?
        let ecology_type: String?
        let is_invasive: Bool?
        let scientific_name: String?
        let common_name: String?
        let confidence_score: Double?
        let colors: [String]?
        
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
        struct Diagnostic: Codable {
            let primary_match_rationale: String?
            let confusing_lookalike_name: String?
            let key_differentiators: [String]?
        }
        let diagnostic_comparison: Diagnostic?
        let wikipedia_url: String?
        let wikipedia_extract: String?
        let reference_image_url: String?
    }    

    
    func analyze(imageData: Data, telemetry: CaptureTelemetry, modelContext: ModelContext? = nil) {
        self.inferenceTask?.cancel()
        
        // Reset states for a fresh native scan
        self.isProcessing = true
        self.activeImageData = imageData
        self.activeCompressedImageData = nil
        self.activeImageDatas = []
        self.validHistoricImagePaths = []
        self.speciesData = nil
        self.isBackgroundRescued = false
        
        self.activeLatitude = telemetry.gpsLatitude
        self.activeLongitude = telemetry.gpsLongitude
        self.activeElevation = telemetry.gpsElevation
        self.activeLocationName = telemetry.locationName
        self.activeWeatherCondition = telemetry.weatherCondition
        self.activeTemperatureF = telemetry.weatherTemperatureF
        self.activePitchDegrees = telemetry.cameraPitchDegrees
        self.activeCompassHeading = telemetry.compassHeading
        self.activeRelativeHumidity = telemetry.relativeHumidity
        self.activeUvIndex = telemetry.uvIndex
        self.activeFlashFired = telemetry.isFlashFired
        self.activeDistanceInMeters = telemetry.subjectDistanceInMeters
        
        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }
            
            let boundaryStartTime = CFAbsoluteTimeGetCurrent()
            
            // 1. Data is already safely compressed from camera cropper directly
            let compressedData = imageData
            self.activeCompressedImageData = compressedData
            
            do {
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }
                
                let client = MerianNetworkClient.shared
                
                // 2. Convert Data to structural base64 string
                let base64String = compressedData.base64EncodedString()
                let targetObjectKey = "staging/\(UUID().uuidString).jpg"
                
                try Task.checkCancellation() 
                
                // 3. Transmit the payload directly skipping R2 hops entirely
                let inferenceStartTime = CFAbsoluteTimeGetCurrent()
                let resultData = try await client.analyzeSubject(
                    r2ObjectKey: targetObjectKey,
                    base64ImageData: base64String,
                    telemetry: telemetry
                )
                let inferenceTime = CFAbsoluteTimeGetCurrent() - inferenceStartTime
                print("⏱️ [Performance] Gemini Edge Inference completed in \(String(format: "%.3f", inferenceTime)) seconds.")
                
                // 4. Decode the returned raw bytes intelligently into our local Swift UI Models bypassing stringification payloads entirely
                let container = modelContext?.container
                let (finalMappedData, isNewDisc) = try await Task.detached(priority: .userInitiated) { () -> (SpeciesData?, Bool) in
                    let decoder = JSONDecoder()
                    
                    let parsedWrapper: EdgeResponseWrapper
                    do {
                        parsedWrapper = try decoder.decode(EdgeResponseWrapper.self, from: resultData)
                    } catch let error as DecodingError {
                        print("⚠️ AI JSON Payload Hallucination / Decoding Error: \(error.localizedDescription)")
                        throw APIError.decodingFailed
                    }
                    
                    let edgeRes = parsedWrapper.data
                    
                    let mappedData = SpeciesData(
                        fromEdgeResponse: edgeRes,
                        locationName: telemetry.locationName,
                        weatherCondition: telemetry.weatherCondition,
                        weatherTemperatureF: telemetry.weatherTemperatureF
                    )
                    
                    // CRITICAL FIX: Prevent phantom DB inserts by strictly validating Task cancellation before inserting!
                    // If the user triggered the offline queue or backed out mid-flight, this structurally aborts the detached thread.
                    try Task.checkCancellation()
                    
                    var newDiscovery = false
                    
                    // Persist to SwiftData Scans securely isolated via @ModelActor off the main thread bounds natively stopping EXC_BAD_ACCESS
                    if mappedData.confidenceScore > 0.0, let container = container {
                        let dbActor = BackgroundDatabaseActor(modelContainer: container)
                        newDiscovery = await dbActor.saveLiveScanRecord(mappedData: mappedData, compressedData: compressedData)
                    }
                    return (mappedData, newDiscovery)
                }.value
                
                if var mappedData = finalMappedData {
                    if isNewDisc {
                        mappedData.isNewDiscovery = true
                        GamificationManager.shared.recordNewSpeciesDiscovered()
                    }
                    CircuitBreakerManager.shared.recordSuccess()
                    AppTelemetry.trackScan(isPro: RevenueCatManager.shared.isProActive)
                    self.speciesData = mappedData
                    
                    let totalPipelineTime = CFAbsoluteTimeGetCurrent() - boundaryStartTime
                    print("⏱️ [Performance] Total Analysis Pipeline (Upload + AI + DB) executed in \(String(format: "%.3f", totalPipelineTime)) seconds!")
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.isProcessing = false
                    if !self.isBackgroundRescued {
                        UsageManager.shared.refundScan()
                    }
                    return
                }
                
                if let apiError = error as? APIError, apiError == .decodingFailed {
                    UsageManager.shared.refundScan()
                    self.speciesData = SpeciesData(
                        scanId: nil,
                        commonName: "Analysis Failed",
                        scientificName: "Data Unreadable",
                        insightData: InsightData(description: "The AI failed to understand the image or produced an unreadable schema.", isPoisonous: false, regionalStatusRationale: nil),
                        confidenceScore: 0,
                        diagnosticComparison: nil,
                        wikipediaUrl: nil,
                        wikipediaExtract: nil,
                        referenceImageUrl: nil,
                        isBiological: true,
                        isLiveCapture: true,
                        isInvasive: false,
                        ecologyType: "unknown",
                        taxonomy: nil,
                        locationName: telemetry.locationName,
                        weatherCondition: telemetry.weatherCondition,
                        weatherTemperatureF: telemetry.weatherTemperatureF,
                        colors: nil
                    )
                    self.isProcessing = false
                    return
                }
                
                if !RevenueCatManager.shared.isProActive {
                    await MainActor.run {
                        self.isProcessing = false
                        UsageManager.shared.refundScan()
                        NotificationCenter.default.post(name: NSNotification.Name("TriggerPaywall"), object: nil)
                    }
                    throw APIError.proRequiredForOfflineTracking
                }
                
                CircuitBreakerManager.shared.recordFailure()
                OfflineQueueManager.shared.enqueueCapture(
                    imageData: compressedData,
                    telemetry: telemetry,
                    blurScore: nil
                )
                print("⚠️ Inference Engine Critical Failure: \(error.localizedDescription)")
                self.speciesData = SpeciesData(
                    scanId: nil,
                    commonName: "Network Timeout",
                    scientificName: "Offline Mode",
                    insightData: InsightData(description: "Please check your network boundary connection. The scan has been safely queued offline.", isPoisonous: false, regionalStatusRationale: nil),
                    confidenceScore: 0,
                    diagnosticComparison: nil,
                    wikipediaUrl: nil,
                    wikipediaExtract: nil,
                    referenceImageUrl: nil,
                    isBiological: true,
                    isLiveCapture: true,
                    isInvasive: false,
                    ecologyType: "unknown",
                    taxonomy: nil,
                    locationName: telemetry.locationName,
                    weatherCondition: telemetry.weatherCondition,
                    weatherTemperatureF: telemetry.weatherTemperatureF
                )
            }
            
            // Unconditionally clear the active loading hardware state
            self.isProcessing = false
        }
    }
    

    
    /// Halts active inferences instantly if the iOS Watchdog forces a termination
    func cancelActiveRequest() {
        print("Cancelled active inference request to prevent watchdog termination.")
        isBackgroundRescued = true
        inferenceTask?.cancel()
        isProcessing = false
        activeImageData = nil
        activeCompressedImageData = nil
        activeImageDatas.removeAll()
        validHistoricImagePaths.removeAll()
        activeLatitude = nil
        activeLongitude = nil
        activeElevation = nil
        activeLocationName = nil
        activeWeatherCondition = nil
        activeTemperatureF = nil
    }
    
    /// Rehydrates the SpeciesData and UI payloads natively from an offline Scans record
    func load(from record: LocalScanRecord) {
        self.isProcessing = true
        
        self.activeImageData = nil
        var paths: [String] = []
        if let localPath = record.localImagePath {
            paths.append(localPath)
        }
        if let extras = record.additionalImagePaths {
            paths.append(contentsOf: extras)
        }
        self.activeImageDatas = paths
        
        Task {
            let validPaths = await Task.detached(priority: .userInitiated) {
                paths.filter { path in
                    FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent(path).path)
                }
            }.value
            
            await MainActor.run {
                self.validHistoricImagePaths = validPaths
            }
        }
        
        let commonName = record.commonName
        let scientificName = record.scientificName
        let insightDescription = record.insightDescription
        let isPoisonous = record.isPoisonous
        let confidenceScore = record.confidenceScore ?? 1.0
        let wikipediaUrl = record.wikipediaUrl
        let wikipediaExtract = record.wikipediaExtract
        let referenceImageUrl = record.referenceImageUrl
        
        var parsedDiagnostic: DiagnosticComparison? = nil
        if let rationale = record.diagnosticPrimaryRationale,
           let lookalike = record.diagnosticLookalikeName,
           let diffJsonStr = record.diagnosticDifferentiatorsJson,
           let diffData = diffJsonStr.data(using: .utf8),
           let diffs = try? JSONDecoder().decode([String].self, from: diffData),
           !diffs.isEmpty {
            
            parsedDiagnostic = DiagnosticComparison(
                primaryMatchRationale: rationale,
                confusingLookalikeName: lookalike,
                keyDifferentiators: diffs
            )
        }
        
        self.speciesData = SpeciesData(
            scanId: record.id,
            commonName: commonName,
            scientificName: scientificName,
            insightData: InsightData(description: insightDescription, isPoisonous: isPoisonous, regionalStatusRationale: nil),
            confidenceScore: confidenceScore, 
            diagnosticComparison: parsedDiagnostic,
            wikipediaUrl: wikipediaUrl,
            wikipediaExtract: wikipediaExtract,
            referenceImageUrl: referenceImageUrl,
            isBiological: record.isBiological,
            isLiveCapture: record.isLiveCapture,
            isInvasive: record.isInvasive,
            ecologyType: record.ecologyType,
            taxonomy: TaxonomyData(
                kingdom: record.taxonomyKingdom,
                phylum: record.taxonomyPhylum,
                className: record.taxonomyClass,
                order: record.taxonomyOrder,
                family: record.taxonomyFamily,
                genus: record.taxonomyGenus
            ),
            locationName: record.locationName,
            weatherCondition: record.weatherCondition,
            weatherTemperatureF: record.weatherTemperatureF
        )
        self.isProcessing = false
    }
    

}
