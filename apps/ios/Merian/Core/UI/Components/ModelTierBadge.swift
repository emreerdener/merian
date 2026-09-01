import SwiftUI

struct ModelTierBadgePresentation: Equatable {
    let text: String

    static func resolve(
        confidenceScore: Double?,
        inferenceTier: String?,
        label: String = "Upgrade for advanced analysis",
        isSubscribed: Bool,
        isProActive: Bool,
        hasComplimentaryAccess: Bool,
        complimentaryScansRemaining: Int,
        isComplimentaryExhausted: Bool
    ) -> Self? {
        if !isSubscribed,
           hasComplimentaryAccess,
           complimentaryScansRemaining > 0 {
            let text = complimentaryScansRemaining == 1
                ? "1 Pro scan remains"
                : "\(complimentaryScansRemaining) Pro scans remain"
            return Self(text: text)
        }

        if !isSubscribed, isComplimentaryExhausted {
            return Self(text: label)
        }

        if !isProActive, let confidenceScore {
            let bands = MerianConfig.confidenceBands(
                forInferenceTier: inferenceTier
            )
            if confidenceScore >= bands.possible,
               confidenceScore < bands.strong {
                return Self(text: label)
            }
        }

        return nil
    }
}

struct ModelTierBadge: View {
    let presentation: ModelTierBadgePresentation?
    let onUpgrade: () -> Void

    var body: some View {
        if let presentation {
            Button(action: onUpgrade) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.footnote.weight(.bold))

                    Text(presentation.text)
                        .font(.subheadline.weight(.semibold))

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                }
                .foregroundStyle(Color(uiColor: .systemBackground))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.primary)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
