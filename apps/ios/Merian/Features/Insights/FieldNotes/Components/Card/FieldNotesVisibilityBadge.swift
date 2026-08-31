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
