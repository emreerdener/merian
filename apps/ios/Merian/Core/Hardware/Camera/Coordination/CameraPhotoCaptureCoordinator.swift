import Foundation
import os

/// Owns still-photo continuation lifetime independently of AVFoundation.
///
/// A request is reserved before its cancellation handler is installed. This
/// lets cancellation mark the reservation even when it runs before the checked
/// continuation is registered. Every terminal path removes the request under
/// one lock before resuming it, so timeout, cancellation, setup failure, and
/// delegate completion cannot resume the same continuation twice.
final class CameraPhotoCaptureCoordinator: Sendable {
    typealias Sleeper = @Sendable (UInt64) async throws -> Void

    static let defaultTimeoutNanoseconds: UInt64 = 5_000_000_000

    private struct ActiveRequest {
        let continuation: CheckedContinuation<Data, Error>
        var timeoutTask: Task<Void, Never>?
    }

    private enum Entry {
        case reserved(isCancelled: Bool)
        case active(ActiveRequest)
    }

    private struct State {
        var entries: [Int64: Entry] = [:]
    }

    private enum RegistrationOutcome {
        case registered
        case cancelled
        case invalid
    }

    private enum CancellationOutcome {
        case deferred
        case active(ActiveRequest)
        case ignored
    }

    private let timeoutNanoseconds: UInt64
    private let sleep: Sleeper
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        timeoutNanoseconds: UInt64 = CameraPhotoCaptureCoordinator.defaultTimeoutNanoseconds,
        sleep: @escaping Sleeper = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.sleep = sleep
    }

    @discardableResult
    func reserve(id: Int64) -> Bool {
        state.withLock { state in
            guard state.entries[id] == nil else { return false }
            state.entries[id] = .reserved(isCancelled: false)
            return true
        }
    }

    @discardableResult
    func register(
        id: Int64,
        continuation: CheckedContinuation<Data, Error>
    ) -> Bool {
        let outcome = state.withLock { state -> RegistrationOutcome in
            guard let entry = state.entries[id] else { return .invalid }

            switch entry {
            case .reserved(isCancelled: true):
                state.entries.removeValue(forKey: id)
                return .cancelled
            case .reserved(isCancelled: false):
                state.entries[id] = .active(ActiveRequest(
                    continuation: continuation,
                    timeoutTask: nil
                ))
                return .registered
            case .active:
                return .invalid
            }
        }

        switch outcome {
        case .cancelled:
            continuation.resume(throwing: CancellationError())
            return false
        case .invalid:
            continuation.resume(throwing: Self.requestStateError())
            return false
        case .registered:
            break
        }

        let sleep = sleep
        let timeoutNanoseconds = timeoutNanoseconds
        let timeoutTask = Task { [weak self] in
            do {
                try await sleep(timeoutNanoseconds)
                try Task.checkCancellation()
            } catch {
                return
            }

            self?.resolve(id: id) {
                .failure(Self.timeoutError())
            }
        }

        let attached = state.withLock { state -> Bool in
            guard case var .active(request)? = state.entries[id] else {
                return false
            }
            request.timeoutTask = timeoutTask
            state.entries[id] = .active(request)
            return true
        }

        if !attached {
            timeoutTask.cancel()
        }
        return attached
    }

    @discardableResult
    func cancel(id: Int64) -> Bool {
        let outcome = state.withLock { state -> CancellationOutcome in
            guard let entry = state.entries[id] else { return .ignored }

            switch entry {
            case .reserved:
                state.entries[id] = .reserved(isCancelled: true)
                return .deferred
            case let .active(request):
                state.entries.removeValue(forKey: id)
                return .active(request)
            }
        }

        switch outcome {
        case .deferred:
            return true
        case let .active(request):
            request.timeoutTask?.cancel()
            request.continuation.resume(throwing: CancellationError())
            return true
        case .ignored:
            return false
        }
    }

    @discardableResult
    func resolve(
        id: Int64,
        result: () -> Result<Data, Error>
    ) -> Bool {
        let request = state.withLock { state -> ActiveRequest? in
            guard case let .active(request)? = state.entries[id] else {
                return nil
            }
            state.entries.removeValue(forKey: id)
            return request
        }

        guard let request else { return false }
        request.timeoutTask?.cancel()
        request.continuation.resume(with: result())
        return true
    }

    var pendingRequestCount: Int {
        state.withLock { $0.entries.count }
    }

    private static func timeoutError() -> NSError {
        NSError(
            domain: "CameraManager",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: "Hardware shutter timed out"]
        )
    }

    static func requestStateError() -> NSError {
        NSError(
            domain: "CameraManager",
            code: -6,
            userInfo: [NSLocalizedDescriptionKey: "Camera capture request was not prepared."]
        )
    }
}
