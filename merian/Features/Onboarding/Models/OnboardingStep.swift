import Foundation

// MARK: - Onboarding Navigation Bounds
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case camera
    case location
    case photoLibrary
    case notifications
    case ready
}
