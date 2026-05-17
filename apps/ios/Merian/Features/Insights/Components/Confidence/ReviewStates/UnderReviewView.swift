import SwiftUI

/// Form state showing that the identification was explicitly flagged as completely incorrect by the user.
struct UnderReviewView: View {
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
                Text("Flagged for review")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
                Spacer()
                Button("Undo", action: onUndo)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
            }

            Text("This identification has been flagged because it was incorrect. It will be verified by a moderator soon.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
    }
}
