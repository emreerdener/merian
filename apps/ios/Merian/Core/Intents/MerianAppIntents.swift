import AppIntents
import Foundation
import os

// MARK: - Core OS Integration

// MARK: - Intent Routing Abstraction
// These Intents proxy into the running SwiftUI hierarchy via the AppEventPublisher
// ensuring the OS immediately jumps into the requested states without UI locks.

// MARK: - Primary Discovery Intent
struct IdentifyNatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Identify Nature"
    static var description: IntentDescription = IntentDescription("Immediately triggers the Merian Instant-On Viewfinder and focuses the lens.")
    
    // Explicitly pops the user strictly into the App UI out of the background.
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        AppEventPublisher.shared.send(.requestIdentifyNatureIntent)
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
        AppEventPublisher.shared.send(.requestRecallLastFindIntent)
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
