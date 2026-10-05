import CryptoKit
import Foundation
import ImageIO
@testable import Merian
import SwiftData
import Testing
import UIKit
import UniformTypeIdentifiers

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisProducerTests {
    let fixture = ObservationReanalysisSourceTests()

    func image() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return try #require(image.pngData())
    }

    func source(_ seed: ObservationReanalysisSourceTests.Seed) throws -> ObservationReanalysisSource {
        try ObservationReanalysisSource.capture(observationID: seed.observationID, ownerID: fixture.fixture.owner, container: seed.container)
    }

    func account(current: @escaping () -> Bool = { true }, finish: @escaping () -> Void = {}) -> ObservationHistoryCloudClient {
        .init(begin: { owner in .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) },
            isCurrent: { _ in current() }, finish: { _ in finish() }, fetch: { _ in throw MerianError.invalidResponse })
    }

    @Test func importedSourceWithExplicitNewPhotoCreatesHeldChildAndPreservesSelection() async throws {
        let seed = try fixture.seed(version: 3), source = try source(seed)
        let plan = try ObservationReanalysisPreparationPlan(source: source, choices: [.description("Synthetic leaf"), .photo(.added(image()))])
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var finished = 0
        let producer = ObservationReanalysisProducer(files: .init(documents: root), account: account(finish: { finished += 1 }))
        let result = try await producer.stage(plan, container: seed.container, isCurrent: { true })
        guard case let .draft(draft) = result else { Issue.record("Expected held draft"); return }
        #expect(draft.identity.analysisID == plan.analysisID && draft.identity.sourceAnalysisID == source.analysisID)
        #expect(finished == 1)
        guard case let .image(photo) = draft.evidence[1] else { Issue.record("Expected photo after description"); return }
        #expect(photo.contentType == "image/jpeg" && !source.photos.contains(where: { $0.mediaID == photo.mediaID }))
        let bytes = try Data(contentsOf: root.appendingPathComponent(try #require(draft.photoPaths.first)))
        let decoded = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        #expect(CGImageSourceGetType(decoded) as String? == UTType.jpeg.identifier)
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(parent.selectedAnalysisID == source.analysisID.uuidString.lowercased() && parent.observationStateRevision == 10)
        #expect(job.kind == .observationReanalysisSync && job.status == .needsAttention && job.attemptCount == 0)
    }

    @Test func accountSwitchDuringOriginalLoadCannotCreateFilesOrQueue() async throws {
        let seed = try fixture.seed(), source = try source(seed), reference = try #require(source.photos.first)
        let plan = try ObservationReanalysisPreparationPlan(source: source, choices: [.photo(.original(reference))])
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var current = true, finished = false
        let producer = ObservationReanalysisProducer(files: .init(documents: root), account: account(current: { current }, finish: { finished = true }),
            loadOriginal: { _, _, _ in current = false; return Data([1, 2, 3]) })
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await producer.stage(plan, container: seed.container, isCurrent: { true })
        }
        #expect(finished)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test(arguments: [true, false])
    func invalidationAfterCommitWithholdsResultAndKeepsSameReadyChild(accountChanged: Bool) async throws {
        let seed = try fixture.seed(version: 3), source = try source(seed)
        let plan = try ObservationReanalysisPreparationPlan(source: source, choices: [.photo(.added(image()))])
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let beforeCommit: @MainActor @Sendable () -> Bool = {
            let context = ModelContext(seed.container)
            guard let job = try? context.fetch(FetchDescriptor<OfflineJobRecord>()).first,
                  let text = job.metadataJSON else { return true }
            return (try? ObservationReanalysisPreparationIntent.decode(Data(text.utf8))) != nil
        }
        var finished = 0
        let producer = ObservationReanalysisProducer(files: .init(documents: root),
            account: account(current: { !accountChanged || beforeCommit() }, finish: { finished += 1 }))
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await producer.stage(plan, container: seed.container, isCurrent: { accountChanged || beforeCommit() })
        }
        #expect(finished == 1)
        let identity = OfflineQueueWork.Reanalysis(observationID: source.observationID,
            sourceAnalysisID: source.analysisID, analysisID: plan.analysisID, ownerID: source.ownerID)
        guard case let .ready(.draft(draft)) = try ObservationReanalysisPersistence.preparation(identity,
            container: seed.container, isCurrent: { true }) else { Issue.record("Ready child was lost"); return }
        let file = root.appendingPathComponent(try #require(draft.photoPaths.first))
        #expect(FileManager.default.fileExists(atPath: file.path))
        let replay = try await ObservationReanalysisProducer(files: .init(documents: root), account: account())
            .stage(plan, container: seed.container, isCurrent: { true })
        guard case let .draft(replayed) = replay else { Issue.record("Replay changed phase"); return }
        #expect(replayed == draft)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
    }

    @Test func preparationRetainsExactOriginalButNormalizesAddedPhoto() async throws {
        let bytes = try image(), id = UUID()
        let original = ObservationHistoryPhotoReference(mediaID: UUID(), contentType: "image/png", byteCount: bytes.count,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        let preserved = try await DetachedWork.value(category: .inferenceRequestPreparation) {
            try ObservationReanalysisPhotoPreparation.prepare(bytes: bytes, mediaID: id, original: original)
        }
        #expect(preserved.bytes == bytes && preserved.reference.mediaID == id && preserved.reference.contentType == "image/png")
        let added = try await DetachedWork.value(category: .inferenceRequestPreparation) {
            try ObservationReanalysisPhotoPreparation.prepare(bytes: bytes, mediaID: id, original: nil)
        }
        #expect(added.bytes != bytes && added.reference.contentType == "image/jpeg")
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPhotoPreparation.prepare(bytes: bytes + Data([0]), mediaID: id, original: original)
        }
    }

    @Test func capturePlanDoesNotReinsertRemovedOriginalsAndRejectsWrongLineage() throws {
        let seed = try fixture.seed(), source = try source(seed), reference = try #require(source.photos.first)
        var capture = StagedCapture()
        capture.observationContexts = [.init(context: .init(freeText: "Before photo"), addedAt: Date(timeIntervalSince1970: 1))]
        capture.images = [.init(compressedData: try image(), displayData: Data(), uiImage: UIImage(),
            original: .init(image: UIImage()), addedAt: Date(timeIntervalSince1970: 2))]
        let plan = try CaptureReanalysisPreparation.plan(source: source, capture: capture)
        #expect(plan.items.count == 2)
        guard case .description("Before photo") = plan.items[0], case .photo(_, .added) = plan.items[1] else {
            Issue.record("Final timeline was not preserved"); return
        }
        capture.images = [.init(compressedData: Data([1]), displayData: Data(), uiImage: UIImage(),
            original: .init(image: UIImage()), reanalysisProvenance: .original(analysisID: UUID(), photo: reference))]
        #expect(throws: (any Error).self) { try CaptureReanalysisPreparation.plan(source: source, capture: capture) }
    }

    @Test func foreignSourceMediaAndReusedSourceIDsAreRejected() throws {
        let seed = try fixture.seed(), source = try source(seed), reference = try #require(source.photos.first)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPreparationPlan(source: source, choices: [.photo(.original(reference))], makeMediaID: { reference.mediaID })
        }
        let imported = try fixture.seed(version: 3), unavailable = try self.source(imported)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPreparationPlan(source: unavailable, choices: [.photo(.original(reference))])
        }
        let plan = try ObservationReanalysisPreparationPlan(source: source,
            choices: [.photo(.edited(reference, image())), .description("After the crop"), .photo(.original(reference))])
        #expect(plan.items.count == 3)
        guard case let .photo(editedID, _) = plan.items[0], case let .photo(originalID, _) = plan.items[2] else { Issue.record("Missing photos"); return }
        #expect(editedID != originalID && editedID != reference.mediaID && originalID != reference.mediaID)
    }
}
