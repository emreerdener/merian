import XCTest
import SwiftUI
@testable import Merian

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    
    var viewModel: OnboardingViewModel!
    var appSettings: AppSettings!
    var userDefaults: UserDefaults!
    var suiteName: String!
    
    override func setUp() {
        super.setUp()
        suiteName = "merian.tests.onboarding.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        appSettings = AppSettings(userDefaults: userDefaults, observeExternalChanges: false)
        appSettings.hasCompletedOnboarding = false
        viewModel = OnboardingViewModel(appSettings: appSettings)
    }
    
    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        viewModel = nil
        appSettings = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }
    
    func testInitialStateIsWelcome() {
        XCTAssertEqual(viewModel.currentStep, .welcome, "ViewModel should strictly start at the .welcome step on cold boot.")
        XCTAssertFalse(viewModel.hasCompletedOnboarding, "AppStorage bypass flag should explicitly be false initially.")
    }
    
    func testAdvanceStepProgression() {
        // Initial boundary is welcome
        XCTAssertEqual(viewModel.currentStep, .welcome)
        
        // Sequence: welcome -> camera
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .camera)
        
        // Sequence: camera -> location
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .location)
        
        // Sequence: location -> ready
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .ready)
        
        // Attempting to advance past .ready should securely trap without crashing Swift's Int boundary indices natively.
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .ready, "ViewModel should actively trap progression at .ready boundary without out-of-bounds scalar execution crashes.")
    }
    
    func testCompleteOnboarding() {
        // Assume user advanced sequentially to completion
        viewModel.currentStep = .ready
        
        // Fire completion
        viewModel.completeOnboarding()
        
        // Verify AppStorage binding actually triggers the physical override
        XCTAssertTrue(viewModel.hasCompletedOnboarding, "The completeOnboarding physical action MUST explicitly flip the global teardown flag in SwiftUI memory.")
        XCTAssertTrue(userDefaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding), "The injected defaults mapping must confirm persistence for WindowGroup reconfiguration on next launch.")
    }
}
