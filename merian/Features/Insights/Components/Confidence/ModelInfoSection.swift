import SwiftUI

struct ModelInfoSection: View {
    let inferenceTier: String?

    private var isPro: Bool { inferenceTier == "pro" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .foregroundColor(.secondary)
                Text("Model")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
            }

            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isPro ? Color.indigo.opacity(0.15) : Color.blue.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: isPro ? "sparkles" : "cpu")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isPro ? Color.indigo : Color.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Merian AI")
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(isPro ? "Pro" : "Standard")
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
                        .font(.footnote)
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
