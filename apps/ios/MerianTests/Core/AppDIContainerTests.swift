@testable import Merian
import Testing

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

        #expect(previewA.appEventPublisher !== previewB.appEventPublisher)
        #expect(previewA.appRouteCoordinator !== previewB.appRouteCoordinator)
        #expect(previewA.milestoneToastPresenter !== previewB.milestoneToastPresenter)
        #expect(previewA.milestoneToastHostRegistry !== previewB.milestoneToastHostRegistry)
        #expect(previewA.appRouteCoordinator !== AppDIContainer.shared.appRouteCoordinator)
        #expect(previewA.milestoneToastPresenter !== AppDIContainer.shared.milestoneToastPresenter)
        
        // Assert it constructs valid structural bindings
        #expect(previewA.hardwareOrchestrator === HardwareOrchestrator.shared)
    }

    @Test func testExploreLaunchPresentationRequiresOnboardingAndOptIn() {
        #expect(!AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: false,
            opensExploreOnLaunch: true
        ))
        #expect(!AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: true,
            opensExploreOnLaunch: false
        ))
        #expect(AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: true,
            opensExploreOnLaunch: true
        ))
    }

    @Test func testRootPresentationWaitsForRequiredConsentRestoration() {
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: false,
            hasCurrentRequiredConsent: false,
            isRestoringRequiredConsent: true
        ) == .onboarding)
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: true,
            hasCurrentRequiredConsent: false,
            isRestoringRequiredConsent: true
        ) == .restoringConsent)
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: true,
            hasCurrentRequiredConsent: true,
            isRestoringRequiredConsent: true
        ) == .workspace)
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: true,
            hasCurrentRequiredConsent: false,
            isRestoringRequiredConsent: false
        ) == .onboarding)
    }

}
