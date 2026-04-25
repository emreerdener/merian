import SwiftUI

struct MerianSystemFeedbackModifier: SwiftUI.ViewModifier {
    @Binding var toastMessage: String?
    @Binding var showCelebration: Bool
    var commonNameForCelebration: String
    var toastAlignment: SwiftUI.Alignment

    func body(content: Content) -> some SwiftUI.View {
        ZStack(alignment: .top) {
            content

            if let message = toastMessage {
                VStack {
                    if toastAlignment == .bottom { Spacer() }
                    
                    ToastBanner(onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toastMessage = nil
                        }
                    }) {
                        Text(message)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    .padding(toastAlignment == .top ? Edge.Set.top : Edge.Set.bottom, toastAlignment == .top ? 16 : 60)
                    
                    if toastAlignment == .top { Spacer() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.move(edge: toastAlignment == .top ? Edge.top : Edge.bottom).combined(with: .opacity))
                .zIndex(100)
            }

            CelebrationBanner(
                commonName: commonNameForCelebration,
                showCelebration: $showCelebration
            )
        }
    }
}

extension View {
    func merianSystemFeedback(
        toastMessage: Binding<String?>,
        showCelebration: Binding<Bool> = .constant(false),
        commonNameForCelebration: String = "",
        toastAlignment: Alignment = .bottom
    ) -> some View {
        self.modifier(MerianSystemFeedbackModifier(
            toastMessage: toastMessage,
            showCelebration: showCelebration,
            commonNameForCelebration: commonNameForCelebration,
            toastAlignment: toastAlignment
        ))
    }
}
