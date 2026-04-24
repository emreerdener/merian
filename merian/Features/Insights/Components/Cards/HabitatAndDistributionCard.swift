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
            ZStack(alignment: .bottom) {
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
                
                if !inferenceEngine.isEnrichmentLoading && inferenceEngine.speciesData?.gbifTaxonKey == nil {
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
