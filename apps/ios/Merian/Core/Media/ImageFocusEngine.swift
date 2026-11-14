import Foundation
import Vision

enum ImageFocusVisionWorkerResult: Sendable, Equatable {
    case candidates([ImageFocusRegionCandidate])
    case noCandidates
    case failed
    case timedOut
    case cancelled

    var region: NormalizedImageFocusRegion? {
        guard case .candidates(let candidates) = self else { return nil }
        return ImageFocusRegionResolver.resolve(candidates: candidates).region
    }
}

/// Image-only worker. Capture may consume the deadline outcome immediately;
/// durable preparation additionally awaits actual worker exit before releasing
/// its account, file or reservation ownership. No telemetry or feature owner.
struct ImageFocusWorkFactory: Sendable {
    #if DEBUG
    private var fixture: ImageFocusWorkerState?
    static func qualification(_ state: ImageFocusWorkerState) -> Self {
        var factory = Self(); factory.fixture = state; return factory
    }
    #endif
    fileprivate func make() -> ImageFocusWorkerState {
        #if DEBUG
        if let fixture { return fixture }
        #endif
        return ImageFocusWorkerState()
    }
}

enum ImageFocusEngine {
    static let timeout: TimeInterval = 0.300

    static func detect(in data: Data) async -> ImageFocusVisionWorkerResult {
        await run(data, waitForDrain: false)
    }

    static func detectAndDrain(in data: Data, factory: ImageFocusWorkFactory = .init()) async -> ImageFocusVisionWorkerResult {
        await run(data, waitForDrain: true, factory: factory)
    }

    private static func run(_ data: Data, waitForDrain: Bool, factory: ImageFocusWorkFactory = .init()) async -> ImageFocusVisionWorkerResult {
        let state = factory.make()
        return await withTaskCancellationHandler {
            if Task.isCancelled { state.cancel(with: .cancelled) }
            state.start(imageData: data)
            let outcome = await state.outcome()
            if waitForDrain { await state.drain() }
            return outcome
        } onCancel: {
            state.cancel(with: .cancelled)
        }
    }
}

/// All shared state is protected by lock. Vision cancellation is called outside
/// it; immutable outcome and physical worker completion are separate facts.
final class ImageFocusWorkerState: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var finished = false
    private var result: ImageFocusVisionWorkerResult?
    private var outcomeWaiters: [CheckedContinuation<ImageFocusVisionWorkerResult, Never>] = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    private var request: VNRequest?
    #if DEBUG
    private var fixtureWorker: (@Sendable () -> ImageFocusVisionWorkerResult)?
    private var fixtureAutomaticTimeout = true
    private var fixtureFinished: (@Sendable () -> Void)?
    private var fixtureBeforeInstall: (@Sendable () -> Void)?
    private var fixtureBeforePerform: (@Sendable () -> Void)?
    private var fixtureDrainRegistered: (@Sendable () -> Void)?
    static func qualification(worker: @escaping @Sendable () -> ImageFocusVisionWorkerResult,
                              drainRegistered: (@Sendable () -> Void)? = nil) -> ImageFocusWorkerState {
        let state = ImageFocusWorkerState()
        state.fixtureWorker = worker; state.fixtureDrainRegistered = drainRegistered
        return state
    }
    static func qualification(beforeInstall: @escaping @Sendable () -> Void,
                              beforePerform: @escaping @Sendable () -> Void,
                              finished: @escaping @Sendable () -> Void,
                              drainRegistered: @escaping @Sendable () -> Void) -> ImageFocusWorkerState {
        let state = ImageFocusWorkerState()
        state.fixtureAutomaticTimeout = false; state.fixtureFinished = finished
        state.fixtureBeforeInstall = beforeInstall; state.fixtureBeforePerform = beforePerform
        state.fixtureDrainRegistered = drainRegistered
        return state
    }
    #endif

    fileprivate init() {}

    func start(imageData: Data) {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        let cancelledBeforeDispatch = result != nil
        lock.unlock()
        if cancelledBeforeDispatch { finish(); return }
        let workerQueue = DispatchQueue(label: "media.image-focus.worker", qos: .userInitiated)
        workerQueue.async { [self] in
            // Completion is after Vision and the autorelease pool, never merely
            // after requesting cancellation or resolving the visible outcome.
            let value = autoreleasepool { work(imageData) }
            resolve(value)
        }
        // A second serial block runs after the worker closure and its captured
        // image data have been released, not from the visible-result callback.
        workerQueue.async { [self] in finish() }
        #if DEBUG
        if !fixtureAutomaticTimeout { return } // Installation-race fixture drives cancellation explicitly.
        #endif
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + ImageFocusEngine.timeout) { [self] in
            cancel(with: .timedOut)
        }
    }

    func outcome() async -> ImageFocusVisionWorkerResult {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result { lock.unlock(); continuation.resume(returning: result) } else { outcomeWaiters.append(continuation); lock.unlock() }
        }
    }

    /// Intentionally nonthrowing: cancellation is not evidence of termination.
    func drain() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished { lock.unlock(); continuation.resume() } else {
                drainWaiters.append(continuation)
                lock.unlock()
                #if DEBUG
                fixtureDrainRegistered?()
                #endif
            }
        }
    }

    func cancel(with value: ImageFocusVisionWorkerResult) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let pending = outcomeWaiters, current = request
        outcomeWaiters.removeAll(); request = nil
        lock.unlock()
        current?.cancel()
        for continuation in pending { continuation.resume(returning: value) }
    }

    private func work(_ data: Data) -> ImageFocusVisionWorkerResult {
        #if DEBUG
        if let fixtureWorker { return fixtureWorker() }
        #endif
        guard !isResolved else { return .cancelled }
        guard let image = ImageDownsampler.downsample(data: data, maxSize: 512) else { return .failed }
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        request.revision = VNGenerateObjectnessBasedSaliencyImageRequestRevision2
        #if DEBUG
        fixtureBeforeInstall?()
        #endif
        guard install(request) else { return .cancelled }
        #if DEBUG
        fixtureBeforePerform?()
        #endif
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
            guard let objects = request.results?.first?.salientObjects, !objects.isEmpty else { return .noCandidates }
            return .candidates(objects.map { .init(boundingBox: $0.boundingBox, confidence: $0.confidence) })
        } catch { return .failed }
    }

    private var isResolved: Bool {
        lock.lock(); defer { lock.unlock() }; return result != nil
    }
    private func install(_ request: VNRequest) -> Bool {
        lock.lock()
        guard result == nil else { lock.unlock(); request.cancel(); return false }
        self.request = request
        lock.unlock(); return true
    }
    private func resolve(_ value: ImageFocusVisionWorkerResult) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value; request = nil
        let pending = outcomeWaiters; outcomeWaiters.removeAll()
        lock.unlock()
        for continuation in pending { continuation.resume(returning: value) }
    }
    private func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; request = nil
        let pending = drainWaiters; drainWaiters.removeAll()
        lock.unlock()
        for continuation in pending { continuation.resume() }
        #if DEBUG
        fixtureFinished?()
        #endif
    }
}
