import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture original discovery", .serialized)
@MainActor
struct CaptureDraftSourceRecoveryTests {
    @Test func retainedPhotoAndAudioOnlyMaterializeTheNewPreparedPhoto() async throws {
        let fixture = CaptureDraftSourceBindingTests()
        let store = try await CaptureDraftSourceBindingTests.Store(), owner = try await store.open()
        let audio = fixture.source(store, ordinal: 1), bytes = store.bytes
        let photo = SharedMediaCaptureDraftSourceInput(id: UUID(), scanID: audio.scanID,
            submissionGeneration: audio.submissionGeneration, mediaID: UUID(), itemIndex: 0,
            role: .sourceImage, contentType: "image/jpeg", byteCount: audio.byteCount,
            sha256: audio.sha256, context: .init(origin: .imported, cameraVerticalCenter: nil))
        let retained = try await owner.materializeAppCaptureSource(photo, bytes: bytes)
        _ = try await owner.materializeAppCaptureSource(audio, bytes: bytes)
        let prepared = UUID()
        let geometry = try ObservationInitialPhotoPreparation(recipe: ObservationInitialPhotoPreparationTests().recipe())
        let plan = try CaptureInitialEvidencePlan(ownerID: store.base.ownerID, scanID: audio.scanID,
            generation: audio.submissionGeneration, items: [
                .audio(.init(source: .init(mediaID: audio.mediaID, contentType: audio.contentType,
                    byteCount: bytes.count, sha256: audio.sha256), preparedMediaID: UUID())),
                .description("Synthetic mixed-media note"),
                .image(source: .init(mediaID: photo.mediaID, contentType: photo.contentType,
                    byteCount: bytes.count, sha256: photo.sha256), prepared: .init(mediaID: prepared,
                    contentType: "image/jpeg", byteCount: bytes.count, sha256: photo.sha256),
                    focus: nil, preparation: geometry)
            ])
        var reads: [UUID] = []
        _ = try await owner.acceptAppCaptureDraft(plan: plan,
            context: SharedMediaCaptureSubmissionContextTests.context(plan)) { input in
            reads.append(input.mediaID); return bytes
        }
        #expect(reads == [prepared])
        let rows = try store.rows().map(SharedMediaCaptureArtifactLedger.receipt)
        #expect(rows.count == 3 && rows.first { $0.request.id == photo.id } == retained)
        #expect(owner.isReadyForCaptureDispatch)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func coldDiscoveryNeedsNoLibraryRowAndStopsListingBoundSources() async throws {
        let fixture = CaptureDraftSourceBindingTests()
        let store = try await CaptureDraftSourceBindingTests.Store(), owner = try await store.open()
        let input = fixture.source(store)
        let original = try await owner.materializeAppCaptureSource(input, bytes: store.bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        let page = try await cold.captureDraftSourcePage()
        #expect(page.sources == [original] && page.nextCursor == nil)
        #expect(try SharedMediaCaptureDraftSourceInput(retained: original.request) == input)
        #expect(try await cold.readAppCaptureSource(input) == store.bytes)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        #expect(try read.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        let plan = try fixture.plan(store, sources: [input])
        _ = try await cold.acceptAppCaptureDraft(plan: plan,
            context: SharedMediaCaptureSubmissionContextTests.context(plan)) { _ in
            Issue.record("Recovered original required another producer read")
            throw SharedMediaStorageFailure.conflict
        }
        #expect(try await cold.captureDraftSourcePage().sources.isEmpty)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func typedReadRejectsStaleDraftFactsWithoutLosingOriginal() async throws {
        let fixture = CaptureDraftSourceBindingTests()
        let store = try await CaptureDraftSourceBindingTests.Store(), owner = try await store.open(), input = fixture.source(store)
        _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes)
        let stale = SharedMediaCaptureDraftSourceInput(id: input.id, scanID: input.scanID,
            submissionGeneration: UUID(), mediaID: input.mediaID, itemIndex: input.itemIndex,
            role: input.role, contentType: input.contentType, byteCount: input.byteCount,
            sha256: input.sha256, context: input.context)
        await #expect(throws: (any Error).self) { _ = try await owner.readAppCaptureSource(stale) }
        await #expect(throws: (any Error).self) { _ = try await owner.captureDraftSourcePage(after: "invalid") }
        #expect(try await owner.readAppCaptureSource(input) == store.bytes)
        #expect(try await owner.captureDraftSourcePage().sources.count == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}
