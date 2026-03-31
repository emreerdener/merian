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

    /// True while the "enrichment" scope call (habitat, taxonomy, GBIF key) is in flight.
    var isEnrichmentLoading: Bool = false
    /// True while the "lookalikes" scope call (similar species cards) is in flight.
    var isLookalikesLoading: Bool = false

    // MARK: - Background Rescue State
    /// Set to `true` by `cancelActiveRequest()` before cancelling the task, so the task's
    /// cancellation handler knows the scan was intentionally backgrounded and should not refund.
    private(set) var isBackgroundRescued = false
    @ObservationIgnored private var wikiFetchAttemptedIds: Set<String> = []
    /// Shared cap for all session-scoped deduplication sets. Matches `wikiFetchAttemptedIds` so
    /// all three sets evict at the same threshold — ~100 bytes × 500 entries ≈ 50 KB per set.
    private let sessionSetCap = 500
    /// Scan IDs for which `fetchAndApplyEnrichment` has already been attempted via `load(from:)`.
    /// Prevents re-firing on every open for species that permanently lack GBIF / habitat data.
    /// Live-inference scans (via `analyze()`) bypass this gate intentionally.
    @ObservationIgnored private var enrichmentAttemptedScanIds: Set<String> = []
    /// Scientific names for which `fetchAndApplyEnrichment` has successfully completed on the
    /// live-inference path within this session. Skips the Edge round-trip for repeat observations
    /// of the same species — habitat, lookalikes, and taxonomy data is identical across scans.
    @ObservationIgnored private var enrichedSpeciesNames: Set<String> = []
    /// Tracks the GBIF image hydration task spawned by `fetchAndApplyEnrichment` so it can be
    /// cancelled immediately when the user navigates away or fires a new scan. Without this handle
    /// the task survives `liveHydrationTask` cancellation and can write stale image URLs back to
    /// a record that is no longer active, or to a record that has already been deleted.
    @ObservationIgnored private var gbifHydrationTask: Task<Void, Never>?
    /// Tracks the single async hydration task spawned by `load(from:)` so it can be
    /// cancelled immediately when the user navigates to a different scan.
    @ObservationIgnored var historicHydrationTask: Task<Void, Never>?
    /// Tracks the single async hydration task spawned after a live inference result so it can be
    /// cancelled if the user fires a new scan before Wikipedia/enrichment/GBIF finish.
    @ObservationIgnored private var liveHydrationTask: Task<Void, Never>?

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
        self.liveHydrationTask?.cancel()
        self.gbifHydrationTask?.cancel()
        self.gbifHydrationTask = nil

        // Reset loading flags synchronously before the cancelled tasks' defer blocks can run
        // on @MainActor. Without this, a stale defer from the old task can fire after the new
        // pipeline has already set these flags to true, prematurely clearing the skeletons.
        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false

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
                        // Capture value types before crossing into the task boundary.
                        let capturedScientificName = mappedData.scientificName
                        let capturedScanId = mappedData.scanId
                        let capturedGbifKey = mappedData.gbifTaxonKey
                        // Single tracked task — cancelled by the next `analyze()` call so stale
                        // hydration results from a previous scan cannot overwrite the new one.
                        // Wikipedia completes first; enrichment and GBIF run concurrently after.
                        // Capture wikipediaOverview before the task boundary — if the identify
                        // response already included it from the species_dictionary join, the
                        // Wikipedia round-trip can be skipped entirely.
                        let capturedHasWikipedia = mappedData.wikipediaOverview != nil
                        liveHydrationTask = Task { [weak self] in
                            guard let self else { return }
                            // Skip Wikipedia fetch when the identify response already includes an
                            // overview from the species_dictionary join (species enriched before).
                            if !capturedHasWikipedia {
                                await self.fetchWikipediaAndHydrate(for: capturedScientificName, scanId: capturedScanId, modelContext: modelContext)
                                guard !Task.isCancelled else { return }
                            }
                            // Gate enrichment at the species level — habitat, lookalikes, and taxonomy
                            // are identical across all scans of the same species. After the first scan
                            // enriches a species in this session, subsequent scans skip the Edge
                            // round-trip entirely. GBIF image hydration always runs (it writes
                            // referenceImageUrl for the specific scan record).
                            let capturedIsEnriched = self.enrichedSpeciesNames.contains(capturedScientificName)
                            // Use withTaskGroup + @MainActor child tasks so the ModelContext
                            // capture stays actor-bound — async let closures are implicitly
                            // @Sendable and cannot capture non-Sendable @MainActor types.
                            await withTaskGroup(of: Void.self) { group in
                                group.addTask { @MainActor [self] in
                                    if !capturedIsEnriched {
                                        await self.fetchAndApplyEnrichment(modelContext: modelContext)
                                    }
                                }
                                group.addTask { @MainActor [self] in
                                    if let key = capturedGbifKey {
                                        await self.fetchGBIFImagesAndHydrate(for: key, scanId: capturedScanId, modelContext: modelContext)
                                    }
                                }
                            }
                            if !capturedIsEnriched && !Task.isCancelled {
                                // Evict 10% on cap hit — same policy as wikiFetchAttemptedIds.
                                if self.enrichedSpeciesNames.count >= self.sessionSetCap {
                                    self.enrichedSpeciesNames.subtract(self.enrichedSpeciesNames.prefix(self.sessionSetCap / 10))
                                }
                                self.enrichedSpeciesNames.insert(capturedScientificName)
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
        // Evict 10% of entries on cap hit so recent attempts survive and the set never grows unboundedly.
        // Full wipe would reset species that were just successfully fetched, causing redundant network calls.
        if wikiFetchAttemptedIds.count >= sessionSetCap {
            let evictCount = sessionSetCap / 10
            wikiFetchAttemptedIds.subtract(wikiFetchAttemptedIds.prefix(evictCount))
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

            // Decode off @MainActor — GBIF occurrence responses can be 50–200 KB and
            // JSONDecoder runs synchronously. Parsing on the main run loop produces a
            // jank spike right after the user receives their scan result.
            let newUrls = try await Task.detached(priority: .utility) {
                let decoded = try JSONDecoder().decode(GBIFMediaResponse.self, from: data)
                var urls: [String] = []
                for result in decoded.results ?? [] {
                    for mediaItem in result.media ?? [] {
                        if mediaItem.type == "StillImage", let id = mediaItem.identifier {
                            urls.append(id)
                            break // Only take the primary image from each observation
                        }
                    }
                }
                return urls
            }.value

            guard !newUrls.isEmpty else { return }

            // Back on @MainActor (InferenceEngine is @MainActor) — direct access, no hop needed.
            var persistUrls: String?
            if self.speciesData?.gbifTaxonKey == taxonKey {
                var currentUrls = self.speciesData?.referenceImageUrl?
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty } ?? []

                for urlStr in newUrls where !currentUrls.contains(urlStr) {
                    currentUrls.append(urlStr)
                }

                // Cap at 5 URLs to prevent unbounded referenceImageUrl string growth across sessions.
                let capped = Array(currentUrls.prefix(5))
                self.speciesData?.referenceImageUrl = capped.joined(separator: ",")
                persistUrls = self.speciesData?.referenceImageUrl
            }

            if let scanId = scanId, let context = modelContext, let finalUrls = persistUrls {
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

    /// Fires the "enrichment" and "lookalikes" scopes of `enrich-scan` concurrently via a
    /// task group. Each scope applies its fields to `speciesData` as soon as its network call
    /// resolves — habitat description and taxonomy appear independently of similar species cards.
    ///
    /// `isEnrichmentLoading` gates the habitat/distribution skeleton (enrichment scope).
    /// `isLookalikesLoading` gates the similar species gallery skeleton (lookalikes scope).
    ///
    /// Called automatically after every successful biological scan and when reloading a historical
    /// record that is missing enrichment data. `needsMetadata` / `needsLookalikes` allow callers
    /// to skip whichever scope is already fully populated locally.
    func fetchAndApplyEnrichment(
        modelContext: ModelContext?,
        needsMetadata: Bool = true,
        needsLookalikes: Bool = true
    ) async {
        guard let data = speciesData,
              let scanId = data.scanId,
              data.isBiological,
              !data.scientificName.isEmpty,
              data.scientificName.lowercased() != "taxonomy unavailable" else { return }

        guard needsMetadata || needsLookalikes else { return }

        if needsMetadata { isEnrichmentLoading = true }
        if needsLookalikes { isLookalikesLoading = true }

        let capturedScanId = scanId
        let capturedScientificName = data.scientificName
        let capturedConfidence = data.confidenceScore
        let capturedTier = data.inferenceTier ?? "flash"

        await withTaskGroup(of: Void.self) { group in
            if needsMetadata {
                group.addTask { @MainActor [self] in
                    defer { self.isEnrichmentLoading = false }
                    do {
                        let response = try await MerianNetworkClient.shared.fetchEnrichment(
                            scanId: capturedScanId,
                            scientificName: capturedScientificName,
                            confidenceScore: capturedConfidence,
                            inferenceTier: capturedTier,
                            scope: "enrichment"
                        )
                        guard let enrichData = response.data else { return }

                        self.speciesData?.habitatDescription = enrichData.habitat_description
                        if let tax = enrichData.taxonomy {
                            self.speciesData?.taxonomy = TaxonomyData(
                                kingdom: tax.kingdom,
                                phylum: tax.phylum,
                                className: tax.`class`,
                                order: tax.order,
                                family: tax.family,
                                genus: tax.genus
                            )
                        }
                        if let key = enrichData.gbif_taxon_key {
                            self.speciesData?.gbifTaxonKey = key
                            // Store in a tracked handle so cancelActiveRequest() can kill this task
                            // before it writes stale GBIF image URLs to a record no longer active.
                            self.gbifHydrationTask?.cancel()
                            self.gbifHydrationTask = Task { [weak self] in
                                guard let self else { return }
                                await self.fetchGBIFImagesAndHydrate(for: key, scanId: capturedScanId, modelContext: modelContext)
                            }
                        }
                        if let context = modelContext {
                            let container = context.container
                            let habitatSnapshot = enrichData.habitat_description
                            let gbifSnapshot = enrichData.gbif_taxon_key
                            let taxonomySnapshot = enrichData.taxonomy
                            Task {
                                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                                await dbActor.updateScanWithEnrichment(
                                    scanId: capturedScanId,
                                    habitatDescription: habitatSnapshot,
                                    gbifTaxonKey: gbifSnapshot,
                                    similarSpeciesJsonData: nil,
                                    taxonomy: taxonomySnapshot
                                )
                            }
                        }
                    } catch let error as MerianError {
                        if case .httpError(let code, _) = error, code == 403 { return }
                        MerianLog.general.debug("Enrichment scope failed: \(error, privacy: .private)")
                    } catch {
                        MerianLog.general.debug("Enrichment scope failed: \(error, privacy: .private)")
                    }
                }
            }

            if needsLookalikes {
                group.addTask { @MainActor [self] in
                    defer { self.isLookalikesLoading = false }
                    do {
                        let response = try await MerianNetworkClient.shared.fetchEnrichment(
                            scanId: capturedScanId,
                            scientificName: capturedScientificName,
                            confidenceScore: capturedConfidence,
                            inferenceTier: capturedTier,
                            scope: "lookalikes"
                        )
                        guard let enrichData = response.data else { return }

                        if let entries = enrichData.similar_species, !entries.isEmpty {
                            self.speciesData?.similarSpecies = SimilarSpecies(
                                entries: entries.map {
                                    SimilarSpeciesEntry(
                                        scientificName: $0.scientific_name,
                                        commonName: $0.common_name,
                                        referenceImageUrl: $0.reference_image_url,
                                        iucnRedListStatus: $0.iucn_red_list_status
                                    )
                                }
                            )
                            if let context = modelContext {
                                let container = context.container
                                let entriesToEncode = self.speciesData?.similarSpecies?.entries
                                Task {
                                    // Encode off @MainActor — JSONEncoder is CPU-bound.
                                    let encodedLookalikes: Data? = await Task.detached(priority: .utility) {
                                        entriesToEncode.flatMap { try? JSONEncoder().encode($0) }
                                    }.value
                                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
                                    await dbActor.updateScanWithEnrichment(
                                        scanId: capturedScanId,
                                        habitatDescription: nil,
                                        gbifTaxonKey: nil,
                                        similarSpeciesJsonData: encodedLookalikes,
                                        taxonomy: nil
                                    )
                                }
                            }
                        }
                    } catch let error as MerianError {
                        if case .httpError(let code, _) = error, code == 403 { return }
                        MerianLog.general.debug("Lookalikes scope failed: \(error, privacy: .private)")
                    } catch {
                        MerianLog.general.debug("Lookalikes scope failed: \(error, privacy: .private)")
                    }
                }
            }
        }
    }

    // MARK: - Identification Override

    /// Called when the user selects a candidate as their preferred identification.
    /// Immediately updates display state, persists locally, syncs to cloud, and hydrates
    /// species data for the override species from `species_dictionary`.
    func applyIdentificationOverride(scientificName: String, modelContext: ModelContext?) async {
        guard let scanId = speciesData?.scanId else { return }

        // 1. Immediately update display — scientificName drives InsightHeader subtitle.
        speciesData?.userIdentificationOverride = scientificName
        speciesData?.scientificName = scientificName
        speciesData?.userConfirmedIdentification = false

        // 2. Persist to SwiftData.
        if let context = modelContext {
            let container = context.container
            Task {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanWithOverride(scanId: scanId, override: scientificName, confirmed: false)
            }
        }

        // 3. Cloud sync — IDOR-guarded direct PostgREST update.
        Task { [weak self] in
            guard let self else { return }
            await self.syncIdentificationReviewToCloud(scanId: scanId, override: scientificName, confirmed: false)
        }

        // 4. Fetch and patch species data for the override species.
        await fetchAndPatchOverrideData(scientificName: scientificName, scanId: scanId, modelContext: modelContext)
    }

    /// Called when the user confirms the AI's primary identification ("Yes, correct").
    /// Persists locally and syncs confirmation to the cloud scan record.
    func confirmAIIdentification(modelContext: ModelContext?) async {
        guard let scanId = speciesData?.scanId else { return }

        speciesData?.userConfirmedIdentification = true

        if let context = modelContext {
            let container = context.container
            Task {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanWithOverride(scanId: scanId, override: nil, confirmed: true)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            await self.syncIdentificationReviewToCloud(scanId: scanId, override: nil, confirmed: true)
        }
    }

    /// Called when the user flags an identification for manual review because no models matched.
    /// Mutates the local display state and persists the flag local-only via the `isFlagged` column.
    func flagAIIdentification(modelContext: ModelContext?) async {
        guard let scanId = speciesData?.scanId else { return }

        speciesData?.isFlagged = true

        if let context = modelContext {
            let container = context.container
            Task {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanAsFlagged(scanId: scanId)
            }
        }
    }

    /// Removes the manual review flag from an identification.
    func unflagAIIdentification(modelContext: ModelContext?) async {
        guard let scanId = speciesData?.scanId else { return }

        speciesData?.isFlagged = false

        if let context = modelContext {
            let container = context.container
            Task {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanAsUnflagged(scanId: scanId)
            }
        }
    }

    /// Resets all identification review state, reverting the scan back to the AI's original
    /// identification. Called by Undo (from `.overridden`) and Change (from `.confirmed`).
    /// Clears both `userIdentificationOverride` and `userConfirmedIdentification` locally,
    /// syncs both columns to null/false in the cloud, and re-hydrates the AI species data.
    func resetIdentificationReview(modelContext: ModelContext?) async {
        guard let scanId = speciesData?.scanId,
              let aiName = speciesData?.aiScientificName,
              !aiName.isEmpty else { return }

        // 1. Revert in-memory state — scientificName must be restored before hydration fires.
        speciesData?.userIdentificationOverride = nil
        speciesData?.userConfirmedIdentification = false
        speciesData?.scientificName = aiName

        // 2. Persist both fields locally.
        if let context = modelContext {
            let container = context.container
            Task {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanWithOverride(scanId: scanId, override: nil, confirmed: false)
            }
        }

        // 3. Zero both cloud columns.
        Task { [weak self] in
            guard let self else { return }
            await self.syncIdentificationReviewToCloud(scanId: scanId, override: nil, confirmed: false)
        }

        // 4. Re-hydrate the AI's original species data from species_dictionary.
        await fetchAndPatchOverrideData(scientificName: aiName, scanId: scanId, modelContext: modelContext)
    }

    /// Queries `species_dictionary` for the given scientific name and patches the live
    /// `speciesData` in-place. On cache miss, falls through to `fetchAndApplyEnrichment`
    /// which triggers the full enrichment pipeline for the override species.
    @MainActor
    private func fetchAndPatchOverrideData(scientificName: String, scanId: String?, modelContext: ModelContext?) async {
        struct SpeciesDictRow: Decodable {
            let common_names: [String: String?]?
            let kingdom: String?
            let phylum: String?
            let `class`: String?
            let order: String?
            let family: String?
            let genus: String?
            let wikipedia_overview: String?
            let hazard_type: String?
            let reference_image_url: String?
            let wikipedia_url: String?
            let iucn_red_list_status: String?
            let habitat_description: String?
            let gbif_taxon_key: Int?
        }

        do {
            let rows: [SpeciesDictRow] = try await SupabaseManager.shared.client
                .from("species_dictionary")
                .select("common_names, kingdom, phylum, class, order, family, genus, wikipedia_overview, hazard_type, reference_image_url, wikipedia_url, iucn_red_list_status, habitat_description, gbif_taxon_key")
                .eq("scientific_name", value: scientificName)
                .limit(1)
                .execute()
                .value

            if let row = rows.first {
                // Cache hit — patch all available fields reactively.
                // Prefer the authoritative "en" locale; fall back to any available translation;
                // final fallback is the scientific name. Mirrors ScanRepository's resolution logic.
                let commonName: String = {
                    guard let names = row.common_names else { return scientificName }
                    return names["en"].flatMap { $0 } ?? names.compactMap { $0.value }.first ?? scientificName
                }()
                // Capture aiReasoning before any mutation to avoid a read-during-write
                // exclusivity violation on the @Observable-tracked speciesData property.
                let existingReasoning = speciesData?.insightData.aiReasoning ?? ""
                speciesData?.commonName = commonName.capitalized
                speciesData?.insightData = InsightData(
                    aiReasoning: existingReasoning,
                    hazardType: row.hazard_type ?? "none"
                )
                speciesData?.taxonomy = TaxonomyData(
                    kingdom: row.kingdom,
                    phylum: row.phylum,
                    className: row.class,
                    order: row.order,
                    family: row.family,
                    genus: row.genus
                )
                speciesData?.iucnRedListStatus = row.iucn_red_list_status
                speciesData?.habitatDescription = row.habitat_description
                speciesData?.gbifTaxonKey = row.gbif_taxon_key
                speciesData?.referenceImageUrl = row.reference_image_url
                speciesData?.wikipediaOverview = row.wikipedia_overview
                speciesData?.wikipediaUrl = row.wikipedia_url
            } else {
                // Cache miss — enrich the override species. fetchAndApplyEnrichment uses
                // speciesData.scientificName which is already set to the override name.
                await fetchAndApplyEnrichment(modelContext: modelContext)
            }
        } catch {
            MerianLog.general.debug("fetchAndPatchOverrideData failed: \(error, privacy: .private)")
        }
    }

    /// IDOR-guarded direct PostgREST update persisting both identification review fields.
    /// Accepts nil for `override` to set the column to NULL (reset / confirmed-only path).
    private func syncIdentificationReviewToCloud(scanId: String, override: String?, confirmed: Bool) async {
        guard let userId = await MainActor.run(body: { SupabaseManager.shared.currentUser?.id.uuidString }) else { return }

        struct ReviewSyncPayload: Encodable {
            let user_identification_override: String?
            let user_confirmed_identification: Bool
        }

        do {
            try await SupabaseManager.shared.client
                .from("scans")
                .update(ReviewSyncPayload(user_identification_override: override,
                                         user_confirmed_identification: confirmed))
                .eq("id", value: scanId)
                .eq("user_id", value: userId)
                .execute()
        } catch {
            MerianLog.general.debug("syncIdentificationReviewToCloud failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Pipeline Modifiers

    func cancelActiveRequest(isUserInitiated: Bool = false) {
        MerianLog.general.debug("Cancelled active inference request.")
        if !isUserInitiated {
            isBackgroundRescued = true
        }
        self.inferenceTask?.cancel()
        self.liveHydrationTask?.cancel()
        self.historicHydrationTask?.cancel()
        // Cancel GBIF hydration so stale image URLs cannot be written to a record
        // that is no longer active after the user fires a new scan or navigates away.
        self.gbifHydrationTask?.cancel()
        self.gbifHydrationTask = nil
        // Reset loading flags synchronously so stale defer blocks from cancelled task group
        // children cannot clear flags belonging to a subsequently opened scan.
        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false
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
    ///
    /// All async work (path validation, JSON decoding, network hydration) runs inside a single
    /// tracked `historicHydrationTask` so that navigating to a different scan immediately
    /// cancels the previous scan's outstanding work.
    func load(from record: LocalScanRecord) {
        self.isProcessing = true
        historicHydrationTask?.cancel()

        self.activeImageData = nil
        self.activeLiveCaptureDatas = []
        self.activeDisplayDatas = []
        self.validHistoricImagePaths = []

        // Capture all non-Sendable model properties synchronously on @MainActor
        // before crossing any concurrency boundary.
        var imagePaths: [String] = []
        if let localPath = record.localImagePath { imagePaths.append(localPath) }
        if let extras = record.additionalImagePaths { imagePaths.append(contentsOf: extras) }

        let lookalikesJsonData: Data? = record.lookalikesData
        let lookalikesLegacyArray: [String]? = record.similarSpecies
        let candidatesRawData: Data? = record.candidatesData
        let overrideName: String? = record.userIdentificationOverride
        let recordIsBiological = record.isBiological
        let recordScientificName = record.scientificName
        let recordId = record.id
        let safeContext = record.modelContext
        let gbifKey = record.gbifTaxonKey
        let needsWiki = recordIsBiological &&
            (record.wikipediaOverview == nil || record.referenceImageUrl == nil || record.referenceImageUrl!.isEmpty)
        // Decode lookalikesData once here on @MainActor — the blob is small (3 entries × 4 fields).
        // The result is reused for both the needsEnrichment gate check and the UI decode step
        // inside historicHydrationTask, avoiding a second JSONDecoder allocation on the same data.
        let preDecodedSimilar: SimilarSpecies? = lookalikesJsonData.flatMap {
            (try? JSONDecoder().decode([SimilarSpeciesEntry].self, from: $0))
                .map { SimilarSpecies(entries: $0) }
        }
        // A scan needs enrichment when any of the three key fields are absent, OR when
        // lookalikesData exists but every decoded entry has a nil commonName — indicating
        // the join table was populated before the common-name back-fill pipeline was added.
        let lookalikesHaveNoCommonNames: Bool = preDecodedSimilar.map {
            !$0.entries.isEmpty && $0.entries.allSatisfy { $0.commonName == nil }
        } ?? false
        // Split enrichment needs by scope so each concurrent call is fired only when required.
        let needsMetadata = recordIsBiological &&
            (record.habitatDescription == nil || record.gbifTaxonKey == nil)
        let needsLookalikes = recordIsBiological &&
            (record.lookalikesData == nil || lookalikesHaveNoCommonNames)
        let needsEnrichment = needsMetadata || needsLookalikes

        // Set speciesData immediately with nil for blob-decoded fields.
        // similarSpecies and candidates are populated by the task below to avoid
        // blocking @MainActor with synchronous JSONDecoder calls on large datasets.
        self.speciesData = SpeciesData(
            scanId: record.id,
            commonName: record.commonName,
            scientificName: record.scientificName,
            insightData: InsightData(aiReasoning: record.aiReasoning ?? "", hazardType: record.hazardType),
            confidenceScore: record.confidenceScore ?? 1.0,
            blurScore: nil,
            similarSpecies: nil,
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
            gbifTaxonKey: record.gbifTaxonKey,
            inferenceTier: record.inferenceTier,
            candidates: nil,
            imageQualityScore: record.imageQualityScore,
            aiScientificName: record.scientificName,
            userIdentificationOverride: record.userIdentificationOverride,
            userConfirmedIdentification: record.userConfirmedIdentification,
            isFlagged: record.isFlagged
        )
        self.isProcessing = false

        historicHydrationTask = Task { [weak self] in
            guard let self else { return }

            // Step 1: Validate image paths (I/O-bound).
            let validPaths = await FileIOActor.shared.validPaths(from: imagePaths)
            guard !Task.isCancelled else { return }
            self.validHistoricImagePaths = validPaths

            // Step 2: Resolve similar species and decode candidates off @MainActor (CPU-bound).
            // similarSpecies reuses the pre-decoded result from the gate check above —
            // no second JSONDecoder pass on lookalikesData. Candidates are decoded here
            // since they were not needed for any @MainActor gate.
            let (parsedSimilar, parsedCandidates) = await Task.detached(priority: .userInitiated) {
                let similar: SimilarSpecies? = preDecodedSimilar
                    ?? lookalikesLegacyArray.flatMap { arr in
                        arr.isEmpty ? nil : SimilarSpecies(entries: arr.map {
                            SimilarSpeciesEntry(scientificName: $0, commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
                        })
                    }
                let candidates: [IdentificationCandidate]? = candidatesRawData.flatMap {
                    try? JSONDecoder().decode([IdentificationCandidate].self, from: $0)
                }
                return (similar, candidates)
            }.value

            guard !Task.isCancelled else { return }
            self.speciesData?.similarSpecies = parsedSimilar
            self.speciesData?.candidates = parsedCandidates

            // Step 3: If an identification override is active, patch in the override species data.
            if let override = overrideName {
                guard !Task.isCancelled else { return }
                await self.fetchAndPatchOverrideData(scientificName: override, scanId: recordId, modelContext: safeContext)
            }

            // Step 4: Retroactively hydrate legacy scans missing Wikipedia data.
            if needsWiki {
                guard !Task.isCancelled else { return }
                await self.fetchWikipediaAndHydrate(for: recordScientificName, scanId: recordId, modelContext: safeContext)
            }

            // Step 5: Enrichment or GBIF-image hydration (mutually exclusive).
            // Two gates prevent redundant enrichment calls:
            // - enrichmentAttemptedScanIds (scan-ID-scoped): prevents re-firing for the same
            //   scan record within a session (e.g. user closes and reopens the same scan).
            // - enrichedSpeciesNames (species-name-scoped): prevents a second enrichment call
            //   if the user opens two different scans of the same species in the same session —
            //   shared species-level data (habitat, lookalikes) is identical across all scans.
            //   Mirrors the same gate used on the live inference path.
            if needsEnrichment
                && !self.enrichmentAttemptedScanIds.contains(recordId)
                && !self.enrichedSpeciesNames.contains(recordScientificName) {
                guard !Task.isCancelled else { return }
                // Evict 10% on cap hit to bound session-scoped set growth.
                if self.enrichmentAttemptedScanIds.count >= self.sessionSetCap {
                    self.enrichmentAttemptedScanIds.subtract(self.enrichmentAttemptedScanIds.prefix(self.sessionSetCap / 10))
                }
                self.enrichmentAttemptedScanIds.insert(recordId)
                await self.fetchAndApplyEnrichment(modelContext: safeContext, needsMetadata: needsMetadata, needsLookalikes: needsLookalikes)
                if !Task.isCancelled {
                    if self.enrichedSpeciesNames.count >= self.sessionSetCap {
                        self.enrichedSpeciesNames.subtract(self.enrichedSpeciesNames.prefix(self.sessionSetCap / 10))
                    }
                    self.enrichedSpeciesNames.insert(recordScientificName)
                }
            } else if let key = gbifKey, recordIsBiological {
                guard !Task.isCancelled else { return }
                await self.fetchGBIFImagesAndHydrate(for: key, scanId: recordId, modelContext: safeContext)
            }
        }
    }
}
