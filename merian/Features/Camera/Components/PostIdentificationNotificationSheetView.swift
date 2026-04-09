import SwiftUI

struct PostIdentificationNotificationSheetView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 48))
                .foregroundColor(.teal)
                .padding(.top, 32)
            
            VStack(spacing: 8) {
                Text("Turn on notifications?")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enable notifications so you receive an alert the exact moment the AI finishes identifying a species.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                Button {
                    AppDIContainer.shared.pushNotificationManager.requestAuthorization {
                        onDismiss()
                    }
                } label: {
                    Text("Enable notifications")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.teal)
                        .clipShape(Capsule())
                }
                
                Button {
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isPushNotificationsEnabled)
                    onDismiss()
                } label: {
                    Text("Not right now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}
