import SwiftUI

/// Form state showing that the user has manually overridden the AI's identification with their own.
struct OverriddenView: View {
    let overrideName: String
    let aiScientificName: String
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.checkmark")
                    .foregroundColor(.indigo)
                Text("Manual override")
                    .font(.system(.headline))
                    .foregroundColor(.indigo)
                Spacer()
                Button("Undo", action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.indigo)
                    .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(overrideName)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Text("Replaced")
                        .foregroundColor(.secondary)
                    Text(aiScientificName)
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(20)
        .background(Color.indigo.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.2), lineWidth: 0.5)
        )
    }
}
