import AVFoundation
import Foundation
import Testing

@testable import Merian

private final class ThreadCheckingAudioPlayer: AVAudioPlayer {
    private var time: TimeInterval = 0
    private var simulatedPlaying = false
    override var duration: TimeInterval { #expect(!Thread.isMainThread); return 10 }
    override var isPlaying: Bool { #expect(!Thread.isMainThread); return simulatedPlaying }
    override var currentTime: TimeInterval {
        get { #expect(!Thread.isMainThread); return time }
        set { #expect(!Thread.isMainThread); time = newValue }
    }
    override func prepareToPlay() -> Bool {
        Issue.record("Loading must not activate the audio session")
        return false
    }
    override func play() -> Bool { #expect(!Thread.isMainThread); simulatedPlaying = true; return true }
    override func pause() { #expect(!Thread.isMainThread); simulatedPlaying = false }
    override func stop() { #expect(!Thread.isMainThread); simulatedPlaying = false }
}

@MainActor
private final class CarouselAudioDriverSpy: AudioPlaybackDriver {
    var time: TimeInterval = 0
    var playing = false
    var events: [String] = []
    var suspendPlay = false
    var suspendSnapshot = false
    var suspendStop = false
    var stopWaiter: CheckedContinuation<Void, Never>?
    var playWaiter: CheckedContinuation<Void, Never>?
    var snapshotWaiter: CheckedContinuation<Void, Never>?
    var delegate: AudioPlayerDelegate?
    func load(delegate: AudioPlayerDelegate) -> AudioPlaybackSnapshot {
        self.delegate = delegate
        events.append("load")
        return value
    }
    func play() async -> AudioPlaybackSnapshot {
        events.append("play")
        if suspendPlay { await withCheckedContinuation { playWaiter = $0 } }
        playing = true
        return value
    }
    func pause() { events.append("pause"); playing = false }
    func stop() async {
        events.append("stop")
        if suspendStop { await withCheckedContinuation { stopWaiter = $0 } }
        playing = false
    }
    func seek(to time: TimeInterval) { events.append("seek"); self.time = time }
    func snapshot() async -> AudioPlaybackSnapshot {
        let snapshot = value
        if suspendSnapshot { await withCheckedContinuation { snapshotWaiter = $0 } }
        return snapshot
    }
    func dispose() { events.append("dispose"); playing = false }
    private var value: AudioPlaybackSnapshot {
        .init(currentTime: time, duration: 10, isPlaying: playing)
    }
}

@Suite("Carousel audio player executor and command lifetime")
@MainActor
struct AudioPlaybackFilePlayerTests {
    @Test("Construction, playback, seeking and disposal run off the UI thread")
    func driverCallsStayOffMainThread() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try makeInferenceTestPCM16WAVData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let driver = AudioPlaybackFileDriver(url: url) { url in
            #expect(!Thread.isMainThread)
            return try ThreadCheckingAudioPlayer(contentsOf: url)
        }
        let loaded = try await driver.load(delegate: AudioPlayerDelegate())
        #expect(loaded.duration == 10)
        #expect(!loaded.isPlaying)
        #expect(await driver.play().isPlaying)
        await driver.seek(to: 3)
        #expect(await driver.snapshot().currentTime == 3)
        await driver.pause()
        #expect(await driver.snapshot().isPlaying == false)
        await driver.stop()
        await driver.dispose()
        #expect(await driver.snapshot().duration == 0)
    }

    @Test("Loading is silent and preserves duration for the UI")
    func loadingDoesNotStartPlayback() async throws {
        let driver = CarouselAudioDriverSpy()
        let player = AudioPlaybackFilePlayer(driver: driver)
        try await player.load()
        #expect(driver.events == ["load"])
        #expect(player.duration == 10)
        #expect(!player.isPlaying)
    }

    @Test("Stop joins an uncancellable play and rejects its late UI result")
    func stopDuringPlay() async throws {
        let driver = CarouselAudioDriverSpy()
        driver.suspendPlay = true
        let player = AudioPlaybackFilePlayer(driver: driver)
        try await player.load()
        let playing = Task { await player.play() }
        await waitUntil { driver.playWaiter != nil }
        let stopping = player.stop()
        #expect(!player.isPlaying)
        #expect(driver.events == ["load", "play"])
        driver.playWaiter?.resume()
        #expect(await playing.value == false)
        await stopping.value
        #expect(driver.events == ["load", "play", "stop"])
        #expect(!driver.playing)
        #expect(!player.isPlaying)
    }

    @Test("A seek during startup preserves both play intent and the new position")
    func seekDuringPlay() async throws {
        let driver = CarouselAudioDriverSpy()
        driver.suspendPlay = true
        let player = AudioPlaybackFilePlayer(driver: driver)
        try await player.load()
        let playing = Task { await player.play() }
        await waitUntil { driver.playWaiter != nil }
        player.currentTime = 7
        driver.playWaiter?.resume()
        #expect(await playing.value)
        #expect(player.isPlaying)
        #expect(player.currentTime >= 7)
        await player.stop().value
        #expect(driver.time == 7)
    }

    @Test("Replacement cannot start until its predecessor stops")
    func replacementWaitsForRetirement() async throws {
        let oldDriver = CarouselAudioDriverSpy()
        let oldPlayer = AudioPlaybackFilePlayer(driver: oldDriver)
        try await oldPlayer.load()
        #expect(await oldPlayer.play())
        oldDriver.suspendStop = true
        let newDriver = CarouselAudioDriverSpy()
        let newPlayer = AudioPlaybackFilePlayer(driver: newDriver)
        try await newPlayer.load()
        newPlayer.waitForRetirement(oldPlayer.stop())
        let starting = Task { await newPlayer.play() }
        await waitUntil { oldDriver.stopWaiter != nil }
        for _ in 0..<10 { await Task.yield() }
        #expect(newDriver.events == ["load"])
        oldDriver.stopWaiter?.resume()
        #expect(await starting.value)
        #expect(!oldDriver.playing)
        await newPlayer.stop().value
    }

    @Test("A late time sample cannot overwrite a seek")
    func staleSnapshotDoesNotUndoSeek() async throws {
        let driver = CarouselAudioDriverSpy()
        let player = AudioPlaybackFilePlayer(driver: driver)
        try await player.load()
        driver.time = 1
        driver.suspendSnapshot = true
        let refresh = Task { await player.refresh() }
        await waitUntil { driver.snapshotWaiter != nil }
        player.currentTime = 7
        driver.snapshotWaiter?.resume()
        await refresh.value
        await player.stop().value
        #expect(player.currentTime == 7)
        #expect(driver.time == 7)
    }

    @Test("Pause and seek are ordered before resume")
    func commandsPreserveOrder() async throws {
        let driver = CarouselAudioDriverSpy()
        let player = AudioPlaybackFilePlayer(driver: driver)
        try await player.load()
        #expect(await player.play())
        player.pause()
        player.currentTime = 4
        #expect(await player.play())
        #expect(driver.events == ["load", "play", "pause", "seek", "play"])
        await player.stop().value
    }

    @Test("A completion after a stopped time sample still finishes; teardown ignores late events")
    func completionAfterStoppedSnapshot() async throws {
        let driver = CarouselAudioDriverSpy()
        let player = AudioPlaybackFilePlayer(driver: driver)
        var finishes = 0
        var failures = 0
        player.onFinish = { _, _ in finishes += 1 }
        player.onDecodeError = { _, _ in failures += 1 }
        try await player.load()
        #expect(await player.play())
        driver.playing = false
        await player.refresh()
        driver.delegate?.onFinish(ObjectIdentifier(player), true)
        #expect(finishes == 1)
        #expect(await player.play())
        await player.stop().value
        driver.delegate?.onFinish(ObjectIdentifier(player), true)
        driver.delegate?.onDecodeError(ObjectIdentifier(player), "synthetic")
        #expect(finishes == 1)
        #expect(failures == 0)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for audio driver")
    }
}
