import Foundation
import AppIntents

// Mocking the Navigation and Haptic architecture to represent standard Merian implementations
struct AppState {
    static let shared = AppState()
    func navigateTo(_ destination: String) { print("Navigated seamlessly to \(destination)") }
    func navigateToLastScan() { print("Pushed Last Scan Modal natively.") }
}

extension HapticManager {
    func triggerFocusSnap() {
        print("Haptic Focus Snap Fired.")
    }
    func triggerSheetSpring() {
        print("Haptic Sheet Spring Fired.")
    }
}

// Intent 1: Identify Nature
struct IdentifyNatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Identify Nature"
    static var description: IntentDescription = IntentDescription("Immediately triggers the Merian Instant-On Viewfinder and focuses the lens.")
    
    // Explicitly pops the user strictly into the App UI out of the background.
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.navigateTo("camera")
        HapticManager.shared.triggerFocusSnap()
        return .result()
    }
}

// Intent 2: Recall Last Find
struct RecallLastFindIntent: AppIntent {
    static var title: LocalizedStringResource = "Look Up My Last Find"
    static var description: IntentDescription = IntentDescription("Quickly pulls up the taxonomy insight sheet for the most recent observation.")
    
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.navigateToLastScan()
        HapticManager.shared.triggerSheetSpring()
        return .result()
    }
}

// Ecosystem App Shortcuts Provider 
struct MerianShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: IdentifyNatureIntent(),
            phrases: [
                "Identify this with \(.applicationName)",
                "Open \(.applicationName) camera",
                "Scan biology with \(.applicationName)"
            ],
            shortTitle: "Identify Nature",
            systemImageName: "leaf.fill"
        )
        
        AppShortcut(
            intent: RecallLastFindIntent(),
            phrases: [
                "What was the last thing I scanned in \(.applicationName)?",
                "Show my newest \(.applicationName) scan"
            ],
            shortTitle: "Recall Last Find",
            systemImageName: "clock.arrow.circlepath"
        )
    }
    
    static var shortcutTileColor: ShortcutTileColor {
        return .teal
    }
}
