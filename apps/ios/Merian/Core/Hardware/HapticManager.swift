import Foundation
import SwiftUI
import UIKit

// MARK: - Core Sensory Feedback Engine
@MainActor
@Observable
final class HapticManager {
    // MARK: - Singleton Architecture
    static let shared = HapticManager()

    // MARK: - Hardware Generators
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let error = UINotificationFeedbackGenerator()
    private let success = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let hardwareOrchestrator: HardwareOrchestrator

    // MARK: - Lifecycle
    init(appSettings: AppSettings? = nil, hardwareOrchestrator: HardwareOrchestrator? = nil) {
        self.appSettings = appSettings ?? AppSettings.shared
        self.hardwareOrchestrator = hardwareOrchestrator ?? HardwareOrchestrator.shared

        Task { @MainActor in
            // Delay preparation to avoid boot stutters.
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.heavy.prepare()
            self.light.prepare()
            self.rigid.prepare()
            self.medium.prepare()
            self.error.prepare()
            self.success.prepare()
        }
    }

    // MARK: - Public Triggers

    func triggerFocusSnap() {
        guard shouldFire else { return }
        heavy.impactOccurred()
        heavy.prepare()
    }

    func triggerSheetSpring() {
        guard shouldFire else { return }
        light.impactOccurred()
    }

    func triggerMediumPulse() {
        guard shouldFire else { return }
        medium.impactOccurred()
        medium.prepare()
    }

    func triggerErrorThump() {
        guard shouldFire else { return }
        rigid.impactOccurred()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.error.notificationOccurred(.error)
        }
    }

    func triggerSelectionPulse() {
        guard shouldFire else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    func triggerSuccessPulse() {
        guard shouldFire else { return }
        success.notificationOccurred(.success)
        success.prepare()
    }

    func triggerLightImpact(intensity: CGFloat? = nil) {
        guard shouldFire else { return }
        if let intensity { light.impactOccurred(intensity: intensity) } else { light.impactOccurred() }
        light.prepare()
    }

    func triggerHeavyImpact(intensity: CGFloat? = nil) {
        guard shouldFire else { return }
        if let intensity { heavy.impactOccurred(intensity: intensity) } else { heavy.impactOccurred() }
        heavy.prepare()
    }

    func prepareHeavyImpact() {
        guard shouldFire else { return }
        heavy.prepare()
    }

    // MARK: - Private

    /// Haptics are suppressed when the user has disabled them or when expedition mode is
    /// active — expedition mode prioritises battery over feedback without permanently
    /// modifying the user's haptics preference.
    private var shouldFire: Bool {
        appSettings.isHapticsEnabled &&
        !hardwareOrchestrator.isExpeditionModeActive
    }
}
