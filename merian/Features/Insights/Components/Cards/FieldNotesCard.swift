import SwiftUI

struct FieldNotesCard: View {
    let previewText: String
    let promptContext: FieldNotesPromptContext
    let action: () -> Void

    private var trimmedPreview: String {
        previewText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasNotes: Bool {
        !trimmedPreview.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(.secondary)
                Text("Field notes")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
            }
            if hasNotes {
                Text(trimmedPreview)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .textSelection(.disabled)
                    .onTapGesture(perform: action)
                    .onLongPressGesture(perform: action)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens field notes for editing.")
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: hasNotes ? "pencil" : "plus.circle.fill")
                    Text(hasNotes ? "Continue notes" : "Add notes")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(
                Capsule()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
        }
        .card()
    }
}
