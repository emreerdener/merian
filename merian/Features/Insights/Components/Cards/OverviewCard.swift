import SwiftUI

struct OverviewCard: View {
    @Environment(InferenceEngine.self) var inferenceEngine
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?
    
    // Fallback dictionary for capitalizing known values if needed
    func capitalizeFirstLetter(_ string: String) -> String {
        guard let first = string.first else { return "" }
        return String(first).uppercased() + string.dropFirst()
    }
    
    var body: some View {
        if let data = inferenceEngine.speciesData {
            let wikiExtract = data.wikipediaOverview
            let hasWiki = (wikiExtract?.count ?? 0) >= 60
            
            let colors = (data.colors?.isEmpty == false) ? data.colors?.joined(separator: ", ").capitalized : nil
            let size = data.estimatedSizeCm.map { String(format: "%.1f cm", $0) }
            let invasive = data.isInvasive ? "Invasive species" : "Non-invasive"
            let ecology = data.ecologyType == "unknown" ? nil : capitalizeFirstLetter(data.ecologyType)
            let lifeStage = (data.lifeStage == "unknown" || data.lifeStage == nil) ? nil : capitalizeFirstLetter(data.lifeStage!)
            let reproduction = (data.reproductiveCondition == "not_applicable" || data.reproductiveCondition == nil) ? nil : capitalizeFirstLetter(data.reproductiveCondition!.replacingOccurrences(of: "_", with: " "))
            let interactions = data.ecologicalInteractions?.isEmpty == false ? data.ecologicalInteractions?.joined(separator: "; ") : nil
            
            let hasAnyMetadata = colors != nil || size != nil || ecology != nil || lifeStage != nil || reproduction != nil || interactions != nil || data.isInvasive
            
            if hasAnyMetadata {
                VStack(alignment: .leading, spacing: 16) {
                    
                    HStack(spacing: 8) {
                        Image(systemName: "book")
                            .foregroundColor(.secondary)
                        Text("Overview")
                            .font(.system(.headline))
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if let val = size {
                            KeyValueRow(title: "EST. SIZE", value: val)
                        }
                        if let val = lifeStage {
                            KeyValueRow(title: "LIFE STAGE", value: val)
                        }
                        if let val = reproduction {
                            KeyValueRow(title: "REPRODUCTION", value: val)
                        }
                        if let val = ecology {
                            KeyValueRow(title: "ECOLOGY", value: val)
                        }
                        KeyValueRow(title: "INVASIVE", value: invasive, valueIcon: data.isInvasive ? "exclamationmark.triangle.fill" : nil)
                        if let val = colors, !val.isEmpty {
                            KeyValueRow(title: "DOMINANT COLORS", value: val)
                        }
                        if let val = interactions {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("INTERACTIONS")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                    .tracking(1)
                                    .foregroundColor(.secondary)
                                
                                Text(val)
                                    .font(.system(.subheadline))
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    if hasWiki, let extract = wikiExtract {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WIKIPEDIA")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            Text(extract)
                                .font(.system(.body))
                                .lineLimit(8)
                        }
                    }
                    
                    if hasWiki, let wikiString = data.wikipediaUrl, let wikiUrl = URL(string: wikiString) {
                        Button(action: {
                            selectedWikiURL = wikiUrl
                            isSafariPresented = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "safari")
                                Text("Learn more on Wikipedia")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .foregroundColor(.blue)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }
}
