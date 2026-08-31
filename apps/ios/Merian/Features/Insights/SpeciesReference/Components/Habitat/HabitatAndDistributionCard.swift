import SwiftData
import SwiftUI

struct HabitatAndDistributionCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine

    @State private var isPulsing = false
    private let dependencies: HabitatDistributionDependencies

    init(dependencies: HabitatDistributionDependencies = .live) {
        self.dependencies = dependencies
    }

    var body: some View {
        let habitatDescription = inferenceEngine.speciesData?.habitatDescription
        let scientificName = inferenceEngine.speciesData?.scientificName

        VStack(alignment: .leading, spacing: 0) {
            GBIFHeatmapMapView(
                taxonKey: inferenceEngine.speciesData?.gbifTaxonKey,
                showsMissingTaxonKeyFallback: !inferenceEngine.isEnrichmentLoading
            )
            .gbifHeatmapCardChrome()
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 16) {
                InsightCardHeader(
                    systemImage: "globe",
                    title: "Habitat & distribution"
                )

                if let habitat = habitatDescription {
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
                    loadingPlaceholder
                        .task { await retryEnrichment() }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, -16)
    }

    private var loadingPlaceholder: some View {
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
            .opacity(isPulsing ? 0.4 : 1)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1).repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
        }
    }

    private func retryEnrichment() async {
        var retryCount = 0
        let maxRetries = 5

        while !Task.isCancelled && retryCount < maxRetries {
            if inferenceEngine.speciesData?.habitatDescription != nil {
                break
            }

            if !inferenceEngine.isEnrichmentLoading {
                let delay = pow(2, Double(retryCount + 1))
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { break }

                retryCount += 1
                await dependencies.requestEnrichment(
                    inferenceEngine,
                    modelContext
                )
            } else {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
