import SwiftUI

struct FieldNotesCard: View {
    let previewText: String
    let promptContext: FieldNotesPromptContext
    var isPublished = false
    var onDismiss: (() -> Void)?
    let action: () -> Void

    private var trimmedPreview: String {
        previewText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasNotes: Bool {
        !trimmedPreview.isEmpty
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.secondary)
                    Text("Field notes")
                        .font(.system(.headline))
                        .foregroundColor(.primary)

                    if isPublished {
                        publishedBadge
                    }
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
                } else {
                    zeroStateIntro
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

            if !hasNotes, let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .accessibilityLabel("Hide field notes card")
            }
        }
        .card()
    }

    private var zeroStateIntro: some View {
        VStack(alignment: .center, spacing: 14) {
            Image("insights_journal")
                .resizable()
                .scaledToFit()
                .frame(width: 200)
                .accessibilityHidden(true)

            VStack(alignment: .center, spacing: 6) {
                Text("Add your field notes")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text("Save details, questions, and observations you want to remember with this scan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var publishedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("Published")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .accessibilityLabel("Published field notes")
    }
}
