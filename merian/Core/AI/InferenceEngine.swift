import Combine
import CoreImage
import Foundation
import ImageIO
import os
import SwiftData
import SwiftUI
import Vision

// MARK: - Private Response Types

/// Thrown from inside Task.detached parse closures when the expected content is absent
/// (e.g. a Wikipedia article with no "Description" section). Distinct from CancellationError
/// so callers can distinguish a missing-data skip from genuine task cancellation.
private struct WikiContentNotFound: Error {}

private struct WikiOriginalImage: Decodable { let source: String? }
private struct WikiSection: Decodable {
    let title: String?
    let anchor: String?
    let text: String?
}
private struct WikiMobileSectionsResponse: Decodable {
    struct Lead: Decodable {
        let normalizedtitle: String?
        let originalimage: WikiOriginalImage?
    }
    struct Remaining: Decodable {
        let sections: [WikiSection]
    }
    let lead: Lead
    let remaining: Remaining
}

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

// MARK: - Inference Engine

/// Drives the live AI taxonomy pipeline and manages all active scan state.
@MainActor
@Observable final class InferenceEngine {

    // MARK: - Pipeline State
    @ObservationIgnored var inferenceTask: Task<Void, Error>?
    /// The client scan ID passed to `analyze()` — matches the `OfflineQueuedScan.id` for the
    /// same capture. Used by the background offline path to detect when it completes the same
    /// scan and should hydrate the engine instead of leaving `isProcessing = true` forever.
    @ObservationIgnored var activeScanId: String?
    var isProcessing: Bool = false
    var scanningPhaseText: String = "Analyzing subject..."
    @ObservationIgnored private var phaseRotationTask: Task<Void, Never>?
    var activeImageData: Data?
    var validHistoricImagePaths: [String] = []
    var speciesData: SpeciesData?
    
    /// Holds the user's staged textual description natively during the active live asynchronous
    /// taxonomy pipeline evaluation. Defensively cleared upfront during `prepareForNewScan` and `analyze`.
    var activeObservationContext: ObservationContext?

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
    /// True while the "reference image" scope call (GBIF imagery) is in flight after inference finishes without one.
    var isReferenceImageLoading: Bool = false

    // MARK: - Background Rescue State
    @ObservationIgnored private var wikiFetchAttemptedIds: Set<String> = []
    /// Shared cap for all session-scoped deduplication sets. Matches `wikiFetchAttemptedIds` so
    /// all three sets evict at the same threshold — ~100 bytes × 500 entries ≈ 50 KB per set.
    private let sessionSetCap = 500
    /// Scan IDs for which `fetchAndApplyEnrichment` has already been attempted via `load(from:)`.
    /// Prevents re-firing on every open for species that permanently lack GBIF / habitat data.
    /// Live-inference scans (via `analyze()`) bypass this gate intentionally.
    @ObservationIgnored private var enrichmentAttemptedScanIds: Set<String> = []
    /// Scientific names for which `fetchAndApplyEnrichment` has successfully completed on the
    /// live-inference path. Stored in UserDefaults with a 24-hour expiration.
    @ObservationIgnored private var enrichedSpeciesTimestamps: [String: Double] = UserDefaults.standard.dictionary(forKey: "enrichedSpeciesTimestamps") as? [String: Double] ?? [:]

    /// Set to the Date 60 seconds in the future the first time `enrich-scan` returns HTTP 429. All subsequent
    /// `fetchAndApplyEnrichment` calls bail out immediately if this date is in the future.
    /// Resets on `prepareForNewScan()`.
    @ObservationIgnored private var enrichmentRateLimitedUntil: Date?
    /// Tracks the GBIF image hydration task spawned by `fetchAndApplyEnrichment` so it can be
    /// cancelled immediately when the user navigates away or fires a new scan. Without this handle
    /// the task survives `liveHydrationTask` cancellation and can write stale image URLs back to
    /// a record that is no longer active, or to a record that has already been deleted.
    @ObservationIgnored private var gbifHydrationTask: Task<Void, Never>?
    /// Tracks the background SwiftData write spawned inside `fetchAndApplyEnrichment` after a
    /// successful enrichment Edge response. Holding the handle lets `cancelActiveRequest()` abort
    /// the write before it triggers a spurious `@Query` invalidation on the next scan's UI.
    @ObservationIgnored private var enrichmentWriteTask: Task<Void, Never>?
    /// Tracks the single async hydration task spawned by `load(from:)` so it can be
    /// cancelled immediately when the user navigates to a different scan.
    @ObservationIgnored var historicHydrationTask: Task<Void, Never>?
    /// Tracks the single async hydration task spawned after a live inference result so it can be
    /// cancelled if the user fires a new scan before Wikipedia/enrichment/GBIF finish.
    @ObservationIgnored private var liveHydrationTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundWriteTasks = [UUID: Task<Void, Never>]()
    /// Hard cap on concurrent background write tasks. When reached, new submissions are dropped
    /// rather than allowed to stack — prevents OOM during rapid offline-queue replay where
    /// multiple wiki/GBIF/enrichment writes can stack faster than SQLite drains them.
    private let backgroundWriteTaskCap = 8

    @ObservationIgnored private var pendingBackgroundTasks: [@Sendable () async -> Void] = []

    private func executeTrackedBackgroundTask(operation: @escaping @Sendable () async -> Void) {
        guard backgroundWriteTasks.count < backgroundWriteTaskCap else {
            pendingBackgroundTasks.append(operation)
            return
        }
        let id = UUID()
        let task = Task { [weak self] in
            defer { 
                Task { @MainActor [weak self] in 
                    self?.backgroundWriteTasks.removeValue(forKey: id)
                    self?.drainPendingBackgroundTasks()
                } 
            }
            await operation()
        }
        backgroundWriteTasks[id] = task
    }

    @MainActor
    private func drainPendingBackgroundTasks() {
        guard backgroundWriteTasks.count < backgroundWriteTaskCap, !pendingBackgroundTasks.isEmpty else { return }
        let next = pendingBackgroundTasks.removeFirst()
        executeTrackedBackgroundTask(operation: next)
    }

    private func isSpeciesEnriched(_ name: String) -> Bool {
        guard let ts = enrichedSpeciesTimestamps[name] else { return false }
        return Date(timeIntervalSinceReferenceDate: ts) > Date.now.addingTimeInterval(-86400)
    }

    private func markSpeciesEnriched(_ name: String) {
        let ts = Date.now.timeIntervalSinceReferenceDate
        enrichedSpeciesTimestamps[name] = ts
        UserDefaults.standard.set(enrichedSpeciesTimestamps, forKey: "enrichedSpeciesTimestamps")
    }

    // MARK: - External API Session

    /// Dedicated URLSession for public third-party APIs (Wikipedia, GBIF).
    /// Uses a separate session from MerianNetworkClient so:
    /// - TLS pinning for *.supabase.co is not applied to public endpoints.
    /// - Cookie storage is isolated (public APIs must not share cookie state with auth sessions).
    /// - Connection pool is independent from the Supabase pool.
    private static let externalAPISession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    // MARK: - Live Inference Pipeline

    /// Synchronously resets all display state so the content router sees
    /// `isProcessing == true && speciesData == nil` from the very first frame
    /// when the insight sheet opens — even when the previous scan was a library
    /// load that had already finished (`isProcessing == false`, `speciesData != nil`).
    ///
    /// Called by `CaptureWorkspaceViewModel.submitActiveScan()` before `activeSheet = .insight`.
    /// `analyze()` will subsequently overwrite image and telemetry fields with the
    /// new scan's data once the async telemetry Task resolves.
    ///
    /// Contrast with `cancelActiveRequest()`, which resets to idle with no upcoming scan.
    func prepareForNewScan() {
        // Cancel all in-flight async work before the new scan claims the engine.
        self.inferenceTask?.cancel()
        self.liveHydrationTask?.cancel()
        self.historicHydrationTask?.cancel()
        self.historicHydrationTask = nil
        self.gbifHydrationTask?.cancel()
        self.gbifHydrationTask = nil
        self.enrichmentWriteTask?.cancel()
        self.enrichmentWriteTask = nil
        self.phaseRotationTask?.cancel()
        for task in self.backgroundWriteTasks.values { task.cancel() }
        self.backgroundWriteTasks.removeAll()

        // Reset scan identity and processing flags.
        self.activeScanId = nil
        self.isProcessing = true
        self.scanningPhaseText = "Analyzing subject..."
        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false
        self.isReferenceImageLoading = false
        self.enrichmentRateLimitedUntil = nil

        // Clear the previous scan's result and image data.
        self.speciesData = nil
        self.validHistoricImagePaths = []
        self.activeImageData = nil
        self.activeObservationContext = nil

        // Clear telemetry so stale GPS/weather cannot bleed into the new scan's display.
        self.activeLatitude = nil
        self.activeLongitude = nil
        self.activeElevation = nil
        self.activeLocationName = nil
        self.activeWeatherCondition = nil
        self.activeTemperatureF = nil
    }

    /// Runs the live AI taxonomy pipeline for a new scan submission.
    ///
    /// Dispatches the Gemini inference request, parses and persists the result, updates all
    /// observable state for the insight sheet, and spawns post-inference background hydration
    /// tasks (Wikipedia, enrichment, GBIF images).
    ///
    /// The method is idempotent with respect to in-flight work — calling it cancels any
    /// existing `inferenceTask` and `liveHydrationTask` before starting the new pipeline.
    ///
    /// - Parameters:
    ///   - scanId: The `OfflineQueuedScan.id` for this capture. Passed to the Edge function
    ///     so the backend can correlate the live response with the queued upload.
    ///   - imageDatas: 1024 px inference-quality images. Sent to Gemini as base64.
    ///   - displayDatas: 2048 px display-quality images. Written to disk so the insight
    ///     sheet renders without JPEG blocking artifacts. Never sent to AI.
    ///     Falls back to `imageDatas` when empty (e.g. offline-queue reprocessing path).
    ///   - telemetry: GPS, weather, and device context bundled at capture time.
    ///   - modelContext: The SwiftData context for persisting the parsed scan record locally.
    ///   - targetEradicationRecord: An optional historic scan record instance passed exclusively when re-running a failed or queued scan, mutating the payload directly on disk.
    ///   - observationContext: Optional structured description staged alongside the photo.
    ///     When non-nil, `ObservationContext.serialized()` is appended as a text part in the
    ///     Gemini request and the raw JSON is forwarded as `observation_context` to the edge
    ///     function and persisted in `LocalScanRecord.observationContextJSON`.
    func analyze(scanId: String? = nil, imageDatas: [Data], displayDatas: [Data] = [], telemetry: CaptureTelemetry, observationContext: ObservationContext? = nil, modelContext: ModelContext? = nil, targetEradicationRecord: LocalScanRecord? = nil) {
        guard !imageDatas.isEmpty else { return }
        self.inferenceTask?.cancel()
        self.liveHydrationTask?.cancel()
        self.historicHydrationTask?.cancel()
        self.historicHydrationTask = nil
        self.gbifHydrationTask?.cancel()
        self.enrichmentWriteTask?.cancel()
        self.phaseRotationTask?.cancel()
        self.gbifHydrationTask = nil
        self.enrichmentWriteTask = nil

        // Reset loading flags synchronously before the cancelled tasks' defer blocks can run
        // on @MainActor. Without this, a stale defer from the old task can fire after the new
        // pipeline has already set these flags to true, prematurely clearing the skeletons.
        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false
        self.isReferenceImageLoading = false
        self.scanningPhaseText = "Analyzing subject..."

        self.activeObservationContext = nil
        self.activeScanId = scanId
        self.isProcessing = true
        self.activeImageData = displayDatas.first ?? imageDatas.first
        self.validHistoricImagePaths = []
        self.speciesData = nil
        
        self.activeObservationContext = observationContext

        self.activeLatitude = telemetry.gpsLatitude
        self.activeLongitude = telemetry.gpsLongitude
        self.activeElevation = telemetry.gpsElevation
        self.activeLocationName = telemetry.locationName
        self.activeWeatherCondition = telemetry.weatherCondition
        self.activeTemperatureF = telemetry.weatherTemperatureF
        self.activeDistanceInMeters = telemetry.subjectDistanceInMeters

        let capturedDisplayDatas = displayDatas

        if let firstData = imageDatas.first {
            classifySubjectLocally(from: firstData)
        }

        // Capture before the Task so the defer can compare against the ID this Task owns.
        let ownedScanId = scanId

        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }

            // Single exit point for isProcessing — covers all success, error, and cancellation paths.
            // Guard on ownedScanId: if a new scan called prepareForNewScan() + analyze() before this
            // Task's defer runs, activeScanId has already been updated to the new scan's ID. Writing
            // isProcessing=false or activeScanId=nil in that window would corrupt the new scan's state
            // (leaving the insight sheet stuck in a done-but-empty state). Only reset when this Task
            // still owns the active slot.
            defer {
                if self.activeScanId == ownedScanId {
                    self.isProcessing = false
                    self.activeScanId = nil
                }
                self.phaseRotationTask?.cancel()
            }

            let pipelineStart = CFAbsoluteTimeGetCurrent()
            let compressedDatas = imageDatas  // 1024 px — only these are base64-encoded for Gemini

            do {
                // --- Step 1: Pre-flight Checks & Data Preparation ---
                
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

                let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
                let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
                let resolvedUserId = (authUserId ?? deviceId).lowercased()
                let targetObjectKey = "staging/\(resolvedUserId)/\(UUID().uuidString.lowercased()).webp"

                try Task.checkCancellation()

                // --- Step 2: Edge Inference Generation (Gemini 1.5 Flash) ---
                
                MerianLog.general.debug("[⏱ BENCH] Pre-flight (encode+auth): \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")
                let inferenceStart = CFAbsoluteTimeGetCurrent()
                // Encode ObservationContext to JSON once: used for DB persistence (observationContextJSON)
                // and already serialised to plain text for the Gemini prompt (description).
                let observationContextJSONString: String? = observationContext.flatMap { ctx in
                    (try? JSONEncoder().encode(ctx)).flatMap { String(data: $0, encoding: .utf8) }
                }
                let resultData = try await client.analyzeSubject(
                    r2ObjectKeys: [targetObjectKey],
                    base64ImageDatas: validBase64Strings,
                    mimeType: imageMimeType,
                    telemetry: telemetry,
                    clientScanId: scanId,
                    description: observationContext?.serialized(),
                    observationContextJSON: observationContextJSONString
                )
                MerianLog.general.debug("Gemini inference completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - inferenceStart), privacy: .public)s.")

                // --- Step 3: Response Parsing & Local Persistence ---
                
                let postFlightStart = CFAbsoluteTimeGetCurrent()
                let parseResult = try await InferenceProcessingActor.shared.parseAndSave(
                    resultData: resultData,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    compressedDatas: compressedDatas,
                    displayDatas: capturedDisplayDatas,
                    observationContextJSON: observationContextJSONString
                )
                let finalMappedData = parseResult.mappedData
                let isNewDisc = parseResult.isNewDiscovery
                let savedImagePaths = parseResult.savedPaths

                // --- Step 4: UI State Updates & Gamification ---
                
                if var mappedData = finalMappedData {
                    if isNewDisc {
                        mappedData.isNewDiscovery = true
                        GamificationManager.shared.recordNewSpeciesDiscovered()
                    }

                    if let container = modelContext?.container {
                        // Reuse the process-lifetime shared profile actor — avoids a full
                        // ModelContext + actor allocation on every scan result.
                        let profileActor = OfflineQueueManager.shared.resolvedProfileDbActor(container: container)
                        let updatedAwards = await profileActor.calculateAwards()
                        // Already on @MainActor — no hop needed.
                        GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards)
                    }
                    
                    if let oldRecord = targetEradicationRecord {
                        if let context = modelContext {
                            // Transfer user-generated metadata to the new scan before the old record is deleted.
                            // Only customTags and collections carry over — review state (overrides, flags)
                            // intentionally resets because this is a fresh analysis.
                            if let newScanId = mappedData.scanId {
                                let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == newScanId })
                                if let newRecord = try? context.fetch(descriptor).first {
                                    newRecord.customTags = oldRecord.customTags
                                    if let oldCollections = oldRecord.collections, !oldCollections.isEmpty {
                                        newRecord.collections = oldCollections
                                    }
                                }
                            }
                            ScanRepository.shared.eradicateScan(record: oldRecord, modelContext: context)
                        } else {
                            assertionFailure("targetEradicationRecord provided but modelContext is nil")
                        }
                    }

                    CircuitBreakerManager.shared.recordSuccess()
                    AppTelemetry.trackScan(isPro: RevenueCatManager.shared.isProActive)
                    if self.activeScanId == ownedScanId {
                        HapticManager.shared.triggerHeavyImpact()
                        // Retain validHistoricImagePaths so the Carousel doesn't structurally tear down the LiveCapturePageView component.
                        self.validHistoricImagePaths = savedImagePaths
                        self.speciesData = mappedData
                    }

                    // Live inference succeeded — flush the queued scan record synchronously
                    // on the main context before the completion notification fires.
                    // flushOfflineQueuedScan is the guaranteed @Query re-evaluation trigger:
                    // it performs a real pending-change save on the main ModelContext, which
                    // reliably wakes @Query in any open sheet. deleteQueuedScan is async
                    // (it awaits backgroundSession.allTasks before touching SwiftData), so
                    // scheduling it via executeTrackedBackgroundTask means the notification
                    // fires first — leaving the library grid stuck in loading state while
                    // the user reacts to the banner.
                    //
                    // Ordering guarantee: flushOfflineQueuedScan runs synchronously here →
                    // SwiftUI's next render pass fires @Query → library updates → THEN the
                    // notification fires. Human reaction time (~200ms+) ensures the grid is
                    // correct before the user looks at it.
                    //
                    // deleteQueuedScan is still called in a background Task to cancel the
                    // parallel URLSession upload. It will find no SwiftData record (already
                    // flushed) and return early after cancelling the task — no duplicate
                    // LocalScanRecord is created because processAndCleanupOfflineScan's
                    // idempotency guard detects the existing record and skips insertion.
                    if let scanId {
                        OfflineQueueManager.shared.flushOfflineQueuedScan(scanId: scanId)
                        executeTrackedBackgroundTask { await OfflineQueueManager.shared.deleteQueuedScan(scanId: scanId) }
                    }

                    // Schedule a local notification for inference complete.
                    // Foreground banner suppression is handled by PushNotificationManager.willPresent:
                    // InsightSheetView sets suppressInferenceBanners=true while it is visible so the
                    // banner is silently delivered (not shown) when the user is already reading results.
                    // When the user is elsewhere in the app (library, camera) the banner is allowed.
                    // Background delivery bypasses willPresent entirely — the OS shows it automatically.
                    if UserDefaults.standard.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled),
                       let scanId = mappedData.scanId {
                        PushNotificationManager.shared.sendInferenceCompleteNotification(
                            speciesName: mappedData.commonName,
                            scanId: scanId
                        )
                    }

                    MerianLog.general.debug("[⏱ BENCH] Post-flight (parse+save+state): \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - postFlightStart), privacy: .public)s")
                    MerianLog.general.debug("[⏱ BENCH] Total pipeline: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")

                    // --- Step 5: Post-Inference Background Hydration ---
                    
                    if mappedData.isBiological {
                        // Capture value types before crossing into the task boundary.
                        let capturedScientificName = mappedData.scientificName
                        let capturedScanId = mappedData.scanId
                        let capturedGbifKey = mappedData.gbifTaxonKey
                        let willFetchGBIF = capturedGbifKey != nil && (mappedData.referenceImageUrl == nil || mappedData.referenceImageUrl?.isEmpty == true)
                        
                        // Single tracked task — cancelled by the next `analyze()` call so stale
                        // hydration results from a previous scan cannot overwrite the new one.
                        // Wikipedia and Enrichment run concurrently; GBIF runs sequentially after Enrichment.
                        // Capture wikipediaOverview before the task boundary — if the identify
                        // response already included it from the species_dictionary join, the
                        // Wikipedia round-trip can be skipped entirely.
                        let capturedHasWikipedia = mappedData.wikipediaOverview != nil
                        liveHydrationTask = Task { [weak self] in
                            guard let self else { return }
                            defer {
                                Task { @MainActor [weak self] in
                                    if self?.speciesData?.scanId == capturedScanId {
                                        self?.isReferenceImageLoading = false
                                    }
                                }
                            }
                            if willFetchGBIF {
                                await MainActor.run { self.isReferenceImageLoading = true }
                            }
                            
                            // Gate enrichment at the species level — habitat, lookalikes, and taxonomy
                            // are identical across all scans of the same species. After the first scan
                            // enriches a species in this session, subsequent scans skip the Edge
                            // round-trip entirely. GBIF image hydration always runs (it writes
                            // referenceImageUrl for the specific scan record).
                            let capturedIsEnriched = self.isSpeciesEnriched(capturedScientificName)
                            // Use withTaskGroup + @MainActor child tasks so the ModelContext
                            // capture stays actor-bound — async let closures are implicitly
                            // @Sendable and cannot capture non-Sendable @MainActor types.
                            await withTaskGroup(of: Void.self) { group in
                                // Task 1: Wikipedia Hydration
                                if !capturedHasWikipedia {
                                    group.addTask { @MainActor [weak self] in
                                        guard let self else { return }
                                        await self.fetchWikipediaAndHydrate(for: capturedScientificName, scanId: capturedScanId, modelContext: modelContext)
                                    }
                                }
                                
                                // Task 2: Enrichment followed by GBIF Images
                                group.addTask { @MainActor [weak self] in
                                    guard let self else { return }
                                    var taxonKeyToUse = capturedGbifKey
                                    
                                    if !capturedIsEnriched {
                                        await self.fetchAndApplyEnrichment(modelContext: modelContext)
                                        // Retrieve the newly updated taxon key if one was provided in the enrichment response
                                        taxonKeyToUse = self.speciesData?.gbifTaxonKey ?? taxonKeyToUse
                                    }
                                    
                                    // Make sure we check for cancellation before proceeding to the next sequential network fetch
                                    guard !Task.isCancelled else { return }
                                    
                                    if let key = taxonKeyToUse {
                                        await self.fetchGBIFImagesAndHydrate(for: key, scanId: capturedScanId, modelContext: modelContext)
                                    }
                                }
                            }
                            // Only mark the species as enriched when the call actually succeeded.
                            // If the network call failed silently, habitatDescription stays nil.
                            // Inserting on failure would permanently skip enrichment for this
                            // species in the current session — causing the retry state on every
                            // subsequent scan of the same species with no auto path out.
                            if !capturedIsEnriched && !Task.isCancelled,
                               self.speciesData?.habitatDescription != nil {
                                self.markSpeciesEnriched(capturedScientificName)
                            }
                        }
                        
                        // Wait up to 3 seconds for hydration so reference images are available before UI clears the "Analyzing" state.
                        if let hydrationTask = liveHydrationTask {
                            do {
                                try await withThrowingTaskGroup(of: Void.self) { group in
                                    group.addTask { await hydrationTask.value }
                                    group.addTask {
                                        try await Task.sleep(nanoseconds: 2_000_000_000)
                                        throw CancellationError()
                                    }
                                    try await group.next()
                                    group.cancelAll()
                                }
                            } catch {
                                // Timeout reached; proceed and let the images finish loading in the background
                            }
                        }
                    }
                }
            } catch {
                // --- Step 6: Failure Handling & Error State ---
                
                // Cancellation: the task was cancelled (e.g., user started a new scan via
                // prepareForNewScan). The scan is already durably in the offline queue, so
                // the background upload path will complete it — no credit refund needed.
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    return
                }

                if let apiError = error as? MerianError, apiError == .decodingFailed {
                    AppTelemetry.trackError("APIDecodingFailure")
                    // No refund: the scan is already durably in the offline queue and will be
                    // retried by the background upload path. Refunding here would give the user
                    // a free extra scan against a quota that was already consumed.
                    if self.activeScanId == ownedScanId {
                        HapticManager.shared.triggerErrorThump()
                        self.speciesData = makeErrorSpeciesData(
                            title: "Analysis Failed",
                            subtitle: "Data Unreadable",
                            reasoning: "The AI failed to understand the image or produced an unreadable schema.",
                            telemetry: telemetry
                        )
                    }
                    return
                }

                // Network failure — the scan is already in the offline queue and will be
                // retried by the background upload path. No refund or re-enqueue needed.
                AppTelemetry.trackError("InferenceNetworkFailure")
                CircuitBreakerManager.shared.recordFailure()
                MerianLog.general.debug("Inference failure: \(error.localizedDescription, privacy: .private)")
                if self.activeScanId == ownedScanId {
                    HapticManager.shared.triggerErrorThump()
                    self.speciesData = makeErrorSpeciesData(
                        title: "Network timeout",
                        subtitle: "Offline mode",
                        reasoning: "Please check your network connection and try again.",
                        telemetry: telemetry
                    )
                }
            }
        }
    }

    // MARK: - Describe Inference Pipeline

    /// Runs the text-only identification pipeline for a Describe submission.
    ///
    /// Mirrors `analyze()` structurally but accepts a verbal `ObservationContext` instead of
    /// image data. No offline queue enqueue — Describes are online-only in V1. No
    /// `validHistoricImagePaths` is set; the carousel will initially
    /// render black until GBIF reference images arrive via the post-inference hydration task.
    func analyzeDescribe(
        scanId: String?,
        observationContext: ObservationContext,
        telemetry: CaptureTelemetry,
        modelContext: ModelContext?,
        targetEradicationRecord: LocalScanRecord? = nil
    ) {
        guard !observationContext.isEmpty else { return }

        self.inferenceTask?.cancel()
        self.liveHydrationTask?.cancel()
        self.historicHydrationTask?.cancel()
        self.historicHydrationTask = nil
        self.gbifHydrationTask?.cancel()
        self.enrichmentWriteTask?.cancel()
        self.phaseRotationTask?.cancel()
        self.gbifHydrationTask = nil
        self.enrichmentWriteTask = nil

        // Reset loading flags synchronously — same pattern as analyze().
        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false
        self.scanningPhaseText = "Identifying describe..."

        self.activeObservationContext = nil
        self.activeScanId = scanId
        self.activeLatitude = telemetry.gpsLatitude
        self.activeLongitude = telemetry.gpsLongitude
        self.activeElevation = telemetry.gpsElevation
        self.activeLocationName = telemetry.locationName
        self.activeWeatherCondition = telemetry.weatherCondition
        self.activeTemperatureF = telemetry.weatherTemperatureF
        
        self.activeObservationContext = observationContext

        let ownedScanId = scanId

        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }

            defer {
                if self.activeScanId == ownedScanId {
                    self.isProcessing = false
                    self.activeScanId = nil
                }
                self.phaseRotationTask?.cancel()
            }

            do {
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }

                try Task.checkCancellation()

                let resultData = try await MerianNetworkClient.shared.identifyDescribe(
                    observationContext: observationContext,
                    telemetry: telemetry,
                    clientScanId: scanId
                )

                let describeObsContextJSON: String? = (try? JSONEncoder().encode(observationContext))
                    .flatMap { String(data: $0, encoding: .utf8) }
                let parseResult = try await InferenceProcessingActor.shared.parseAndSave(
                    resultData: resultData,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    compressedDatas: [],
                    displayDatas: [],
                    skipImageRequirement: true,
                    observationContextJSON: describeObsContextJSON
                )
                let finalMappedData = parseResult.mappedData
                let isNewDisc = parseResult.isNewDiscovery

                if var mappedData = finalMappedData {
                    if isNewDisc {
                        mappedData.isNewDiscovery = true
                        GamificationManager.shared.recordNewSpeciesDiscovered()
                    }

                    if let container = modelContext?.container {
                        let profileActor = OfflineQueueManager.shared.resolvedProfileDbActor(container: container)
                        let updatedAwards = await profileActor.calculateAwards()
                        GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards)
                    }

                    if let oldRecord = targetEradicationRecord {
                        if let context = modelContext {
                            if let newScanId = mappedData.scanId {
                                let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == newScanId })
                                if let newRecord = try? context.fetch(descriptor).first {
                                    newRecord.customTags = oldRecord.customTags
                                    if let oldCollections = oldRecord.collections, !oldCollections.isEmpty {
                                        newRecord.collections = oldCollections
                                    }
                                }
                            }
                            ScanRepository.shared.eradicateScan(record: oldRecord, modelContext: context)
                        } else {
                            assertionFailure("targetEradicationRecord provided but modelContext is nil")
                        }
                    }

                    CircuitBreakerManager.shared.recordSuccess()
                    AppTelemetry.trackScan(isPro: RevenueCatManager.shared.isProActive)

                    if self.activeScanId == ownedScanId {
                        HapticManager.shared.triggerHeavyImpact()
                        self.speciesData = mappedData
                        // No validHistoricImagePaths — describes have no captured image.
                    }

                    if UserDefaults.standard.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled),
                       let describeScanId = mappedData.scanId {
                        PushNotificationManager.shared.sendInferenceCompleteNotification(
                            speciesName: mappedData.commonName,
                            scanId: describeScanId
                        )
                    }

                    // Post-inference hydration — identical to analyze() path.
                    // Wikipedia + enrichment + GBIF images populate the carousel after the result appears.
                    if mappedData.isBiological {
                        let capturedScientificName = mappedData.scientificName
                        let capturedScanId = mappedData.scanId
                        let capturedGbifKey = mappedData.gbifTaxonKey
                        let capturedHasWikipedia = mappedData.wikipediaOverview != nil

                        liveHydrationTask = Task { [weak self] in
                            guard let self else { return }
                            let capturedIsEnriched = self.isSpeciesEnriched(capturedScientificName)

                            await withTaskGroup(of: Void.self) { group in
                                if !capturedHasWikipedia {
                                    group.addTask { @MainActor [weak self] in
                                        guard let self else { return }
                                        await self.fetchWikipediaAndHydrate(
                                            for: capturedScientificName,
                                            scanId: capturedScanId,
                                            modelContext: modelContext
                                        )
                                    }
                                }
                                group.addTask { @MainActor [weak self] in
                                    guard let self else { return }
                                    var taxonKeyToUse = capturedGbifKey
                                    if !capturedIsEnriched {
                                        await self.fetchAndApplyEnrichment(modelContext: modelContext)
                                        taxonKeyToUse = self.speciesData?.gbifTaxonKey ?? taxonKeyToUse
                                    }
                                    guard !Task.isCancelled else { return }
                                    if let key = taxonKeyToUse {
                                        await self.fetchGBIFImagesAndHydrate(
                                            for: key,
                                            scanId: capturedScanId,
                                            modelContext: modelContext
                                        )
                                    }
                                }
                            }

                            if !capturedIsEnriched && !Task.isCancelled,
                               self.speciesData?.habitatDescription != nil {
                                self.markSpeciesEnriched(capturedScientificName)
                            }
                        }
                        
                        // Wait up to 3 seconds for hydration so reference images are available before UI clears the "Identifying..." state.
                        if let hydrationTask = liveHydrationTask {
                            do {
                                try await withThrowingTaskGroup(of: Void.self) { group in
                                    group.addTask { await hydrationTask.value }
                                    group.addTask {
                                        try await Task.sleep(nanoseconds: 2_000_000_000)
                                        throw CancellationError()
                                    }
                                    try await group.next()
                                    group.cancelAll()
                                }
                            } catch {
                                // Timeout reached; proceed and let the images finish loading in the background
                            }
                        }
                    }
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }

                AppTelemetry.trackError("DescribeInferenceFailure")
                CircuitBreakerManager.shared.recordFailure()
                MerianLog.general.debug("Describe inference failure: \(error.localizedDescription, privacy: .private)")
                if self.activeScanId == ownedScanId {
                    HapticManager.shared.triggerErrorThump()
                    self.speciesData = makeErrorSpeciesData(
                        title: "Network timeout",
                        subtitle: "Please try again",
                        reasoning: "Please check your network connection and try again.",
                        telemetry: telemetry
                    )
                }
            }
        }
    }

    // MARK: - Audio Inference

    /// Fires the `audio_spec` edge function for bioacoustic species identification.
    ///
    /// Mirrors `analyzeDescribe` structurally. Always called in parallel with
    /// `OfflineQueueManager.enqueueAudio` so the scan is durable on interruption.
    func analyzeAudio(
        scanId: String?,
        audioFileName: String,
        telemetry: CaptureTelemetry,
        observationContext: ObservationContext? = nil,
        modelContext: ModelContext?
    ) {
        self.inferenceTask?.cancel()
        self.liveHydrationTask?.cancel()
        self.historicHydrationTask?.cancel()
        self.historicHydrationTask = nil
        self.gbifHydrationTask?.cancel()
        self.enrichmentWriteTask?.cancel()
        self.phaseRotationTask?.cancel()
        self.gbifHydrationTask = nil
        self.enrichmentWriteTask = nil

        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false
        self.scanningPhaseText = "Listening..."

        self.activeObservationContext = observationContext
        self.activeScanId = scanId
        self.activeLatitude = telemetry.gpsLatitude
        self.activeLongitude = telemetry.gpsLongitude
        self.activeElevation = telemetry.gpsElevation
        self.activeLocationName = telemetry.locationName
        self.activeWeatherCondition = telemetry.weatherCondition
        self.activeTemperatureF = telemetry.weatherTemperatureF

        let ownedScanId = scanId

        self.inferenceTask = Task { [weak self] in
            guard let self else { return }

            defer {
                if self.activeScanId == ownedScanId {
                    self.isProcessing = false
                    self.activeScanId = nil
                }
                self.phaseRotationTask?.cancel()
            }

            do {
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }

                try Task.checkCancellation()

                let contextJSON: String? = observationContext.flatMap { ctx in
                    guard !ctx.isEmpty else { return nil }
                    return (try? JSONEncoder().encode(ctx)).flatMap { String(data: $0, encoding: .utf8) }
                }

                let resultData = try await MerianNetworkClient.shared.identifyAudio(
                    audioFilePath: audioFileName,
                    telemetry: telemetry,
                    clientScanId: scanId,
                    observationContextJSON: contextJSON
                )

                let parseResult = try await InferenceProcessingActor.shared.parseAndSave(
                    resultData: resultData,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    compressedDatas: [],
                    displayDatas: [],
                    skipImageRequirement: true,
                    observationContextJSON: contextJSON
                )
                let finalMappedData = parseResult.mappedData
                let isNewDisc = parseResult.isNewDiscovery

                if var mappedData = finalMappedData {
                    if isNewDisc {
                        mappedData.isNewDiscovery = true
                        GamificationManager.shared.recordNewSpeciesDiscovered()
                    }

                    if let container = modelContext?.container {
                        let profileActor = OfflineQueueManager.shared.resolvedProfileDbActor(container: container)
                        let updatedAwards = await profileActor.calculateAwards()
                        GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards)
                    }

                    CircuitBreakerManager.shared.recordSuccess()
                    AppTelemetry.trackScan(isPro: RevenueCatManager.shared.isProActive)

                    if self.activeScanId == ownedScanId {
                        HapticManager.shared.triggerHeavyImpact()
                        self.speciesData = mappedData
                    }

                    // Flush the offline queue record so the background replay cycle doesn't
                    // make a redundant Gemini call on the same audio file. Audio always enqueues
                    // for durability, so unlike describe, there is always a record to clean up.
                    if let scanId = ownedScanId {
                        OfflineQueueManager.shared.flushOfflineQueuedScan(scanId: scanId)
                        executeTrackedBackgroundTask {
                            await OfflineQueueManager.shared.deleteQueuedScan(scanId: scanId)
                        }
                    }

                    if UserDefaults.standard.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled),
                       let audioScanId = mappedData.scanId {
                        PushNotificationManager.shared.sendInferenceCompleteNotification(
                            speciesName: mappedData.commonName,
                            scanId: audioScanId
                        )
                    }

                    if mappedData.isBiological {
                        let capturedScientificName = mappedData.scientificName
                        let capturedScanId = mappedData.scanId
                        let capturedGbifKey = mappedData.gbifTaxonKey
                        let capturedHasWikipedia = mappedData.wikipediaOverview != nil

                        liveHydrationTask = Task { [weak self] in
                            guard let self else { return }
                            let capturedIsEnriched = self.isSpeciesEnriched(capturedScientificName)

                            await withTaskGroup(of: Void.self) { group in
                                if !capturedHasWikipedia {
                                    group.addTask { @MainActor [weak self] in
                                        guard let self else { return }
                                        await self.fetchWikipediaAndHydrate(
                                            for: capturedScientificName,
                                            scanId: capturedScanId,
                                            modelContext: modelContext
                                        )
                                    }
                                }
                                group.addTask { @MainActor [weak self] in
                                    guard let self else { return }
                                    var taxonKeyToUse = capturedGbifKey
                                    if !capturedIsEnriched {
                                        await self.fetchAndApplyEnrichment(modelContext: modelContext)
                                        taxonKeyToUse = self.speciesData?.gbifTaxonKey ?? taxonKeyToUse
                                    }
                                    guard !Task.isCancelled else { return }
                                    if let key = taxonKeyToUse {
                                        await self.fetchGBIFImagesAndHydrate(
                                            for: key,
                                            scanId: capturedScanId,
                                            modelContext: modelContext
                                        )
                                    }
                                }
                            }

                            if !capturedIsEnriched && !Task.isCancelled,
                               self.speciesData?.habitatDescription != nil {
                                self.markSpeciesEnriched(capturedScientificName)
                            }
                        }

                        if let hydrationTask = liveHydrationTask {
                            do {
                                try await withThrowingTaskGroup(of: Void.self) { group in
                                    group.addTask { await hydrationTask.value }
                                    group.addTask {
                                        try await Task.sleep(nanoseconds: 2_000_000_000)
                                        throw CancellationError()
                                    }
                                    try await group.next()
                                    group.cancelAll()
                                }
                            } catch {
                                // Timeout; hydration continues in background
                            }
                        }
                    }
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }

                AppTelemetry.trackError("AudioInferenceFailure")
                CircuitBreakerManager.shared.recordFailure()
                MerianLog.general.debug("Audio inference failure: \(error.localizedDescription, privacy: .private)")
                if self.activeScanId == ownedScanId {
                    HapticManager.shared.triggerErrorThump()
                    self.speciesData = makeErrorSpeciesData(
                        title: "Network timeout",
                        subtitle: "Please try again",
                        reasoning: "Please check your network connection and try again.",
                        telemetry: telemetry
                    )
                }
            }
        }
    }

    // MARK: - Error State Factory

    /// Builds an error-placeholder `SpeciesData` for the two failure paths in `analyze()`.
    /// Both branches share identical field layout — only the title, subtitle, and reasoning differ.
    private func makeErrorSpeciesData(
        title: String,
        subtitle: String,
        reasoning: String,
        telemetry: CaptureTelemetry
    ) -> SpeciesData {
        SpeciesData(
            scanId: nil,
            commonName: title,
            scientificName: subtitle,
            insightData: InsightData(aiReasoning: reasoning, hazardType: "none"),
            confidenceScore: 0,
            blurScore: nil,
            similarSpecies: nil,
            wikipediaUrl: nil,
            wikipediaOverview: nil,
            referenceImageUrl: nil,
            isBiological: false,
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
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/mobile-sections/\(encoded)") else { return }

        var request = URLRequest(url: url)
        // mobile-sections payload is larger than summary — allow extra headroom.
        request.timeoutInterval = 8.0
        request.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await InferenceEngine.externalAPISession.data(for: request)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return }

            // Decode and parse off @MainActor — mobile-sections payloads are 20–150 KB of raw HTML.
            // JSONDecoder + 6× string replacements + regex on the main run loop produces a visible
            // jank spike right as the user is watching scan results populate.
            let capturedNormalized = normalized
            let (descriptionText, webUrl, imageUrl) = try await Task.detached(priority: .utility) {
                let decoded = try JSONDecoder().decode(WikiMobileSectionsResponse.self, from: data)
                let descSection = decoded.remaining.sections.first {
                    $0.title?.caseInsensitiveCompare("Description") == .orderedSame
                }
                guard let rawHTML = descSection?.text, !rawHTML.isEmpty else {
                    throw WikiContentNotFound()
                }
                let text = Self.stripHTML(rawHTML)
                guard !text.isEmpty else { throw WikiContentNotFound() }
                let pageTitle = (decoded.lead.normalizedtitle ?? capturedNormalized)
                    .replacingOccurrences(of: " ", with: "_")
                let encodedTitle = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pageTitle
                let url = "https://en.wikipedia.org/wiki/\(encodedTitle)"
                return (text, url, decoded.lead.originalimage?.source)
            }.value

            // Mark as attempted only on success — transient failures (timeout, 404) remain retryable.
            wikiFetchAttemptedIds.insert(species)

            await MainActor.run {
                // Individual optional-chain mutations (self.speciesData?.field = x) do not
                // reliably fire @Observable notifications for struct value types; a single
                // full-value replacement is the only guaranteed trigger.
                if var updated = self.speciesData, updated.scientificName == species {
                    updated.wikipediaOverview = descriptionText
                    updated.wikipediaUrl = webUrl
                    if let img = imageUrl, !img.isEmpty {
                        updated.referenceImageUrl = img
                    }
                    self.speciesData = updated
                }
            }

            if let scanId = scanId, let context = modelContext {
                let container = context.container
                // Route through executeTrackedBackgroundTask: bounded by the cap and
                // cancelled by prepareForNewScan() / cancelActiveRequest() so a stale
                // wiki write cannot touch a record that is no longer active.
                executeTrackedBackgroundTask {
                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
                    await dbActor.updateScanWithWikipedia(scanId: scanId, extract: descriptionText, url: webUrl, imageUrl: imageUrl)
                }
            }
        } catch {
            MerianLog.general.debug("Wikipedia hydration skipped: \(error, privacy: .private)")
        }
    }

    /// Strips HTML tags and decodes common entities from a Wikipedia section's raw HTML text.
    private nonisolated static func stripHTML(_ html: String) -> String {
        var result = html
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        // Collapse runs of blank lines left by stripped block elements.
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - GBIF Background Hydration

    /// Fetches high-quality field observations from GBIF (e.g. iNaturalist) once the Taxon Key is known.
    /// This acts as a robust supplement/fallback to Wikipedia imagery.
    private func fetchGBIFImagesAndHydrate(for taxonKey: Int, scanId: String?, modelContext: ModelContext?) async {
        guard let url = URL(string: "https://api.gbif.org/v1/occurrence/search?taxonKey=\(taxonKey)&mediaType=StillImage&limit=4") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0

        do {
            let (data, response) = try await InferenceEngine.externalAPISession.data(for: request)
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
            if var updated = self.speciesData, updated.scanId == scanId {
                var currentUrls = updated.referenceImageUrl?
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty } ?? []

                for urlStr in newUrls where !currentUrls.contains(urlStr) {
                    currentUrls.append(urlStr)
                }

                // Cap at 5 URLs to prevent unbounded referenceImageUrl string growth across sessions.
                let capped = Array(currentUrls.prefix(5))
                updated.referenceImageUrl = capped.joined(separator: ",")
                persistUrls = updated.referenceImageUrl
                // Single full-value replacement — see fetchAndApplyEnrichment comment.
                self.speciesData = updated
            }

            if let scanId = scanId, let context = modelContext, let finalUrls = persistUrls {
                let container = context.container
                executeTrackedBackgroundTask {
                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
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
        guard enrichmentRateLimitedUntil.map({ $0 <= Date.now }) ?? true else { return }

        if needsMetadata { isEnrichmentLoading = true }
        if needsLookalikes { isLookalikesLoading = true }

        let capturedScanId = scanId
        let capturedScientificName = data.scientificName
        let capturedConfidence = data.confidenceScore
        let capturedTier = data.inferenceTier ?? "flash"

        await withTaskGroup(of: Void.self) { group in
            if needsMetadata {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    defer { if self.speciesData?.scanId == capturedScanId { self.isEnrichmentLoading = false } }
                    do {
                        let response = try await MerianNetworkClient.shared.fetchEnrichment(
                            scanId: capturedScanId,
                            scientificName: capturedScientificName,
                            confidenceScore: capturedConfidence,
                            inferenceTier: capturedTier,
                            scope: "enrichment"
                        )
                        guard let enrichData = response.data else { return }

                        // Collect all enrichment mutations into a local copy, then assign once.
                        // Individual optional-chain mutations (self.speciesData?.field = x) do not
                        // reliably fire @Observable notifications for struct value types; a single
                        // full-value replacement is the only guaranteed trigger.
                        // Guard on scanId: a stale enrichment task completing after a new scan
                        // has already set speciesData must not overwrite the new scan's fields.
                        if var updated = self.speciesData, self.speciesData?.scanId == capturedScanId {
                            updated.habitatDescription = enrichData.habitat_description
                            if let tax = enrichData.taxonomy {
                                updated.taxonomy = TaxonomyData(
                                    kingdom: tax.kingdom,
                                    phylum: tax.phylum,
                                    className: tax.`class`,
                                    order: tax.order,
                                    family: tax.family,
                                    genus: tax.genus
                                )
                            }
                            if let key = enrichData.gbif_taxon_key {
                                updated.gbifTaxonKey = key
                            }
                            if let names = enrichData.alternative_common_names {
                                updated.alternativeCommonNames = SpeciesData.sanitizeAlternativeNames(names)
                            }
                            self.speciesData = updated  // Single @Observable-triggering assignment
                        }
                        if let key = enrichData.gbif_taxon_key {
                            // Assign immediately on @MainActor so prepareForNewScan() / cancelActiveRequest()
                            // can always cancel this handle regardless of when the enrichment DB write completes.
                            // Late assignment (inside enrichmentWriteTask) would leave gbifHydrationTask nil
                            // during the write, causing a cancel race where the fetch leaks into the next scan.
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
                            let altNamesSnapshot = enrichData.alternative_common_names
                            self.enrichmentWriteTask?.cancel()
                            self.enrichmentWriteTask = Task {
                                guard !Task.isCancelled else { return }
                                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                                await dbActor.updateScanWithEnrichment(
                                    scanId: capturedScanId,
                                    habitatDescription: habitatSnapshot,
                                    gbifTaxonKey: gbifSnapshot,
                                    similarSpeciesJsonData: nil,
                                    taxonomy: taxonomySnapshot,
                                    alternativeCommonNames: altNamesSnapshot
                                )
                            }
                        }
                    } catch let error as MerianError {
                        if case .httpError(let code, _) = error, code == 403 { return }
                        if case .httpError(let code, _) = error, code == 429 {
                            self.enrichmentRateLimitedUntil = Date.now.addingTimeInterval(60)
                            return
                        }
                        MerianLog.general.debug("Enrichment scope failed: \(error, privacy: .private)")
                    } catch {
                        MerianLog.general.debug("Enrichment scope failed: \(error, privacy: .private)")
                    }
                }
            }

            if needsLookalikes {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    defer { if self.speciesData?.scanId == capturedScanId { self.isLookalikesLoading = false } }
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
                            let mappedEntries = entries.map {
                                let splitCommonName = $0.common_name?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                                return SimilarSpeciesEntry(
                                    scientificName: $0.scientific_name,
                                    commonName: splitCommonName,
                                    referenceImageUrl: $0.reference_image_url,
                                    iucnRedListStatus: $0.iucn_red_list_status
                                )
                            }
                            // Single full-value replacement — see enrichment scope comment above.
                            // Guard on scanId: a stale lookalikes task completing after a new scan
                            // has set speciesData must not overwrite the new scan's similar species.
                            if var updated = self.speciesData, self.speciesData?.scanId == capturedScanId {
                                updated.similarSpecies = SimilarSpecies(entries: mappedEntries)
                                self.speciesData = updated
                            }
                            if let context = modelContext {
                                let container = context.container
                                let entriesToEncode: [SimilarSpeciesEntry]? = mappedEntries
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
                        if case .httpError(let code, _) = error, code == 429 {
                            self.enrichmentRateLimitedUntil = Date.now.addingTimeInterval(60)
                            return
                        }
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
        // Wipe stale contextual data to prevent old UI cards from lingering during the fetch.
        // Full-value replacement guarantees a single @Observable notification for the entire wipe.
        if var updated = speciesData {
            updated.userIdentificationOverride = scientificName
            updated.scientificName = scientificName
            updated.commonName = scientificName
            updated.insightData = InsightData(aiReasoning: "", hazardType: "none")
            updated.wikipediaOverview = nil
            updated.wikipediaUrl = nil
            updated.referenceImageUrl = nil
            updated.iucnRedListStatus = nil
            updated.habitatDescription = nil
            updated.gbifTaxonKey = nil
            updated.similarSpecies = nil
            updated.userConfirmedIdentification = false
            updated.isFlagged = false
            updated.alternativesExhausted = false
            speciesData = updated
        }

        // 2. Fetch and patch species data for the override species first, so we obtain the UUID.
        let confirmedId = await fetchAndPatchOverrideData(scientificName: scientificName, scanId: scanId, modelContext: modelContext)

        // 3. Persist to SwiftData.
        if let context = modelContext {
            let container = context.container
            Task {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanWithOverride(scanId: scanId, override: scientificName, confirmed: false, newConfirmedSpeciesId: confirmedId, userReviewState: .userOverridden)
            }
        }

        // 4. Cloud sync — IDOR-guarded direct PostgREST update.
        executeTrackedBackgroundTask { [weak self] in
            guard let self else { return }
            await self.syncIdentificationReviewToCloud(scanId: scanId, override: scientificName, confirmed: false, confirmedSpeciesId: confirmedId, userReviewState: UserReviewState.userOverridden.rawValue)
        }
    }

    /// Called when the user confirms the AI's primary identification ("Yes, correct").
    /// Persists locally and syncs confirmation to the cloud scan record.
    func confirmAIIdentification(modelContext: ModelContext?) async {
        guard let scanId = speciesData?.scanId else { return }

        speciesData?.userConfirmedIdentification = true

        var activeSpeciesId: String?
        if let context = modelContext {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
            activeSpeciesId = (try? context.fetch(descriptor))?.first?.speciesId

            let container = context.container
            let confirmedSpeciesId = activeSpeciesId
            executeTrackedBackgroundTask {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanWithOverride(scanId: scanId, override: nil, confirmed: true, newConfirmedSpeciesId: confirmedSpeciesId, userReviewState: .aiConfirmed)
            }
        }

        let capturedSpeciesId = activeSpeciesId
        executeTrackedBackgroundTask { [weak self] in
            guard let self else { return }
            await self.syncIdentificationReviewToCloud(scanId: scanId, override: nil, confirmed: true, confirmedSpeciesId: capturedSpeciesId, userReviewState: UserReviewState.aiConfirmed.rawValue)
        }
    }

    /// Called when the user flags an identification for manual review because no models matched.
    /// Mutates the local display state and persists the flag local-only via the `isFlagged` column.
    func flagAIIdentification(modelContext: ModelContext?) async {
        guard let scanId = speciesData?.scanId else { return }

        speciesData?.isFlagged = true
        speciesData?.alternativesExhausted = false

        if let context = modelContext {
            let container = context.container
            executeTrackedBackgroundTask {
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
            executeTrackedBackgroundTask {
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
        speciesData?.isFlagged = false
        speciesData?.alternativesExhausted = false
        speciesData?.scientificName = aiName

        // 2. Persist all reset fields locally.
        if let context = modelContext {
            let container = context.container
            executeTrackedBackgroundTask {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanWithOverride(scanId: scanId, override: nil, confirmed: false, newConfirmedSpeciesId: nil, userReviewState: .unreviewed)
                await dbActor.updateScanAsUnflagged(scanId: scanId)
            }
        }

        // 3. Zero both cloud columns.
        executeTrackedBackgroundTask { [weak self] in
            guard let self else { return }
            await self.syncIdentificationReviewToCloud(scanId: scanId, override: nil, confirmed: false, confirmedSpeciesId: nil, userReviewState: UserReviewState.unreviewed.rawValue)
        }

        // 4. Re-hydrate the AI's original species data from species_dictionary.
        // Read the original aiReasoning from the record so it reappears after undo.
        // The record is always accessible on @MainActor here; modelContext is never crossed
        // into a concurrent scope at this point.
        var originalAiReasoning: String?
        if let context = modelContext {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
            originalAiReasoning = (try? context.fetch(descriptor))?.first?.aiReasoning
        }
        await fetchAndPatchOverrideData(scientificName: aiName, scanId: scanId, modelContext: modelContext, restoringAiReasoning: originalAiReasoning)
    }

    /// Queries `species_dictionary` for the given scientific name and patches the live
    /// `speciesData` in-place. On cache miss, falls through to `fetchAndApplyEnrichment`
    /// which triggers the full enrichment pipeline for the override species.
    ///
    /// - Parameter restoringAiReasoning: When non-nil, the AI reasoning text is restored to
    ///   this value instead of being wiped. Pass the original `record.aiReasoning` when
    ///   called from `resetIdentificationReview` so the reasoning reappears after an undo.
    ///   Pass nil (default) when called from `applyIdentificationOverride` to suppress the
    ///   original AI reasoning under the override species name.
    @MainActor
    @discardableResult
    private func fetchAndPatchOverrideData(scientificName: String, scanId: String?, modelContext: ModelContext?, restoringAiReasoning: String? = nil) async -> String? {
        struct SpeciesDictRow: Decodable {
            let id: String
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
        
        struct IdOnlyRow: Decodable { let id: String }

        do {
            let rows: [SpeciesDictRow] = try await SupabaseManager.shared.client
                .from("species_dictionary")
                .select("id, common_names, kingdom, phylum, class, order, family, genus, wikipedia_overview, hazard_type, reference_image_url, wikipedia_url, iucn_red_list_status, habitat_description, gbif_taxon_key")
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
                // On override: wipe aiReasoning — the AI's explanation was for the rejected species.
                // On reset (restoringAiReasoning != nil): restore the original reasoning so the
                // paragraph reappears under the reverted AI identification.
                //
                // Individual optional-chain mutations (speciesData?.field = x) do not reliably
                // fire @Observable notifications for struct value types; a single full-value
                // replacement is the only guaranteed trigger.
                if var updated = speciesData {
                    updated.commonName = commonName.capitalized
                    updated.insightData = InsightData(
                        aiReasoning: restoringAiReasoning ?? "",
                        hazardType: row.hazard_type ?? "none"
                    )
                    updated.taxonomy = TaxonomyData(
                        kingdom: row.kingdom,
                        phylum: row.phylum,
                        className: row.class,
                        order: row.order,
                        family: row.family,
                        genus: row.genus
                    )
                    updated.iucnRedListStatus = row.iucn_red_list_status
                    updated.habitatDescription = row.habitat_description
                    updated.gbifTaxonKey = row.gbif_taxon_key
                    updated.referenceImageUrl = row.reference_image_url
                    updated.wikipediaOverview = row.wikipedia_overview
                    updated.wikipediaUrl = row.wikipedia_url
                    speciesData = updated
                }

                // Persist updated species fields so they survive sheet dismissal and reopen.
                // scientificName is intentionally excluded — it is preserved as aiScientificName.
                if let scanId, let context = modelContext {
                    let container = context.container
                    let capturedCommonName = commonName.capitalized
                    let capturedHazardType = row.hazard_type ?? "none"
                    let capturedTaxonomy = TaxonomyData(
                        kingdom: row.kingdom, phylum: row.phylum, className: row.class,
                        order: row.order, family: row.family, genus: row.genus
                    )
                    let capturedWikiOverview = row.wikipedia_overview
                    let capturedWikiUrl = row.wikipedia_url
                    let capturedRefImageUrl = row.reference_image_url
                    let capturedIucn = row.iucn_red_list_status
                    let capturedHabitat = row.habitat_description
                    let capturedGbif = row.gbif_taxon_key
                    executeTrackedBackgroundTask {
                        let dbActor = BackgroundDatabaseActor(modelContainer: container)
                        await dbActor.updateScanWithOverrideSpeciesData(
                            scanId: scanId,
                            commonName: capturedCommonName,
                            hazardType: capturedHazardType,
                            wikipediaOverview: capturedWikiOverview,
                            wikipediaUrl: capturedWikiUrl,
                            referenceImageUrl: capturedRefImageUrl,
                            iucnRedListStatus: capturedIucn,
                            habitatDescription: capturedHabitat,
                            gbifTaxonKey: capturedGbif,
                            taxonomy: capturedTaxonomy
                        )
                    }
                }
                return row.id
            } else {
                // Cache miss — enrich the override species. fetchAndApplyEnrichment uses
                // speciesData.scientificName which is already set to the override name.
                // Persist the scientific name as a commonName placeholder so the title survives
                // sheet reopen before enrichment data arrives.
                if let scanId, let context = modelContext {
                    let container = context.container
                    let capturedScientificName = scientificName
                    executeTrackedBackgroundTask {
                        let dbActor = BackgroundDatabaseActor(modelContainer: container)
                        await dbActor.updateScanWithOverrideSpeciesData(
                            scanId: scanId,
                            commonName: capturedScientificName,
                            hazardType: "none",
                            wikipediaOverview: nil,
                            wikipediaUrl: nil,
                            referenceImageUrl: nil,
                            iucnRedListStatus: nil,
                            habitatDescription: nil,
                            gbifTaxonKey: nil,
                            taxonomy: nil
                        )
                    }
                }
                await fetchAndApplyEnrichment(modelContext: modelContext)

                let fallbackRows: [IdOnlyRow]? = try? await SupabaseManager.shared.client
                    .from("species_dictionary")
                    .select("id")
                    .eq("scientific_name", value: scientificName)
                    .limit(1)
                    .execute()
                    .value
                return fallbackRows?.first?.id
            }
        } catch {
            MerianLog.general.debug("fetchAndPatchOverrideData failed: \(error, privacy: .private)")
            
            let fallbackRows: [IdOnlyRow]? = try? await SupabaseManager.shared.client
                .from("species_dictionary")
                .select("id")
                .eq("scientific_name", value: scientificName)
                .limit(1)
                .execute()
                .value
            return fallbackRows?.first?.id
        }
    }

    /// IDOR-guarded direct PostgREST update persisting both identification review fields.
    /// Accepts nil for `override` to set the column to NULL (reset / confirmed-only path).
    private func syncIdentificationReviewToCloud(scanId: String, override: String?, confirmed: Bool, confirmedSpeciesId: String?, userReviewState: String) async {
        guard let userId = await MainActor.run(body: { SupabaseManager.shared.currentUser?.id.uuidString }) else { return }

        struct ReviewSyncPayload: Encodable {
            let user_identification_override: String?
            let user_confirmed_identification: Bool
            let confirmed_species_id: String?
            let user_review_state: String
        }

        do {
            try await SupabaseManager.shared.client
                .from("scans")
                .update(ReviewSyncPayload(user_identification_override: override,
                                         user_confirmed_identification: confirmed,
                                         confirmed_species_id: confirmedSpeciesId,
                                         user_review_state: userReviewState))
                .eq("id", value: scanId)
                .eq("user_id", value: userId)
                .execute()
        } catch {
            MerianLog.general.debug("syncIdentificationReviewToCloud failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Pipeline Modifiers

    /// Cancels all in-flight work and resets the engine to idle.
    ///
    /// Contrast with `prepareForNewScan()`, which also cancels in-flight work but leaves
    /// `isProcessing = true` in anticipation of an *upcoming* scan. `cancelActiveRequest`
    /// resets to `isProcessing = false, speciesData = nil` — appropriate when the user
    /// dismisses the insight sheet with no new scan queued.
    func cancelActiveRequest(isUserInitiated: Bool = false) {
        // NOTE: activeScanId is intentionally NOT cleared here.
        // processInferenceDownloadResult reads activeScanId to detect the background-wins race
        // (background URLSession completing while the live task is suspended). Clearing it here
        // would break that detection. activeScanId is owned exclusively by:
        //   - The inferenceTask's defer block (clears after task exits)
        //   - prepareForNewScan() (clears synchronously before the next scan starts)
        self.isProcessing = false
        self.inferenceTask?.cancel()
        self.liveHydrationTask?.cancel()
        self.historicHydrationTask?.cancel()
        self.phaseRotationTask?.cancel()
        for task in self.backgroundWriteTasks.values { task.cancel() }
        self.backgroundWriteTasks.removeAll()
        // Cancel GBIF hydration so stale image URLs cannot be written to a record
        // that is no longer active after the user fires a new scan or navigates away.
        self.gbifHydrationTask?.cancel()
        self.gbifHydrationTask = nil
        // Cancel the enrichment SwiftData write so it cannot trigger a spurious @Query
        // invalidation on a subsequently opened scan's UI.
        self.enrichmentWriteTask?.cancel()
        self.enrichmentWriteTask = nil
        // Reset loading flags synchronously so stale defer blocks from cancelled task group
        self.scanningPhaseText = "Analyzing subject..."
        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false
        self.isReferenceImageLoading = false
        self.speciesData = nil
        activeImageData = nil
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

        if var updated = self.speciesData, let currentRef = updated.referenceImageUrl {
            var parts = currentRef.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if let idx = parts.firstIndex(of: urlStr) {
                parts.remove(at: idx)
                let joined = parts.joined(separator: ",")
                updated.referenceImageUrl = joined.isEmpty ? nil : joined
                self.speciesData = updated
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
        gbifHydrationTask?.cancel()

        self.activeScanId = record.id
        self.activeImageData = nil
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
        // When a manual override is active, display the override scientific name as the title.
        // record.scientificName is preserved as the original-AI identifier and reused below
        // as aiScientificName so that resetIdentificationReview can recover it without a new
        // schema field.
        let displayScientificName: String = overrideName ?? record.scientificName
        // Suppress AI reasoning when an override is active — it was written for the originally
        // predicted species and is misleading when displayed under the override species name.
        let displayAiReasoning: String = overrideName == nil ? (record.aiReasoning ?? "") : ""
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
            scientificName: displayScientificName,
            insightData: InsightData(aiReasoning: displayAiReasoning, hazardType: record.hazardType),
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
            alternativeCommonNames: record.alternativeCommonNames,
            candidates: nil,
            imageQualityScore: record.imageQualityScore,
            aiScientificName: recordScientificName,
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
            if var updated = self.speciesData {
                updated.similarSpecies = parsedSimilar
                updated.candidates = parsedCandidates
                self.speciesData = updated
            }

            // Step 3: If an identification override is active, patch in the override species data.
            if let override = overrideName {
                guard !Task.isCancelled else { return }
                await self.fetchAndPatchOverrideData(scientificName: override, scanId: recordId, modelContext: safeContext)
            }

            // Steps 4 & 5: Retroactive Wikipedia hydration, Enrichment, and GBIF-image hydration.
            // Run Wikipedia and Enrichment concurrently. GBIF images run sequentially after Enrichment.
            await withTaskGroup(of: Void.self) { group in
                if needsWiki {
                    group.addTask { @MainActor [weak self] in
                        guard let self else { return }
                        guard !Task.isCancelled else { return }
                        await self.fetchWikipediaAndHydrate(for: recordScientificName, scanId: recordId, modelContext: safeContext)
                    }
                }

                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    var taxonKeyToUse = gbifKey

                    // Enrichment: Two gates prevent redundant calls (scan-ID-scoped and species-name-scoped).
                    if needsEnrichment
                        && !self.enrichmentAttemptedScanIds.contains(recordId)
                        && !self.isSpeciesEnriched(recordScientificName) {
                        guard !Task.isCancelled else { return }
                        // Evict 10% on cap hit to bound session-scoped set growth.
                        if self.enrichmentAttemptedScanIds.count >= self.sessionSetCap {
                            self.enrichmentAttemptedScanIds.subtract(self.enrichmentAttemptedScanIds.prefix(self.sessionSetCap / 10))
                        }
                        self.enrichmentAttemptedScanIds.insert(recordId)
                        await self.fetchAndApplyEnrichment(modelContext: safeContext, needsMetadata: needsMetadata, needsLookalikes: needsLookalikes)
                        if !Task.isCancelled {
                            self.markSpeciesEnriched(recordScientificName)
                        }
                        taxonKeyToUse = self.speciesData?.gbifTaxonKey ?? taxonKeyToUse
                    }

                    if let key = taxonKeyToUse, recordIsBiological {
                        guard !Task.isCancelled else { return }
                        await self.fetchGBIFImagesAndHydrate(for: key, scanId: recordId, modelContext: safeContext)
                    }
                }
            }
        }
    }

    // MARK: - On-Device Subject Study

    /// Sequential multi-pass Vision pipeline — each request runs off the main actor and
    /// streams its observation to the UI the moment that model completes.
    /// Phase rotation is updated independently in parallel via a fire-and-forget Task.
    private func classifySubjectLocally(from data: Data) {
        var shuffled = Self.genericFallbackPhrases
        let anchor = shuffled.removeFirst()
        shuffled.shuffle()
        shuffled.insert(anchor, at: 0)
        startPhaseRotation(phrases: shuffled)

        HapticManager.shared.triggerLightImpact(intensity: 0.3)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Downsample once
            guard let cgImage = ImageDownsampler.downsample(data: data, maxSize: 512) else {
                return
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            // ── Pass 1: Broad classification ─────────────────────────────────
            let classifyReq = VNClassifyImageRequest()
            autoreleasepool { try? handler.perform([classifyReq]) }
            let observations = classifyReq.results ?? []

            guard !Task.isCancelled else { return }
            
            let specificPhrases = Self.specificPhraseSeries(for: observations) ?? Self.genericFallbackPhrases
            
            await MainActor.run { [weak self] in 
                guard let self else { return }
                self.startPhaseRotation(phrases: specificPhrases, startIndex: 0)
            }
        }
    }

    private func startPhaseRotation(phrases: [String], startIndex: Int = 0) {
        phaseRotationTask?.cancel()
        phaseRotationTask = Task { @MainActor [weak self] in
            guard !phrases.isEmpty else { return }
            var index = startIndex % phrases.count
            
            // If passing off sequentially, we don't delay to hit the next phrase immediately
            guard !Task.isCancelled else { return }
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: MerianConfig.scanningPhaseRotationIntervalNs)
                guard !Task.isCancelled else { break }
                guard let self else { return }
                self.scanningPhaseText = phrases[index]
                index = (index + 1) % phrases.count
            }
        }
    }

    #if DEBUG
    /// Simulates a live analyzing state for UI development — starts phase rotation
    /// so the badge cycles visibly without requiring a real scan submission.
    func simulateAnalyzing() {
        isProcessing = true
        startPhaseRotation(phrases: [
            "Arthropod detected",
            "Analyzing wing venation",
            "Analyzing body segmentation",
            "Analyzing field markers",
            "Checking taxonomic indicators",
            "Checking entomology records",
            "Checking regional distribution",
            "Confirming species..."
        ])
    }
    #endif

    private nonisolated static let genericFallbackPhrases: [String] = [
        "Scanning subject...",
        "Analyzing subject morphology",
        "Analyzing biological traits",
        "Analyzing structural patterns",
        "Checking taxonomic data",
        "Checking species records",
        "Checking habitat context",
        "Identifying species..."
    ]

    private nonisolated static func specificPhraseSeries(for observations: [VNClassificationObservation]) -> [String]? {
        guard let top = observations.first, top.confidence >= MerianConfig.visionConfidenceThreshold else { return nil }
        if observations.count >= 2 { guard top.confidence - observations[1].confidence >= MerianConfig.visionMarginThreshold else { return nil } }

        let id = top.identifier.lowercased()

        if id.contains("bird") || id.contains("avian") || id.contains("raptor") || id.contains("songbird") || id.contains("waterfowl") || id.contains("owl") {
            return ["Avian detected", "Analyzing plumage", "Analyzing bill morphology", "Checking seasonal variation", "Checking eBird records", "Checking geographic range", "Checking subspecies", "Confirming species..."]
        }
        if id.contains("insect") || id.contains("arthropod") || id.contains("butterfly") || id.contains("moth") || id.contains("bee") || id.contains("beetle") || id.contains("fly") || id.contains("ant") || id.contains("wasp") || id.contains("dragonfly") || id.contains("cricket") || id.contains("grasshopper") {
            return ["Arthropod detected", "Analyzing wing venation", "Analyzing body segmentation", "Analyzing field markers", "Checking taxonomic indicators", "Checking entomology records", "Checking regional distribution", "Confirming species..."]
        }
        if id.contains("spider") || id.contains("arachnid") || id.contains("scorpion") || id.contains("tick") || id.contains("mite") {
            return ["Arachnid detected", "Analyzing body segmentation", "Analyzing appendage morphology", "Analyzing leg spinnerets", "Checking taxonomic data", "Checking arachnology records", "Checking occurrence records", "Confirming species..."]
        }
        if id.contains("mushroom") || id.contains("fungi") || id.contains("fungus") || id.contains("lichen") {
            return ["Fungal specimen", "Analyzing cap morphology", "Analyzing gill structure", "Analyzing surface coloration", "Checking substrate context", "Checking mycology records", "Checking fruiting patterns", "Confirming species..."]
        }
        if id.contains("flower") || id.contains("blossom") || id.contains("bloom") {
            return ["Flowering plant", "Analyzing petal arrangement", "Analyzing reproductive structures", "Analyzing inflorescence pattern", "Checking pollinator associations", "Checking botanical records", "Checking flora records", "Confirming species..."]
        }
        if id.contains("tree") || id.contains("conifer") || id.contains("palm") {
            return ["Arboreal detected", "Analyzing bark texture", "Analyzing leaf form", "Analyzing growth habit", "Checking fruit characteristics", "Checking botanical records", "Checking elevation range", "Confirming species..."]
        }
        if id.contains("cactus") || id.contains("cactaceae") || id.contains("succulent") {
            return ["Succulent detected", "Analyzing spine patterns", "Analyzing stem morphology", "Analyzing growth form", "Analyzing surface texture", "Checking flora records", "Checking native range", "Confirming species..."]
        }
        if id.contains("plant") || id.contains("leaf") || id.contains("vegetation") || id.contains("shrub") || id.contains("grass") || id.contains("fern") || id.contains("moss") || id.contains("algae") || id.contains("vine") {
            return ["Botanical detected", "Analyzing leaf morphology", "Analyzing structural patterns", "Analyzing growth habit", "Checking field markers", "Checking flora records", "Checking native range", "Confirming species..."]
        }
        if id.contains("reptile") || id.contains("snake") || id.contains("lizard") || id.contains("turtle") || id.contains("crocodile") || id.contains("gecko") {
            return ["Reptilian detected", "Analyzing scale patterns", "Analyzing body plan", "Analyzing dorsal pattern", "Checking taxonomic data", "Checking herpetology records", "Checking population data", "Confirming species..."]
        }
        if id.contains("amphibian") || id.contains("frog") || id.contains("toad") || id.contains("salamander") || id.contains("newt") || id.contains("caecilian") {
            return ["Amphibian detected", "Analyzing skin texture", "Analyzing body form", "Checking taxonomic indicators", "Analyzing call signatures", "Checking herpetology records", "Checking wetland habitat", "Confirming species..."]
        }
        if id.contains("fish") || id.contains("shark") || id.contains("ray") || id.contains("eel") || id.contains("salmon") || id.contains("trout") {
            return ["Aquatic vertebrate", "Analyzing fin morphology", "Analyzing lateral line", "Analyzing lateral coloration", "Analyzing body shape", "Checking ichthyology records", "Checking watershed data", "Confirming species..."]
        }
        if id.contains("mammal") || id.contains("dog") || id.contains("cat") || id.contains("deer") || id.contains("fox") || id.contains("bear") || id.contains("rabbit") || id.contains("squirrel") || id.contains("raccoon") || id.contains("rodent") || id.contains("primate") {
            return ["Mammalian detected", "Analyzing body proportions", "Analyzing pelage detail", "Checking behavioural markers", "Checking geographic range", "Checking habitat indicators", "Checking population range", "Confirming species..."]
        }
        return nil
    }

    func markAlternativesExhausted() {
        speciesData?.alternativesExhausted = true
    }
}
