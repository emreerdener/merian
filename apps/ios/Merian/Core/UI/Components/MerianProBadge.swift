import SwiftUI

struct MerianProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .black))
            .tracking(0.5)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary)
            }
            .accessibilityLabel("Pro")
    }
}
