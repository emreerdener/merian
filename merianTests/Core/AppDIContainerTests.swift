import Testing
import Foundation
import SwiftUI
@testable import Merian

@MainActor
struct AppDIContainerTests {
    
    @Test func testSharedInstanceUnification() {
        let sharedContainerA = AppDIContainer.shared
        let sharedContainerB = AppDIContainer.shared
        
        // Because these contain critical heavy references (InferenceEngine, HardwareOrchestrator)
        // fetching shared across the app must mathematically return the exact same memory pointer structure.
        let isIdentical = sharedContainerA === sharedContainerB
        #expect(isIdentical == true, "AppDIContainer broke singleton rules. Multiple instantiations found.")
    }
    
    @Test func testMockPreviewInitialization() {
        let previewA = AppDIContainer.preview
        let previewB = AppDIContainer.preview
        
        // Mock init creates independent containers manually each time to prevent preview artifacts from permanently locking memory
        let isIdentical = previewA === previewB
        #expect(isIdentical == false, "AppDIContainer.preview shouldn't leak singletons to parallel SwiftUI macro previews")
        
        // Assert it constructs valid structural bindings
        #expect(previewA.hardwareOrchestrator === HardwareOrchestrator.shared)
    }

    @Test func testAppSettingsOwnsTransientUIFlags() {
        let suiteName = "merian.tests.app-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.hasUnseenScan == false)
        #expect(settings.hasPromptedForNotificationsPostIdent == false)
        #expect(settings.hasSeenExploreOnboarding == false)
        #expect(settings.hasSeenExploreNewChip == false)
        #expect(settings.hasUnseenExplorePost == false)
        #expect(settings.lastSeenExplorePostSharedAt.isEmpty)
        #expect(settings.suppressInferenceBanners == false)

        settings.hasUnseenScan = true
        settings.hasPromptedForNotificationsPostIdent = true
        settings.hasSeenExploreOnboarding = true
        settings.hasSeenExploreNewChip = true
        settings.hasUnseenExplorePost = true
        settings.lastSeenExplorePostSharedAt = "2026-05-09T12:34:56Z"
        settings.suppressInferenceBanners = true

        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenScan))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasSeenExploreNewChip))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost))
        #expect(defaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) == "2026-05-09T12:34:56Z")
        #expect(defaults.bool(forKey: UserDefaultsKeys.suppressInferenceBanners))

        defaults.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
        defaults.set(false, forKey: UserDefaultsKeys.suppressInferenceBanners)
        settings.refreshFromDefaults()

        #expect(settings.hasUnseenScan == false)
        #expect(settings.suppressInferenceBanners == false)
    }
}
