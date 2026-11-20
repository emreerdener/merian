#if DEBUG
import AVFoundation
import Foundation
import SwiftData

/// Seed only: real local owners, synthetic authorization and server receipts.
/// Reopening must never call these constructors or consume another attempt.
@MainActor enum ReanalysisRecoveryUISeed {
    static func create(media: String, child: UUID, root: URL, container: ModelContainer,
                       cloud: ObservationHistoryCloudClient) async throws {
        guard UITestSeedCoordinator.reanalysisRecoveryRestartEnabled else { throw MerianError.invalidResponse }
        let source = try ObservationReanalysisSource.capture(observationID: UUID(uuidString: PublicationConsentUIFixture.observation)!,
            ownerID: PublicationConsentUIFixture.owner, container: container)
        switch media {
        case "photo": try await photo(source, child, root, container, cloud)
        case "audio": try await audio(source, child, root, container, cloud)
        case "video": try await video(source, child, root, container, cloud)
        default: throw MerianError.invalidResponse
        }
    }

    private static func photo(_ source: ObservationReanalysisSource, _ child: UUID, _ root: URL,
                              _ container: ModelContainer, _ cloud: ObservationHistoryCloudClient) async throws {
        let plan = try ObservationReanalysisPreparationPlan(source: source,
            choices: [.description("  Exact recovery note\nwith spacing.  "), .photo(.added(UITestSeedCoordinator.uiTestPNGData()))], analysisID: child)
        let prepared = try await ObservationReanalysisProducer(files: .init(documents: root), ownership: .init(), account: cloud)
            .stage(plan, container: container, action: .submit, isCurrent: { true })
        guard case .submitted(let submitted) = prepared else { throw MerianError.invalidResponse }
        let admission = ObservationReanalysisAdmission(account: cloud,
            preflight: { _, _, validate in try validate(); return .init(recipient: .gemini, validate: validate) },
            authorizeBound: { _, _, _ in throw MerianError.invalidResponse })
        let bound = try await admission.admit(submitted.draft, container: container, isCurrent: { true })
        let claim = try ObservationReanalysisExecutionStore.claim(bound, admission: .initial, now: Date(), container: container, isCurrent: { true })
        let consumed = try ObservationReanalysisExecutionStore.consumeDispatch(claim, container: container, isCurrent: { true })
        try ObservationReanalysisExecutionStore.settle(consumed, as: .held(.retryLimit), now: Date(), container: container, isCurrent: { true })
    }

    private static func audio(_ source: ObservationReanalysisSource, _ child: UUID, _ root: URL,
                              _ container: ModelContainer, _ cloud: ObservationHistoryCloudClient) async throws {
        let input = root.appendingPathComponent("input.wav")
        try UITestSeedCoordinator.queuedAudioHandoffWAVData().write(to: input, options: .atomic)
        let bytes = try await CaptureAudioInputPreparer(directory: root.appendingPathComponent("audio-conversion", isDirectory: true))
            .prepare(input)
        let upload = try ObservationAudioEvidenceUpload(observationID: source.observationID, analysisID: child, mediaID: UUID(), bytes: bytes).prepare()
        let preparation = try ObservationAudioPreparation(identity: .init(observationID: source.observationID,
            sourceAnalysisID: source.analysisID, analysisID: child, ownerID: source.ownerID),
            evidence: [.description("  Exact recovery note\nwith spacing.  "), .audio(upload.reference)], source: source, action: .submit)
        _ = try await ObservationAudioPreparationProducer(files: .init(documents: root), ownership: .init(), account: cloud)
            .prepare(preparation, source: source, bytes: bytes, container: container, isCurrent: { true })
        let proof = try preparation.verified(source: source)
        let bound = try ObservationAudioExecutionStore.bind(.init(preparation: preparation), proof: proof,
            authorization: .init(recipient: .gemini, validate: {}), container: container, isCurrent: { true })
        let claim = try ObservationAudioExecutionStore.claim(bound, purpose: .initial, proof: proof, container: container, isCurrent: { true })
        let permit = try ObservationAudioExecutionStore.consume(claim, proof: proof, container: container, isCurrent: { true })
        try ObservationAudioExecutionStore.hold(permit.claim, proof: proof, container: container, isCurrent: { true })
    }

    private static func video(_ source: ObservationReanalysisSource, _ child: UUID, _ root: URL,
                              _ container: ModelContainer, _ cloud: ObservationHistoryCloudClient) async throws {
        let input = root.appendingPathComponent("input.mp4")
        try await writeVideo(input)
        let cohort = try await ObservationVideoCohortPreparer().prepare(source: input,
            directory: root.appendingPathComponent("cohort", isDirectory: true), observationID: source.observationID,
            analysisID: child, sourceAnalysisID: source.analysisID, descriptions: ["  Exact recovery note\nwith spacing.  "],
            cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
        let preparation = try ObservationVideoPreparation(request: cohort.request, source: source)
        _ = try await ObservationVideoPreparationProducer(files: .init(documents: root), ownership: .init(), account: cloud)
            .prepare(preparation, source: source, cohort: cohort, container: container, isCurrent: { true })
        let proof = try preparation.verified(source: source)
        let reserved = try ObservationVideoSourceReservationStore.stage(.init(video: preparation.request), proof: proof, container: container, isCurrent: { true })
        let claim = try ObservationVideoSourceReservationStore.claim(reserved, proof: proof, container: container, isCurrent: { true })
        var reply = reserved.work.request.identity.fields
        reply["owner_id"] = source.ownerID.uuidString.lowercased(); reply["state"] = "reserved"
        let receipt = try ObservationVideoSourceReservationReply(data: JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]),
            identity: reserved.work.request.identity, ownerID: source.ownerID)
        let acknowledged = try ObservationVideoSourceReservationStore.settle(claim, settlement: .reply(receipt), proof: proof, container: container, isCurrent: { true })
        _ = try ObservationVideoUploadStore.stage(acknowledged, proof: proof, container: container, isCurrent: { true })
        let staged = try ObservationVideoUploadLifecycleStore.read(proof: proof, container: container, isCurrent: { true })
        let upload = try ObservationVideoUploadLifecycleStore.claim(staged, proof: proof, container: container, isCurrent: { true })
        let request = upload.snapshot.work.staged.request
        guard var row = try JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              var items = row["items"] as? [[String: Any]] else { throw MerianError.invalidResponse }
        for index in items.indices {
            items[index]["object_id"] = UUID().uuidString.lowercased()
            items[index]["ready_at"] = "2026-10-10T01:00:00.000Z"
        }
        row["items"] = items; row["owner_id"] = source.ownerID.uuidString.lowercased()
        row["expires_at"] = "2099-10-11T01:00:00.000Z"; row["state"] = "ready"
        let ready = try ObservationVideoEvidenceReceipt(data: JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
            request: request, ownerID: source.ownerID, previous: nil)
        let uploaded = try ObservationVideoUploadLifecycleStore.settle(upload, receipt: ready, proof: proof, container: container, isCurrent: { true })
        let authorization = IdentificationDispatchAuthorization(recipient: .gemini, validate: {})
        let bound = try ObservationVideoExecutionStore.stage(uploaded, proof: proof, authorization: authorization, container: container, isCurrent: { true })
        let execution = try ObservationVideoExecutionStore.claim(bound, proof: proof, container: container, isCurrent: { true })
        let consumed = try ObservationVideoExecutionStore.consume(execution, proof: proof, authorization: authorization, container: container, isCurrent: { true })
        _ = try ObservationVideoExecutionStore.hold(consumed.snapshot, proof: proof, container: container, isCurrent: { true })
    }

    /// Tiny valid silent source. This is neither a playback nor a resource test.
    private static func writeVideo(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        guard writer.canAdd(input) else { throw MerianError.invalidResponse }
        writer.add(input)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        guard writer.startWriting() else { throw MerianError.invalidResponse }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess,
              let pixels = buffer else { throw MerianError.invalidResponse }
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) { memset(base, 0, CVPixelBufferGetDataSize(pixels)) }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        for frame in 0..<30 {
            let deadline = ContinuousClock.now + .seconds(5)
            while !input.isReadyForMoreMediaData && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
            try Task.checkCancellation()
            guard input.isReadyForMoreMediaData,
                  adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw MerianError.invalidResponse }
        }
        writer.endSession(atSourceTime: CMTime(value: 30, timescale: 30)); input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw MerianError.invalidResponse }
    }
}
#endif
