import SwiftUI

/// Form state showing that the user has swiped through all available alternative candidates and rejected them all.
/// Acts as a summary state when they dismiss the `CandidateSwipeModal` without making a selection.
struct AllCandidatesReviewedView: View {
    let candidatesCount: Int
    let onReviewAgain: () -> Void
    let onReset: () -> Void
    var onAskCommunity: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.minus")
                    .foregroundColor(.secondary)
                Text("Alternatives reviewed")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
                Spacer()
                Button("Reset", action: onReset)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
            }

            Text("You reviewed all \(candidatesCount) alternative\(candidatesCount == 1 ? "" : "s") and none matched.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                HapticManager.shared.triggerLightImpact()
                onReviewAgain()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.circlepath")
                    Text("Review again")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if let onAskCommunity {
                Button {
                    HapticManager.shared.triggerMediumPulse()
                    onAskCommunity()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2")
                        Text("Ask the community")
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}
