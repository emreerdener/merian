import SwiftUI

struct CameraNavigationBarOverlay: ViewModifier {
    @Binding var isLifeListOpen: Bool
    @Binding var isUserProfileOpen: Bool
    let isAnalyzingFullscreen: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if !isAnalyzingFullscreen {
                    HStack {
                        Button(action: {
                            isLifeListOpen = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "book")
                                    .font(.system(size: 24, weight: .light))
                                Text("Scans")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .environment(\.colorScheme, .dark)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            isUserProfileOpen = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "person")
                                    .font(.system(size: 24, weight: .light))
                                Text("Profile")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .environment(\.colorScheme, .dark)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)
                    .background(Color.clear)
                }
            }
    }
}

extension View {
    func cameraNavigationToolbar(isLifeListOpen: Binding<Bool>, isUserProfileOpen: Binding<Bool>, isAnalyzingFullscreen: Bool) -> some View {
        self.modifier(CameraNavigationBarOverlay(isLifeListOpen: isLifeListOpen, isUserProfileOpen: isUserProfileOpen, isAnalyzingFullscreen: isAnalyzingFullscreen))
    }
}
