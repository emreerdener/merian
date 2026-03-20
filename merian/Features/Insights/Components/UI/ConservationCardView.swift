import SwiftUI

struct InsightConservationCard: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    private var formattedStatus: String? {
        guard let rawStatus = inferenceEngine.speciesData?.iucnRedListStatus?.lowercased() else { return nil }
        if rawStatus == "not evaluated" || rawStatus == "not applicable" || rawStatus.isEmpty || rawStatus == "data deficient" { return nil }
        
        switch rawStatus {
        case _ where rawStatus.contains("least_concern") || rawStatus.contains("least concern"): return "Not at risk"
        case _ where rawStatus.contains("near_threatened") || rawStatus.contains("near threatened"): return "Near Threatened"
        case _ where rawStatus.contains("vulnerable"): return "Vulnerable"
        case _ where rawStatus.contains("endangered") && !rawStatus.contains("critically"): return "Endangered"
        case _ where rawStatus.contains("critically_endangered") || rawStatus.contains("critically endangered"): return "Critically Endangered"
        case _ where rawStatus.contains("extinct in the wild"): return "Extinct in the Wild"
        case _ where rawStatus.contains("extinct"): return "Extinct"
        default: return rawStatus.capitalized.replacingOccurrences(of: "_", with: " ")
        }
    }
    
    var body: some View {
        if let status = formattedStatus {
            HStack(spacing: 16) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green.opacity(0.8))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("IUCN RED LIST")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.green.opacity(0.7))
                        
                    Text(status)
                        .font(.system(.title3))
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                Spacer()
            }
            .padding(20)
            .background(Color.green.opacity(0.05))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.green.opacity(0.4), lineWidth: 1)
            )
        }
    }
}

