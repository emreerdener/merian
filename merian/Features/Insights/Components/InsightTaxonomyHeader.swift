import SwiftUI

struct InsightTaxonomyHeader: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    private var commonName: String {
        inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning Subject..."
    }
    private var scientificName: String {
        inferenceEngine.speciesData?.scientificName ?? "Awaiting Taxonomy"
    }
    private var isPoisonous: Bool {
        inferenceEngine.speciesData?.insightData.isPoisonous ?? false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

              if let score = inferenceEngine.speciesData?.confidenceScore, score > 0.0 {
                    Text("\(Int(score * 100))% match")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(score >= 0.85 ? .green : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(score >= 0.85 ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
            
            Text(commonName)
                .font(.largeTitle)
                .fontWeight(.bold)
                // Tie header routing to the name if there's no active poison banner
                .accessibilityAddTraits(isPoisonous ? [] : .isHeader)
            
            
                Text(scientificName)
                    .font(.title3)
                    .italic()
                    .foregroundColor(.secondary)
                    

            if let species = inferenceEngine.speciesData {
                if species.locationName != nil || species.weatherCondition != nil {
                    HStack(spacing: 12) {
                        if let name = species.locationName {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                Text(name)
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        
                        if let temp = species.weatherTemperatureF, let condition = species.weatherCondition {
                            HStack(spacing: 4) {
                                Image(systemName: "cloud.sun.fill")
                                Text("\(Int(temp))°F • \(condition)")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if species.isInvasive {
                            BadgeView(text: "Invasive", color: .purple, icon: "exclamationmark.shield.fill")
                        }
                        
                        if !species.isLiveCapture {
                            BadgeView(text: "Not a live capture", color: .gray, icon: "photo.badge.exclamationmark.fill")
                        }
                        
                        if !species.isBiological {
                            BadgeView(text: "Not biological", color: .gray, icon: "xmark.seal.fill")
                        }   
                        
                        if species.ecologyType != "Unknown" {
                            BadgeView(text: species.ecologyType.capitalized, color: .blue, icon: "leaf.fill")
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }
}
