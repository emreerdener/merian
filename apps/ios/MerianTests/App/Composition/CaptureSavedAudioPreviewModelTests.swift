import Foundation
import Testing
@testable import Merian

@MainActor private final class SavedAudioActivationProbe {
    var waiter: CheckedContinuation<Void, Never>?
    var releases = 0
    func wait() async { await withCheckedContinuation { waiter = $0 } }
    func release() { releases += 1 }
}

@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
struct CaptureSavedAudioPreviewModelTests {
    @Test(arguments: ["pause", "close", "scope"])
    func lateActivationCannotStartRetiredPreview(_ change: String) async throws {
        let coordinator = AudioSessionCoordinator(operations: .init(configureAndActivate: { _ in }, deactivate: {}))
        let lease = try await coordinator.activate(.playbackDucking)
        let probe = SavedAudioActivationProbe(), driver = CarouselAudioDriverSpy()
        let session = AudioPlaybackSessionController(dependencies: .init(activate: { _ in
            await probe.wait(); return lease
        }, deactivate: { returned in
            await coordinator.deactivate(ifCurrent: returned); await probe.release()
        }, isCurrent: { await coordinator.isCurrent($0) }))
        var current = true
        let model = CaptureSavedAudioPreviewModel(driver: driver, validate: { current }, session: session)
        await model.load(); model.toggle()
        while probe.waiter == nil { await Task.yield() }
        if change == "pause" { model.pause() }
        else if change == "close" { model.close() }
        else { current = false; model.checkScope() }
        probe.waiter?.resume()
        while probe.releases == 0 { await Task.yield() }
        #expect(!driver.events.contains("play") && !model.isPlaying)
        #expect(probe.releases == 1 && !session.hasActiveLease)
        model.close()
    }

    @Test(arguments: ["pause", "close", "scope"])
    func latePlayStopsBeforeExactSessionRelease(_ change: String) async throws {
        let coordinator = AudioSessionCoordinator(operations: .init(configureAndActivate: { _ in }, deactivate: {}))
        let probe = SavedAudioActivationProbe(), driver = CarouselAudioDriverSpy()
        driver.suspendPlay = true; driver.suspendStop = true
        let session = AudioPlaybackSessionController(dependencies: .init(
            activate: { try await coordinator.activate($0) },
            deactivate: { returned in
                await coordinator.deactivate(ifCurrent: returned); await probe.release()
            }, isCurrent: { await coordinator.isCurrent($0) }))
        var current = true
        let model = CaptureSavedAudioPreviewModel(driver: driver, validate: { current }, session: session)
        await model.load(); model.toggle()
        while driver.playWaiter == nil { await Task.yield() }
        if change == "pause" { model.pause() }
        else if change == "close" { model.close() }
        else { current = false; model.checkScope() }
        #expect(probe.releases == 0 && !model.isPlaying)
        driver.playWaiter?.resume()
        while driver.stopWaiter == nil { await Task.yield() }
        #expect(probe.releases == 0)
        driver.stopWaiter?.resume()
        while probe.releases == 0 { await Task.yield() }
        #expect(!driver.playing && !model.isPlaying && probe.releases == 1)
        driver.suspendStop = false
        model.close()
    }
}
