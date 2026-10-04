import SwiftUI

/// Next steps for an incorrect identification; actions remain owned by the host.
struct IncorrectIdentificationGuidanceCard: View {
    var onReanalyze: (() -> Void)?
    var onAskCommunity: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 8) {
                Text("Find a better match")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("Try reanalyzing this scan or ask the community to help identify it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                if let onReanalyze {
                    action("Reanalyze species", icon: "arrow.2.circlepath", color: .orange, perform: onReanalyze)
                        .accessibilityIdentifier("IncorrectGuidanceReanalyzeButton")
                }
                if let onAskCommunity {
                    action("Ask the community", icon: "person.2", color: .blue, perform: onAskCommunity)
                        .accessibilityIdentifier("IncorrectGuidanceCommunityButton")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        )
        .accessibilityIdentifier("IncorrectIdentificationGuidanceCard")
    }

    private func action(_ title: String, icon: String, color: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(color.opacity(0.14))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Light") {
    IncorrectIdentificationGuidanceCard(onReanalyze: {}, onAskCommunity: {})
        .padding()
}
#Preview("Dark, large text") {
    IncorrectIdentificationGuidanceCard(onReanalyze: {}, onAskCommunity: {})
        .padding()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
