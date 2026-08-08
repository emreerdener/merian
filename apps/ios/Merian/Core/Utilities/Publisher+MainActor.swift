import Combine
import Foundation

extension Publisher where Failure == Never {
    /// Bridges a publisher with an unknown originating executor to the main
    /// actor while preserving Combine's ordered delivery.
    ///
    /// AppEventPublisher must not use this helper: that bus is already
    /// synchronously `@MainActor`-isolated and scheduling it would change its
    /// reentrancy contract.
    func sinkOnMainActor(
        receiveValue: @MainActor @escaping (Output) -> Void
    ) -> AnyCancellable {
        receive(on: DispatchQueue.main)
            .sink { value in
                MainActor.assumeIsolated {
                    receiveValue(value)
                }
            }
    }
}
