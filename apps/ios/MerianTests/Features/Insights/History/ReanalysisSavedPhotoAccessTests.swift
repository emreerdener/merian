import CryptoKit
import UIKit
import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ReanalysisSavedPhotoAccessTests {
    let fixture = ObservationReanalysisRecoveryTests()

    @Test(arguments: ["pending", "draft", "bound", "missing", "changed", "account"])
    func originalPhotoReadDoesNotAdoptOrDispatch(_ state: String) async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed)
        if state == "draft" || state == "bound" { _ = try await fixture.recover(seed) }
        if state == "bound" {
            _ = try ObservationReanalysisPersistence.bindDraft(seed.pending.draft, processor: .gemini,
                container: seed.container, isCurrent: { true })
        }
        let id = seed.pending.draft.identity
        let context = ModelContext(seed.container)
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: id.analysisID.uuidString.lowercased())))
        let metadata = job.metadataJSON, attempt = job.attemptCount, status = job.statusRaw
        if state == "missing" { try FileManager.default.removeItem(at: seed.file) }
        if state == "changed" { try Data(repeating: 0, count: seed.bytes.count).write(to: seed.file) }
        var current = state != "account", leases = 0
        var account = fixture.producerFixture.account()
        account.begin = { owner in leases += 1; return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        account.finish = { _ in leases -= 1 }
        let read = {
            try await ReanalysisSavedPhotoAccess.read(identity: id, index: 0, container: seed.container,
                files: .init(documents: seed.root), ownership: .init(), account: account, isCurrent: { current })
        }
        if ["missing", "changed", "account"].contains(state) {
            await #expect(throws: (any Error).self) { try await read() }
        } else {
            let preview = try await read()
            #expect(preview.count == 1 && preview.index == 0)
            #expect(preview.image.cgImage.width <= 2048 && preview.image.cgImage.height <= 2048)
            try preview.validate()
            current = false
            #expect(throws: (any Error).self) { try preview.validate() }
            current = true
            #expect(try Data(contentsOf: seed.file) == seed.bytes)
            let fresh = try #require(try ModelContext(seed.container).fetchOfflineJob(id: job.id))
            #expect(fresh.metadataJSON == metadata && fresh.attemptCount == attempt && fresh.statusRaw == status)
            context.delete(job); try context.save()
            #expect(throws: (any Error).self) { try preview.validate() }
            #expect(leases == 0)
            return
        }
        let fresh = try #require(try ModelContext(seed.container).fetchOfflineJob(id: job.id))
        #expect(fresh.metadataJSON == metadata && fresh.attemptCount == attempt && fresh.statusRaw == status && leases == 0)
    }

    @Test(arguments: ["ready", "held", "files", "malformed", "changed"])
    func admissionWrapperIsReadWithoutClaimOrRearm(_ state: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed)
        let id = seed.pending.draft.identity, context = ModelContext(seed.container)
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: id.analysisID.uuidString.lowercased())))
        let work = try ObservationReanalysisAdmissionWork(preparation: seed.pending,
            phase: state == "files" ? .filesPending : .admissionPending,
            state: state == "held" ? .held : .pending, attempt: state == "held" ? 1 : 0,
            updatedAt: state == "held" ? Date(timeIntervalSince1970: 2_000_000_000) : nil,
            hold: state == "held" ? .consentRequired : nil)
        var object = try #require(JSONSerialization.jsonObject(with: work.storedData()) as? [String: Any])
        if state == "malformed" { object["unexpected"] = true }
        job.metadataJSON = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)
        try context.save()
        let metadata = job.metadataJSON
        let read = {
            try await ReanalysisSavedPhotoAccess.read(identity: id, index: 0, container: seed.container,
                files: .init(documents: seed.root), ownership: .init(), account: fixture.producerFixture.account(), isCurrent: { true })
        }
        if state == "malformed" {
            await #expect(throws: (any Error).self) { try await read() }
        } else {
            let preview = try await read(); try preview.validate()
            if state == "changed" {
                object["phase"] = "files_pending"
                job.metadataJSON = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)
                try context.save()
                #expect(throws: (any Error).self) { try preview.validate() }
                return
            }
        }
        let fresh = try #require(try ModelContext(seed.container).fetchOfflineJob(id: job.id))
        #expect(fresh.metadataJSON == metadata && fresh.attemptCount == 0 && fresh.status == .needsAttention)
    }

    @Test(arguments: [false, true])
    func secondPhotoUsesOriginalOrderAndRequiresUnselectedSibling(corruptSibling: Bool) async throws {
        let seed = try fixture.sourceFixture.seed(version: 3)
        let source = try fixture.producerFixture.source(seed)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let photos = try [CGSize(width: 16, height: 16), CGSize(width: 24, height: 12)].map { size in
            try #require(UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.green.setFill(); context.fill(CGRect(origin: .zero, size: size))
            }.pngData())
        }
        let evidence = photos.map { bytes in
            ObservationReanalysisRequest.Evidence.image(.init(mediaID: UUID(), contentType: "image/png", byteCount: bytes.count,
                sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()))
        }
        let draft = try ObservationReanalysisDraft(identity: .init(observationID: source.observationID,
            sourceAnalysisID: source.analysisID, analysisID: UUID(), ownerID: source.ownerID), evidence: evidence)
        let pending = try ObservationReanalysisPreparationIntent(draft: draft, source: source)
        _ = try ObservationReanalysisPersistence.beginPreparation(pending.verified(source: source), container: seed.container, isCurrent: { true })
        let files = ObservationReanalysisFileStore(documents: root)
        try await files.persist(draft: draft, photos: photos) {}
        if corruptSibling { try Data(repeating: 0, count: photos[0].count).write(to: root.appendingPathComponent(draft.photoPaths[0])) }
        let read = {
            try await ReanalysisSavedPhotoAccess.read(identity: draft.identity, index: 1, container: seed.container,
                files: files, ownership: .init(), account: fixture.producerFixture.account(), isCurrent: { true })
        }
        if corruptSibling { await #expect(throws: (any Error).self) { try await read() } }
        else {
            let preview = try await read()
            #expect(preview.count == 2 && preview.index == 1)
            #expect(preview.image.cgImage.width == 24 && preview.image.cgImage.height == 12)
        }
    }

    @Test(arguments: ["close", "background", "account", "visible"])
    func lateImageCannotReopenDepartedScreen(_ departure: String) async throws {
        let bytes = try fixture.producerFixture.image()
        let image = try #require(ImageDownsampler.downsampledSendableImage(data: bytes, maxSize: 2048))
        let row = ObservationReanalysisOperationStatus.Summary(id: UUID(), sourceAnalysisID: UUID(), phase: .reconciliationRequired)
        var current = true, waiter: CheckedContinuation<Void, Never>?, finished = false
        var dependencies = ReanalysisStatusDependencies(page: { _ in .init(items: [row], next: nil) },
            validate: {}, isCurrent: { current }, close: {})
        dependencies.photo = { requested, index, _ in
            #expect(requested == row && index == 0)
            await withCheckedContinuation { waiter = $0 }
            finished = true
            return .init(image: image, index: 0, count: 1, validate: {})
        }
        let model = ReanalysisStatusViewModel(dependencies: dependencies)
        await model.load(); model.viewPhoto(row)
        while waiter == nil { await Task.yield() }
        if departure == "close" { model.close() }
        if departure == "background" { model.setVisible(false) }
        if departure == "account" { current = false }
        waiter?.resume()
        while !finished || model.isBusy { await Task.yield() }
        #expect((model.photo != nil) == (departure == "visible"))
        model.close(); #expect(model.photo == nil && model.photoRow == nil)
    }
}
