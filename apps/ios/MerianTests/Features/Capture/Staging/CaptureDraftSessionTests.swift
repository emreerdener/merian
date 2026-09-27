import Foundation
import Testing
import UIKit
@testable import Merian

@MainActor
@Suite("Staged draft ownership", .serialized)
struct CaptureDraftSessionTests {
    @Test func eligibilityIsMintedOnlyAtEntryAndNeverRearmed() {
        var session = CaptureDraftSession()
        let attempt = session.begin(autoSubmit: true, compositionIsEmpty: true, isRefining: false)
        #expect(session.hasUnresolvedWork)
        #expect(session.automaticAttempt == attempt)
        session.revokeAutomaticSubmission()
        let finished = session.finish(attempt, succeeded: true)
        #expect(finished)
        #expect(!session.hasUnresolvedWork)
        #expect(session.automaticAttempt == nil)
        let duplicate = session.finish(attempt, succeeded: true)
        #expect(!duplicate)
        let old = session.begin(autoSubmit: true, compositionIsEmpty: true, isRefining: false)
        session.reset()
        let stale = session.finish(old, succeeded: true)
        #expect(!stale)
        #expect(session.automaticAttempt == nil)
    }

    @Test func compositionAndReanalysisAlwaysRequireReview() {
        for (empty, refining) in [(false, false), (true, true)] {
            var session = CaptureDraftSession()
            let attempt = session.begin(autoSubmit: true, compositionIsEmpty: empty, isRefining: refining)
            session.finish(attempt, succeeded: true)
            #expect(session.automaticAttempt == nil)
        }
    }

    @Test func sharedNoteDoesNotRevealTrayUntilStagedAndSurvivesMediaRemoval() {
        let vm = makeViewModel()
        vm.updateDescriptionDraft(ObservationContext(freeText: "On a leaf"))
        #expect(vm.stagedCapture.isEmpty)
        #expect(!vm.shouldPresentActiveScanToolbar)
        vm.stagedCapture.audios = [StagedAudio(filePath: "synthetic.wav")]
        vm.isReviewActive = true
        vm.synchronizeSharedDescription()
        #expect(vm.stagedCapture.observationContexts.count == 1)
        vm.removeStagedAudio(at: 0)
        #expect(vm.shouldPresentActiveScanToolbar)
        #expect(vm.descriptionDraft.freeText == "On a leaf")
        vm.updateDescriptionDraft(ObservationContext())
        #expect(!vm.shouldPresentActiveScanToolbar)
    }

    @Test func removingLastMediaReturnsDescribeToUnstagedEntry() {
        let vm = makeViewModel()
        vm.stagedCapture.audios = [StagedAudio(filePath: "synthetic.wav")]
        vm.isReviewActive = true
        vm.removeStagedAudio(at: 0)
        #expect(!vm.isReviewActive)
        vm.updateDescriptionDraft(ObservationContext(freeText: "A new observation"))
        #expect(vm.stagedCapture.isEmpty)
        #expect(!vm.shouldPresentActiveScanToolbar)
        #expect(vm.descriptionDraft.freeText == "A new observation")
    }

    @Test func unresolvedSecondItemBlocksSubmissionAndDiscardIsGenerationBound() throws {
        let vm = makeViewModel()
        vm.updateDescriptionDraft(ObservationContext(freeText: "A call in reeds"))
        vm.isReviewActive = true
        vm.synchronizeSharedDescription()
        let operation = try #require(vm.beginDraftOperation())
        #expect(!vm.canSubmitDraft)
        vm.requestDraftDiscard()
        let generation = try #require(vm.discardConfirmationGeneration)
        #expect(vm.beginDraftOperation() == nil)
        vm.discardConfirmationGeneration = nil
        #expect(vm.descriptionDraft.freeText == "A call in reeds")
        vm.completeDraftOperation(operation, succeeded: false)
        #expect(vm.canSubmitDraft)
        vm.requestDraftDiscard()
        #expect(vm.confirmDraftDiscard(generation: generation))
        #expect(vm.descriptionDraft.isEmpty)
        #expect(!vm.confirmDraftDiscard(generation: generation))
        vm.completeDraftOperation(operation, succeeded: true)
        #expect(vm.stagedCapture.isEmpty)
    }

    @Test func settingOffThenOnCannotArmAnExistingAttempt() throws {
        let vm = makeViewModel()
        vm.diContainer.appSettings.autoSubmitScans = true
        let operation = try #require(vm.beginDraftOperation())
        vm.diContainer.appSettings.autoSubmitScans = false
        vm.diContainer.appSettings.autoSubmitScans = true
        vm.stagedCapture.audios = [StagedAudio(filePath: "synthetic.wav")]
        vm.completeDraftOperation(operation, succeeded: true)
        #expect(!vm.shouldAutoSubmitStagedCapture)
        #expect(!vm.isAutomaticStagedSubmissionPending)
    }

    @Test func photoAndAudioPlusNoteAreFreeInEitherOrder() {
        for media: CaptureSubmissionMediaItem in [.image(index: 0), .audio("synthetic.wav")] {
            let note = CaptureSubmissionMediaItem.description(ObservationContext(freeText: "In reeds"))
            #expect(CaptureSubmissionPolicy.isFlashFallbackEligible([media, note]))
            #expect(CaptureSubmissionPolicy.isFlashFallbackEligible([note, media]))
            #expect(!CaptureSubmissionPolicy.isFlashFallbackEligible([media, note, note]))
            #expect(!CaptureSubmissionPolicy.isFlashFallbackEligible([media, media, note]))
        }
        let vm = makeViewModel()
        vm.updateDescriptionDraft(ObservationContext(freeText: "In reeds"))
        #expect(vm.isProspectiveFreeMediaEligible(images: 1))
        #expect(vm.isProspectiveFreeMediaEligible(audio: 1))
    }

    @Test func acceptedCopiesOutliveSourceAndFailurePreservesSource() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let docs = base.appendingPathComponent("queue")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("synthetic.wav")
        try Data([1, 2, 3]).write(to: source)
        #expect(throws: (any Error).self) {
            try OfflineCaptureFileStore.persistFiles([source.path, base.appendingPathComponent("missing.wav").path], documentsDirectory: docs)
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
        let map = try OfflineCaptureFileStore.persistFiles([source.path], documentsDirectory: docs)
        let timeline = try OfflineCaptureFileStore.acceptedTimeline([.audio(source.path)], audio: map, video: [:], documentsDirectory: docs)
        let accepted = try #require(timeline.audioFilePaths.first)
        #expect(accepted != source.path)
        try FileManager.default.removeItem(at: source)
        #expect(try Data(contentsOf: URL(fileURLWithPath: accepted)) == Data([1, 2, 3]))
    }

    @Test func terminalAudioFailureReleasesReadinessWithoutErasingContent() throws {
        let vm = makeViewModel()
        vm.updateDescriptionDraft(ObservationContext(freeText: "Existing context"))
        vm.isReviewActive = true
        vm.synchronizeSharedDescription()
        vm.audioDraftOperation = try #require(vm.beginDraftOperation())
        vm.reconcileEndedAudioOperation(isRecording: false, hasPendingReview: true, hasSubmittedAudio: false)
        #expect(vm.draftSession.hasUnresolvedWork)
        vm.reconcileEndedAudioOperation(isRecording: false, hasPendingReview: false, hasSubmittedAudio: false)
        #expect(!vm.draftSession.hasUnresolvedWork)
        #expect(vm.canSubmitDraft)
        #expect(vm.descriptionDraft.freeText == "Existing context")
    }

    @Test func videoHandoffPreservesCompanionAudioAndEvidenceOrder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let video = base.appendingPathComponent("clip.mp4")
        let audio = base.appendingPathComponent("companion.wav")
        try Data([1]).write(to: video)
        try Data([2]).write(to: audio)
        let videos = try OfflineCaptureFileStore.persistFiles([video.path], documentsDirectory: base)
        let audios = try OfflineCaptureFileStore.persistFiles([audio.path], documentsDirectory: base)
        let note = CaptureSubmissionMediaItem.description(ObservationContext(freeText: "At dusk"))
        let accepted = try OfflineCaptureFileStore.acceptedTimeline(
            [note, .video(video.path, posterImageIndex: 0, audioFilePath: audio.path)],
            audio: audios, video: videos, documentsDirectory: base)
        #expect(accepted.first == note)
        guard case .video(let movie, let poster, let companion) = accepted[1] else {
            Issue.record("Video classification must survive queue ownership transfer")
            return
        }
        #expect(poster == 0)
        try FileManager.default.removeItem(at: video)
        try FileManager.default.removeItem(at: audio)
        #expect(try Data(contentsOf: URL(fileURLWithPath: movie)) == Data([1]))
        #expect(try Data(contentsOf: URL(fileURLWithPath: #require(companion))) == Data([2]))
        #expect(!CaptureSubmissionPolicy.isFlashFallbackEligible(accepted))
    }

    @Test func paywallDescribesCapacityAndDoesNotSellExpedition() throws {
        #expect(!ProPlanValueProps.featuredSlides.contains { $0.title.contains("Expedition") })
        #expect(!ProPlanValueProps.reviews.contains { $0.body.localizedCaseInsensitiveContains("expedition") })
        let comparison = try #require(ProPlanValueProps.comparisons.first { $0.title == "Expedition mode" })
        #expect(comparison.freeValue == "Included")
        #expect(comparison.proValue == "Included")
        #expect(ProPlanValueProps.featuredSlides.contains { $0.subtitle.contains("two media items plus an optional note") })
    }

    @Test func newPreferenceIgnoresLegacyKeysAndPreservesExplicitChoice() throws {
        let name = "capture.preferences.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "requiresScanConfirmation")
        defaults.set(true, forKey: "isMultiCaptureEnabled")
        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(!settings.autoSubmitScans)
        settings.autoSubmitScans = true
        #expect(AppSettings(userDefaults: defaults, observeExternalChanges: false).autoSubmitScans)
    }

    private func makeViewModel() -> CaptureWorkspaceViewModel {
        let container = AppDIContainer.preview
        container.appSettings.autoSubmitScans = false
        return CaptureWorkspaceViewModel(diContainer: container, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
    }
}
