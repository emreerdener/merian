import Foundation
import Combine

@MainActor
class CircuitBreakerManager: ObservableObject {
    static let shared = CircuitBreakerManager()
    
    @Published var isCircuitTripped: Bool = false
    private var consecutiveFailures: Int = 0
    private let failureThreshold: Int = 2
    private let cooldownPeriod: TimeInterval = 900 // 15 minutes
    private var cooldownTimer: Timer?

    func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= failureThreshold && !isCircuitTripped { tripCircuit() }
    }

    func recordSuccess() {
        consecutiveFailures = 0
        if isCircuitTripped { resetCircuit() }
    }

    private func tripCircuit() {
        isCircuitTripped = true
        print("CircuitBreakerManager: Circuit Tripped! Routing all network requests to local Field Queue.")
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: cooldownPeriod, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resetCircuit() }
        }
    }

    private func resetCircuit() {
        isCircuitTripped = false
        consecutiveFailures = 0
        cooldownTimer?.invalidate()
        print("CircuitBreakerManager: Circuit Reset. Resuming standard network requests.")
    }
}
