import SwiftUI

struct FieldNotesVisibilityBadge: View {
    enum Visibility {
        case published
        case privateNotes

        var title: String {
            switch self {
            case .published:
                return "Published"
            case .privateNotes:
                return "Private"
            }
        }

        var systemImage: String {
            switch self {
            case .published:
                return "eye.fill"
            case .privateNotes:
                return "eye.slash.fill"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .published:
                return "Published field notes"
            case .privateNotes:
                return "Private field notes"
            }
        }
    }

    let visibility: Visibility

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: visibility.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(visibility.title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .accessibilityLabel(visibility.accessibilityLabel)
    }
}

struct FieldNotesCard: View {
    let previewText: String
    let promptContext: FieldNotesPromptContext
    var visibility: FieldNotesVisibilityBadge.Visibility?
    var onDismiss: (() -> Void)?
    let action: () -> Void

    init(
        previewText: String,
        promptContext: FieldNotesPromptContext,
        visibility: FieldNotesVisibilityBadge.Visibility? = nil,
        onDismiss: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.previewText = previewText
        self.promptContext = promptContext
        self.visibility = visibility
        self.onDismiss = onDismiss
        self.action = action
    }

    private var trimmedPreview: String {
        previewText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasNotes: Bool {
        !trimmedPreview.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.secondary)
                    Text("Field notes")
                        .font(.system(.headline))
                        .foregroundColor(.primary)

                    if hasNotes, let visibility {
                        FieldNotesVisibilityBadge(visibility: visibility)
                    }
                }

                Spacer(minLength: 8)

                if hasNotes {
                    Button(action: action) {
                        Label("Edit", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Edit field notes")
                } else if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hide field notes card")
                }
            }

            if hasNotes {
                Text(trimmedPreview)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .textSelection(.disabled)
                    .onTapGesture(perform: action)
                    .onLongPressGesture(perform: action)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens field notes for editing.")
            } else {
                zeroStateIntro

                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add field notes")
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
                .accessibilityLabel("Add field notes")
            }
        }
        .card()
    }

    private var zeroStateIntro: some View {
        VStack(alignment: .center, spacing: 14) {
            Image("journal-open")
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
}
