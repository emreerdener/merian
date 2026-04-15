import SwiftUI

struct MainTabBar: View {
    // MARK: - Navigation Dependencies
    @Binding var isScansOpen: Bool
    @Binding var isUserProfileOpen: Bool
    
    // MARK: - Component State
    @State private var showComingSoon = false
    @State private var tooltipTask: Task<Void, Never>?
    @AppStorage(UserDefaultsKeys.hasUnseenScan) private var hasUnseenScan: Bool = false
    
    // MARK: - Visual Layout
    var body: some View {
        HStack(spacing: 48) {
            
            // 1. Map/Explore Network
            TabBarButton(
                iconName: "safari",
                title: "Explore",
                action: {
                    HapticManager.shared.triggerSheetSpring()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        showComingSoon = true
                    }
                    
                    tooltipTask?.cancel()
                    tooltipTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if !Task.isCancelled {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showComingSoon = false
                            }
                        }
                    }
                }
            )
            .overlay(
                Group {
                    if showComingSoon {
                        Text("Coming soon")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                                    .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
                            )
                            .offset(y: -45)
                            .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                            .zIndex(100)
                    }
                }
                .allowsHitTesting(false)
            )

            // 2. Local Taxonomy Library
            TabBarButton(
                iconName: "rectangle.stack",
                title: "Scans",
                action: {
                    HapticManager.shared.triggerSheetSpring()
                    isScansOpen = true
                },
                showBadge: hasUnseenScan
            )

            // 3. User Identity Profile 
            TabBarButton(
                iconName: "person",
                title: "Profile",
                action: { 
                    HapticManager.shared.triggerSheetSpring()
                    isUserProfileOpen = true 
                }
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 32)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.16), radius: 15, x: 0, y: 8)
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

// MARK: - Internal Component Layout Wrappers

private struct TabBarButton: View {
    // MARK: - Properties
    let iconName: String
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    var showBadge: Bool = false

    // MARK: - Visual Layout
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if showBadge {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -2)
                        }
                    }
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
