import Foundation
import SwiftData
import UIKit

#if DEBUG
enum UITestSeedCoordinator {
    private struct PrivateScanMapFixture {
        let id: String
        let commonName: String
        let scientificName: String
        let kingdom: String
        let className: String
        let latitude: Double
        let longitude: Double
        let timestamp: Date
    }

    private static let requiredConsentArgument = "-seedCurrentRequiredConsent"
    private static let achievementDeletionRefreshArgument = "-seedAchievementDeletionRefreshFlow"
    private static let queuedAudioHandoffArgument = "-seedQueuedAudioHandoffFlow"
    private static let queuedRetryPresentationArgument = "-seedQueuedRetryPresentationFlow"
    private static let liveQueueHandoffArgument = "-seedLiveQueueHandoffFlow"
    private static let progressiveAnalyzingArgument = "-seedProgressiveAnalyzingFlow"
    private static let suppressLocationPermissionPromptArgument =
        "-seedLocationPermissionPromptSuppressed"
    private static let missingVideoFallbackArgument = "-seedMissingVideoFallbackFlow"
    private static let stagedAudioReviewArgument = "-seedStagedAudioReviewFlow"
    private static let nonBiologicalCollectionRouteArgument =
        "-seedNonBiologicalCollectionRoute"
    private static let privateScanMapArgument =
        "-seedPrivateScanMapFlow"
    private static let captureGoalIndicatorArgument =
        "-seedCaptureGoalIndicatorFlow"
    private static let captureGoalIntroductionArgument =
        "-seedCaptureGoalIntroductionFlow"
    private static let captureGoalFixtureAccountId =
        "00000000-0000-4000-8000-0000000000c1"
    private static let captureGoalFixtureDefaultsSuite =
        "merian.ui-tests.capture-goal"
    private static let queuedAudioHandoffScanId = "ui_test_queued_audio_handoff"
    private static let queuedRetryScheduledScanId = "ui_test_queued_retry_scheduled"
    private static let queuedRetryAttentionScanId = "ui_test_queued_retry_attention"
    private static let liveQueueHandoffScanId = "ui_test_live_queue_handoff"
    private static let liveQueueHandoffImageFilename =
        "ui_test_live_queue_handoff.png"
    private static let liveQueueHandoffImageAssetName =
        "fieldtrip-park-flowering-plant"
    private static let queuedAudioHandoffAudioFilename = "ui_test_queued_audio_handoff.wav"
    private static let queuedAudioHandoffImageFilename = "ui_test_queued_audio_handoff.webp"
    private static let missingVideoFallbackScanId = "ui_test_missing_video_fallback"
    private static let missingVideoFilename = "ui_test_missing_video.mp4"
    private static let missingVideoFallbackImageFilename = "ui_test_video_fallback.png"
    private static let stagedAudioReviewFilename = "ui_test_staged_audio_review.wav"
    @MainActor private static var triggeredQueuedAudioHandoffs: Set<String> = []
    @MainActor private static var triggeredLiveQueueHandoffs: Set<String> = []
    @MainActor private static var hasSeededStagedAudioReview = false

    static var isEnabled: Bool {
        return TestExecutionCoordinator.isRunningUITests
    }

    static var isLocationPermissionPromptSuppressed: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(
            suppressLocationPermissionPromptArgument
        )
    }

    static var captureGoalAccountId: String? {
        guard isEnabled else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(captureGoalIndicatorArgument) ||
                arguments.contains(captureGoalIntroductionArgument) else {
            return nil
        }
        return captureGoalFixtureAccountId
    }

    @MainActor
    static func prepareRequiredConsentIfNeeded(
        consentManager: ConsentManager
    ) {
        guard isEnabled,
              ProcessInfo.processInfo.arguments.contains(requiredConsentArgument) else {
            return
        }
        try? consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: false
        )
    }

    @MainActor
    static func prepareCaptureGoalStoreIfNeeded(
        container: AppDIContainer
    ) {
        guard isEnabled,
              let snapshot = captureGoalSnapshot(
                  arguments: ProcessInfo.processInfo.arguments
              ),
              let fixtureDefaults = UserDefaults(
                  suiteName: captureGoalFixtureDefaultsSuite
              ) else {
            return
        }

        fixtureDefaults.removePersistentDomain(
            forName: captureGoalFixtureDefaultsSuite
        )
        container.appSettings.showsCaptureGoalProgress = true
        container.activeCaptureGoalStore = ActiveCaptureGoalStore(
            userDefaults: fixtureDefaults
        ) {
            snapshot
        }
    }

    @MainActor
    static func prepareStagedAudioReviewIfNeeded(
        viewModel: CaptureWorkspaceViewModel
    ) {
        guard isEnabled,
              ProcessInfo.processInfo.arguments.contains(stagedAudioReviewArgument),
              !hasSeededStagedAudioReview else {
            return
        }

        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            stagedAudioReviewFilename,
            isDirectory: false
        )

        do {
            try queuedAudioHandoffWAVData().write(to: audioURL, options: .atomic)
            viewModel.stagedCapture.audios = [
                StagedAudio(filePath: stagedAudioReviewFilename)
            ]
            hasSeededStagedAudioReview = true
            MerianLog.general.debug(
                "UITestSeedCoordinator seeded staged audio review flow."
            )
        } catch {
            MerianLog.general.error(
                "UITestSeedCoordinator failed to seed staged audio review: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    @MainActor
    static func prepareIfNeeded(container: ModelContainer) {
        guard isEnabled else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedAchievementDetailFlow") ||
                arguments.contains(achievementDeletionRefreshArgument) ||
                arguments.contains(queuedAudioHandoffArgument) ||
                arguments.contains(queuedRetryPresentationArgument) ||
                arguments.contains(liveQueueHandoffArgument) ||
                arguments.contains(progressiveAnalyzingArgument) ||
                arguments.contains(missingVideoFallbackArgument) ||
                arguments.contains(privateScanMapArgument) ||
                arguments.contains(nonBiologicalCollectionRouteArgument) else { return }

        let context = container.mainContext

        do {
            try context.delete(model: LocalScanRecord.self)
            try context.delete(model: ScanCollection.self)
            try context.delete(model: OfflineQueuedScan.self)
            try context.delete(model: ActiveOfflineQueuedScanGoalHint.self)
            try context.delete(model: PendingCloudDeletionTask.self)

            if arguments.contains("-seedAchievementDetailFlow") {
                for record in achievementDetailFlowRecords() {
                    context.insert(record)
                }
                OfflineQueueManager.shared.unsyncedItemsCount = 0
                MerianLog.general.debug("UITestSeedCoordinator seeded achievement detail flow records.")
            } else if arguments.contains(achievementDeletionRefreshArgument) {
                context.insert(achievementDeletionRefreshRecord())
                OfflineQueueManager.shared.unsyncedItemsCount = 0
                MerianLog.general.debug("UITestSeedCoordinator seeded achievement deletion refresh record.")
            } else if arguments.contains(queuedAudioHandoffArgument) {
                try prepareQueuedAudioHandoffMedia()
                context.insert(queuedAudioHandoffScan())
                OfflineQueueManager.shared.unsyncedItemsCount = 1
                triggeredQueuedAudioHandoffs.removeAll(keepingCapacity: false)
                MerianLog.general.debug("UITestSeedCoordinator seeded queued audio handoff flow.")
            } else if arguments.contains(queuedRetryPresentationArgument) {
                context.insert(queuedRetryScheduledScan())
                context.insert(queuedRetryAttentionScan())
                let queueManager = OfflineQueueManager.shared
                // Queue monitoring is intentionally disabled under tests, so
                // make this seed's scheduled-retry state explicitly online.
                queueManager.isOnline = true
                queueManager.unsyncedItemsCount = 2
                MerianLog.general.debug(
                    "UITestSeedCoordinator seeded queued retry presentation flow."
                )
            } else if arguments.contains(liveQueueHandoffArgument) {
                try prepareLiveQueueHandoffImage()
                context.insert(liveQueueHandoffScan())
                OfflineQueueManager.shared.unsyncedItemsCount = 1
                triggeredLiveQueueHandoffs.removeAll(keepingCapacity: false)
                MerianLog.general.debug("UITestSeedCoordinator seeded live queue handoff flow.")
            } else if arguments.contains(progressiveAnalyzingArgument) {
                OfflineQueueManager.shared.unsyncedItemsCount = 0
            } else if arguments.contains(missingVideoFallbackArgument) {
                try prepareMissingVideoFallbackImage()
                context.insert(missingVideoFallbackRecord())
                OfflineQueueManager.shared.unsyncedItemsCount = 0
                MerianLog.general.debug("UITestSeedCoordinator seeded missing video fallback flow.")
            } else if arguments.contains(privateScanMapArgument) {
                for record in privateScanMapRecords() {
                    context.insert(record)
                }
                OfflineQueueManager.shared.unsyncedItemsCount = 0
                MerianLog.general.debug(
                    "UITestSeedCoordinator seeded the private scan map flow."
                )
            } else if arguments.contains(nonBiologicalCollectionRouteArgument) {
                OfflineQueueManager.shared.unsyncedItemsCount = 0
                MerianLog.general.debug(
                    "UITestSeedCoordinator seeded the non-biological collection route."
                )
            }

            try context.save()

            AppSettings.shared.hasUnseenScan = false

            if arguments.contains(liveQueueHandoffArgument) {
                let inferenceEngine = AppDIContainer.shared.inferenceEngine
                inferenceEngine.simulateProgressiveAnalyzing(
                    automaticallyAdvances: true,
                    scanId: liveQueueHandoffScanId
                )
                inferenceEngine.activeMedia = ActiveScanMedia(
                    items: [.liveImage(try liveQueueHandoffImageData())]
                )
                AppDIContainer.shared.appRouteCoordinator.request(
                    .debugPreviewAnalyzing,
                    source: .debug
                )
            } else if arguments.contains(progressiveAnalyzingArgument) {
                AppDIContainer.shared.inferenceEngine
                    .simulateProgressiveAnalyzing(
                        automaticallyAdvances: false
                    )
                AppDIContainer.shared.appRouteCoordinator.request(
                    .debugPreviewAnalyzing,
                    source: .debug
                )
            } else if arguments.contains(nonBiologicalCollectionRouteArgument) {
                AppDIContainer.shared.appRouteCoordinator.request(
                    .nonBiologicalScans,
                    source: .debug
                )
            } else if arguments.contains(privateScanMapArgument) {
                AppDIContainer.shared.appRouteCoordinator.request(
                    .scansLibrary,
                    source: .debug
                )
            }
        } catch {
            MerianLog.general.error("UITestSeedCoordinator failed to seed data: \(error.localizedDescription, privacy: .private)")
        }
    }

    @discardableResult
    @MainActor
    static func completeQueuedAudioHandoffIfNeeded(
        scanId: String,
        modelContext: ModelContext
    ) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard isEnabled,
              arguments.contains(queuedAudioHandoffArgument),
              scanId == queuedAudioHandoffScanId,
              !triggeredQueuedAudioHandoffs.contains(scanId) else { return false }

        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let queuedScan = try? modelContext.fetch(descriptor).first else {
            MerianLog.general.error(
                "UITestSeedCoordinator could not find the queued row for audio handoff."
            )
            return false
        }
        triggeredQueuedAudioHandoffs.insert(scanId)
        modelContext.insert(queuedAudioHandoffCompletedRecord())
        modelContext.delete(queuedScan)

        do {
            try modelContext.save()
            OfflineQueueManager.shared.unsyncedItemsCount = 0
            MerianLog.general.info(
                "UITestSeedCoordinator committed the queued audio handoff transaction."
            )
            return true
        } catch {
            modelContext.rollback()
            triggeredQueuedAudioHandoffs.remove(scanId)
            MerianLog.general.error("UITestSeedCoordinator failed completing queued audio handoff flow: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    static var isLiveQueueHandoffTriggerEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(
            liveQueueHandoffArgument
        )
    }

    static var isProgressiveAnalyzingTriggerEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains(
            progressiveAnalyzingArgument
        )
    }

    @MainActor
    static func advanceProgressiveAnalyzingIfNeeded(
        inferenceEngine: InferenceEngine
    ) {
        guard isProgressiveAnalyzingTriggerEnabled else { return }
        inferenceEngine.debugAdvanceProgressiveAnalyzing()
    }

    /// Deterministically exercises the production live-sheet queue binding only
    /// after UI automation has observed and tapped the analyzing badge. The row
    /// must already be durable in the exact environment context before the
    /// engine is allowed to publish its presentation ID.
    @discardableResult
    @MainActor
    static func performLiveQueueHandoffIfNeeded(
        inferenceEngine: InferenceEngine,
        modelContext: ModelContext
    ) -> Bool {
        guard isLiveQueueHandoffTriggerEnabled,
              !triggeredLiveQueueHandoffs.contains(liveQueueHandoffScanId) else {
            return false
        }

        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == liveQueueHandoffScanId }
        )
        descriptor.fetchLimit = 1
        guard (try? modelContext.fetch(descriptor).first) != nil else {
            MerianLog.general.error(
                "UITestSeedCoordinator could not find the durable live-handoff row."
            )
            return false
        }

        guard inferenceEngine.debugTransitionProgressiveAnalyzingToQueue(
            scanId: liveQueueHandoffScanId
        ) else {
            return false
        }
        triggeredLiveQueueHandoffs.insert(liveQueueHandoffScanId)
        MerianLog.general.info(
            "UITestSeedCoordinator published the live queue handoff presentation."
        )
        return true
    }

    private static func achievementDetailFlowRecords() -> [LocalScanRecord] {
        let calendar = Calendar(identifier: .gregorian)

        let latestFungiDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 28, hour: 10, minute: 15)) ?? Date()
        let duplicateFungiDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 8, minute: 5)) ?? latestFungiDate.addingTimeInterval(-86_400)
        let secondFungiDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 26, hour: 9, minute: 45)) ?? latestFungiDate.addingTimeInterval(-172_800)

        return [
            LocalScanRecord(
                id: "achievement_fungi_latest",
                speciesId: "fungi_amanita_ai",
                scientificName: "Amanita muscaria",
                commonName: "Fly Agaric",
                timestamp: latestFungiDate,
                hazardType: "none",
                isInvasive: false,
                ecologyType: "forest",
                confidenceScore: 0.992,
                isLocallyArchived: true,
                taxonomyKingdom: "fungi",
                locationName: "North Woods",
                confirmedSpeciesId: "fungi_amanita_confirmed"
            ),
            LocalScanRecord(
                id: "achievement_fungi_duplicate",
                speciesId: "fungi_amanita_alternate",
                scientificName: "Amanita cf. muscaria",
                commonName: "Fly Agaric",
                timestamp: duplicateFungiDate,
                hazardType: "none",
                isInvasive: false,
                ecologyType: "forest",
                confidenceScore: 0.981,
                isLocallyArchived: true,
                taxonomyKingdom: "fungi",
                locationName: "North Woods",
                userIdentificationOverride: "Amanita muscaria",
                confirmedSpeciesId: "fungi_amanita_confirmed"
            ),
            LocalScanRecord(
                id: "achievement_fungi_second",
                speciesId: "fungi_boletus",
                scientificName: "Boletus edulis",
                commonName: "Porcini",
                timestamp: secondFungiDate,
                hazardType: "none",
                isInvasive: false,
                ecologyType: "forest",
                confidenceScore: 0.989,
                isLocallyArchived: true,
                taxonomyKingdom: "fungi",
                locationName: "Creek Trail",
                confirmedSpeciesId: "fungi_boletus"
            )
        ]
    }

    private static func privateScanMapRecords() -> [LocalScanRecord] {
        let baseTimestamp = Date(timeIntervalSince1970: 1_787_501_200)
        let primaryFixtures = [
            PrivateScanMapFixture(
                id: "private_map_bird",
                commonName: "Map Meadowlark",
                scientificName: "Sturnella magna",
                kingdom: "Animalia",
                className: "Aves",
                latitude: 12.02,
                longitude: 45.01,
                timestamp: baseTimestamp
            ),
            PrivateScanMapFixture(
                id: "private_map_insect",
                commonName: "Map Dragonfly",
                scientificName: "Anax junius",
                kingdom: "Animalia",
                className: "Insecta",
                latitude: 11.99,
                longitude: 45.04,
                timestamp: baseTimestamp.addingTimeInterval(-60)
            ),
            PrivateScanMapFixture(
                id: "private_map_plant",
                commonName: "Map Sunflower",
                scientificName: "Helianthus annuus",
                kingdom: "Plantae",
                className: "Magnoliopsida",
                latitude: 12.00,
                longitude: 44.98,
                timestamp: baseTimestamp.addingTimeInterval(-120)
            )
        ]
        let stressFixtures = (0..<302).map { index in
            let row = index / 23
            let column = index % 23
            return PrivateScanMapFixture(
                id: "private_map_stress_\(index)",
                commonName: "Map Mammal \(index)",
                scientificName: "Syntheticus fixture \(index)",
                kingdom: "Animalia",
                className: "Mammalia",
                latitude: 11.90 + (Double(row) * 0.015),
                longitude: 44.88 + (Double(column) * 0.015),
                timestamp: baseTimestamp.addingTimeInterval(-Double(index + 3) * 60)
            )
        }
        let fixtures = primaryFixtures + stressFixtures

        return fixtures.map { fixture in
            let mediaItems: [SerializedMediaItem] = fixture.id.hasPrefix(
                "private_map_stress_"
            ) ? [] : [
                .image(.documents("\(fixture.id).webp"))
            ]
            return LocalScanRecord(
                id: fixture.id,
                speciesId: fixture.id,
                scientificName: fixture.scientificName,
                commonName: fixture.commonName,
                timestamp: fixture.timestamp,
                capturedMediaJSON: CapturedMediaSnapshot(items: mediaItems).jsonString,
                hazardType: "none",
                isBiological: true,
                isLiveCapture: true,
                isInvasive: false,
                ecologyType: "wild",
                confidenceScore: 0.98,
                isLocallyArchived: true,
                taxonomyKingdom: fixture.kingdom,
                taxonomyClass: fixture.className,
                locationName: "Map Test Range",
                gpsLatitude: fixture.latitude,
                gpsLongitude: fixture.longitude,
                hasBeenViewed: true,
                confirmedSpeciesId: fixture.id
            )
        }
    }

    private static func achievementDeletionRefreshRecord() -> LocalScanRecord {
        let calendar = Calendar(identifier: .gregorian)
        let dogDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 11, minute: 20)) ?? Date()

        return LocalScanRecord(
            id: "achievement_domestic_dog_refresh",
            speciesId: "dog_canis_lupus_familiaris",
            scientificName: "Canis lupus familiaris",
            commonName: "Domestic Dog",
            timestamp: dogDate,
            hazardType: "none",
            isInvasive: false,
            ecologyType: "domesticated",
            confidenceScore: 0.995,
            isLocallyArchived: true,
            taxonomyKingdom: "Animalia",
            locationName: "Home",
            confirmedSpeciesId: "dog_canis_lupus_familiaris_confirmed"
        )
    }

    private static func queuedAudioHandoffCapturedMediaJSON() -> String? {
        let items: [SerializedMediaItem] = [
            .audio(.documents(
                queuedAudioHandoffAudioFilename,
                sourceIndex: 0
            )),
            .image(.documents(queuedAudioHandoffImageFilename))
        ]
        guard let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func prepareQueuedAudioHandoffMedia() throws {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let audioURL = documentsURL.appendingPathComponent(
            queuedAudioHandoffAudioFilename,
            isDirectory: false
        )
        try queuedAudioHandoffWAVData().write(to: audioURL, options: .atomic)
    }

    private static func queuedAudioHandoffWAVData() -> Data {
        let sampleRate: UInt32 = 8_000
        let sampleCount = Int(sampleRate)
        let bytesPerSample: UInt16 = 2
        let audioByteCount = UInt32(sampleCount) * UInt32(bytesPerSample)

        var data = Data()
        func appendASCII(_ value: String) {
            data.append(contentsOf: value.utf8)
        }
        func appendUInt16LE(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func appendUInt32LE(_ value: UInt32) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
            data.append(UInt8(truncatingIfNeeded: value >> 16))
            data.append(UInt8(truncatingIfNeeded: value >> 24))
        }

        appendASCII("RIFF")
        appendUInt32LE(36 + audioByteCount)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32LE(16)
        appendUInt16LE(1)
        appendUInt16LE(1)
        appendUInt32LE(sampleRate)
        appendUInt32LE(sampleRate * UInt32(bytesPerSample))
        appendUInt16LE(bytesPerSample)
        appendUInt16LE(16)
        appendASCII("data")
        appendUInt32LE(audioByteCount)

        for sampleIndex in 0..<sampleCount {
            let sample: Int16 = (sampleIndex / 10).isMultiple(of: 2) ? 4_000 : -4_000
            appendUInt16LE(UInt16(bitPattern: sample))
        }

        return data
    }

    private static func queuedAudioHandoffScan() -> OfflineQueuedScan {
        OfflineQueuedScan(
            id: queuedAudioHandoffScanId,
            timestamp: Date(timeIntervalSince1970: 1_777_376_400),
            capturedMediaJSON: queuedAudioHandoffCapturedMediaJSON(),
            coverImagePath: queuedAudioHandoffImageFilename,
            weatherCondition: "overcast",
            weatherTemperatureF: 68,
            locationName: "UITest Queue",
            scanState: .pending
        )
    }

    private static func liveQueueHandoffScan() -> OfflineQueuedScan {
        let mediaItems: [SerializedMediaItem] = [
            .image(.documents(liveQueueHandoffImageFilename))
        ]
        let capturedMediaJSON = try? JSONEncoder().encode(mediaItems)
        return OfflineQueuedScan(
            id: liveQueueHandoffScanId,
            timestamp: Date(timeIntervalSince1970: 1_778_586_600),
            capturedMediaJSON: capturedMediaJSON.flatMap {
                String(data: $0, encoding: .utf8)
            },
            coverImagePath: liveQueueHandoffImageFilename,
            weatherCondition: "partly cloudy",
            weatherTemperatureF: 72,
            locationName: "UITest Garden",
            scanState: .pending
        )
    }

    private static func queuedRetryCapturedMediaJSON(
        description: String
    ) -> String? {
        let mediaItems: [SerializedMediaItem] = [
            .description(ObservationContext(freeText: description))
        ]
        guard let data = try? JSONEncoder().encode(mediaItems) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func queuedRetryScheduledScan() -> OfflineQueuedScan {
        OfflineQueuedScan(
            id: queuedRetryScheduledScanId,
            timestamp: Date(timeIntervalSince1970: 1_778_759_000),
            capturedMediaJSON: queuedRetryCapturedMediaJSON(
                description: "Seeded scheduled retry observation"
            ),
            locationName: "UITest Retry",
            scanState: .staged,
            queueAttemptCount: 1,
            queueNextRetryAt: Date().addingTimeInterval(30),
            queueLastErrorCode: "network_timed_out",
            queueLastErrorMessage: "RAW_QUEUE_ERROR_SENTINEL"
        )
    }

    private static func queuedRetryAttentionScan() -> OfflineQueuedScan {
        OfflineQueuedScan(
            id: queuedRetryAttentionScanId,
            timestamp: Date(timeIntervalSince1970: 1_778_758_900),
            capturedMediaJSON: queuedRetryCapturedMediaJSON(
                description: "Seeded missing-media retry observation"
            ),
            locationName: "UITest Retry",
            scanState: .failed,
            queueAttemptCount: 10,
            queueLastErrorCode: "local_media_missing",
            queueLastErrorMessage: "RAW_QUEUE_ERROR_SENTINEL",
            queueNeedsAttention: true
        )
    }

    private static func queuedAudioHandoffCompletedRecord() -> LocalScanRecord {
        LocalScanRecord(
            id: queuedAudioHandoffScanId,
            speciesId: "ui_test_cardinal",
            scientificName: "Cardinalis cardinalis",
            commonName: "Northern Cardinal",
            timestamp: Date(timeIntervalSince1970: 1_777_376_400),
            capturedMediaJSON: queuedAudioHandoffCapturedMediaJSON(),
            coverImagePath: queuedAudioHandoffImageFilename,
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "woodland",
            wikipediaUrl: "https://example.com/cardinal",
            wikipediaOverview: "Seeded UI test overview.",
            referenceImageUrl: "https://example.com/cardinal.jpg",
            confidenceScore: 0.97,
            locationName: "UITest Queue",
            weatherCondition: "overcast",
            weatherTemperatureF: 68,
            aiReasoning: "Seeded UI test reasoning.",
            habitatDescription: "Seeded UI test habitat.",
            gbifTaxonKey: 2492488,
            hasBeenViewed: true
        )
    }

    private static func prepareLiveQueueHandoffImage() throws {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        try liveQueueHandoffImageData().write(
            to: documentsURL.appendingPathComponent(
                liveQueueHandoffImageFilename
            ),
            options: .atomic
        )
    }

    private static func liveQueueHandoffImageData() throws -> Data {
        guard let image = UIImage(named: liveQueueHandoffImageAssetName),
              let imageData = image.pngData() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return imageData
    }

    private static func uiTestPNGData() throws -> Data {
        guard let imageData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return imageData
    }

    private static func prepareMissingVideoFallbackImage() throws {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        try uiTestPNGData().write(
            to: documentsURL.appendingPathComponent(missingVideoFallbackImageFilename),
            options: .atomic
        )
    }

    private static func missingVideoFallbackCapturedMediaJSON() -> String? {
        let items: [SerializedMediaItem] = [
            .video(StoredVideoMediaReference(
                .documents(missingVideoFilename),
                thumbnail: .documents(missingVideoFallbackImageFilename)
            ))
        ]
        guard let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func missingVideoFallbackRecord() -> LocalScanRecord {
        LocalScanRecord(
            id: missingVideoFallbackScanId,
            speciesId: "ui_test_blue_swallowtail",
            scientificName: "Battus philenor",
            commonName: "Blue Swallowtail",
            timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            capturedMediaJSON: missingVideoFallbackCapturedMediaJSON(),
            coverImagePath: missingVideoFallbackImageFilename,
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "garden",
            confidenceScore: 0.98,
            locationName: "UITest Garden",
            aiReasoning: "Seeded missing-video fallback regression.",
            hasBeenViewed: true
        )
    }

    private static func captureGoalSnapshot(
        arguments: [String]
    ) -> CaptureGoalContextSnapshot? {
        if arguments.contains(captureGoalIntroductionArgument) {
            return CaptureGoalContextSnapshot(
                goals: [],
                introduction: CaptureGoalIntroduction(
                    id: "ui-test-field-trip-introduction",
                    sourceKind: .fieldTrip,
                    headline: "Start an outing",
                    subheadline: "Backyard Safari · 2 goals",
                    progress: CaptureGoalProgress(
                        completedCount: 0,
                        targetCount: 2
                    ),
                    artworks: [
                        .bundledImage(name: "fieldtrip-backyard-cardinal"),
                        .bundledImage(name: "fieldtrip-backyard-dog")
                    ],
                    destination: .fieldTripTemplate(slug: "backyard_safari"),
                    accessibilityLabel: "Start an outing. Backyard Safari, 2 goals.",
                    accessibilityValue: "0 of 2 goals complete.",
                    accessibilityHint: "Opens outing details."
                )
            )
        }

        guard arguments.contains(captureGoalIndicatorArgument) else {
            return nil
        }

        let source = CaptureGoalSource(
            kind: .fieldTrip,
            id: "ui-test-field-trip",
            title: "Backyard Safari"
        )
        return CaptureGoalContextSnapshot(
            goals: [
                CaptureGoal(
                    id: "ui-test-flowering-plant",
                    source: source,
                    prompt: "Flowering plant",
                    progress: CaptureGoalProgress(
                        completedCount: 3,
                        targetCount: 4
                    ),
                    artwork: .bundledImage(
                        name: "fieldtrip-backyard-flowers"
                    ),
                    destination: .fieldTrip(
                        templateId: "ui-test-backyard-safari",
                        checklistItemId: "ui-test-flowering-plant"
                    )
                ),
                CaptureGoal(
                    id: "ui-test-bird",
                    source: source,
                    prompt: "Bird",
                    progress: CaptureGoalProgress(
                        completedCount: 3,
                        targetCount: 4
                    ),
                    artwork: .bundledImage(
                        name: "fieldtrip-backyard-cardinal"
                    ),
                    destination: .fieldTrip(
                        templateId: "ui-test-backyard-safari",
                        checklistItemId: "ui-test-bird"
                    )
                )
            ],
            introduction: nil
        )
    }
}
#else
enum UITestSeedCoordinator {
    static var isEnabled: Bool { return false }
    static var isLocationPermissionPromptSuppressed: Bool { return false }
    static var captureGoalAccountId: String? { return nil }

    @MainActor
    static func prepareRequiredConsentIfNeeded(
        consentManager _: ConsentManager
    ) {}

    @MainActor
    static func prepareCaptureGoalStoreIfNeeded(
        container _: AppDIContainer
    ) {}

    @MainActor
    static func prepareIfNeeded(container _: ModelContainer) {}

    @discardableResult
    @MainActor
    static func completeQueuedAudioHandoffIfNeeded(
        scanId _: String,
        modelContext _: ModelContext
    ) -> Bool {
        false
    }
}
#endif
