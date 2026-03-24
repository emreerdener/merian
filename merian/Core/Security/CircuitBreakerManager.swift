import Foundation
import Combine
import Observation
import os

// MARK: - Core Fault Tolerance Engine
@MainActor
@Observable final class CircuitBreakerManager {
    // MARK: - Singleton Architecture
    static let shared = CircuitBreakerManager()
    
    // MARK: - State Management
    var isCircuitTripped: Bool = false
    
    // MARK: - Telemetry Thresholds
    private var consecutiveFailures: Int = 0
    private let failureThreshold: Int = 2
    private let cooldownPeriod: TimeInterval = 900 // 15 minutes
    private var cooldownTimer: Timer?

    // MARK: - Public API Telemetry
    func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= failureThreshold && !isCircuitTripped { tripCircuit() }
    }

    func recordSuccess() {
        consecutiveFailures = 0
        if isCircuitTripped { resetCircuit() }
    }

    // MARK: - Private Circuit Breaker Logic
    private func tripCircuit() {
        isCircuitTripped = true
        MerianLog.general.debug("CircuitBreakerManager: Circuit Tripped! Routing all network requests to local Field Queue.")
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: cooldownPeriod, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resetCircuit() }
        }
    }

    private func resetCircuit() {
        isCircuitTripped = false
        consecutiveFailures = 0
        cooldownTimer?.invalidate()
        MerianLog.general.debug("CircuitBreakerManager: Circuit Reset. Resuming standard network requests.")
    }
}
