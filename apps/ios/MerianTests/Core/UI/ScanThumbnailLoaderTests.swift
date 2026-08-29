import Testing
import UIKit

@testable import Merian

struct ScanThumbnailLoaderTests {
    @Test func referencePreferredAudioSkipsSpectrogramLoading() async {
        let calls = ThumbnailLoaderCallRecorder()
        let loader = ScanThumbnailLoader(
            dependencies: .init(
                loadSpectrogram: { _, _ in
                    await calls.recordSpectrogram()
                    return nil
                },
                loadVisual: { _, _, _ in
                    await calls.recordVisual()
                    return UIImage()
                }
            )
        )

        let result = await loader.load(
            request(prefersReferenceForAudio: true)
        )

        guard case .loaded? = result else {
            Issue.record("Expected the reference image to load")
            return
        }
        #expect(await calls.spectrogramCount == 0)
        #expect(await calls.visualCount == 1)
    }

    @Test func cancelledSpectrogramCannotStartStaleVisualFallback() async {
        let gate = ThumbnailLoaderContinuationGate()
        let calls = ThumbnailLoaderCallRecorder()
        let loader = ScanThumbnailLoader(
            dependencies: .init(
                loadSpectrogram: { _, _ in
                    await calls.recordSpectrogram()
                    await gate.wait()
                    return nil
                },
                loadVisual: { _, _, _ in
                    await calls.recordVisual()
                    return UIImage()
                }
            )
        )
        let task = Task {
            await loader.load(
                request(prefersReferenceForAudio: false)
            )
        }

        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()

        #expect(await task.value == nil)
        #expect(await calls.spectrogramCount == 1)
        #expect(await calls.visualCount == 0)
    }

    @Test func missingSourcesDoNotInvokeEitherLoader() async {
        let calls = ThumbnailLoaderCallRecorder()
        let loader = ScanThumbnailLoader(
            dependencies: .init(
                loadSpectrogram: { _, _ in
                    await calls.recordSpectrogram()
                    return UIImage()
                },
                loadVisual: { _, _, _ in
                    await calls.recordVisual()
                    return UIImage()
                }
            )
        )
        let result = await loader.load(
            ScanThumbnailLoadRequest(
                imagePath: nil,
                fallbackImageURL: nil,
                audioPath: nil,
                prefersReferenceForAudio: false,
                maxDimension: 300
            )
        )

        guard case .noVisualSource? = result else {
            Issue.record("Expected the no-source result")
            return
        }
        #expect(await calls.spectrogramCount == 0)
        #expect(await calls.visualCount == 0)
    }

    private func request(
        prefersReferenceForAudio: Bool
    ) -> ScanThumbnailLoadRequest {
        ScanThumbnailLoadRequest(
            imagePath: "reference.webp",
            fallbackImageURL: nil,
            audioPath: "recording.wav",
            prefersReferenceForAudio: prefersReferenceForAudio,
            maxDimension: 300
        )
    }
}

private actor ThumbnailLoaderCallRecorder {
    private(set) var spectrogramCount = 0
    private(set) var visualCount = 0

    func recordSpectrogram() {
        spectrogramCount += 1
    }

    func recordVisual() {
        visualCount += 1
    }
}

private actor ThumbnailLoaderContinuationGate {
    private var isEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        isEntered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !isEntered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
