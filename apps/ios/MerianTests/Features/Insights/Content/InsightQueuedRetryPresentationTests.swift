import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightQueuedRetryPresentationTests {
    @Test func queuedRetryPresentationExplainsScheduledRetryWithoutRawErrors() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let presentation = try #require(QueuedRetryPresentation.resolve(
            queueState: .staged,
            nextRetryAt: now.addingTimeInterval(30),
            errorCode: "network_unavailable",
            needsAttention: false,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))

        #expect(presentation.message == [
            "The analysis paused because the connection was interrupted.",
            "It will retry automatically in 30 seconds."
        ].joined(separator: " "))
        #expect(presentation.action == .retryNow)
        #expect(!presentation.message.contains("private-provider-sentinel"))

        let unknown = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "private-provider-sentinel",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(unknown.message == "The analysis couldn’t complete this time.")
        #expect(!unknown.message.contains("private-provider-sentinel"))
    }

    @Test func queuedRetryPresentationSuppressesElapsedAndOfflineActions() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(QueuedRetryPresentation.resolve(
            queueState: .staged,
            nextRetryAt: now,
            errorCode: "inference_retry",
            needsAttention: false,
            canRetryNow: true,
            isOnline: true,
            now: now
        ) == nil)

        let offline = try #require(QueuedRetryPresentation.resolve(
            queueState: .staged,
            nextRetryAt: now.addingTimeInterval(30),
            errorCode: "upload_http_503",
            needsAttention: false,
            canRetryNow: true,
            isOnline: false,
            now: now
        ))
        #expect(offline.message == [
            "The analysis paused because the connection was interrupted.",
            "It will retry when your connection returns."
        ].joined(separator: " "))
        #expect(offline.action == nil)
        #expect(!offline.message.contains("30"))
        #expect(!offline.message.contains("starting"))
    }

    @Test func queuedRetryPresentationMapsAttentionActionsSafely() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let consent = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "ai_consent_required",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(consent.message.contains("required AI consent"))
        #expect(consent.action == nil)

        let entitlement = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "pro_required",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(entitlement.action == .viewPlans)

        let fallbackEntitlement = try #require(
            QueuedRetryPresentation.resolve(
                queueState: .failed,
                nextRetryAt: nil,
                errorCode: "inference_http_402",
                needsAttention: true,
                canRetryNow: true,
                isOnline: true,
                now: now
            )
        )
        #expect(fallbackEntitlement.action == .viewPlans)

        let missingMedia = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "local_media_missing",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(missingMedia.action == nil)

        let retryLimit = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "automatic_retry_limit_reached",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(retryLimit.action == .retryNow)

        let service = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "http_503",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(service.message.contains("temporarily unavailable"))
        #expect(service.action == .retryNow)

        let processing = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "server_result_processing",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(processing.message == "The analysis is taking longer than expected.")
        #expect(processing.action == .retryNow)

        let terminal = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "observation_rejected",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(terminal.message.contains("different photo or recording"))
        #expect(terminal.action == nil)

        let serverTerminal = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "server_terminal_failure",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(serverTerminal.message.contains("different photo or recording"))
        #expect(serverTerminal.action == nil)

        let invalidManifest = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "queued_upload_manifest_invalid",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(invalidManifest.message.contains("different photo or recording"))
        #expect(invalidManifest.action == nil)

        let invalidMedia = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "queued_media_invalid",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(invalidMedia.message.contains("no longer available"))
        #expect(invalidMedia.action == nil)

        let serverRetryable = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "server_retryable_failure",
            needsAttention: true,
            canRetryNow: true,
            isOnline: true,
            now: now
        ))
        #expect(serverRetryable.message == "The analysis is taking longer than expected.")
        #expect(serverRetryable.action == .retryNow)

        let offlineAttention = try #require(QueuedRetryPresentation.resolve(
            queueState: .failed,
            nextRetryAt: nil,
            errorCode: "server_retryable_failure",
            needsAttention: true,
            canRetryNow: true,
            isOnline: false,
            now: now
        ))
        #expect(offlineAttention.message == "The analysis is taking longer than expected.")
        #expect(offlineAttention.action == nil)
    }

    @Test func testQueuedPresentationRemainsQueuedWhenCompletionIsAbsent() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let queuedRoute = QueuedScanContext(
            id: "queued_route_without_completion",
            capturedMediaItems: [.audio(.documents("pending.wav"))],
            queueState: .inferencing,
            timestamp: Date(timeIntervalSince1970: 4)
        )
        let engine = InferenceEngine()
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)

        #expect(!viewModel.bindQueuedPresentationPreferringCompletedRecord(
            queuedRoute,
            modelContext: context,
            inferenceEngine: engine
        ))
        #expect(viewModel.queuedContext?.id == queuedRoute.id)
        #expect(viewModel.presentedLocalRecordScanId == nil)
        #expect(engine.speciesData == nil)
        #expect(viewModel.cachedActiveMedia?.items.count == 1)
        #expect(!viewModel.revealBottomBarTools(
            expectedScanId: queuedRoute.id,
            expectedGeneration: viewModel.scanBoundActionGeneration
        ))
        #expect(!viewModel.state.showBottomBarTools)
    }

}
