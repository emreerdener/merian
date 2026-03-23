import SwiftUI

struct PushNotificationPermissionStepView: View {
    // MARK: - Callbacks
    let onNext: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            iconColor: Color.teal.opacity(0.1),
            iconText: "Bell Animation",
            iconCornerRadius: 60,
            title: "Stay instantly\nupdated",
            subtitle: "Enable notifications so you receive an alert the exact moment the AI finishes identifying a new species. You can toggle this off later.",
            primaryButtonTitle: "Enable notifications",
            primaryButtonTextColor: Color.white,
            primaryButtonColor: Color.teal,
            primaryAction: {
                // Request OS Permission manually natively
                AppDIContainer.shared.pushNotificationManager.requestAuthorization {
                    DispatchQueue.main.async {
                        // We advance automatically immediately upon boundary completion cleanly
                        onNext()
                    }
                }
            },
            secondaryButtonTitle: "Not right now",
            secondaryAction: {
                UserDefaults.standard.set(false, forKey: "isPushNotificationsEnabled")
                onNext()
            }
        )
    }
}
