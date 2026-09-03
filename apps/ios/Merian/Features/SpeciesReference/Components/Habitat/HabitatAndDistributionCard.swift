import SwiftData
import SwiftUI

struct HabitatAndDistributionCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine

    @State private var isPulsing = false
    @State private var exhaustedEnrichmentIdentity: EnrichmentIdentity?
    private let dependencies: HabitatDistributionDependencies

    private struct EnrichmentIdentity: Equatable {
        let scanID: String?
        let scientificName: String?
        let presentationGeneration: UInt64
    }

    init(dependencies: HabitatDistributionDependencies = .live) {
        self.dependencies = dependencies
    }

    var body: some View {
        let habitatDescription = inferenceEngine.speciesData?.habitatDescription?.trimmedNonEmptyValue
        let scientificName = inferenceEngine.speciesData?.scientificName
        let identity = enrichmentIdentity

        VStack(alignment: .leading, spacing: 0) {
            GBIFHeatmapMapView(
                taxonKey: inferenceEngine.speciesData?.gbifTaxonKey,
                showsMissingTaxonKeyFallback: !inferenceEngine.isEnrichmentLoading
            )
            .gbifHeatmapCardChrome()
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 16) {
                MerianCardHeader(
                    systemImage: "globe",
                    title: "Habitat & distribution"
                )

                if let habitat = habitatDescription {
                    Text(
                        ScientificNameStyler.highlightedText(
                            habitat,
                            scientificName: scientificName
                        )
                    )
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                } else if canRequestEnrichment && exhaustedEnrichmentIdentity != identity {
                    loadingPlaceholder
                        .task(id: identity) { await retryEnrichment(for: identity) }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Habitat information is not available for this species yet.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if canRequestEnrichment {
                            Button("Retry") {
                                exhaustedEnrichmentIdentity = nil
                            }
                            .accessibilityLabel("Retry habitat information")
                        }
                    }
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

    private var enrichmentIdentity: EnrichmentIdentity {
        EnrichmentIdentity(
            scanID: inferenceEngine.speciesData?.scanId,
            scientificName: inferenceEngine.speciesData?.scientificName,
            presentationGeneration: inferenceEngine.scanPresentationGeneration
        )
    }

    private var canRequestEnrichment: Bool {
        guard let data = inferenceEngine.speciesData else { return false }
        return data.scanId?.trimmedNonEmptyValue != nil &&
            data.hasResolvedBiologicalIdentification && !data.isHumanSubject
    }

    private func retryEnrichment(for identity: EnrichmentIdentity) async {
        var retryCount = 0
        let maxRetries = 5

        while !Task.isCancelled && retryCount < maxRetries {
            guard identity == enrichmentIdentity,
                  canRequestEnrichment,
                  inferenceEngine.speciesData?.habitatDescription?.trimmedNonEmptyValue == nil else { return }

            if !inferenceEngine.isEnrichmentLoading {
                let delay = pow(2, Double(retryCount + 1))
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled,
                      identity == enrichmentIdentity,
                      canRequestEnrichment,
                      inferenceEngine.speciesData?.habitatDescription?.trimmedNonEmptyValue == nil else { return }
                guard !inferenceEngine.isEnrichmentLoading else { continue }

                retryCount += 1
                await dependencies.requestEnrichment(
                    inferenceEngine,
                    modelContext
                )
            } else {
                try? await Task.sleep(for: .seconds(1))
            }
        }

        guard !Task.isCancelled,
              identity == enrichmentIdentity,
              inferenceEngine.speciesData?.habitatDescription?.trimmedNonEmptyValue == nil else { return }
        exhaustedEnrichmentIdentity = identity
    }
}
