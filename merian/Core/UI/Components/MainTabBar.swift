import SwiftUI

struct MainTabBar: View {
    @Binding var isScansOpen: Bool
    @Binding var isUserProfileOpen: Bool
    @Binding var isSettingsOpen: Bool
    
    var body: some View {
        HStack(spacing: 32) {
            TabBarButton(
                iconName: "globe",
                title: "Explore",
                action: {},
                isDisabled: true
            )

            TabBarButton(
                iconName: "rectangle.stack",
                title: "Scans",
                action: { isScansOpen = true }
            )

             TabBarButton(
                iconName: "person",
                title: "Profile",
                action: { isUserProfileOpen = true }
            )

            TabBarButton(
                iconName: "gearshape",
                title: "Settings",
                action: { isSettingsOpen = true }
            ) 
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 32)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
}

fileprivate struct TabBarButton: View {
    let iconName: String
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.primary)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }
}
