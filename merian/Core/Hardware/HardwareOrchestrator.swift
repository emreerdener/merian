import Foundation
import Combine

/// HardwareOrchestrator acts as the thermal management and concurrency bridge for hardware elements.
@MainActor
final class HardwareOrchestrator: ObservableObject {
    static let shared = HardwareOrchestrator()
    
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
    
    func evaluateConstraints() {
        let processInfo = ProcessInfo.processInfo
        
        isExpeditionModeActive = processInfo.isLowPowerModeEnabled
        // Note: ExpeditionModeActive disabling cellular uploads is handled by network/queue logic elsewhere reading this flag.
        
        // If locked in 1fps idle state, we must NOT overwrite settings
        guard !isIdleLocked else { return }
        
        isCriticalHeatWarningActive = false
        
        if isExpeditionModeActive {
            targetFPS = 24
            isGlassmorphismEnabled = false
            return
        }
        
        switch processInfo.thermalState {
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
    
    func onAppWillResignActive() {
        CameraManager.shared.stopSession()
    }
    
    func onAppDidBecomeActive() {
        CameraManager.shared.startSession()
    }
}
