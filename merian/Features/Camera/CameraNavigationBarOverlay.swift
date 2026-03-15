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
                                Text("Scans")
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            isUserProfileOpen = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "person")
                                Text("Profile")
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                    }
                    .padding(.horizontal, 16)
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
