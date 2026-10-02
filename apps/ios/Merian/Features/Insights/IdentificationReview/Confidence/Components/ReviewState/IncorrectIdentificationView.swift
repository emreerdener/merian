import SwiftUI

/// Review state for an AI identification marked incorrect.
struct IncorrectIdentificationView: View {
    var onUndo: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Marked as incorrect")
                    .font(.system(.headline))
                    .foregroundColor(.red)
                Spacer()
                if let onUndo {
                    Button("Undo", action: onUndo)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("IncorrectIdentificationUndoButton")
                }
            }

            Text("You marked the AI’s identification as incorrect. Your scan and its original details are preserved.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5)
        )
    }
}
