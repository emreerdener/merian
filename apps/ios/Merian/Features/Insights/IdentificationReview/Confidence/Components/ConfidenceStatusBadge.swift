import SwiftUI

extension ConfidenceBadgePresentation.Style {
    /// Shared by the Insight badge, Identification, History and confidence scale.
    var color: Color {
        switch self {
        case .confirmed, .strong: .green
        case .incorrect: .red
        case .possible, .awaitingReview: .orange
        case .analyzing: .blue
        case .weak, .unknown: .gray
        }
    }
}

struct ConfidenceStatusBadge: View {
    let label: String
    let style: ConfidenceBadgePresentation.Style

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(style.color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style.color.opacity(0.12), in: Capsule())
    }
}

struct CurrentIdentificationBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("Current")
            .font(.caption2.bold())
            .foregroundStyle(colorScheme == .dark ? Color.black : .white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(colorScheme == .dark ? Color.white : .black, in: Capsule())
    }
}
