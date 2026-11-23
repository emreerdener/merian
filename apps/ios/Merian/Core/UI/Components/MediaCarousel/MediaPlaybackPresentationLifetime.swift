import Foundation
import Observation

/// A reusable page gets a fresh reader scope only after its previous
/// presentation has completely retired. Disposable injected scopes never renew.
@Observable @MainActor
final class MediaPlaybackPresentationLifetime {
    private(set) var current = MediaPlaybackLifetime()

    func prepare() async throws -> MediaPlaybackLifetime {
        let previous = current
        if previous.isClosed {
            await previous.close()
            try Task.checkCancellation()
            guard current === previous else { throw CancellationError() }
            current = MediaPlaybackLifetime()
        }
        try Task.checkCancellation()
        return current
    }

    func retire() {
        let previous = current
        previous.seal()
        Task { await previous.close() }
    }
}
