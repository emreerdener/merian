import SwiftUI
import SwiftData

struct HabitatAndDistributionCard: View {
    let habitatDescription: String?
    let scientificName: String?
    let scanId: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine

    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .foregroundColor(.secondary)
                Text("Habitat & distribution")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
            }

            if let key = inferenceEngine.speciesData?.gbifTaxonKey {
                GBIFHeatmapMapView(taxonKey: key)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let habitat = habitatDescription {
                // LOADED STATE
                Text(habitat)
                    .font(.body)
                    .lineSpacing(4)

            } else if inferenceEngine.isEnrichmentLoading {
                // LOADING STATE
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(uiColor: .systemFill))
                                .frame(maxWidth: .infinity)
                                .frame(height: 14)
                        }
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(uiColor: .systemFill))
                            .frame(width: 160, height: 14)
                    }
                    .redacted(reason: .placeholder)
                    .shimmering()
                }

            } else {
                // RETRY STATE
                VStack(spacing: 12) {
                    Text("Habitat and distribution data couldn't be loaded.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)

                    Button(action: {
                        Task { await triggerEnrichment() }
                    }) {
                        HStack {
                            if isRetrying {
                                ProgressView().tint(.white)
                            } else {
                                Text("Retry").fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                    }
                    .disabled(isRetrying)
                }
            }
        }
        .card()
    }

    @MainActor
    private func triggerEnrichment() async {
        isRetrying = true
        defer { isRetrying = false }
        await inferenceEngine.fetchAndApplyEnrichment(modelContext: modelContext)
        HapticManager.shared.triggerSuccessPulse()
    }
}

// MARK: - Shimmer Modifier

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.35), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.5)
                .offset(x: geo.size.width * phase)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
            }
            .clipped()
        )
        .clipped()
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
