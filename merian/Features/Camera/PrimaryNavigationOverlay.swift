import SwiftUI

struct PrimaryNavigationOverlay: ViewModifier {
    @Binding var isLifeListOpen: Bool
    @Binding var isUserProfileOpen: Bool
    let isAnalyzingFullscreen: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !isAnalyzingFullscreen {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            isLifeListOpen = true
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "book")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Scans")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .frame(width: 50, height: 50)
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            isUserProfileOpen = true
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "person")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Profile")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .frame(width: 50, height: 50)
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func primaryNavigationToolbar(isLifeListOpen: Binding<Bool>, isUserProfileOpen: Binding<Bool>, isAnalyzingFullscreen: Bool) -> some View {
        self.modifier(PrimaryNavigationOverlay(isLifeListOpen: isLifeListOpen, isUserProfileOpen: isUserProfileOpen, isAnalyzingFullscreen: isAnalyzingFullscreen))
    }
}
