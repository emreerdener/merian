import XCTest
import SwiftUI
@testable import Merian

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    
    var viewModel: OnboardingViewModel!
    
    override func setUp() {
        super.setUp()
        // Reset the explicit AppStorage binding manually on the physical host
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        viewModel = OnboardingViewModel()
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        viewModel = nil
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
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"), "The physical standard defaults mapping must confirm persistence for WindowGroup reconfiguration on next launch.")
    }
}
