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
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Map View
            ZStack(alignment: .bottom) {
                if inferenceEngine.isEnrichmentLoading {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .frame(height: 280)
                        .redacted(reason: .placeholder)
                        .shimmering()
                } else {
                    GBIFHeatmapMapView(taxonKey: inferenceEngine.speciesData?.gbifTaxonKey)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.black.opacity(0.3), lineWidth: 4)
                                .blur(radius: 6)
                                .offset(y: 2)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1) // Crisp inner border line
                        )
                    
                    if inferenceEngine.speciesData?.gbifTaxonKey == nil {
                        Text("No distribution data available")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(.bottom, 12)
                    }
                }
            }
            .padding(.horizontal, 16)

            // MARK: - Content Below Map
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Header
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text("Habitat & distribution")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                // MARK: - Habitat Description
                if let habitat = habitatDescription {
                    // MARK: - LOADED STATE
                    Text(styledHabitat(text: habitat, name: scientificName))
                        .font(.body)
                        .lineSpacing(4)

                } else if inferenceEngine.isEnrichmentLoading {
                    // MARK: - LOADING STATE
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
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, -16) // Reaches edge of standard container bounds
    }

    @MainActor
    private func triggerEnrichment() async {
        isRetrying = true
        defer { isRetrying = false }
        await inferenceEngine.fetchAndApplyEnrichment(modelContext: modelContext)
        HapticManager.shared.triggerSuccessPulse()
    }
    
    // MARK: - View Helpers
    
    private func styledHabitat(text: String, name: String?) -> AttributedString {
        var result = AttributedString(text)
        
        if let name = name, !name.isEmpty {
            var searchRange = result.startIndex..<result.endIndex
            while let range = result[searchRange].range(of: name, options: .caseInsensitive) {
                result[range].font = .system(.body, design: .monospaced)
                result[range].backgroundColor = Color.secondary.opacity(0.15)
                searchRange = range.upperBound..<result.endIndex
            }
        }
        
        return result
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


