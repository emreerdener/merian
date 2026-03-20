import SwiftUI

struct InsightDescriptionSection: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?
    
    var body: some View {
        if let data = inferenceEngine.speciesData, (data.wikipediaExtract != nil || data.wikipediaUrl != nil) {
            VStack(alignment: .leading, spacing: 16) {
                if let wikiExtract = data.wikipediaExtract {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("More information")
                          .font(.system(.headline))
                            .padding(.bottom, 8)
                        Text(wikiExtract)
                            .font(.system(.body))
                            .foregroundColor(.secondary)
                    }
                }
                    
                if let wikiString = data.wikipediaUrl, let wikiUrl = URL(string: wikiString) {
                    Button(action: {
                        selectedWikiURL = wikiUrl
                        isSafariPresented = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "safari")
                                
                            Text("Read more on Wikipedia")
                                .font(.system(.body))
                                
                            Spacer()
                            
                            // Maps mathematically to the exact native iOS indicator geometries
                            Image(systemName: "chevron.right")
                        }
                        .padding(.vertical, 14) // Standard List row vertical metrics
                        .padding(.horizontal, 16)
                        .background(Color(UIColor.tertiarySystemFill)) // Native translucent overlay depth
                        .cornerRadius(12)
                    }
                    .padding(.top, 4)
                }
            }
            .glassCard()
        }
    }
}
