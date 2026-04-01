import SwiftUI

struct ModelInfoSection: View {
    let inferenceTier: String?

    private var isPro: Bool { inferenceTier == "pro" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.2")
                    .foregroundColor(.secondary)
                Text("Confidence score")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Merian AI")
                            .font(.system(.title3, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(isPro ? "Pro" : "Flash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isPro ? Color.indigo : Color.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isPro ? Color.indigo.opacity(0.12) : Color.secondary.opacity(0.1))
                            )
                    }

                    Text(isPro
                         ? "This scan used an enhanced reasoning model for deeper accuracy."
                         : "This scan used the standard model optimized for speed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)

                    if isPro {
                        Text("Powered by Gemini 2.5 Pro")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
