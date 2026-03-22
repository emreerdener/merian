import Foundation
import UIKit
import SwiftUI

// MARK: - Core Sensory Feedback Engine
@MainActor
final class HapticManager {
    // MARK: - Singleton Architecture
    static let shared = HapticManager()
    
    // MARK: - Hardware Generators
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let error = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    // MARK: - Lifecycle Bootstrapping
    private init() {
        Task { @MainActor in
            // Intentionally delay Taptic Engine instantiation to prevent boot stutters natively
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.heavy.prepare()
            self.light.prepare()
            self.rigid.prepare()
            self.medium.prepare()
            self.error.prepare()
        }
    }

    // MARK: - Public Triggers
    func triggerFocusSnap() {
        if UserDefaults.standard.bool(forKey: "isHapticsEnabled") { heavy.impactOccurred() }
    }
    
    func triggerSheetSpring() {
        if UserDefaults.standard.bool(forKey: "isHapticsEnabled") { light.impactOccurred() }
    }
    
    func triggerMediumPulse() {
        if UserDefaults.standard.bool(forKey: "isHapticsEnabled") { medium.impactOccurred() }
    }
    
    func triggerErrorThump() {
        if UserDefaults.standard.bool(forKey: "isHapticsEnabled") {
            rigid.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.error.notificationOccurred(.error) }
        }
    }
    
    func triggerSelectionPulse() {
        if UserDefaults.standard.bool(forKey: "isHapticsEnabled") { selection.selectionChanged() }
    }
    
    func triggerSuccessPulse() {
        if UserDefaults.standard.bool(forKey: "isHapticsEnabled") {
            let success = UINotificationFeedbackGenerator()
            success.notificationOccurred(.success)
        }
    }
}
