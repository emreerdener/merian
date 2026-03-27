import SwiftUI
import SwiftData

struct SpeciesInsightsCard: View {
    let habitatDescription: String?
    let globalDistributionRegions: [String]?
    let scientificName: String?
    let scanId: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine

    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.green)
                    .frame(width: 28, height: 28)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Circle())

                Text("Habitat & Distribution")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal)

            if let habitat = habitatDescription {
                // LOADED STATE
                VStack(alignment: .leading, spacing: 12) {
                    Text(habitat)
                        .font(.body)
                        .lineSpacing(4)

                    if let regions = globalDistributionRegions, !regions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(regions, id: \.self) { region in
                                    Text(region)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.1))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

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

                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 72, height: 28)
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

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
                .padding(.vertical, 20)
                .padding(.horizontal)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
            }
        }
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
