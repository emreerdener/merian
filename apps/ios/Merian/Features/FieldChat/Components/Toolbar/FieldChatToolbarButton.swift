import SwiftUI

struct FieldChatToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text("Field chat")
            }
            .padding(.horizontal, 8)
            .fixedSize()
        }
        .rainbowCapsuleAccent(width: 140, height: 42)
        .accessibilityLabel("Open Field chat")
        .accessibilityIdentifier("FieldChatToolbarButton")
    }
}
