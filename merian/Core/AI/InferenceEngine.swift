import Foundation
import CoreImage
import Combine
import SwiftUI
import SwiftData
import ImageIO
import os

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

    // MARK: - Background Rescue State
    /// Set to `true` by `cancelActiveRequest()` before cancelling the task, so the task's
    /// cancellation handler knows the scan was intentionally backgrounded and should not refund.
    private(set) var isBackgroundRescued = false
    @ObservationIgnored private var wikiFetchAttemptedIds: Set<String> = []

    // MARK: - Live Inference Pipeline

    func analyze(imageDatas: [Data], telemetry: CaptureTelemetry, modelContext: ModelContext? = nil) {
        guard !imageDatas.isEmpty else { return }
        self.inferenceTask?.cancel()

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
        self.activeDistanceInMeters = telemetry.subjectDistanceInMeters

        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }

            // Single exit point for isProcessing — covers all success, error, and cancellation paths.
            defer { self.isProcessing = false }

            let pipelineStart = CFAbsoluteTimeGetCurrent()
            let compressedDatas = imageDatas
            self.activeCompressedImageData = compressedDatas.first

            do {
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }

                let client = MerianNetworkClient.shared

                let base64Strings = await InferenceProcessingActor.shared.encodeBase64(compressedDatas: compressedDatas)
                let targetObjectKey = "staging/\(UUID().uuidString).jpg"

                try Task.checkCancellation()

                let inferenceStart = CFAbsoluteTimeGetCurrent()
                let resultData = try await client.analyzeSubject(
                    r2ObjectKeys: [targetObjectKey],
                    base64ImageDatas: base64Strings,
                    telemetry: telemetry
                )
                MerianLog.general.debug("Gemini inference completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - inferenceStart), privacy: .public)s.")

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
                    }

                    if let container = modelContext?.container {
                        let profileActor = ProfileDatabaseActor(modelContainer: container)
                        let updatedAwards = await profileActor.calculateAwards()
                        await MainActor.run { GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards) }
                    }

                    CircuitBreakerManager.shared.recordSuccess()
                    AppTelemetry.trackScan(isPro: RevenueCatManager.shared.isProActive)
                    self.speciesData = mappedData

                    // Send a background notification if the user left while the scan was running.
                    // The offline queue path sends its own notification; this covers live inference only.
                    #if canImport(UIKit)
                    await MainActor.run {
                        if UIApplication.shared.applicationState != .active,
                           UserDefaults.standard.bool(forKey: "isPushNotificationsEnabled"),
                           let scanId = mappedData.scanId {
                            PushNotificationManager.shared.sendInferenceCompleteNotification(
                                speciesName: mappedData.commonName,
                                scanId: scanId
                            )
                        }
                    }
                    #endif

                    MerianLog.general.debug("Total pipeline (upload + AI + DB) completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s.")

                    if mappedData.isBiological {
                        Task {
                            await self.fetchWikipediaAndHydrate(for: mappedData.scientificName, scanId: mappedData.scanId, modelContext: modelContext)
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
                    return
                }

                // Network failure — refund the scan since the user never got a result.
                UsageManager.shared.refundScan()

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
                    insightData: InsightData(description: "Please check your network connection and try again.", isPoisonous: false, regionalStatusRationale: nil),
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

        let normalized = species.replacingOccurrences(of: " ", with: "_")
        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0

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
            MerianLog.general.debug("Wikipedia hydration skipped: \(error, privacy: .private)")
        }
    }

    // MARK: - Pipeline Modifiers

    func cancelActiveRequest() {
        MerianLog.general.debug("Cancelled active inference request.")
        isBackgroundRescued = true
        self.inferenceTask?.cancel()
        // isBackgroundRescued is reset by the task's cancellation catch block.
        // If the task was already finished, analyze() resets it at the start of the next scan.
        self.speciesData = nil
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
        self.validHistoricImagePaths = []

        var paths: [String] = []
        if let localPath = record.localImagePath { paths.append(localPath) }
        if let extras = record.additionalImagePaths { paths.append(contentsOf: extras) }

        Task {
            let validPaths = await FileIOActor.shared.validPaths(from: paths)
            await MainActor.run { self.validHistoricImagePaths = validPaths }
        }

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
            commonName: record.commonName,
            scientificName: record.scientificName,
            insightData: InsightData(description: record.insightDescription, isPoisonous: record.isPoisonous, regionalStatusRationale: nil),
            confidenceScore: record.confidenceScore ?? 1.0,
            diagnosticComparison: parsedDiagnostic,
            wikipediaUrl: record.wikipediaUrl,
            wikipediaExtract: record.wikipediaExtract,
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
            gpsLongitude: record.gpsLongitude
        )
        self.isProcessing = false

        // Retroactively hydrate legacy scans that missed Wikipedia data on initial save.
        if record.isBiological && (record.wikipediaExtract == nil || record.referenceImageUrl == nil || record.referenceImageUrl!.isEmpty) {
            let safeContext = record.modelContext
            Task {
                await self.fetchWikipediaAndHydrate(for: record.scientificName, scanId: record.id, modelContext: safeContext)
            }
        }
    }
}
