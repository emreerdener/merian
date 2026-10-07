import SwiftUI

/// Form state showing that the user has explicitly confirmed the AI's primary identification.
struct ConfirmedView: View {
    var onReset: (() -> Void)?
    var unavailableReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Match confirmed")
                    .font(.system(.headline))
                    .foregroundColor(.green)
                Spacer()
                if let onReset {
                    Button("Undo", action: onReset)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ConfidenceUndoConfirmation")
                }
            }

            Text("You verified that the AI identified this subject correctly.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let unavailableReason {
                Text(unavailableReason).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.green.opacity(0.2), lineWidth: 0.5)
        )
    }
}
