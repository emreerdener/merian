import Foundation
import UIKit
import Combine

// MARK: - Core UIDevice Architecture
extension UIDevice {
    /// Determines whether the device is considered a "modern iPhone" (iPhone 14 series or newer).
    /// Used globally to default heavy AI features to off on modern bounds due to rapid thermal heat warnings natively.
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
        
        // "iPhone14,x" mapping maps to iPhone 13.
        // "iPhone15,x" mapping maps to iPhone 14 / iPhone 14 Plus / iPhone 14 Pro, etc.
        // Thus, we classify >= 15 as a "modern iPhone" which experiences severe thermal load quickly.
        if identifier.hasPrefix("iPhone") {
            let numberPart = identifier.dropFirst(6).split(separator: ",").first ?? "0"
            if let majorVersion = Int(numberPart), majorVersion >= 15 {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Core Hardware Engine
/// HardwareOrchestrator acts as the thermal management and concurrency bridge for hardware elements.
@MainActor
final class HardwareOrchestrator: ObservableObject {
    // MARK: - Singleton Architecture
    static let shared = HardwareOrchestrator()
    
    // MARK: - State Management
    @Published var targetFPS: Int = 60
    @Published var isGlassmorphismEnabled: Bool = true
    @Published var isCriticalHeatWarningActive: Bool = false
    @Published var isExpeditionModeActive: Bool = false
    
    var isIdleLocked: Bool = false {
        didSet {
            // Re-evaluate limits immediately when unlock occurs
            if !isIdleLocked {
                evaluateConstraints()
            }
        }
    }
    
    // MARK: - Publisher Bounds
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupMonitors()
        evaluateConstraints()
    }
    
    private func setupMonitors() {
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateConstraints()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateConstraints()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Thermal Algorithms
    // Default parameters accept nil to map dynamically to native boundaries, or accept explicitly injected test values
    func evaluateConstraints(isLowPowerModeEnabled: Bool? = nil, thermalState: ProcessInfo.ThermalState? = nil) {
        let processInfo = ProcessInfo.processInfo
        
        // Respect explicit user Settings bounds OR automatically engage if iOS Low Power Mode is tripped natively
        let isUserForcedExpedition = UserDefaults.standard.bool(forKey: "isExpeditionModeActive")
        isExpeditionModeActive = isUserForcedExpedition || (isLowPowerModeEnabled ?? processInfo.isLowPowerModeEnabled)
        // Note: ExpeditionModeActive disabling cellular uploads is handled by network/queue logic elsewhere reading this flag.
        
        // If locked in 1fps idle state, we must NOT overwrite settings
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
    
    // MARK: - OS Foreground Orchestration
    func onAppWillResignActive() {
        CameraManager.shared.stopSession()
    }
    
    func onAppDidBecomeActive() {
        CameraManager.shared.startSession()
    }
}
