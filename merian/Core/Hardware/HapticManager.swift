import SwiftUI
import UIKit

@MainActor
final class HapticManager {
    static let shared = HapticManager()
    
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let error = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    init() {
        heavy.prepare()
        light.prepare()
        rigid.prepare()
        medium.prepare()
        error.prepare()
    }

    func triggerFocusSnap() { if UserDefaults.standard.bool(forKey: "isHapticsEnabled") { heavy.impactOccurred() } }
    func triggerSheetSpring() { if UserDefaults.standard.bool(forKey: "isHapticsEnabled") { light.impactOccurred() } }
    func triggerMediumPulse() { if UserDefaults.standard.bool(forKey: "isHapticsEnabled") { medium.impactOccurred() } }
    func triggerErrorThump() {
        if UserDefaults.standard.bool(forKey: "isHapticsEnabled") {
            rigid.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.error.notificationOccurred(.error) }
        }
    }
    func triggerSelectionPulse() { if UserDefaults.standard.bool(forKey: "isHapticsEnabled") { selection.selectionChanged() } }
    func triggerSuccessPulse() {
        if UserDefaults.standard.bool(forKey: "isHapticsEnabled") {
            let success = UINotificationFeedbackGenerator()
            success.notificationOccurred(.success)
        }
    }
}
