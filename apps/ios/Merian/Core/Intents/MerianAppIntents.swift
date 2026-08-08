import AppIntents
import Foundation
import os

// MARK: - Core OS Integration

// MARK: - Intent Routing Abstraction
// These intents submit delivery-critical requests to AppRouteCoordinator. The
// Capture host applies them only after its active presentation slot is available.

// MARK: - Primary Discovery Intent
struct IdentifyNatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Identify Nature"
    static var description: IntentDescription = IntentDescription("Immediately triggers the Naturebook Instant-On Viewfinder and focuses the lens.")
    
    // Explicitly pops the user strictly into the App UI out of the background.
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        AppDIContainer.shared.appRouteCoordinator.request(.identifyNature, source: .appIntent)
        HapticManager.shared.triggerFocusSnap()
        return .result()
    }
}

// MARK: - Historical Retrieval Intent
struct RecallLastFindIntent: AppIntent {
    static var title: LocalizedStringResource = "Look Up My Last Find"
    static var description: IntentDescription = IntentDescription("Quickly pulls up the taxonomy insight sheet for the most recent observation.")
    
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        AppDIContainer.shared.appRouteCoordinator.request(.recallLastFind, source: .appIntent)
        HapticManager.shared.triggerSheetSpring()
        return .result()
    }
}

// MARK: - OS Ecosystem Shortcuts
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
