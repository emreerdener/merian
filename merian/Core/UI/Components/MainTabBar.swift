import SwiftUI

struct MainTabBar: View {
    @Binding var isScansOpen: Bool
    @Binding var isUserProfileOpen: Bool
    @State private var showComingSoon = false
    @State private var tooltipTask: Task<Void, Never>?
    
    var body: some View {
        HStack(spacing: 48) {
            TabBarButton(
                iconName: "safari",
                title: "Explore",
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                        Text("Coming soon!")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.green)
                                    .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
                            )
                            .offset(y: -45)
                            .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                            .zIndex(100)
                    }
                }
                .allowsHitTesting(false)
            )

            TabBarButton(
                iconName: "rectangle.stack",
                title: "Scans",
                action: { 
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isScansOpen = true 
                }
            )

             TabBarButton(
                iconName: "person",
                title: "Profile",
                action: { 
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isUserProfileOpen = true 
                }
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
