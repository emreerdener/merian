import SwiftUI
import UIKit

final class HapticManager {
    static let shared = HapticManager()
    
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let error = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    init() {
        heavy.prepare()
        light.prepare()
        rigid.prepare()
        error.prepare()
    }

    func triggerFocusSnap() { heavy.impactOccurred() }
    func triggerSheetSpring() { light.impactOccurred() }
    func triggerErrorThump() {
        rigid.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.error.notificationOccurred(.error) }
    }
    func triggerSelectionPulse() { selection.selectionChanged() }
    func triggerSuccessPulse() {
        let success = UINotificationFeedbackGenerator()
        success.notificationOccurred(.success)
    }
}
