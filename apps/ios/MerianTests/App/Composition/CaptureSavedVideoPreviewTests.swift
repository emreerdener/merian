import AVFoundation
import Foundation
import Testing
@testable import Merian

@MainActor private final class SavedVideoActivationProbe {
    var waiter: CheckedContinuation<Void, Never>?
    var releases = 0
    func wait() async { await withCheckedContinuation { waiter = $0 } }
    func release() { releases += 1 }
}

@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
struct CaptureSavedVideoPreviewTests {
    @Test(arguments: ["pause", "close", "scope"])
    func lateActivationCannotStartRetiredClip(_ change: String) async throws {
        let fixture = try await VideoAudioFixture(channels: nil); defer { fixture.remove() }
        let coordinator = AudioSessionCoordinator(operations: .init(configureAndActivate: { _ in }, deactivate: {}))
        let lease = try await coordinator.activate(.playbackDucking), probe = SavedVideoActivationProbe()
        let session = AudioPlaybackSessionController(dependencies: .init(activate: { _ in
            await probe.wait(); return lease
        }, deactivate: { returned in
            await coordinator.deactivate(ifCurrent: returned); await probe.release()
        }, isCurrent: { await coordinator.isCurrent($0) }))
        var current = true
        let model = try CaptureSavedVideoPreviewModel(bytes: Data(contentsOf: fixture.videoURL), validate: { current }, session: session)
        await model.load(); #expect(model.isReady && model.player.rate == 0 && !session.hasActiveLease)
        model.toggle()
        while probe.waiter == nil { await Task.yield() }
        if change == "pause" { model.pause() }
        else if change == "close" { model.close() }
        else { current = false; model.checkScope() }
        probe.waiter?.resume()
        while probe.releases == 0 { await Task.yield() }
        #expect(!model.isPlaying && model.player.rate == 0 && !session.hasActiveLease && probe.releases == 1)
        model.close(); #expect(model.player.currentItem == nil)
    }

    @Test(arguments: ["close", "background", "account", "visible"])
    func lateReadCannotPublishIntoDepartedSavedScreen(_ departure: String) async {
        let row = CaptureVideoSavedModelTests().row()
        var current = true, waiter: CheckedContinuation<Void, Never>?, returned = false, creations = 0, resumes = 0
        let model = CaptureVideoSavedRequestsModel(status: .init(isCurrent: { current }, page: { _, _, _ in
            .init(items: [row], next: nil, omittedCount: 0)
        }), openResume: { identity in
            #expect(identity == row.identity)
            return .init(resume: { _ in resumes += 1; return .unavailable }, preview: { _ in
                await withCheckedContinuation { waiter = $0 }; returned = true
                return .init(bytes: Data([1]), validate: {})
            })
        }, isPresented: { true }, makePreview: { _, _ in creations += 1; throw MerianError.invalidResponse })
        model.start(); while model.isBusy { await Task.yield() }
        model.select(row); model.previewSelected()
        while waiter == nil { await Task.yield() }
        if departure == "close" { model.close() }
        if departure == "background" { model.setVisible(false) }
        if departure == "account" { current = false }
        waiter?.resume()
        while !returned || model.isBusy { await Task.yield() }
        #expect(creations == (departure == "visible" ? 1 : 0) && resumes == 0 && model.preview == nil)
        model.close()
    }
}
