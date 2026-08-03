import Combine
import Foundation
import UIKit

// MARK: - UIDevice Extension

extension UIDevice {
    /// Returns true for iPhone 14 and newer (model identifier ≥ iPhone15,x).
    /// Used to default live-inference off on modern hardware, which reaches thermal limits quickly.
    var isModernIPhone: Bool {
        var systemInfo = utsname()
        uname(&systemInfo)

        var identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { ptr in
                String(cString: ptr)
            }
        }

        #if targetEnvironment(simulator)
        if let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            identifier = simulatorModel
        }
        #endif

        // "iPhone14,x" → iPhone 13. "iPhone15,x" → iPhone 14.
        // Classify ≥ 15 as modern to catch devices prone to thermal load under sustained inference.
        if identifier.hasPrefix("iPhone") {
            let numberPart = identifier.dropFirst(6).split(separator: ",").first ?? "0"
            if let majorVersion = Int(numberPart), majorVersion >= 15 {
                return true
            }
        }

        return false
    }
}

// MARK: - Hardware Orchestrator

/// Thermal management and FPS orchestration for the hardware layer.
/// Monitors system thermal state and Low Power Mode, adjusting frame rate and UI quality accordingly.
@MainActor
@Observable final class HardwareOrchestrator {
    // MARK: - Singleton Architecture
    static let shared = HardwareOrchestrator()

    // MARK: - State
    var targetFPS: Int = 60
    var isGlassmorphismEnabled: Bool = true
    var isCriticalHeatWarningActive: Bool = false

    /// Expedition mode is a persisted preference, but its Pro-only behavior is
    /// enabled only while functional entitlement is currently proven. Paid
    /// access may remain proven offline; complimentary access may not.
    var isExpeditionModeActive: Bool {
        appSettings.isExpeditionModeActive && functionalProAccessProvider()
    }

    var isIdleLocked: Bool = false {
        didSet {
            if !isIdleLocked {
                evaluateConstraints()
            }
        }
    }

    // MARK: - Private
    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let functionalProAccessProvider: @MainActor () -> Bool
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    init(
        appSettings: AppSettings? = nil,
        observeSystemChanges: Bool = true,
        functionalProAccessProvider: @escaping @MainActor () -> Bool = {
            RevenueCatManager.shared.isProActive
        }
    ) {
        self.appSettings = appSettings ?? AppSettings.shared
        self.functionalProAccessProvider = functionalProAccessProvider
        if observeSystemChanges {
            setupMonitors()
        }
        evaluateConstraints()
    }

    private func setupMonitors() {
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateConstraints() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateConstraints() }
            .store(in: &cancellables)
    }

    // MARK: - Thermal Evaluation

    /// Evaluates current thermal and power conditions and updates FPS/quality targets.
    /// Parameters accept injected values for testing; nil reads live system state.
    func evaluateConstraints(thermalState: ProcessInfo.ThermalState? = nil) {
        let processInfo = ProcessInfo.processInfo

        // Do not overwrite FPS while idling at 1fps.
        guard !isIdleLocked else { return }

        isCriticalHeatWarningActive = false

        if isExpeditionModeActive {
            targetFPS = 24
            isGlassmorphismEnabled = false
            return
        }

        let currentState = thermalState ?? processInfo.thermalState
        switch currentState {
        case .nominal:
            targetFPS = 60
            isGlassmorphismEnabled = true
        case .fair:
            targetFPS = 45
            isGlassmorphismEnabled = true
        case .serious:
            targetFPS = 30
            isGlassmorphismEnabled = false
        case .critical:
            targetFPS = 15
            isGlassmorphismEnabled = false
            isCriticalHeatWarningActive = true
            AppTelemetry.trackThermalThrottling(fpsLimit: 15)
        @unknown default:
            targetFPS = 30
            isGlassmorphismEnabled = false
        }
    }

    // MARK: - Animation Gate

    /// True when the device can sustain entrance animations.
    /// False under expedition mode (battery conservation) or serious/critical thermal pressure.
    /// Mirrors `isGlassmorphismEnabled` — both flags are set together in `evaluateConstraints`.
    var isAnimationEnabled: Bool { isGlassmorphismEnabled }

    // MARK: - App Lifecycle

    func onAppWillResignActive() {
        CameraManager.shared.stopSession()
    }

    func onAppDidBecomeActive() {
        CameraManager.shared.startSession()
    }
}
