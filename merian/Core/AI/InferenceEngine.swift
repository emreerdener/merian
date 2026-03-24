import Foundation
import CoreImage
import Combine
import SwiftUI
import SwiftData
import ImageIO
import os

// MARK: - Engine Boundaries
enum APIError: Error {
    case proRequiredForOfflineTracking
    case decodingFailed
}

// MARK: - Core Cloud Inference Engine
/// Manages real-time AI taxonomy processing via Supabase Edge Functions
@MainActor
@Observable final class InferenceEngine {
    // MARK: - Active Pipeline State
    @ObservationIgnored var inferenceTask: Task<Void, Error>?
    var isProcessing: Bool = false
    var activeImageData: Data? = nil
    var activeCompressedImageData: Data? = nil
    var activeLiveCaptureDatas: [Data] = []
    var validHistoricImagePaths: [String] = []
    var speciesData: SpeciesData? = nil
    
    // MARK: - Environmental Telemetry State
    private(set) var activeLatitude: Double? = nil
    private(set) var activeLongitude: Double? = nil
    private(set) var activeElevation: Double? = nil
    private var activeDeviceLocale: String?
    private var activeCurrentMonth: Int?
    private var activeTimeOfDay: String? = nil
    private(set) var activeLocationName: String? = nil
    private(set) var activeWeatherCondition: String? = nil
    private(set) var activeTemperatureF: Double? = nil
    private(set) var activeFlashFired: Bool? = nil
    private(set) var activeDistanceInMeters: Float? = nil
    
    // MARK: - Asynchronous Execution Controllers
    public var isBackgroundRescued = false
    
    // MARK: - Network Edge DTOs
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
        let iucn_red_list_status: String?
    }    

    // MARK: - Main Pipeline Triggers
    func analyze(imageDatas: [Data], telemetry: CaptureTelemetry, modelContext: ModelContext? = nil) {
        guard !imageDatas.isEmpty else { return }
        self.inferenceTask?.cancel()
        
        // Reset states for a fresh native scan
        self.isProcessing = true
        self.activeImageData = imageDatas.first
        self.activeCompressedImageData = nil
        self.activeLiveCaptureDatas = imageDatas
        self.validHistoricImagePaths = []
        self.speciesData = nil
        self.isBackgroundRescued = false
        
        self.activeLatitude = telemetry.gpsLatitude
        self.activeLongitude = telemetry.gpsLongitude
        self.activeElevation = telemetry.gpsElevation
        self.activeLocationName = telemetry.locationName
        self.activeWeatherCondition = telemetry.weatherCondition
        self.activeTemperatureF = telemetry.weatherTemperatureF
        // Ephemeral telemetry removed to preserve memory boundaries
        self.activeDistanceInMeters = telemetry.subjectDistanceInMeters
        
        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }
            
            let boundaryStartTime = CFAbsoluteTimeGetCurrent()
            
            // 1. Data is already safely compressed from camera cropper directly
            let compressedDatas = imageDatas
            self.activeCompressedImageData = compressedDatas.first
            
            do {
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }
                
                let client = MerianNetworkClient.shared
                
                // 2. Convert Data to structural base64 string
                let base64Strings = await InferenceProcessingActor.shared.encodeBase64Concurrent(compressedDatas: compressedDatas)
                
                let targetObjectKey = "staging/\(UUID().uuidString).jpg"
                
                try Task.checkCancellation() 
                
                // 3. Transmit the payload directly skipping R2 hops entirely
                let inferenceStartTime = CFAbsoluteTimeGetCurrent()
                let resultData = try await client.analyzeSubject(
                    r2ObjectKeys: [targetObjectKey],
                    base64ImageDatas: base64Strings,
                    telemetry: telemetry
                )
                let inferenceTime = CFAbsoluteTimeGetCurrent() - inferenceStartTime
                MerianLog.general.debug("⏱️ [Performance] Gemini Edge Inference completed in \(String(format: "%.3f", inferenceTime), privacy: .public) seconds.")
                
                let (finalMappedData, isNewDisc) = try await InferenceProcessingActor.shared.parseAndSave(
                    resultData: resultData,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    compressedDatas: compressedDatas
                )
                
                if var mappedData = finalMappedData {
                    if isNewDisc {
                        mappedData.isNewDiscovery = true
                        
                        await MainActor.run { GamificationManager.shared.recordNewSpeciesDiscovered() }
                        
                        if let container = modelContext?.container {
                            let profileActor = ProfileDatabaseActor(modelContainer: container)
                            let updatedAwards = await profileActor.calculateAwards()
                            await MainActor.run { GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards) }
                        }
                    }
                    CircuitBreakerManager.shared.recordSuccess()
                    AppTelemetry.trackScan(isPro: RevenueCatManager.shared.isProActive)
                    self.speciesData = mappedData
                    
                    let totalPipelineTime = CFAbsoluteTimeGetCurrent() - boundaryStartTime
                    MerianLog.general.debug("⏱️ [Performance] Total Analysis Pipeline (Upload + AI + DB) executed in \(String(format: "%.3f", totalPipelineTime), privacy: .public) seconds!")
                    
                    if mappedData.isBiological {
                        Task {
                            await self.asynchronouslyFetchWikipediaAndHydrate(for: mappedData.scientificName, scanId: mappedData.scanId, modelContext: modelContext)
                        }
                    }
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
                        gpsElevation: telemetry.gpsElevation,
                        gpsLatitude: telemetry.gpsLatitude,
                        gpsLongitude: telemetry.gpsLongitude,
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
                    imageDatas: compressedDatas,
                    telemetry: telemetry,
                    blurScore: nil
                )
                MerianLog.general.debug("⚠️ Inference Engine Critical Failure: \(error.localizedDescription, privacy: .private)")
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
                    weatherTemperatureF: telemetry.weatherTemperatureF,
                    gpsElevation: telemetry.gpsElevation,
                    gpsLatitude: telemetry.gpsLatitude,
                    gpsLongitude: telemetry.gpsLongitude
                )
            }
            
            // Unconditionally clear the active loading hardware state
            self.isProcessing = false
        }
    }
    
    // MARK: - Background Hydration Syncs
    /// Hits the Wikimedia Desktop Summary framework independently skipping the Inference loop latency cost natively.
    private func asynchronouslyFetchWikipediaAndHydrate(for species: String, scanId: String?, modelContext: ModelContext?) async {
        guard !species.isEmpty, species.lowercased() != "taxonomy unavailable", species.lowercased() != "unknown subject" else { return }
        
        // Match the backend whitespace replacement strategy safely enforcing capital bounds explicitly
        let normalized = species.replacingOccurrences(of: " ", with: "_")
        guard let enc = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(enc)") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return }
            
            struct WikiRes: Decodable {
                let extract: String?
                let content_urls: ContentURLs?
                struct ContentURLs: Decodable { let desktop: Desktop? }
                struct Desktop: Decodable { let page: String? }
                let originalimage: OriginalImage?
                struct OriginalImage: Decodable { let source: String? }
            }
            
            let decoded = try JSONDecoder().decode(WikiRes.self, from: data)
            
            guard let extract = decoded.extract, let webUrl = decoded.content_urls?.desktop?.page else { return }
            let imageUrl = decoded.originalimage?.source
            
            await MainActor.run {
                if self.speciesData?.scientificName == species {
                    self.speciesData?.wikipediaExtract = extract
                    self.speciesData?.wikipediaUrl = webUrl
                    if let img = imageUrl, !img.isEmpty {
                        self.speciesData?.referenceImageUrl = img
                    }
                }
            }
            
            if let scanId = scanId, let context = modelContext {
                 let container = context.container
                 Task {
                     let dbActor = BackgroundDatabaseActor(modelContainer: container)
                     await dbActor.updateScanWithWikipedia(scanId: scanId, extract: extract, url: webUrl, imageUrl: imageUrl)
                 }
            }
            
        } catch {
            MerianLog.general.debug("Silently bypassed Wikipedia background hydration: \(error, privacy: .private)")
        }
    }
    
    // MARK: - Active Pipeline Modifiers
    func cancelActiveRequest() {
        MerianLog.general.debug("Cancelled active inference request to prevent watchdog termination.")
        isBackgroundRescued = true
        self.inferenceTask?.cancel()
        self.speciesData = nil
        isBackgroundRescued = false
        activeImageData = nil
        activeCompressedImageData = nil
        activeLiveCaptureDatas.removeAll()
        validHistoricImagePaths.removeAll()
        activeLatitude = nil
        activeLongitude = nil
        activeElevation = nil
        activeLocationName = nil
        activeWeatherCondition = nil
        activeTemperatureF = nil
    }
    
    /// Safely cascades failing URLs directly out of the primary UI loops preserving continuous Carousel streams without throwing out-of-bounds Array indices natively
    func dropInvalidCarouselImage(_ urlStr: String) {
        if let idx = self.validHistoricImagePaths.firstIndex(of: urlStr) {
            self.validHistoricImagePaths.remove(at: idx)
        }
        
        if let currentRef = self.speciesData?.referenceImageUrl {
            var parts = currentRef.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            if let idx = parts.firstIndex(of: urlStr) {
                parts.remove(at: idx)
                let newJoined = parts.joined(separator: ",")
                self.speciesData?.referenceImageUrl = newJoined.isEmpty ? nil : newJoined
            }
        }
    }
    
    // MARK: - Local Hardware Loaders
    /// Rehydrates the SpeciesData and UI payloads natively from an offline Scans record
    func load(from record: LocalScanRecord) {
        self.isProcessing = true
        
        self.activeImageData = nil
        self.validHistoricImagePaths = []
        var paths: [String] = []
        if let localPath = record.localImagePath {
            paths.append(localPath)
        }
        if let extras = record.additionalImagePaths {
            paths.append(contentsOf: extras)
        }
        self.activeLiveCaptureDatas = []
        
        Task {
            let validPaths = await FileIOActor.shared.validPaths(from: paths)
            
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
            weatherTemperatureF: record.weatherTemperatureF,
            gpsElevation: record.gpsElevation,
            gpsLatitude: record.gpsLatitude,
            gpsLongitude: record.gpsLongitude
        )
        self.isProcessing = false
        
        // Retroactively hydrate any legacy offline scans that missed the initial Wikipedia extract resolution OR Wikipedia reference images
        if record.isBiological && (record.wikipediaExtract == nil || record.referenceImageUrl == nil || record.referenceImageUrl!.isEmpty) {
            let safeContext = record.modelContext
            Task {
                await self.asynchronouslyFetchWikipediaAndHydrate(for: record.scientificName, scanId: record.id, modelContext: safeContext)
            }
        }
    }
    


}

// MARK: - Dedicated Actors for Background Offloading
actor FileIOActor {
    static let shared = FileIOActor()
    
    func validPaths(from paths: [String]) -> [String] {
        return paths.filter { path in
            if path.starts(with: "http") { return true }
            return FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent(path).path)
        }
    }
}

actor InferenceProcessingActor {
    static let shared = InferenceProcessingActor()
    
    func encodeBase64Concurrent(compressedDatas: [Data]) async -> [String] {
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, data) in compressedDatas.enumerated() {
                group.addTask {
                    return (index, data.base64EncodedString())
                }
            }
            var results: [(Int, String)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted(by: { $0.0 < $1.0 }).map { $1 }
        }
    }
    
    func parseAndSave(resultData: Data, telemetry: CaptureTelemetry, modelContext: ModelContext?, compressedDatas: [Data]) async throws -> (SpeciesData?, Bool) {
        let decoder = JSONDecoder()
        
        let parsedWrapper: InferenceEngine.EdgeResponseWrapper
        do {
            parsedWrapper = try decoder.decode(InferenceEngine.EdgeResponseWrapper.self, from: resultData)
        } catch let error as DecodingError {
            MerianLog.general.debug("⚠️ AI JSON Payload Hallucination / Decoding Error: \(error.localizedDescription, privacy: .private)")
            throw APIError.decodingFailed
        }
        
        let edgeRes = parsedWrapper.data
        
        let mappedData = SpeciesData(
            fromEdgeResponse: edgeRes,
            locationName: telemetry.locationName,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            gpsElevation: telemetry.gpsElevation,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude
        )
        
        try Task.checkCancellation()
        
        var newDiscovery = false
        
        if mappedData.confidenceScore > 0.0, let container = modelContext?.container, !compressedDatas.isEmpty {
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            newDiscovery = await dbActor.saveLiveScanRecord(mappedData: mappedData, compressedDatas: compressedDatas)
        }
        return (mappedData, newDiscovery)
    }
}
