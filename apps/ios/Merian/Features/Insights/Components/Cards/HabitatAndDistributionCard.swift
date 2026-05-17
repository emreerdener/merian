import SwiftData
import SwiftUI

struct HabitatAndDistributionCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine

    @State private var isPulsing = false

    var body: some View {
        let habitatDescription = inferenceEngine.speciesData?.habitatDescription
        let scientificName = inferenceEngine.speciesData?.scientificName
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Map View
            GBIFHeatmapMapView(
                taxonKey: inferenceEngine.speciesData?.gbifTaxonKey,
                showsMissingTaxonKeyFallback: !inferenceEngine.isEnrichmentLoading
            )
                .gbifHeatmapCardChrome()
            .padding(.horizontal, 16)

            // MARK: - Content Below Map
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Header
                InsightCardHeader(systemImage: "globe", title: "Habitat & distribution")

                // MARK: - Habitat Description
                if let habitat = habitatDescription {
                    // MARK: - LOADED STATE
                    Text(
                        InsightScientificNameStyler.highlightedText(
                            habitat,
                            scientificName: scientificName
                        )
                    )
                        .font(.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                } else {
                    // MARK: - LOADING & AUTO-RETRY STATE
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
                        .opacity(isPulsing ? 0.4 : 1.0)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                isPulsing = true
                            }
                        }
                    }
                    .task {
                        var retryCount = 0
                        let maxRetries = 5
                        
                        while !Task.isCancelled && retryCount < maxRetries {
                            if inferenceEngine.speciesData?.habitatDescription != nil { break }
                            
                            if !inferenceEngine.isEnrichmentLoading {
                                // Exponential backoff: 2s, 4s, 8s, 16s, 32s
                                let delay = pow(2.0, Double(retryCount + 1))
                                try? await Task.sleep(for: .seconds(delay))
                                guard !Task.isCancelled else { break }
                                
                                retryCount += 1
                                await triggerEnrichment()
                            } else {
                                // Wait and poll again
                                try? await Task.sleep(for: .seconds(1))
                            }
                        }
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
        await inferenceEngine.fetchAndApplyEnrichment(
            modelContext: modelContext,
            needsMetadata: true,
            needsLookalikes: false
        )
    }
}
