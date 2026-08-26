import SwiftUI

struct FieldTripGoalTipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FieldTripMetadataPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1)
            }
    }
}

struct FieldTripTagRow: View {
    let tags: [String]

    private var displayTags: [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    var body: some View {
        if !displayTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(displayTags, id: \.self) { tag in
                        Text(tag.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

struct FieldTripCoverImage: View {
    let urlString: String?
    let templateSlug: String?
    private let placeholderFontSize: CGFloat

    init(urlString: String?, templateSlug: String? = nil) {
        self.urlString = urlString
        self.templateSlug = templateSlug
        placeholderFontSize = 26
    }

    init(
        urlString: String?,
        templateSlug: String?,
        placeholderFontSize: CGFloat
    ) {
        self.urlString = urlString
        self.templateSlug = templateSlug
        self.placeholderFontSize = placeholderFontSize
    }

    var body: some View {
        if let imageName = FieldTripTemplatePresentation.bundledCoverImageName(for: templateSlug) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            FieldTripRemoteImage(
                urlString: urlString,
                placeholderSystemImage: "map",
                placeholderFontSize: placeholderFontSize
            )
        }
    }
}

struct FieldTripChallengeProgressBar: View {
    let participation: FieldTripChallengeParticipation

    var body: some View {
        FieldTripLevelProgressBar(
            progress: FieldTripLevelProgressPresentation(participation)
        )
    }
}

struct FieldTripLevelProgressBar: View {
    let progress: FieldTripLevelProgressPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let completionLabel = progress.completionLabel {
                    Label(completionLabel, systemImage: "rosette")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(progress.completedCount)/\(max(progress.targetCount, 0))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(6, proxy.size.width * progress.fractionComplete))
                }
            }
            .frame(height: 7)
        }
    }
}
