import Combine
import CoreImage
import Foundation
import ImageIO
import os
import SwiftData
import SwiftUI

// MARK: - Wikipedia Response (private)

private struct WikiSummaryResponse: Decodable {
    let extract: String?
    let content_urls: ContentURLs?
    let originalimage: OriginalImage?

    struct ContentURLs: Decodable { let desktop: Desktop? }
    struct Desktop: Decodable { let page: String? }
    struct OriginalImage: Decodable { let source: String? }
}

// MARK: - Inference Engine

/// Drives the live AI taxonomy pipeline and manages all active scan state.
@MainActor
@Observable final class InferenceEngine {

    // MARK: - Pipeline State
    @ObservationIgnored var inferenceTask: Task<Void, Error>?
    var isProcessing: Bool = false
    var activeImageData: Data?
    var activeLiveCaptureDatas: [Data] = []
    var activeDisplayDatas: [Data] = []
    var validHistoricImagePaths: [String] = []
    var speciesData: SpeciesData?

    // MARK: - Environmental Telemetry State
    private(set) var activeLatitude: Double?
    private(set) var activeLongitude: Double?
    private(set) var activeElevation: Double?
    private var activeDeviceLocale: String?
    private var activeCurrentMonth: Int?
    private var activeTimeOfDay: String?
    private(set) var activeLocationName: String?
    private(set) var activeWeatherCondition: String?
    private(set) var activeTemperatureF: Double?
    private(set) var activeFlashFired: Bool?
    private(set) var activeDistanceInMeters: Float?

    var isEnrichmentLoading: Bool = false

    // MARK: - Background Rescue State
    /// Set to `true` by `cancelActiveRequest()` before cancelling the task, so the task's
    /// cancellation handler knows the scan was intentionally backgrounded and should not refund.
    private(set) var isBackgroundRescued = false
    @ObservationIgnored private var wikiFetchAttemptedIds: Set<String> = []
    private let wikiFetchAttemptCap = 500

    // MARK: - Live Inference Pipeline

    /// - Parameters:
    ///   - imageDatas: 1024 px inference-quality images. Sent to Gemini as base64 and
    ///     retained in `activeLiveCaptureDatas` for background rescue re-queuing.
    ///   - displayDatas: 2048 px display-quality images. Written to disk so the insight
    ///     sheet and scan library render without JPEG blocking artifacts. Never sent to AI.
    ///     Falls back to `imageDatas` when empty (e.g. offline-queue reprocessing path).
    func analyze(imageDatas: [Data], displayDatas: [Data] = [], telemetry: CaptureTelemetry, modelContext: ModelContext? = nil) {
        guard !imageDatas.isEmpty else { return }
        self.inferenceTask?.cancel()

        self.isProcessing = true
        self.activeImageData = displayDatas.first ?? imageDatas.first
        self.activeLiveCaptureDatas = imageDatas
        self.activeDisplayDatas = displayDatas.isEmpty ? imageDatas : displayDatas
        self.validHistoricImagePaths = []
        self.speciesData = nil
        self.isBackgroundRescued = false

        self.activeLatitude = telemetry.gpsLatitude
        self.activeLongitude = telemetry.gpsLongitude
        self.activeElevation = telemetry.gpsElevation
        self.activeLocationName = telemetry.locationName
        self.activeWeatherCondition = telemetry.weatherCondition
        self.activeTemperatureF = telemetry.weatherTemperatureF
        self.activeDistanceInMeters = telemetry.subjectDistanceInMeters

        let capturedDisplayDatas = displayDatas

        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }

            // Single exit point for isProcessing — covers all success, error, and cancellation paths.
            defer { self.isProcessing = false }

            let pipelineStart = CFAbsoluteTimeGetCurrent()
            let compressedDatas = imageDatas  // 1024 px — only these are base64-encoded for Gemini

            do {
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }

                let client = MerianNetworkClient.shared

                let base64Strings = await InferenceProcessingActor.shared.encodeBase64(compressedDatas: compressedDatas)
                let validBase64Strings = base64Strings.filter { !$0.isEmpty }
                guard !validBase64Strings.isEmpty else {
                    MerianLog.general.error("All base64 payloads are empty — corrupted capture data. Refunding scan.")
                    UsageManager.shared.refundScan()
                    return
                }

                // Detect actual encoding from JPEG magic bytes (FF D8 FF).
                // Falls back to WebP when the image was encoded with the primary path.
                let imageMimeType: String = {
                    guard let first = compressedDatas.first, first.count >= 3 else { return "image/webp" }
                    let prefix = [UInt8](first.prefix(3))
                    return (prefix[0] == 0xFF && prefix[1] == 0xD8 && prefix[2] == 0xFF) ? "image/jpeg" : "image/webp"
                }()

                let resolvedUserId = await MainActor.run { (SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId).lowercased() }
                let targetObjectKey = "staging/\(resolvedUserId)/\(UUID().uuidString.lowercased()).webp"

                try Task.checkCancellation()

                MerianLog.general.debug("[⏱ BENCH] Pre-flight (encode+auth): \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")
                let inferenceStart = CFAbsoluteTimeGetCurrent()
                let resultData = try await client.analyzeSubject(
                    r2ObjectKeys: [targetObjectKey],
                    base64ImageDatas: validBase64Strings,
                    mimeType: imageMimeType,
                    telemetry: telemetry
                )
                MerianLog.general.debug("Gemini inference completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - inferenceStart), privacy: .public)s.")

                let postFlightStart = CFAbsoluteTimeGetCurrent()
                let parseResult = try await InferenceProcessingActor.shared.parseAndSave(
                    resultData: resultData,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    compressedDatas: compressedDatas,
                    displayDatas: capturedDisplayDatas
                )
                let finalMappedData = parseResult.mappedData
                let isNewDisc = parseResult.isNewDiscovery
                let savedImagePaths = parseResult.savedPaths

                if var mappedData = finalMappedData {
                    if isNewDisc {
                        mappedData.isNewDiscovery = true
                        GamificationManager.shared.recordNewSpeciesDiscovered()
                    }

                    if let container = modelContext?.container {
                        let profileActor = ProfileDatabaseActor(modelContainer: container)
                        let updatedAwards = await profileActor.calculateAwards()
                        // Already on @MainActor — no hop needed.
                        GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards)
                    }

                    CircuitBreakerManager.shared.recordSuccess()
                    AppTelemetry.trackScan(isPro: RevenueCatManager.shared.isProActive)
                    HapticManager.shared.triggerSuccessPulse()
                    // Populate on-disk paths before speciesData so the carousel has the user's
                    // image ready the moment the insight sheet renders. Clear live in-memory
                    // data afterwards — validHistoricImagePaths takes over as the image source.
                    self.validHistoricImagePaths = savedImagePaths
                    self.speciesData = mappedData
                    self.activeImageData = nil
                    self.activeLiveCaptureDatas.removeAll()
                    self.activeDisplayDatas.removeAll()

                    // Send a local notification for inference complete.
                    // The Offline queue path sends its own notification; this covers live inference.
                    #if canImport(UIKit)
                    if UserDefaults.standard.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled),
                       let scanId = mappedData.scanId {
                        PushNotificationManager.shared.sendInferenceCompleteNotification(
                            speciesName: mappedData.commonName,
                            scanId: scanId
                        )
                    }
                    #endif

                    MerianLog.general.debug("[⏱ BENCH] Post-flight (parse+save+state): \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - postFlightStart), privacy: .public)s")
                    MerianLog.general.debug("[⏱ BENCH] Total pipeline: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")

                    if mappedData.isBiological {
                        Task { [weak self] in
                            guard let self else { return }
                            await self.fetchWikipediaAndHydrate(for: mappedData.scientificName, scanId: mappedData.scanId, modelContext: modelContext)
                        }
                        Task { [weak self] in
                            guard let self else { return }
                            await self.fetchAndApplyEnrichment(modelContext: modelContext)
                        }
                        if let key = mappedData.gbifTaxonKey {
                            Task { [weak self] in
                                guard let self else { return }
                                await self.fetchGBIFImagesAndHydrate(for: key, scanId: mappedData.scanId, modelContext: modelContext)
                            }
                        }
                    }
                }
            } catch {
                // Cancellation: the task was intentionally cancelled (e.g., app backgrounded).
                // Only refund if this was NOT a background rescue — isBackgroundRescued is reset
                // here so cancelActiveRequest() doesn't need to race against this block.
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    let wasRescued = self.isBackgroundRescued
                    self.isBackgroundRescued = false
                    if !wasRescued {
                        UsageManager.shared.refundScan()
                    }
                    return
                }

                if let apiError = error as? MerianError, apiError == .decodingFailed {
                    AppTelemetry.trackError("APIDecodingFailure")
                    UsageManager.shared.refundScan()
                    HapticManager.shared.triggerErrorThump()
                    self.speciesData = SpeciesData(
                        scanId: nil,
                        commonName: "Analysis Failed",
                        scientificName: "Data Unreadable",
                        insightData: InsightData(aiReasoning: "The AI failed to understand the image or produced an unreadable schema.", hazardType: "none"),
                        confidenceScore: 0,
                        blurScore: nil,
                        similarSpecies: nil,
                        wikipediaUrl: nil,
                        wikipediaOverview: nil,
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
                        colors: nil,
                        groupTags: nil,
                        iucnRedListStatus: nil,
                        zoomFactor: telemetry.zoomFactor.map { Double($0) }
                    )
                    return
                }

                // Network failure — refund the scan since the user never got a result.
                AppTelemetry.trackError("InferenceNetworkFailure")
                UsageManager.shared.refundScan()
                HapticManager.shared.triggerErrorThump()

                if RevenueCatManager.shared.isProActive {
                    CircuitBreakerManager.shared.recordFailure()
                    OfflineQueueManager.shared.enqueueCapture(
                        imageDatas: compressedDatas,
                        telemetry: telemetry,
                        blurScore: nil
                    )
                }
                MerianLog.general.debug("Inference failure: \(error.localizedDescription, privacy: .private)")
                self.speciesData = SpeciesData(
                    scanId: nil,
                    commonName: "Network Timeout",
                    scientificName: "Offline Mode",
                    insightData: InsightData(aiReasoning: "Please check your network connection and try again.", hazardType: "none"),
                    confidenceScore: 0,
                    blurScore: nil,
                    similarSpecies: nil,
                    wikipediaUrl: nil,
                    wikipediaOverview: nil,
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
                    colors: nil,
                    groupTags: nil,
                    iucnRedListStatus: nil,
                    zoomFactor: telemetry.zoomFactor.map { Double($0) }
                )
            }
        }
    }

    // MARK: - Wikipedia Background Hydration

    /// Fetches and patches the Wikipedia extract and reference image for a species after inference completes.
    /// Runs independently to avoid adding latency to the inference round-trip.
    /// Only marks the species as attempted after a *successful* fetch, so transient failures are retryable.
    private func fetchWikipediaAndHydrate(for species: String, scanId: String?, modelContext: ModelContext?) async {
        guard !species.isEmpty,
              species.lowercased() != "taxonomy unavailable",
              species.lowercased() != "unknown subject" else { return }
        guard !wikiFetchAttemptedIds.contains(species) else { return }
        // Evict the entire set when the cap is hit so a long session never grows unboundedly.
        if wikiFetchAttemptedIds.count >= wikiFetchAttemptCap {
            wikiFetchAttemptedIds.removeAll()
        }

        let normalized = species.replacingOccurrences(of: " ", with: "_")
        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return }

            let decoded = try JSONDecoder().decode(WikiSummaryResponse.self, from: data)
            guard let extract = decoded.extract, let webUrl = decoded.content_urls?.desktop?.page else { return }
            let imageUrl = decoded.originalimage?.source

            // Mark as attempted only on success — transient failures (timeout, 404) remain retryable.
            wikiFetchAttemptedIds.insert(species)

            await MainActor.run {
                if self.speciesData?.scientificName == species {
                    self.speciesData?.wikipediaOverview = extract
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
            MerianLog.general.debug("Wikipedia hydration skipped: \(error, privacy: .private)")
        }
    }

    // MARK: - GBIF Background Hydration

    private struct GBIFMediaResponse: Decodable {
        let results: [GBIFResult]?
    }
    
    private struct GBIFResult: Decodable {
        let media: [GBIFMedia]?
    }
    
    private struct GBIFMedia: Decodable {
        let type: String?
        let identifier: String?
    }

    /// Fetches high-quality field observations from GBIF (e.g. iNaturalist) once the Taxon Key is known.
    /// This acts as a robust supplement/fallback to Wikipedia imagery.
    private func fetchGBIFImagesAndHydrate(for taxonKey: Int, scanId: String?, modelContext: ModelContext?) async {
        guard let url = URL(string: "https://api.gbif.org/v1/occurrence/search?taxonKey=\(taxonKey)&mediaType=StillImage&limit=4") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return }

            let decoded = try JSONDecoder().decode(GBIFMediaResponse.self, from: data)
            
            var newUrls: [String] = []
            if let results = decoded.results {
                for result in results {
                    if let mediaList = result.media {
                        for mediaItem in mediaList {
                            if mediaItem.type == "StillImage", let id = mediaItem.identifier {
                                newUrls.append(id)
                                break // Only take the primary image from each observation
                            }
                        }
                    }
                }
            }

            guard !newUrls.isEmpty else { return }

            await MainActor.run {
                if self.speciesData?.gbifTaxonKey == taxonKey {
                    var currentUrls = self.speciesData?.referenceImageUrl?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
                    
                    // Prevent duplicates if already hydrated
                    for urlStr in newUrls where !currentUrls.contains(urlStr) {
                        currentUrls.append(urlStr)
                    }
                    
                    self.speciesData?.referenceImageUrl = currentUrls.joined(separator: ",")
                }
            }
            
            // Persist the updated image URLs to SwiftData if possible
            let finalUrls = await MainActor.run { self.speciesData?.referenceImageUrl }
            if let scanId = scanId, let context = modelContext, let finalUrls = finalUrls {
                let container = context.container
                Task {
                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
                    // We only want to patch the image URL. Re-use updateScanWithWikipedia since it allows patching just the image URL.
                    await dbActor.updateScanWithWikipedia(scanId: scanId, extract: nil, url: nil, imageUrl: finalUrls)
                }
            }
        } catch {
            // Silently fail on network/timeout
            MerianLog.general.debug("GBIF image hydration skipped: \(error, privacy: .private)")
        }
    }

    // MARK: - Species Enrichment

    /// Fetches habitat, distribution, and (if low-confidence) diagnostic data from `enrich-scan`
    /// and patches the live `speciesData` in-place, then persists the result to SwiftData.
    ///
    /// Called automatically after every successful biological scan and when reloading a historical
    /// record that is missing enrichment data.
    func fetchAndApplyEnrichment(modelContext: ModelContext?) async {
        guard let data = speciesData,
              let scanId = data.scanId,
              data.isBiological,
              !data.scientificName.isEmpty,
              data.scientificName.lowercased() != "taxonomy unavailable" else { return }

        isEnrichmentLoading = true
        defer { isEnrichmentLoading = false }

        do {
            let response = try await MerianNetworkClient.shared.fetchEnrichment(
                scanId: scanId,
                scientificName: data.scientificName,
                confidenceScore: data.confidenceScore,
                inferenceTier: data.inferenceTier ?? "flash"
            )
            guard let enrichData = response.data else { return }

            speciesData?.habitatDescription = enrichData.habitat_description
            if let key = enrichData.gbif_taxon_key {
                speciesData?.gbifTaxonKey = key
                Task { [weak self] in
                    guard let self else { return }
                    await self.fetchGBIFImagesAndHydrate(for: key, scanId: scanId, modelContext: modelContext)
                }
            }
            if let tax = enrichData.taxonomy {
                speciesData?.taxonomy = TaxonomyData(
                    kingdom: tax.kingdom,
                    phylum: tax.phylum,
                    className: tax.`class`,
                    order: tax.order,
                    family: tax.family,
                    genus: tax.genus
                )
            }

            if let entries = enrichData.similar_species, !entries.isEmpty {
                speciesData?.similarSpecies = SimilarSpecies(
                    entries: entries.map {
                        SimilarSpeciesEntry(
                            scientificName: $0.scientific_name,
                            commonName: $0.common_name,
                            referenceImageUrl: $0.reference_image_url,
                            iucnRedListStatus: $0.iucn_red_list_status
                        )
                    }
                )
            }

            if let context = modelContext {
                let container = context.container
                Task {
                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
                    await dbActor.updateScanWithEnrichment(
                        scanId: scanId,
                        habitatDescription: enrichData.habitat_description,
                        gbifTaxonKey: enrichData.gbif_taxon_key,
                        similarSpecies: enrichData.similar_species?.map(\.scientific_name),
                        taxonomy: enrichData.taxonomy
                    )
                }
            }
        } catch let error as MerianError {
            if case .httpError(let code, _) = error, code == 403 { return }
            MerianLog.general.debug("Enrichment fetch failed: \(error, privacy: .private)")
        } catch {
            MerianLog.general.debug("Enrichment fetch failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Pipeline Modifiers

    func cancelActiveRequest(isUserInitiated: Bool = false) {
        MerianLog.general.debug("Cancelled active inference request.")
        if !isUserInitiated {
            isBackgroundRescued = true
        }
        self.inferenceTask?.cancel()
        // isBackgroundRescued is reset by the task's cancellation catch block.
        // If the task was already finished, analyze() resets it at the start of the next scan.
        self.speciesData = nil
        activeImageData = nil
        activeLiveCaptureDatas.removeAll()
        activeDisplayDatas.removeAll()
        validHistoricImagePaths.removeAll()
        activeLatitude = nil
        activeLongitude = nil
        activeElevation = nil
        activeLocationName = nil
        activeWeatherCondition = nil
        activeTemperatureF = nil
    }

    /// Removes an invalid image URL from the carousel and from the stored `referenceImageUrl` field.
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
                let joined = parts.joined(separator: ",")
                self.speciesData?.referenceImageUrl = joined.isEmpty ? nil : joined
            }
        }
    }

    // MARK: - Local Record Loading

    /// Rehydrates engine state from a persisted `LocalScanRecord` for the insight sheet.
    func load(from record: LocalScanRecord) {
        self.isProcessing = true

        self.activeImageData = nil
        self.activeLiveCaptureDatas = []
        self.activeDisplayDatas = []
        self.validHistoricImagePaths = []

        var paths: [String] = []
        if let localPath = record.localImagePath { paths.append(localPath) }
        if let extras = record.additionalImagePaths { paths.append(contentsOf: extras) }

        Task { [weak self] in
            let validPaths = await FileIOActor.shared.validPaths(from: paths)
            await MainActor.run { self?.validHistoricImagePaths = validPaths }
        }

        var parsedSimilar: SimilarSpecies?
        if let lookalikesArray = record.similarSpecies, !lookalikesArray.isEmpty {
            parsedSimilar = SimilarSpecies(
                entries: lookalikesArray.map {
                    SimilarSpeciesEntry(scientificName: $0, commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
                }
            )
        }

        self.speciesData = SpeciesData(
            scanId: record.id,
            commonName: record.commonName,
            scientificName: record.scientificName,
            insightData: InsightData(aiReasoning: record.aiReasoning ?? "No ecological description available for this subject.", hazardType: record.hazardType),
            confidenceScore: record.confidenceScore ?? 1.0,
            blurScore: nil,
            similarSpecies: parsedSimilar,
            wikipediaUrl: record.wikipediaUrl,
            wikipediaOverview: record.wikipediaOverview,
            referenceImageUrl: record.referenceImageUrl,
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
            gpsLongitude: record.gpsLongitude,
            colors: nil,
            groupTags: nil,
            iucnRedListStatus: record.iucnRedListStatus,
            zoomFactor: record.zoomFactor,
            estimatedSizeCm: record.estimatedSizeCm,
            lifeStage: record.lifeStage,
            reproductiveCondition: record.reproductiveCondition,
            individualCount: record.individualCount,
            ecologicalInteractions: record.ecologicalInteractions,
            aiReasoning: record.aiReasoning,
            habitatDescription: record.habitatDescription,
            gbifTaxonKey: record.gbifTaxonKey
        )
        self.isProcessing = false

        // Retroactively hydrate legacy scans that missed Wikipedia data on initial save.
        if record.isBiological && (record.wikipediaOverview == nil || record.referenceImageUrl == nil || record.referenceImageUrl!.isEmpty) {
            let safeContext = record.modelContext
            Task { [weak self] in
                guard let self else { return }
                await self.fetchWikipediaAndHydrate(for: record.scientificName, scanId: record.id, modelContext: safeContext)
            }
        }

        // Fetch enrichment for any record missing habitat data, a GBIF key,
        // or similar species data.
        if record.isBiological {
            let needsEnrichment = record.habitatDescription == nil ||
                record.gbifTaxonKey == nil ||
                (record.similarSpecies == nil || record.similarSpecies!.isEmpty)
            if needsEnrichment {
                let safeContext = record.modelContext
                Task { [weak self] in
                    guard let self else { return }
                    await self.fetchAndApplyEnrichment(modelContext: safeContext)
                }
            } else if let key = record.gbifTaxonKey {
                // If we didn't need enrichment but have a key, ensure we dynamically hydrate GBIF images 
                // deduplicating against any existing ones from the DB.
                let safeContext = record.modelContext
                Task { [weak self] in
                    guard let self else { return }
                    await self.fetchGBIFImagesAndHydrate(for: key, scanId: record.id, modelContext: safeContext)
                }
            }
        }
    }
}
