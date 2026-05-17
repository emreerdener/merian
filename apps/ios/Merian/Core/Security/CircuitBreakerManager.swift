import Foundation
import Observation
import os

@MainActor
@Observable final class CircuitBreakerManager {
    static let shared = CircuitBreakerManager()

    // MARK: - State

    var isCircuitTripped: Bool = false

    // MARK: - Configuration

    private var consecutiveFailures: Int = 0
    private let failureThreshold: Int = 3
    private let cooldownPeriod: TimeInterval = 15 * 60
    private var cooldownTimer: Timer?

    // MARK: - Recording

    func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= failureThreshold && !isCircuitTripped {
            tripCircuit()
        }
    }

    func recordSuccess() {
        consecutiveFailures = 0
        if isCircuitTripped {
            resetCircuit()
        }
    }

    // MARK: - Private

    private func tripCircuit() {
        isCircuitTripped = true
        MerianLog.general.debug("Circuit tripped after \(self.consecutiveFailures) failures; entering cooldown.")
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: cooldownPeriod, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resetCircuit() }
        }
    }

    private func resetCircuit() {
        isCircuitTripped = false
        consecutiveFailures = 0
        cooldownTimer?.invalidate()
        MerianLog.general.debug("Circuit reset; resuming normal requests.")
    }
}
